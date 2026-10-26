-- The heroes' levels (Config.Progress, Shared.Leveling): XP when enemies die nearby, a level-up raising the hero's
-- health, and the points a player spends on ranks through ReplicatedStorage.Net.Upgrade (the ability's key). A hero's
-- death scores for the other team, and its killing blow (the last player to hurt him, within KillCredit seconds) earns
-- the bounty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Economy = require(script.Parent.Economy)
local MatchService = require(script.Parent.MatchService)

local SETTINGS = Config.Progress

local ProgressService = {}

local credit: { [Model]: { player: Player, at: number } } = {}

local function living(character: Model?): (Humanoid?, BasePart?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

-- Sets the player's hero's health to its level, healing it by what the level adds.
function ProgressService.refresh(player: Player)
	local character = player.Character
	local hero = character and character:GetAttribute("Hero")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hero or not humanoid then
		return
	end
	local max = Leveling.maxHealth(Config.Heroes[hero].Health, Leveling.level(player))
	local gain = max - humanoid.MaxHealth
	humanoid.MaxHealth = max
	if humanoid.Health > 0 then
		humanoid.Health = math.min(max, humanoid.Health + math.max(gain, 0))
	end
end

function ProgressService.give(player: Player, xp: number)
	local level = Leveling.level(player)
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
local function share(team: string, position: Vector3, xp: number, killer: Player?)
	local takers = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
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
		and killer.Character
		and killer.Character:GetAttribute("Team") == team
	then
		table.insert(takers, killer)
	end
	for _, player in takers do
		ProgressService.give(player, xp / #takers)
	end
end

-- A minion of `team` died at `position`.
function ProgressService.minionDied(team: string, kind: string, position: Vector3, killer: Player?)
	share(MatchService.enemyOf(team), position, SETTINGS.MinionXp[kind] or 0, killer)
end

-- `player` hurt the hero `victim`.
function ProgressService.hurt(victim: Model, player: Player)
	credit[victim] = { player = player, at = os.clock() }
end

-- The hero `character` of `player` died at `position`.
function ProgressService.heroDied(character: Model, player: Player, position: Vector3)
	local enemy = MatchService.enemyOf(character:GetAttribute("Team") or "Blue")
	MatchService.scored(enemy)
	local last = credit[character]
	credit[character] = nil
	local killer = if last
			and os.clock() - last.at <= SETTINGS.KillCredit
			and last.player.Parent
		then last.player
		else nil
	if killer then
		Economy.give(killer, Config.Economy.HeroBounty, "killed " .. player.Name)
	end
	share(enemy, position, SETTINGS.HeroXp + SETTINGS.HeroXpPerLevel * (Leveling.level(player) - 1), killer)
end

function ProgressService.start()
	local function join(player: Player)
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
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end

	local net = ReplicatedStorage:FindFirstChild("Net") or Instance.new("Folder")
	net.Name = "Net"
	net.Parent = ReplicatedStorage
	local upgrade = Instance.new("RemoteEvent")
	upgrade.Name = "Upgrade"
	upgrade.Parent = net
	upgrade.OnServerEvent:Connect(function(player, key)
		if typeof(key) ~= "string" or not Leveling.canRaise(player, key) then
			return
		end
		player:SetAttribute("Rank" .. key, Leveling.rank(player, key) + 1)
		player:SetAttribute("Points", player:GetAttribute("Points") - 1)
	end)
end

return ProgressService
