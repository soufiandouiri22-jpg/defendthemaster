-- The music: one track looped under the game's sounds, in the "Music" SoundGroup (Preferences), so the settings turn
-- it up or down; in the lobby the menu's own track (Assets.MenuMusic, faded in the first time), which the menu music
-- setting turns off, in a match the match's (Assets.Music) until the match ends: then it fades out and stays out, so
-- the VICTORY or DEFEAT sting and the results have their quiet moment (MatchEndView). Silent on Studio's test ground
-- (the Workspace attribute "TestGround", server TestGround). The track downloads under the loading screen, which waits
-- for it (Loading.need), and starts the moment the screen goes (Loading.waitGone).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Preferences = require(script.Parent.Preferences)

local Music = {}

local VOLUME = 0.18
local FADE_IN = 1.5

local track: Sound? = nil

function Music.start()
	if RunService:IsStudio() and Workspace:GetAttribute("TestGround") == true then
		return
	end
	local lobby = Workspace:GetAttribute("Role") == "Lobby"
	local group = Preferences.group("Music")
	local sound = Instance.new("Sound")
	sound.Name = if lobby then "MenuMusic" else "MatchMusic"
	sound.SoundId = if lobby then Assets.MenuMusic else Assets.Music
	sound.Looped = true
	sound.Volume = if lobby then 0 else VOLUME
	sound.SoundGroup = group
	sound.Parent = group
	track = sound
	Loading.need(sound)
	task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { sound })
	task.spawn(function()
		Loading.waitGone()
		if track ~= sound then
			return
		end
		sound:Play()
		if lobby then
			TweenService:Create(sound, TweenInfo.new(FADE_IN), { Volume = VOLUME }):Play()
		end
	end)
end

-- Fades the music out over `seconds` and leaves it off.
function Music.stop(seconds: number)
	local sound = track
	if not sound then
		return
	end
	track = nil
	local fade = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = 0 })
	fade.Completed:Connect(function()
		sound:Destroy()
	end)
	fade:Play()
end

return Music
