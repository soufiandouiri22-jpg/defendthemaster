-- A hero's sounds from its animation pack's sound add-on (Shared.PackSounds.<Pack>, made by Tools/hero_sounds.py): every
-- recording sits in one uploaded file and plays as its own region of it, from the hero's root part so it is heard
-- where the hero is. The clips' cues come through Shared.Motion; the game's own events (a dagger let go) through
-- HeroSounds.event.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeroSounds = {}

local VOLUME = 1
-- Heard at full strength within this many studs, fading out to nothing at the far one.
local NEAR = 14
local FAR = 160

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
			local probe = Instance.new("Sound")
			probe.SoundId = bank.Asset
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
	sound.Volume = volume * VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = NEAR
	sound.RollOffMaxDistance = FAR
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, region[2] + 0.5)
end

-- Plays a clip's cue on `character`: one of its recordings, or the next footstep.
function HeroSounds.cue(character: Model, bank: Bank, cue: any)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local choices = cue.Sounds
	if cue.Footstep then
		local next = (contact[character] or 0) % #bank.Footsteps + 1
		contact[character] = next
		choices = bank.Footsteps[next]
	end
	if choices and #choices > 0 then
		play(root, bank, choices[math.random(#choices)], cue.Volume)
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

function HeroSounds.forget(character: Model)
	contact[character] = nil
end

return HeroSounds
