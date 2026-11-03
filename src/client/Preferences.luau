-- The player's settings (design 17, Shared.Profile's Settings) at work: the sound groups in SoundService ("Music",
-- "Effects", "Interface", each at Master times its own volume; the menu's music only with MenuMusic on), the shadows,
-- whether damage numbers show, and the mouse's speed on the camera. The saved settings come from the profile
-- (ProfileClient); the settings page may try values first (Preferences.preview) before it saves them.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.ProfileClient)

local Preferences = {}

local GROUPS = { "Music", "Effects", "Interface" }
-- The effects an announcement never sinks (healing, owner 2026-11-01): as loud as the effects are set, never ducked.
local STEADY = "EffectsSteady"
Preferences.STEADY = STEADY

local current: Profile.Settings = Profile.defaultSettings()
local changed = Instance.new("BindableEvent")
-- How loud the music and the effects play beside the interface's sounds (Preferences.duck).
local duck = 1

-- The sound group `name` ("Music", "Effects" or "Interface"), made the first time it is asked for.
function Preferences.group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Parent = SoundService
	return group
end

local function setVolumes()
	local lobby = Workspace:GetAttribute("Role") == "Lobby"
	for _, name in GROUPS do
		local own = (current :: any)[name] or 1
		local volume = current.Master * own
		if name == "Music" and lobby and not current.MenuMusic then
			volume = 0
		end
		if name == "Effects" then
			Preferences.group(STEADY).Volume = volume
		end
		if name ~= "Interface" then
			volume *= duck
		end
		Preferences.group(name).Volume = volume
	end
end

local function apply(values: Profile.Settings)
	current = values
	setVolumes()
	Lighting.GlobalShadows = values.Shadows
	changed:Fire(values)
end

-- Plays the music and the effects at `level` (0 to 1) of their set volume, so an interface sound stands out above
-- them (UiSound.announce); 1 again when it is over.
function Preferences.duck(level: number)
	duck = level
	setVolumes()
end

-- The setting `key` as it is now (previewed or saved).
function Preferences.get(key: string): any
	return (current :: any)[key]
end

-- How many times the usual speed the mouse turns the camera (HeroCamera): the Sensitivity slider (0 to 1) from 0.1
-- at its left over 1 in its middle to 3 at its right.
function Preferences.sensitivity(slider: number?): number
	local v = slider or current.Sensitivity
	return if v <= 0.5 then 0.1 + 0.9 * v / 0.5 else 1 + 2 * (v - 0.5) / 0.5
end

-- Runs `callback` whenever a setting changes.
function Preferences.onChanged(callback: (values: Profile.Settings) -> ()): RBXScriptConnection
	return changed.Event:Connect(callback)
end

-- Uses `values` without saving them; the saved ones come back with Preferences.restore.
function Preferences.preview(values: Profile.Settings)
	apply(values)
end

-- Goes back to the saved settings.
function Preferences.restore()
	local data = ProfileClient.get()
	apply(if data then data.Settings else Profile.defaultSettings())
end

function Preferences.start()
	for _, name in GROUPS do
		Preferences.group(name)
	end
	apply(Profile.defaultSettings())
	ProfileClient.watch(function(data)
		local merged = Profile.defaultSettings() :: any
		for key, value in data.Settings :: any do
			if typeof(value) == typeof(merged[key]) then
				merged[key] = value
			end
		end
		apply(merged)
	end)
end

return Preferences
