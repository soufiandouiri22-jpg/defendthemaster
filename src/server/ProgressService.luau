-- The heroes' levels (Config.Progress, Shared.Leveling): XP when enemies die nearby, a level-up raising the hero's
-- health, and the points a player spends on ranks through ReplicatedStorage.Net.Upgrade (the ability's key). A hero's
-- death scores for the other team, and its killing blow (the last player to hurt him, within KillCredit seconds) earns
-- the bounty, and the other enemies who hurt him within KillCredit seconds share the assist. Bots (Actors) level up the
-- same way, and spend their points themselves (ProgressService.raise). Every hero's death is told to the clients
-- (Net.Kill, see `announce`) with the one call it earns (Config.Kills), and counted on the player or bot for the
-- scoreboard: "Kills" for the killing blow, "Assists" for the others who hurt him, "Deaths" for every death.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Economy = require(script.Parent.Economy)
local Actors = require(script.Parent.Actors)
local MatchService = require(script.Parent.MatchService)
local TestGround = require(script.Parent.TestGround)

local SETTINGS = Config.Progress

local ProgressService = {}

-- Per hurt hero: who hurt him last, and when each enemy last did (os.clock).
local credit: { [Model]: { last: Instance, at: number, by: { [Instance]: number } } } = {}
-- Per hurt hero: when a Master last struck him, and when a minion last did (os.clock).
local masterHits: { [Model]: number } = {}
local minionHits: { [Model]: number } = {}
-- Per killer: his kills in a row within Config.Kills.MultiWindow of each other, and when the last was.
local multi: { [Instance]: { count: number, at: number } } = {}
local firstBlood = false
local killEvent: RemoteEvent

local function living(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

-- Sets the hero's health to its level and items, healing it by what they add; the hero carries its level for the HUD.
function ProgressService.refresh(player: Instance)
	local character = Actors.character(player)
	local hero = character and character:GetAttribute("Hero")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not hero or not humanoid then
		return
	end
	character:SetAttribute("Level", Leveling.level(player :: any))
	local max = Leveling.heroHealth(player :: any, hero)
	local gain = max - humanoid.MaxHealth
	humanoid.MaxHealth = max
	if humanoid.Health > 0 then
		humanoid.Health = math.min(max, humanoid.Health + math.max(gain, 0))
	end
end

function ProgressService.give(player: Instance, xp: number)
	local level = Leveling.level(player :: any)
	local have = (player:GetAttribute("Xp") or 0) + xp
	local points = player:GetAttribute("Points") or 0
	local before = level
	while true do
		local step = Leveling.step(level)
		if not step then
			have = 0
			break
		end
		if have < step then
			break
		end
		have -= step
		level += 1
		points += 1
	end
	player:SetAttribute("Xp", math.round(have))
	if level ~= before then
		player:SetAttribute("Level", level)
		player:SetAttribute("Points", points)
		ProgressService.refresh(player)
	end
end

-- Shares `xp` evenly among the living heroes of `team` within Share studs of `position`, and `killer`.
local function share(team: string, position: Vector3, xp: number, killer: Instance?)
	local takers = {}
	for _, player in Actors.all() do
		local character = Actors.character(player)
		local _, root = living(character)
		if
			character
			and root
			and character:GetAttribute("Team") == team
			and HeroKit.flat(root.Position - position).Magnitude <= SETTINGS.Share
		then
			table.insert(takers, player)
		end
	end
	if
		killer
		and killer.Parent
		and not table.find(takers, killer)
		and Actors.character(killer)
		and (Actors.character(killer) :: Model):GetAttribute("Team") == team
	then
		table.insert(takers, killer)
	end
	for _, player in takers do
		ProgressService.give(player, xp / #takers)
	end
end

-- A minion of `team` died at `position`.
function ProgressService.minionDied(team: string, kind: string, position: Vector3, killer: Instance?)
	share(MatchService.enemyOf(team), position, SETTINGS.MinionXp[kind] or 0, killer)
end

-- `player` hurt the hero `victim`.
function ProgressService.hurt(victim: Model, player: Instance)
	local now = os.clock()
	local entry = credit[victim] or { last = player, at = now, by = {} }
	entry.last = player
	entry.at = now
	entry.by[player] = now
	credit[victim] = entry
end

-- A Master struck the hero `victim`.
function ProgressService.hurtByMaster(victim: Model)
	masterHits[victim] = os.clock()
end

-- A minion struck the hero `victim`.
function ProgressService.hurtByMinion(victim: Model)
	minionHits[victim] = os.clock()
end

-- When an enemy hero last hurt `victim` (os.clock), if he did since `victim` came back.
function ProgressService.hurtAt(victim: Model): number?
	local last = credit[victim]
	return last and last.at
end

-- What killing `player`'s hero earns (Config.Economy): less after deaths without a kill, more on a kill streak.
local function bounty(player: Instance): number
	local economy = Config.Economy
	local deaths = player:GetAttribute("DeathsSinceKill") or 0
	if deaths > 0 then
		return economy.DeathBounty[math.min(deaths, #economy.DeathBounty)]
	end
	local streak = math.max(0, (player:GetAttribute("KillsSinceDeath") or 0) - 1)
	return economy.HeroBounty + math.min(economy.StreakMax, streak * economy.StreakBounty)
end

-- How long `player`'s hero, dying now, stays dead (Config.Respawn); counts the death towards his streak.
local function respawnTime(player: Instance): number
	local settings = Config.Respawn
	local now = os.clock()
	local last = player:GetAttribute("LastDeath")
	local streak = if last and now - last <= settings.StreakWindow
		then (player:GetAttribute("DeathStreak") or 0) + 1
		else 0
	player:SetAttribute("LastDeath", now)
	player:SetAttribute("DeathStreak", streak)
	local level = Leveling.level(player :: any)
	return settings.Base + settings.PerLevel * (level - 1) + math.min(settings.StreakMax, settings.Streak * streak)
end

-- Whether a hero of `team` other than `except` is alive.
local function anyAlive(team: string, except: Model): boolean
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		if character and character ~= except and character:GetAttribute("Team") == team and living(character) then
			return true
		end
	end
	return false
end

-- The one call a kill earns, the first that fits (Config.Kills): the match's first kill, a multi-kill, ending a
-- streak, the killer's own streak, else a plain kill.
local function call(killer: Instance, victimStreak: number): string
	local settings = Config.Kills
	local now = os.clock()
	local run = multi[killer]
	local count = if run and now - run.at <= settings.MultiWindow then run.count + 1 else 1
	multi[killer] = { count = count, at = now }
	local streak = killer:GetAttribute("KillsSinceDeath") or 0
	if not firstBlood then
		firstBlood = true
		return "FirstBlood"
	elseif count >= 4 then
		return "Quad"
	elseif count == 3 then
		return "Triple"
	elseif count == 2 then
		return "Double"
	elseif victimStreak >= settings.ShutdownStreak then
		return "Shutdown"
	end
	local named = nil
	for _, step in settings.Streaks do
		if streak >= step.kills then
			named = step.call
		end
	end
	return named or "Slain"
end

local function count(actor: Instance, key: string)
	actor:SetAttribute(key, (actor:GetAttribute(key) or 0) + 1)
end

local function display(actor: Instance?, character: Model?): string?
	if actor and actor:IsA("Player") then
		return actor.DisplayName
	end
	return character and character:GetAttribute("Hero")
end

-- Tells every client of the death of `player`'s hero `character` at `position` (Net.Kill): the call, whether Wipeout
-- follows it, both sides' players (nil for bots), names, heroes and teams, and the bounty. Felled by a Master or a
-- minion, the killer's hero is `by`: "Master" or "Minion".
local function announce(
	character: Model,
	player: Instance,
	position: Vector3,
	killer: Instance?,
	kind: string,
	wipe: boolean,
	worth: number,
	by: string?
)
	local killerCharacter = killer and Actors.character(killer)
	killEvent:FireAllClients({
		kind = kind,
		wipe = wipe,
		killer = if killer and killer:IsA("Player") then killer else nil,
		killerName = by or display(killer, killerCharacter),
		killerHero = by or killerCharacter and killerCharacter:GetAttribute("Hero"),
		killerTeam = MatchService.enemyOf(character:GetAttribute("Team") or "Blue"),
		victim = if player:IsA("Player") then player else nil,
		victimName = display(player, character),
		victimHero = character:GetAttribute("Hero"),
		victimTeam = character:GetAttribute("Team"),
		coins = if killer then worth else 0,
		at = position,
	})
end

-- The hero `character` of `player` died at `position`. Returns how many seconds he stays dead; the hero carries when
-- he comes back (the "RespawnAt" attribute, in server time) for the HUD's countdown.
function ProgressService.heroDied(character: Model, player: Instance, position: Vector3): number
	local enemy = MatchService.enemyOf(character:GetAttribute("Team") or "Blue")
	MatchService.scored(enemy)
	local entry = credit[character]
	credit[character] = nil
	local now = os.clock()
	local killer = if entry and now - entry.at <= SETTINGS.KillCredit and entry.last.Parent then entry.last else nil
	-- A Master's blow after every enemy hero's is his kill: nobody earns the bounty.
	local masterAt = masterHits[character]
	masterHits[character] = nil
	local byMaster = masterAt ~= nil
		and now - masterAt <= SETTINGS.KillCredit
		and (killer == nil or masterAt > (entry :: any).at)
	if byMaster then
		killer = nil
	end
	-- With no enemy hero's blow to credit, a minion's last blow (after any Master's) makes it the minion's kill.
	local minionAt = minionHits[character]
	minionHits[character] = nil
	local byMinion = killer == nil
		and minionAt ~= nil
		and now - minionAt <= SETTINGS.KillCredit
		and (not byMaster or minionAt > (masterAt :: number))
	if byMinion then
		byMaster = false
	end
	local assists = {}
	for actor, at in if entry then entry.by else {} do
		if actor ~= killer and actor.Parent and now - at <= SETTINGS.KillCredit then
			table.insert(assists, actor)
		end
	end
	local worth = bounty(player)
	local kind = "Died"
	if killer then
		Economy.give(killer :: any, worth, "killed " .. player.Name)
		killer:SetAttribute("KillsSinceDeath", (killer:GetAttribute("KillsSinceDeath") or 0) + 1)
		killer:SetAttribute("DeathsSinceKill", 0)
		kind = call(killer, player:GetAttribute("KillsSinceDeath") or 0)
		count(killer, "Kills")
	end
	count(player, "Deaths")
	local wiped = not anyAlive(character:GetAttribute("Team") or "Blue", character)
	announce(
		character,
		player,
		position,
		killer,
		kind,
		wiped,
		worth,
		if byMinion then "Minion" elseif byMaster then "Master" else nil
	)
	for _, actor in assists do
		Economy.give(actor, math.round(worth * Config.Economy.Assist / #assists), "assist on " .. player.Name)
		count(actor, "Assists")
	end
	share(enemy, position, SETTINGS.HeroXp + SETTINGS.HeroXpPerLevel * (Leveling.level(player :: any) - 1), killer)
	player:SetAttribute("KillsSinceDeath", 0)
	player:SetAttribute("DeathsSinceKill", (player:GetAttribute("DeathsSinceKill") or 0) + 1)
	local wait = respawnTime(player)
	character:SetAttribute("RespawnAt", Workspace:GetServerTimeNow() + wait)
	return wait
end

-- A new player or bot starts at level 1 with StartPoints to spend, M2, E and R unlearned and no kills. On the test
-- ground every ability is learned from the start, at its first rank.
function ProgressService.join(player: Instance)
	if player:GetAttribute("Level") ~= nil then
		return
	end
	player:SetAttribute("Level", 1)
	player:SetAttribute("Xp", 0)
	player:SetAttribute("Points", SETTINGS.StartPoints)
	for _, key in { "Kills", "Deaths", "Assists" } do
		player:SetAttribute(key, 0)
	end
	local learned = if TestGround.on() then 1 else 0
	for _, key in SETTINGS.Upgrades do
		player:SetAttribute("Rank" .. key, learned)
	end
end

-- Spends one of the hero's points on raising `key` a rank, if it can; whether it did.
function ProgressService.raise(player: Instance, key: string): boolean
	if not Leveling.canRaise(player :: any, key) then
		return false
	end
	player:SetAttribute("Rank" .. key, Leveling.rank(player :: any, key) + 1)
	player:SetAttribute("Points", (player:GetAttribute("Points") or 0) - 1)
	return true
end

function ProgressService.start()
	Players.PlayerAdded:Connect(ProgressService.join)
	for _, player in Players:GetPlayers() do
		ProgressService.join(player)
	end

	local net = ReplicatedStorage:FindFirstChild("Net") or Instance.new("Folder")
	net.Name = "Net"
	net.Parent = ReplicatedStorage
	killEvent = Instance.new("RemoteEvent")
	killEvent.Name = "Kill"
	killEvent.Parent = net
	local upgrade = Instance.new("RemoteEvent")
	upgrade.Name = "Upgrade"
	upgrade.Parent = net
	upgrade.OnServerEvent:Connect(function(player, key)
		if typeof(key) == "string" then
			ProgressService.raise(player, key)
		end
	end)
end

return ProgressService
