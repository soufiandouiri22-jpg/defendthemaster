-- The match music: one track looped under the game's sounds, in the "Music" SoundGroup so a volume setting can turn
-- it up or down later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Music = {}

local VOLUME = 0.18

function Music.start()
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
