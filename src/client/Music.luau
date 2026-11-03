-- The music: one track looped under the game's sounds, in the "Music" SoundGroup (Preferences), so the settings turn
-- it up or down; in the lobby the menu's own track (Assets.MenuMusic, faded in the first time), which the menu music
-- setting turns off, in a match the match's (Assets.Music) until the match ends: then it fades out and stays out, so
-- the VICTORY or DEFEAT sting and the results have their quiet moment (MatchEndView). Silent on Studio's test ground
-- (the Workspace attribute "TestGround", server TestGround). The track downloads under the loading screen, which waits
-- for it (Loading.need), and starts the moment the screen goes (Loading.waitGone), or once a screen over it has gone
-- too (Music.hold: the match's cards, VersusView, which fade out after the loading screen went; owner, 2026-11-03).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Trace = require(ReplicatedFirst:WaitForChild("Trace"))
local Preferences = require(script.Parent.Preferences)

local Music = {}

local VOLUME = 0.18
-- Seconds the track fades in over, in the lobby and in a match (as the arena comes in sight, before the buy phase's
-- title, BuyPhase).
local FADE_IN, MATCH_FADE_IN = 1.5, 1.2
-- The longest a hold keeps the music back after the loading screen went, should what holds it never let go.
local HELD = 10

local track: Sound? = nil
local holds = 0

-- Keeps the music from starting until what it returns is called (at most HELD seconds after the loading screen).
function Music.hold(): () -> ()
	holds += 1
	local released = false
	return function()
		if not released then
			released = true
			holds -= 1
		end
	end
end

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
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = group
	track = sound
	Loading.need(sound)
	task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { sound })
	task.spawn(function()
		Loading.waitGone()
		local since = os.clock()
		while holds > 0 and os.clock() - since < HELD do
			task.wait(0.05)
		end
		if track ~= sound then
			return
		end
		Trace.mark("music.start", { name = sound.Name, held = math.floor((os.clock() - since) * 100) / 100 })
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(if lobby then FADE_IN else MATCH_FADE_IN), { Volume = VOLUME }):Play()
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
