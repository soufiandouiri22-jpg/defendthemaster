-- The match music: one track looped under the game's sounds, in the "Music" SoundGroup so a volume setting can turn
-- it up or down later. Silent on Studio's test ground (the Workspace attribute "TestGround", server TestGround).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Music = {}

local VOLUME = 0.18

function Music.start()
	if RunService:IsStudio() and Workspace:GetAttribute("TestGround") == true then
		return
	end
	local group = Instance.new("SoundGroup")
	group.Name = "Music"
	group.Volume = 1
	group.Parent = SoundService
	local track = Instance.new("Sound")
	track.Name = "MatchMusic"
	track.SoundId = Assets.Music
	track.Looped = true
	track.Volume = VOLUME
	track.SoundGroup = group
	track.Parent = group
	track:Play()
end

return Music
