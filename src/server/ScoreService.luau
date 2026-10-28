-- What the scoreboard (the client's Scoreboard) shows of every hero: ReplicatedStorage.Scores holds a Configuration
-- per player or bot (Actors), so every client sees the bots as well, whose own attributes stay on the server. Each
-- carries "Name" (the player's display name, "" for a bot), "Player" (his UserId, 0 for a bot), "Order" (when he
-- joined, which keeps the rows in place), "Team", "Hero", "Level", "Kills", "Deaths" and "Assists"
-- (ProgressService), his bag ("Item" .. n and "Count" .. n, Shared.Items) and "RespawnAt" while his hero is dead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Actors = require(script.Parent.Actors)

local ScoreService = {}

local EVERY = 0.25

local entries: { [Instance]: Configuration } = {}
local joined = 0

local function sync(folder: Folder)
	local seen = {}
	for _, actor in Actors.all() do
		seen[actor] = true
		local entry = entries[actor]
		if not entry then
			joined += 1
			local made = Instance.new("Configuration")
			made.Name = actor.Name
			made:SetAttribute("Order", joined)
			made:SetAttribute("Name", if actor:IsA("Player") then actor.DisplayName else "")
			made:SetAttribute("Player", if actor:IsA("Player") then actor.UserId else 0)
			made.Parent = folder
			entries[actor] = made
			entry = made
		end
		local character = Actors.character(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local team = character and character:GetAttribute("Team") or actor:GetAttribute("Team")
		if team then
			entry:SetAttribute("Team", team)
		end
		entry:SetAttribute("Hero", character and character:GetAttribute("Hero") or Config.DefaultHero)
		entry:SetAttribute("Level", Leveling.level(actor :: any))
		for _, key in { "Kills", "Deaths", "Assists" } do
			entry:SetAttribute(key, actor:GetAttribute(key) or 0)
		end
		for n = 1, Config.Shop.Slots do
			entry:SetAttribute("Item" .. n, actor:GetAttribute("Item" .. n) or "")
			entry:SetAttribute("Count" .. n, actor:GetAttribute("Count" .. n))
		end
		local dead = character ~= nil and (humanoid == nil or humanoid.Health <= 0)
		entry:SetAttribute("RespawnAt", if dead and character then character:GetAttribute("RespawnAt") else nil)
	end
	for actor, entry in entries do
		if not seen[actor] then
			entry:Destroy()
			entries[actor] = nil
		end
	end
end

function ScoreService.start()
	local folder = Instance.new("Folder")
	folder.Name = "Scores"
	folder.Parent = ReplicatedStorage
	task.spawn(function()
		while true do
			sync(folder)
			task.wait(EVERY)
		end
	end)
end

return ScoreService
