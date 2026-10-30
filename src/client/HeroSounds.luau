-- A hero's sounds from its animation pack's sound add-on (Shared.PackSounds.<Pack>, made by Tools/hero_sounds.py): every
-- recording sits in one uploaded file and plays as its own region of it, from the hero's root part so it is heard
-- where the hero is. The clips' cues come through Shared.Motion; the game's own events (a dagger let go) through
-- HeroSounds.event. Roblox's own character sounds (its death voice, plastic footsteps, jumps and landings) are turned
-- off, so the heroes sound only as their packs do.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Preferences = require(script.Parent.Preferences)

local HeroSounds = {}

local VOLUME = 1
-- Other heroes sound this much softer than the player's own, so he hears above all what he does.
local OTHERS = 0.6
-- Heard at full strength within this many studs, fading out to nothing at the far one: about what is on screen.
local NEAR = 14
local FAR = 80

export type Bank = {
	Asset: string,
	Regions: { [string]: { number } },
	Cues: { [string]: { any } },
	Footsteps: { { string } },
	Events: { [string]: { Sounds: { string }, Volume: number } },
}

local banks: { [string]: Bank | false } = {}
local contact: { [Instance]: number } = {}

-- The sound bank of the pack `name`, or nil when it has none (yet).
function HeroSounds.bank(name: string): Bank?
	if banks[name] == nil then
		local module = ReplicatedStorage.Shared:FindFirstChild("PackSounds")
		module = module and module:FindFirstChild(name)
		local bank = if module then require(module) :: any else false
		banks[name] = bank
		if bank then
			-- Kept for the whole session: while one Sound holds the file it stays loaded, and every recording
			-- played from it sounds at once instead of waiting for the file again (or not at all).
			local probe = Instance.new("Sound")
			probe.Name = `{name}Sounds`
			probe.SoundId = bank.Asset
			probe.Volume = 0
			probe.Parent = SoundService
			task.spawn(ContentProvider.PreloadAsync, ContentProvider, { probe })
		end
	end
	return banks[name] or nil
end

local function play(root: BasePart, bank: Bank, id: string, volume: number)
	local region = bank.Regions[id]
	if not region then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = bank.Asset
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
	local own = root.Parent ~= nil and root.Parent == Players.LocalPlayer.Character
	sound.Volume = volume * VOLUME * (if own then 1 else OTHERS)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = NEAR
	sound.RollOffMaxDistance = FAR
	sound.SoundGroup = Preferences.group("Effects")
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, region[2] + 0.5)
end

-- Plays `walker`'s next footstep on the sand from `at`, its contacts alternating.
function HeroSounds.step(walker: Instance, at: BasePart, bank: Bank, volume: number)
	local next = (contact[walker] or 0) % #bank.Footsteps + 1
	contact[walker] = next
	local choices = bank.Footsteps[next]
	if choices and #choices > 0 then
		play(at, bank, choices[math.random(#choices)], volume)
	end
end

-- Plays a clip's cue on `character`: one of its recordings, or the next footstep.
function HeroSounds.cue(character: Model, bank: Bank, cue: any)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if cue.Footstep then
		HeroSounds.step(character, root, bank, cue.Volume)
	elseif cue.Sounds and #cue.Sounds > 0 then
		play(root, bank, cue.Sounds[math.random(#cue.Sounds)], cue.Volume)
	end
end

-- Plays the sound of the game's event `name` (Events in the bank) on `character`.
function HeroSounds.event(character: Model, packName: string, name: string)
	local bank = HeroSounds.bank(packName)
	local event = bank and bank.Events[name]
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if bank and event and root then
		play(root, bank, event.Sounds[math.random(#event.Sounds)], event.Volume)
	end
end

function HeroSounds.forget(walker: Instance)
	contact[walker] = nil
end

-- Whether `sound` is one of Roblox's own character sounds (its death cry, jumps, falls, splashes).
local function roblox(sound: Instance): boolean
	return sound:IsA("Sound") and string.find(sound.SoundId, "rbxasset://sounds/", 1, true) == 1
end

-- Takes `sound` away when it is, or becomes, one of Roblox's character sounds.
local function silence(sound: Instance)
	if not sound:IsA("Sound") then
		return
	end
	if roblox(sound) then
		sound:Destroy()
		return
	end
	local changed
	changed = sound:GetPropertyChangedSignal("SoundId"):Connect(function()
		if roblox(sound) then
			changed:Disconnect()
			sound:Destroy()
		end
	end)
	sound.AncestryChanged:Once(function()
		changed:Disconnect()
	end)
end

-- Stops Roblox's RbxCharacterSounds, and keeps every Roblox character sound off for the whole session: those it
-- already gave the characters, and any that come later (a respawn, a bot, a moment before the script was stopped),
-- so the default death cry never sounds (owner, 2026-10-29). A script of that name in StarterPlayerScripts no
-- longer stands in for it: Roblox puts its own back.
function HeroSounds.start()
	Workspace.DescendantAdded:Connect(function(added)
		if added:IsA("Sound") then
			task.defer(silence, added)
		end
	end)
	for _, sound in Workspace:GetDescendants() do
		if roblox(sound) then
			sound:Destroy()
		end
	end
	task.spawn(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
		local script = scripts:WaitForChild("RbxCharacterSounds", 10)
		if script and script:IsA("LocalScript") then
			script.Enabled = false
		end
		for _, sound in Workspace:GetDescendants() do
			if roblox(sound) then
				sound:Destroy()
			end
		end
	end)
end

return HeroSounds
