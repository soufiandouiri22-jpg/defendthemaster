-- The draft (design 07, Config.Draft): before the buy phase both teams pick their heroes in turn, as in League of
-- Legends without bans, Turn seconds a pick. A player picks from the heroes he owns (Shared.Profile): he chooses one
-- (Net.Draft "Hover", shown to everyone) and locks it in ("Lock"); when his time runs out the one he chose is locked,
-- else one of his own at random. Each hero once per match while the picker still has an untaken one of his own, so
-- with few heroes a taken one may be picked again. Bots, and players who left, pick after a moment. Every change goes
-- to every client (Net.Draft) with that client's own heroes; the Workspace attribute "Phase" is "Draft" meanwhile and
-- "Ready" while the picks are shown at the end. The picked hero is the player's "Hero" attribute (HeroService) and his
-- profile's LastHero.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local MatchSetup = require(script.Parent.MatchSetup)
local ProfileService = require(script.Parent.ProfileService)
local Remote = require(script.Parent.Remote)

local SETTINGS = Config.Draft

local DraftService = {}

type Pick = MatchSetup.Slot & { hero: string?, hover: string?, locked: boolean }

local picks: { Pick } = {}
local turn = 0
local endsAt = 0
local phase = "Waiting"
local event: RemoteEvent
local rng = Random.new()

-- A bot's hero: the first of Config.Bots.Lineup his team has not picked yet, else Config.Bots.Hero.
local function botHero(pick: Pick): string
	local left = table.clone(Config.Bots.Lineup)
	for _, other in picks do
		if other ~= pick and other.locked and other.team == pick.team then
			local at = table.find(left, other.hero)
			if at then
				table.remove(left, at)
			end
		end
	end
	return left[1] or Config.Bots.Hero
end

local function owned(pick: Pick): { string }
	if pick.player and pick.player.Parent then
		local data = ProfileService.get(pick.player)
		if data then
			return Profile.owned(data)
		end
	end
	return { botHero(pick) }
end

local function taken(hero: string): boolean
	for _, pick in picks do
		if pick.locked and pick.hero == hero then
			return true
		end
	end
	return false
end

-- Whether `pick` may take `hero`: his own, and not taken unless all of his own are.
local function allowed(pick: Pick, hero: string): boolean
	local own = owned(pick)
	if not table.find(own, hero) then
		return false
	end
	if not taken(hero) then
		return true
	end
	for _, other in own do
		if not taken(other) then
			return false
		end
	end
	return true
end

-- `player`'s mastery level of every hero he played, for the crest beside his pick.
local function masteries(player: Player): { [string]: number }
	local levels = {}
	local data = ProfileService.get(player)
	for hero, entry in (data and data.Mastery) or {} do
		levels[hero] = entry.Level
	end
	return levels
end

local function state(): any
	local list = {}
	for _, pick in picks do
		local player = pick.player
		table.insert(list, {
			key = pick.key,
			team = pick.team,
			userId = pick.userId,
			name = pick.name,
			hero = pick.hero,
			hover = pick.hover,
			locked = pick.locked,
			shown = if player then player:GetAttribute("RankShown") else nil,
			division = if player then player:GetAttribute("RankDivision") else nil,
			level = if player then player:GetAttribute("AccountLevel") else nil,
			mastery = if player then masteries(player) else nil,
		})
	end
	return { phase = phase, turn = turn, endsAt = endsAt, picks = list, mode = MatchSetup.mode() }
end

local function broadcast()
	local shared = state()
	for _, player in Players:GetPlayers() do
		local data = ProfileService.get(player)
		local mine = table.clone(shared)
		mine.owned = if data then Profile.owned(data) else {}
		event:FireClient(player, mine)
	end
end

local function lock(pick: Pick, hero: string)
	pick.hero, pick.hover, pick.locked = hero, hero, true
	local player = pick.player
	if player and player.Parent then
		player:SetAttribute("Hero", hero)
		ProfileService.update(player, function(data)
			data.LastHero = hero
		end)
	end
end

-- What `pick` gets when his time runs out: the hero he chose if he may, else one of his own at random.
local function fallback(pick: Pick): string
	if pick.hover and allowed(pick, pick.hover) then
		return pick.hover
	end
	local options = {}
	for _, hero in owned(pick) do
		if allowed(pick, hero) then
			table.insert(options, hero)
		end
	end
	return if #options > 0 then options[rng:NextInteger(1, #options)] else Config.DefaultHero
end

-- The draft's places from MatchSetup.slots; returns once every hero is picked and shown.
function DraftService.run(slots: { MatchSetup.Slot })
	picks = {}
	for _, slot in slots do
		local pick = table.clone(slot) :: any
		pick.locked = false
		table.insert(picks, pick)
	end
	phase = "Draft"
	Workspace:SetAttribute("Phase", "Draft")
	for index, pick in picks do
		turn = index
		local human = pick.player ~= nil and pick.player.Parent ~= nil
		local wait = if human then SETTINGS.Turn else rng:NextNumber(SETTINGS.BotDelay[1], SETTINGS.BotDelay[2])
		endsAt = Workspace:GetServerTimeNow() + wait
		broadcast()
		local deadline = os.clock() + wait
		while not pick.locked and os.clock() < deadline do
			if pick.player and not pick.player.Parent then
				break
			end
			task.wait(0.1)
		end
		if not pick.locked then
			lock(pick, fallback(pick))
		end
	end
	turn = #picks + 1
	phase = "Ready"
	Workspace:SetAttribute("Phase", "Ready")
	endsAt = Workspace:GetServerTimeNow() + SETTINGS.Ready
	broadcast()
	task.wait(SETTINGS.Ready)
	phase = "Done"
	broadcast()
end

-- Per team the heroes picked for the places no player plays, in their order.
function DraftService.botHeroes(): { [string]: { string } }
	local heroes = {}
	for _, pick in picks do
		if pick.hero and not (pick.player and pick.player.Parent) then
			heroes[pick.team] = heroes[pick.team] or {}
			table.insert(heroes[pick.team], pick.hero)
		end
	end
	return heroes
end

-- The hero `player` picked, if any.
function DraftService.heroOf(player: Player): string?
	for _, pick in picks do
		if pick.player == player then
			return pick.hero
		end
	end
	return nil
end

function DraftService.start()
	event = Remote.event("Draft", 12, function(player, action, hero)
		if phase ~= "Draft" or typeof(hero) ~= "string" or not Config.Heroes[hero] then
			if action == "Hello" then
				local data = ProfileService.get(player)
				local mine = state()
				mine.owned = if data then Profile.owned(data) else {}
				event:FireClient(player, mine)
			end
			return
		end
		local pick = picks[turn]
		if not pick or pick.player ~= player or pick.locked then
			-- Anyone may look at heroes out of turn; only the picker's choice is shown.
			return
		end
		if action == "Hover" and table.find(owned(pick), hero) then
			pick.hover = hero
			broadcast()
		elseif action == "Lock" and allowed(pick, hero) then
			lock(pick, hero)
			broadcast()
		end
	end)
end

return DraftService
