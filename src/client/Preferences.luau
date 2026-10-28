-- The player's settings (design 17, Shared.Profile's Settings) at work: the sound groups in SoundService ("Music",
-- "Effects", "Interface", each at Master times its own volume; the menu's music only with MenuMusic on), the shadows,
-- and whether damage numbers show. The saved settings come from the profile (ProfileClient); the settings page may
-- try values first (Preferences.preview) before it saves them.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.ProfileClient)

local Preferences = {}

local GROUPS = { "Music", "Effects", "Interface" }

local current: Profile.Settings = Profile.defaultSettings()
local changed = Instance.new("BindableEvent")

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

local function apply(values: Profile.Settings)
	current = values
	local lobby = Workspace:GetAttribute("Role") == "Lobby"
	for _, name in GROUPS do
		local own = (values :: any)[name] or 1
		local volume = values.Master * own
		if name == "Music" and lobby and not values.MenuMusic then
			volume = 0
		end
		Preferences.group(name).Volume = volume
	end
	Lighting.GlobalShadows = values.Shadows
	changed:Fire(values)
end

-- The setting `key` as it is now (previewed or saved).
function Preferences.get(key: string): any
	return (current :: any)[key]
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
