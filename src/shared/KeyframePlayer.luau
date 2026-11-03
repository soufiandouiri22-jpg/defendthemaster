-- The player of a pack that comes as KeyframeSequences (the Elementalist), made by Tools/keyframe_pack.py into a
-- ComponentPlayer as the newer packs have: its Sample gives Shared.Motion the same pose of a clip at a time, every body
-- joint's Transform as on the pack's rig, and its weapon as a prop, always shown: the Transform of the joint it hangs
-- from in the pack, on a hand (its Configuration's `weapon`), where HeroLook binds it to the hero's own hand. A pack
-- without a weapon (the Dance Collection) gives the body alone.

local HttpService = game:GetService("HttpService")

type Track = { frames: { CFrame }, constant: { boolean }? }
type Clip = { meta: any, times: { number }, tracks: { [string]: Track } }

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SIXES: { [number]: number } = {}
for i = 1, #ALPHABET do
	SIXES[string.byte(ALPHABET, i)] = i - 1
end

-- The float32s of a base64 string (Tools/keyframe_pack.py).
local function floats(text: string): { number }
	local padding = if text:sub(-2) == "==" then 2 elseif text:sub(-1) == "=" then 1 else 0
	local bytes = buffer.create(#text // 4 * 3 - padding)
	local at = 0
	for i = 1, #text, 4 do
		local a, b, c, d = string.byte(text, i, i + 3)
		local n = SIXES[a] * 262144 + SIXES[b] * 4096 + (SIXES[c] or 0) * 64 + (SIXES[d] or 0)
		for shift = 16, 0, -8 do
			if at < buffer.len(bytes) then
				buffer.writeu8(bytes, at, bit32.band(bit32.rshift(n, shift), 255))
				at += 1
			end
		end
	end
	local out = table.create(buffer.len(bytes) // 4)
	for i = 0, buffer.len(bytes) - 4, 4 do
		table.insert(out, buffer.readf32(bytes, i))
	end
	return out
end

return function(module: ModuleScript)
	local config = HttpService:JSONDecode((module:WaitForChild("Configuration") :: StringValue).Value)
	local data = require(module:WaitForChild("Data")) :: any
	local weapon = config.weapon
	local parts = {}
	for _, j in config.body_joints do
		table.insert(parts, j.part1)
	end

	local cache: { [string]: Clip } = {}
	local function clip(id: string): Clip
		local found = cache[id]
		if found then
			return found
		end
		local raw = data[id]
		assert(raw, "Unknown motion: " .. tostring(id))
		local tracks = {}
		for part, track in raw.tracks do
			local frames = {}
			local values = floats(track.values)
			for i = 1, #values, 7 do
				local x, y, z = values[i], values[i + 1], values[i + 2]
				local qx, qy, qz, qw = values[i + 3], values[i + 4], values[i + 5], values[i + 6]
				table.insert(frames, CFrame.new(x, y, z, qx, qy, qz, qw))
			end
			tracks[part] = { frames = frames, constant = track.constant }
		end
		found = { meta = raw.meta, times = floats(raw.times), tracks = tracks }
		cache[id] = found
		return found
	end

	-- The keyframe at or before `t` and the share of the way to the next.
	local function locate(times: { number }, t: number): (number, number)
		local count = #times
		if t <= times[1] then
			return 1, 0
		elseif t >= times[count] then
			return count, 0
		end
		local low, high = 1, count
		while high - low > 1 do
			local middle = (low + high) // 2
			if times[middle] <= t then
				low = middle
			else
				high = middle
			end
		end
		return low, (t - times[low]) / (times[high] - times[low])
	end

	local Player = {}

	function Player.Sample(_: any, id: string, time: number)
		local c = clip(id)
		local index, alpha = locate(c.times, time)
		local pose: { [string]: CFrame } = {}
		for part, track in c.tracks do
			local a = track.frames[index]
			local b = track.frames[index + 1]
			if b and alpha > 0 and not (track.constant and track.constant[index]) then
				pose[part] = a:Lerp(b, alpha)
			else
				pose[part] = a
			end
		end
		local body = {}
		for _, part in parts do
			body[part] = pose[part] or CFrame.identity
		end
		local props, opacity = {}, {}
		if weapon then
			props[weapon.name] = { world = pose[weapon.name] or CFrame.identity, scale = Vector3.one }
			opacity[weapon.name] = 1
		end
		return {
			body = body,
			props = props,
			bones = {},
			opacity = opacity,
			body_opacity = 1,
			time = time,
		},
			c.meta
	end

	return Player
end
