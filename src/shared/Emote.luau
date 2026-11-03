-- Dances an emote (Config.Emotes) on a hero's Motion: its `Start` once if it has one, then its clip, over and over
-- unless it plays `Once`; in place, so he dances where he stands. Another clip played over him (an attack) ends it.

local Config = require(script.Parent.Config)
local Motion = require(script.Parent.Motion)

local SETTINGS = Config.Emotes
-- Seconds a dance takes to ease in from the pose he stands in, and out of it again.
local FADE = 0.3

Motion.lend(SETTINGS.Prefix, SETTINGS.Pack)

local Emote = {}
Emote.FADE = FADE

export type Dance = { motion: Motion.Motion, id: string, clip: string }

local function start(dance: Dance, clip: string)
	local emote = SETTINGS.List[dance.id]
	dance.clip = clip
	dance.motion:play(clip, 1, nil, true)
	if clip == emote.Motion and not emote.Once then
		dance.motion:keepPlaying()
	end
end

-- Starts emote `id` on `motion`, or nil when there is no such emote.
function Emote.dance(motion: Motion.Motion, id: string): Dance?
	local emote = SETTINGS.List[id]
	if not emote then
		return nil
	end
	local dance: Dance = { motion = motion, id = id, clip = "" }
	motion:crossfade(FADE)
	start(dance, emote.Start or emote.Motion)
	return dance
end

-- Moves `dance` from its start into its clip once the start has played; whether it still dances.
function Emote.going(dance: Dance): boolean
	local playing = dance.motion:playing()
	if playing == dance.clip then
		return true
	end
	local emote = SETTINGS.List[dance.id]
	if playing == nil and emote.Start and dance.clip == emote.Start then
		start(dance, emote.Motion)
		return true
	end
	return false
end

-- Ends `dance` if it still plays, fading back to the base.
function Emote.stop(dance: Dance)
	if dance.motion:playing() == dance.clip then
		dance.motion:crossfade(FADE)
		dance.motion:stop()
	end
end

return Emote
