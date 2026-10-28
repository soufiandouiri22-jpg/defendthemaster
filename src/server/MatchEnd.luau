-- The end of a match (design 16, Config.Rewards). When a Master falls (MatchService.onFinished) every hero gets a match
-- score from his kills, assists and deaths, his share of his team's damage to heroes ("HeroDamage", CombatService)
-- and to the enemy Master ("MasterDamage") and the Sun Crowns he took ("Crowns", CrownService), and from it a grade
-- (S+ to D-); the winners' best is the MVP. Every player then earns his coins, account XP and pass XP (twice the XP
-- while his pass boost runs), and in Ranked his LP (Shared.Ranks, against the enemies' rating) with the ladder told;
-- it is saved at once and sent to him (Net.MatchEnd "Result"), with every hero's line for the scoreboard. A player who leaves a match from the queue before its
-- end loses it. After the end "PlayAgain" sends the player back to the lobby and into the queue with his party,
-- "Menu" only back, and after Config.MatchEnd.Return seconds everyone still here goes back, each party together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Account = require(ReplicatedStorage.Shared.Account)
local Config = require(ReplicatedStorage.Shared.Config)
local Mastery = require(ReplicatedStorage.Shared.Mastery)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Places = require(ReplicatedStorage.Shared.Places)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local Actors = require(script.Parent.Actors)
local Ladder = require(script.Parent.Ladder)
local MatchService = require(script.Parent.MatchService)
local MatchSetup = require(script.Parent.MatchSetup)
local ProfileService = require(script.Parent.ProfileService)
local Remote = require(script.Parent.Remote)

local MatchEnd = {}

local SETTINGS = Config.Rewards

type Line = {
	actor: Instance,
	team: string,
	hero: string,
	kills: number,
	deaths: number,
	assists: number,
	damage: number,
	score: number,
	grade: string,
}

local event: RemoteEvent
local results: { [number]: any } = {}
-- Who has had his result or his loss, so nobody is paid twice.
local settled: { [number]: boolean } = {}
local over = false
local leaving: { [Player]: boolean } = {}

local function count(actor: Instance, key: string): number
	return tonumber(actor:GetAttribute(key)) or 0
end

local function heroOf(actor: Instance): string
	local character = Actors.character(actor)
	local hero = character and character:GetAttribute("Hero") or actor:GetAttribute("Hero")
	return if typeof(hero) == "string" and Config.Heroes[hero] then hero else Config.DefaultHero
end

local function gradeOf(score: number): string
	for _, step in SETTINGS.Grades do
		if score >= step[2] then
			return step[1]
		end
	end
	return "D-"
end

-- Every hero's line, and the MVP among the winners.
local function lines(winner: string): ({ Line }, Line?)
	local totals: { [string]: { hero: number, master: number } } = {}
	local actors = Actors.all()
	for _, actor in actors do
		local team = actor:GetAttribute("Team")
		if typeof(team) == "string" then
			totals[team] = totals[team] or { hero = 0, master = 0 }
			totals[team].hero += count(actor, "HeroDamage")
			totals[team].master += count(actor, "MasterDamage")
		end
	end
	local list: { Line } = {}
	local mvp: Line? = nil
	local weights = SETTINGS.Score
	for _, actor in actors do
		local team = actor:GetAttribute("Team")
		if typeof(team) == "string" then
			local total = totals[team]
			local damage = count(actor, "HeroDamage")
			local share = if total.hero > 0 then damage / total.hero else 0
			local masterShare = if total.master > 0 then count(actor, "MasterDamage") / total.master else 0
			local score = count(actor, "Kills") * weights.Kill
				+ count(actor, "Assists") * weights.Assist
				+ count(actor, "Deaths") * weights.Death
				+ share * weights.Damage
				+ masterShare * weights.Master
				+ count(actor, "Crowns") * weights.Crown
			local line: Line = {
				actor = actor,
				team = team,
				hero = heroOf(actor),
				kills = count(actor, "Kills"),
				deaths = count(actor, "Deaths"),
				assists = count(actor, "Assists"),
				damage = math.round(damage),
				score = score,
				grade = gradeOf(score),
			}
			table.insert(list, line)
			if team == winner and score > 0 and (not mvp or score > mvp.score) then
				mvp = line
			end
		end
	end
	return list, mvp
end

-- The average rating of `player`'s enemies who are players; his own when they are all bots.
local function against(player: Player, data: Profile.Data): number
	local team = player:GetAttribute("Team")
	local sum, n = 0, 0
	for _, other in Players:GetPlayers() do
		local theirs = other:GetAttribute("Team")
		local otherData = ProfileService.get(other)
		if theirs and theirs ~= team and otherData then
			sum += otherData.Rank.Rating
			n += 1
		end
	end
	return if n > 0 then sum / n else data.Rank.Rating
end

local function rankView(rank: any): any
	return { tier = rank.Tier, division = rank.Division, lp = rank.Lp }
end

-- Pays `player` for the match and saves it; returns what he got, for his screen.
local function reward(player: Player, line: Line?, won: boolean, mvp: boolean): any
	local key = if won then "Win" else "Loss"
	local grade = if line then line.grade else "D-"
	local coins = SETTINGS.Coins[key] + (SETTINGS.GradeCoins[string.sub(grade, 1, 1)] or 0)
	local ranked = MatchSetup.mode() == "Ranked"
	return ProfileService.update(player, function(data)
		local boosted = data.Pass.BoostUntil > os.time()
		local times = if boosted then 2 else 1
		local accountXp = SETTINGS.AccountXp[key] * times
		local passXp = SETTINGS.PassXp[key] * times
		local accountBefore = Account.level(data.Xp)
		local passBefore = Pass.level(data.Pass.Xp)
		local rankBefore = rankView(data.Rank)
		local change: Ranks.Change? = nil
		if ranked then
			change = Ranks.apply(data.Rank, won, against(player, data))
		end
		data.Coins += coins
		data.Xp += accountXp
		data.Pass.Xp += passXp
		data.Stats.Games += 1
		if won then
			data.Stats.Wins += 1
		end
		if line then
			data.Stats.Kills += line.kills
			data.Stats.Deaths += line.deaths
			data.Stats.Assists += line.assists
		end
		if mvp then
			data.Stats.Mvps += 1
		end
		local hero = if line then line.hero else heroOf(player)
		local entry = Mastery.entry(data, hero)
		local gain = Mastery.play(entry, grade, won)
		local accountLevel, accountInto, accountNeed = Account.level(data.Xp)
		local passLevel, passInto, passNeed = Pass.level(data.Pass.Xp)
		return {
			coins = coins,
			accountXp = accountXp,
			passXp = passXp,
			boosted = boosted,
			accountBefore = accountBefore,
			account = { level = accountLevel, into = accountInto, need = accountNeed },
			passBefore = passBefore,
			pass = { level = passLevel, into = passInto, need = passNeed },
			ranked = ranked,
			rankBefore = rankBefore,
			rank = rankView(data.Rank),
			lp = if change then change.lp else 0,
			promoted = change ~= nil and change.promoted,
			demoted = change ~= nil and change.demoted,
			placing = change ~= nil and change.placing,
			placed = change ~= nil and change.placed,
			placements = data.Rank.Placements,
			mastery = {
				hero = hero,
				points = gain.points,
				levelBefore = gain.levelBefore,
				marks = gain.marks,
				milestone = gain.milestone,
				view = Mastery.view(entry),
			},
		}
	end)
end

-- `player`'s mastery level of `hero`, for the others to see.
local function masteryOf(player: Player, hero: string): number?
	local data = ProfileService.get(player)
	local entry = data and data.Mastery and data.Mastery[hero]
	return if entry then entry.Level else nil
end

-- Every hero's line as the clients show it: by team, the winners first, each team by its score.
local function board(list: { Line }, winner: string, mvp: Line?): { any }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		if a.team ~= b.team then
			return a.team == winner
		end
		return a.score > b.score
	end)
	local rows = {}
	for _, line in sorted do
		local human = line.actor:IsA("Player")
		local player = line.actor :: Player
		table.insert(rows, {
			userId = if human then player.UserId else 0,
			name = if human then player.DisplayName else "Bot",
			team = line.team,
			hero = line.hero,
			kills = line.kills,
			deaths = line.deaths,
			assists = line.assists,
			damage = line.damage,
			grade = line.grade,
			mvp = line == mvp,
			shown = if human then player:GetAttribute("RankShown") else nil,
			division = if human then player:GetAttribute("RankDivision") else nil,
			mastery = if human then masteryOf(player, line.hero) else nil,
		})
	end
	return rows
