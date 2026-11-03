-- Every player sees his own team in blue and the other in red, whichever the server put him on (owner, 2026-11-02:
-- "altijd blauw zijn"); the server and every attribute keep the real teams. `Side.shown` is the team whose colours a
-- team takes on this screen, `Side.name` what it is called here ("ALLIES" and "ENEMIES" once the player has a team).
-- In the world the team pieces that come in both colours (the throne room's dais, throne and banner, the armory
-- stalls, the Master's shirt and cape) carry the other colour's texture in their "OtherTexture" attribute and the
-- "TeamSwap" tag (server ColosseumBuilder, MasterService): on a red player's screen they wear that one.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Side = {}

local OWN, OTHER = Config.TeamOrder[1], Config.TeamOrder[2]
-- How long a match's client waits for the server to put its player on a team before its views are built.
local WAIT = 6

local player = Players.LocalPlayer
-- The team a screen before the match (the lobby's cards of a found match) knows its player is on.
local told: string? = nil

-- The player's own team, nil before he has one.
function Side.own(): string?
	local team = player:GetAttribute("Team")
	if team == nil and player.Character then
		team = player.Character:GetAttribute("Team")
	end
	return team or told
end

-- Tells a screen without the "Team" attribute (the lobby) which team its player is on.
function Side.tell(team: string?)
	told = team
end

-- Whether this screen shows the teams the other way round: its player is on the second team.
function Side.swapped(): boolean
	return Side.own() == OTHER
end

-- The team whose colours `team` shows in on this screen.
function Side.shown(team: string?): string
	local real = team or OWN
	if Side.swapped() then
		return if real == OWN then OTHER else OWN
	end
	return real
end

-- The teams as this screen lists them: the player's own first, which shows in blue.
function Side.order(): { string }
	return if Side.swapped() then { OTHER, OWN } else { OWN, OTHER }
end

-- What `team` is called on this screen.
function Side.name(team: string): string
	local mine = Side.own()
	if not mine then
		return string.upper(Config.Teams[team].Name)
	end
	return if team == mine then "ALLIES" else "ENEMIES"
end

local function swap(instance: Instance)
	local other = instance:GetAttribute("OtherTexture")
	if type(other) ~= "string" or instance:GetAttribute("Swapped") then
		return
	end
	if instance:IsA("MeshPart") then
		instance:SetAttribute("Swapped", instance.TextureID)
		instance.TextureID = other
	elseif instance:IsA("SpecialMesh") then
		instance:SetAttribute("Swapped", instance.TextureId)
		instance.TextureId = other
	elseif instance:IsA("Shirt") then
		instance:SetAttribute("Swapped", instance.ShirtTemplate)
		instance.ShirtTemplate = other
	end
end

-- In a match: waits for the player's team, then dresses the world's team pieces in this screen's colours.
function Side.start()
	local started = os.clock()
	while Side.own() == nil and os.clock() - started < WAIT do
		task.wait(0.1)
	end
	if not Side.swapped() then
		return
	end
	CollectionService:GetInstanceAddedSignal("TeamSwap"):Connect(swap)
	for _, instance in CollectionService:GetTagged("TeamSwap") do
		swap(instance)
	end
end

return Side
