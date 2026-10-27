-- The heroes' levels (Config.Progress, Shared.Leveling): XP when enemies die nearby, a level-up raising the hero's
-- health, and the points a player spends on ranks through ReplicatedStorage.Net.Upgrade (the ability's key). A hero's
-- death scores for the other team, and its killing blow (the last player to hurt him, within KillCredit seconds) earns
-- the bounty, and the other enemies who hurt him within KillCredit seconds share the assist. Bots (Actors) level up the same way, and spend their points themselves (ProgressService.raise).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Economy = require(script.Parent.Economy)
local Actors = require(script.Parent.Actors)
local MatchService = require(script.Parent.MatchService)

local SETTINGS = Config.Progress

local ProgressService = {}

-- Per hurt hero: who hurt him last, and when each enemy last did (os.clock).
local credit: { [Model]: { last: Instance, at: number, by: { [Instance]: number } } } = {}

local function living(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

-- Sets the hero's health to its level, healing it by what the level adds; the hero carries its level for the HUD.
function ProgressService.refresh(player: Instance)
	local character = Actors.character(player)
	local hero = character and character:GetAttribute("Hero")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not hero or not humanoid then
		return
	end
	character:SetAttribute("Level", Leveling.level(player :: any))
	local max = Leveling.maxHealth(Config.Heroes[hero].Health, Leveling.level(player :: any))
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

-- The hero `character` of `player` died at `position`. Returns how many seconds he stays dead; the hero carries when
-- he comes back (the "RespawnAt" attribute, in server time) for the HUD's countdown.
function ProgressService.heroDied(character: Model, player: Instance, position: Vector3): number
	local enemy = MatchService.enemyOf(character:GetAttribute("Team") or "Blue")
	MatchService.scored(enemy)
	local entry = credit[character]
	credit[character] = nil
	local now = os.clock()
	local killer = if entry and now - entry.at <= SETTINGS.KillCredit and entry.last.Parent then entry.last else nil
	local assists = {}
	for actor, at in if entry then entry.by else {} do
		if actor ~= killer and actor.Parent and now - at <= SETTINGS.KillCredit then
			table.insert(assists, actor)
		end
	end
	local worth = bounty(player)
	if killer then
		Economy.give(killer :: any, worth, "killed " .. player.Name)
		killer:SetAttribute("KillsSinceDeath", (killer:GetAttribute("KillsSinceDeath") or 0) + 1)
		killer:SetAttribute("DeathsSinceKill", 0)
	end
	for _, actor in assists do
		Economy.give(actor, math.round(worth * Config.Economy.Assist / #assists), "assist on " .. player.Name)
	end
	share(enemy, position, SETTINGS.HeroXp + SETTINGS.HeroXpPerLevel * (Leveling.level(player :: any) - 1), killer)
	player:SetAttribute("KillsSinceDeath", 0)
	player:SetAttribute("DeathsSinceKill", (player:GetAttribute("DeathsSinceKill") or 0) + 1)
	local wait = respawnTime(player)
	character:SetAttribute("RespawnAt", Workspace:GetServerTimeNow() + wait)
	return wait
end

-- A new player or bot starts at level 1 with every ability at rank 1.
function ProgressService.join(player: Instance)
	if player:GetAttribute("Level") ~= nil then
		return
	end
	player:SetAttribute("Level", 1)
	player:SetAttribute("Xp", 0)
	player:SetAttribute("Points", 0)
	for _, key in SETTINGS.Upgrades do
		player:SetAttribute("Rank" .. key, 1)
	end
end

-- Spends one of the hero's points on raising `key` a rank, if it can; whether it did.
function ProgressService.raise(player: Instance, key: string): boolean
	if not Leveling.canRaise(player :: any, key) then
		return false
	end
	player:SetAttribute("Rank" .. key, Leveling.rank(player :: any, key) + 1)
	player:SetAttribute("Points", (player:GetAttribute("Points") or 1) - 1)
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