end

local function finish(winner: string)
	over = true
	local list, mvp = lines(winner)
	local started = Workspace:GetAttribute("MatchStart") or Workspace:GetServerTimeNow()
	local ended = Workspace:GetAttribute("MatchEnd") or Workspace:GetServerTimeNow()
	local base: any = {
		winner = winner,
		mode = MatchSetup.mode(),
		score = {
			Blue = Workspace:GetAttribute("ScoreBlue") or 0,
			Red = Workspace:GetAttribute("ScoreRed") or 0,
		},
		duration = math.max(0, ended - started),
		mvpName = if mvp
			then (if mvp.actor:IsA("Player") then (mvp.actor :: Player).DisplayName else mvp.hero)
			else nil,
		mvpHero = if mvp then mvp.hero else nil,
		returnAt = Workspace:GetServerTimeNow() + Config.MatchEnd.Return,
	}
	-- Everyone is paid first, so the board shows each player's mastery after this match.
	local paid: { { player: Player, line: Line?, team: string, won: boolean, mvp: boolean, got: any } } = {}
	for _, player in Players:GetPlayers() do
		if not settled[player.UserId] then
			settled[player.UserId] = true
			local line: Line? = nil
			for _, l in list do
				if l.actor == player then
					line = l
				end
			end
			local team = player:GetAttribute("Team") or "Blue"
			local won = team == winner
			local isMvp = mvp ~= nil and mvp.actor == player
			local got = reward(player, line, won, isMvp)
			local data = ProfileService.get(player)
			if got and got.ranked and data then
				Ladder.submit(player, data.Rank)
			end
			table.insert(paid, { player = player, line = line, team = team, won = won, mvp = isMvp, got = got })
		end
	end
	base.players = board(list, winner, mvp)
	for _, entry in paid do
		local player, line = entry.player, entry.line
		local result = table.clone(base)
		result.team = entry.team
		result.won = entry.won
		result.mvp = entry.mvp
		result.hero = if line then line.hero else heroOf(player)
		result.kills = if line then line.kills else 0
		result.deaths = if line then line.deaths else 0
		result.assists = if line then line.assists else 0
		result.damage = if line then line.damage else 0
		result.grade = if line then line.grade else "D-"
		result.rewards = entry.got
		results[player.UserId] = result
		event:FireClient(player, "Result", result)
	end
end

-- A player who leaves a match from the queue before its end loses it, in Ranked as well.
local function left(player: Player, data: Profile.Data)
	if over or settled[player.UserId] or not MatchSetup.queued() then
		return
	end
	local phase = Workspace:GetAttribute("Phase")
	if phase ~= "Draft" and phase ~= "Ready" and phase ~= "Buy" and phase ~= "Fight" then
		return
	end
	settled[player.UserId] = true
	data.Stats.Games += 1
	if MatchSetup.mode() == "Ranked" then
		Ranks.apply(data.Rank, false, against(player, data))
		Ladder.submit(player, data.Rank)
	end
end

-- Sends `players` (one party) back to the lobby together; with `again` the party queues again in `mode`.
local function back(players: { Player }, again: boolean)
	if #players == 0 then
		return
	end
	if not Places.canTeleport() then
		for _, player in players do
			event:FireClient(
				player,
				"Notice",
				"Going back to the lobby only works in the published game: in Studio, play the lobby place itself."
			)
		end
		return
	end
	local ids = {}
	for _, player in players do
		leaving[player] = true
	end
	local party = MatchSetup.partyOf(players[1].UserId)
	for _, id in party do
		table.insert(ids, id)
	end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		party = party[1],
		members = ids,
		again = if again then MatchSetup.mode() else nil,
	})
	for attempt = 1, 3 do
		local ok, err =
			pcall(TeleportService.TeleportAsync, TeleportService, Config.Places.Lobby :: number, players, options)
		if ok then
			return
		end
		warn("[MatchEnd] teleport failed:", err)
		task.wait(attempt * 2)
	end
	for _, player in players do
		leaving[player] = nil
		event:FireClient(player, "Notice", "Could not go back to the lobby. Try again.")
	end
end

-- Everyone still here back to the lobby, each party in one go.
local function sendAll()
	local groups: { [number]: { Player } } = {}
	for _, player in Players:GetPlayers() do
		if not leaving[player] then
			local key = MatchSetup.partyOf(player.UserId)[1]
			groups[key] = groups[key] or {}
			table.insert(groups[key], player)
		end
	end
	for _, group in groups do
		task.spawn(back, group, false)
	end
end

function MatchEnd.start()
	event = Remote.event("MatchEnd", 2, function(player, action)
		if action == "Hello" then
			if results[player.UserId] then
				event:FireClient(player, "Result", results[player.UserId])
			end
		elseif over and not leaving[player] and (action == "PlayAgain" or action == "Menu") then
			back({ player }, action == "PlayAgain")
		end
	end)
	MatchService.onFinished(function(winner)
		finish(winner)
		task.wait(Config.MatchEnd.Return)
		sendAll()
	end)
	ProfileService.onLeaving(left)
	TeleportService.TeleportInitFailed:Connect(function(player)
		if leaving[player] then
			leaving[player] = nil
			event:FireClient(player, "Notice", "Could not go back to the lobby. Try again.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = nil
	end)
end

return MatchEnd
