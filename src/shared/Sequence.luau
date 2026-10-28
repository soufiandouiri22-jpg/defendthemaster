-- Plays a bought pack's KeyframeSequences (ReplicatedStorage[pack], Docs/Third_Party.md) straight on a character's
-- joints, so they need not be published as Roblox animations. A pack's rig (its "Rig" model) may have its joints'
-- frames turned otherwise than the character's (KitsBlox' "RobloxY180"): each pose is turned over to the character's
-- joint so every part takes the same turn as on the pack's rig, and its shifts grow with the character as Roblox's
-- animations do (its hip height over the hip height the pack was authored at, which the caller gives: a game script may
-- not read a KeyframeSequence's AuthoredHipHeight). Poses ease linearly between keyframes, or hold
-- (Constant), as the packs have them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sequence = {}

type Track = {
	times: { number },
	frames: { CFrame },
	hold: { boolean },
}

export type Clip = {
	duration: number,
	authoredHipHeight: number,
	tracks: { [string]: Track },
}

type Joint = {
	instance: Instance,
	before: CFrame,
	after: CFrame,
}

export type Rig = {
	joints: { [string]: Joint },
	shift: number,
}

local clips: { [Instance]: Clip } = {}

local function collect(pose: Instance, time: number, tracks: { [string]: Track })
	for _, child in pose:GetChildren() do
		if child:IsA("Pose") then
			local track = tracks[child.Name]
			if not track then
				track = { times = {}, frames = {}, hold = {} }
				tracks[child.Name] = track
			end
			table.insert(track.times, time)
			table.insert(track.frames, child.CFrame)
			table.insert(track.hold, child.EasingStyle == Enum.PoseEasingStyle.Constant)
			collect(child, time, tracks)
		end
	end
end

-- The poses of `sequence`, authored for a hip height of `authoredHipHeight`, per part, in time order.
function Sequence.load(sequence: KeyframeSequence, authoredHipHeight: number): Clip
	local cached = clips[sequence]
	if cached then
		return cached
	end
	local keyframes = {}
	for _, child in sequence:GetChildren() do
		if child:IsA("Keyframe") then
			table.insert(keyframes, child)
		end
	end
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)
	local tracks = {}
	for _, keyframe in keyframes do
		collect(keyframe, keyframe.Time, tracks)
	end
	local clip = {
		duration = if #keyframes > 0 then keyframes[#keyframes].Time else 0,
		authoredHipHeight = authoredHipHeight,
		tracks = tracks,
	}
	clips[sequence] = clip
	return clip
end

-- The clip `name` of the pack `pack`, authored for a hip height of `authoredHipHeight`.
function Sequence.clip(pack: string, name: string, authoredHipHeight: number): Clip
	return Sequence.load(ReplicatedStorage:WaitForChild(pack):WaitForChild(name) :: KeyframeSequence, authoredHipHeight)
end

local function sampleTrack(track: Track, time: number): CFrame
	local times = track.times
	local count = #times
	if time <= times[1] then
		return track.frames[1]
	elseif time >= times[count] then
		return track.frames[count]
	end
	local low, high = 1, count
	while high - low > 1 do
		local middle = (low + high) // 2
		if times[middle] <= time then
			low = middle
		else
			high = middle
		end
	end
	if track.hold[low] then
		return track.frames[low]
	end
	local span = times[high] - times[low]
	local alpha = if span > 0 then (time - times[low]) / span else 0
	return track.frames[low]:Lerp(track.frames[high], alpha)
end

-- The pose of every part of `clip` at `time` seconds, as the pack's rig has it.
function Sequence.sample(clip: Clip, time: number): { [string]: CFrame }
	local pose = {}
	for name, track in clip.tracks do
		pose[name] = sampleTrack(track, time)
	end
	return pose
end

-- The joint of `character` that moves its part named `part1`, and that joint's two frames; of several, the one named
-- `name`.
local function findJoint(character: Model, part1: string, name: string): (Instance?, CFrame, CFrame)
	local part = character:FindFirstChild(part1)
	if not part then
		return nil, CFrame.identity, CFrame.identity
	end
	local named = nil
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 == part and d.Name == name then
			named = d
		end
	end
	if named then
		return named, named.C0, named.C1
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 == part then
			return d, d.C0, d.C1
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a1.Parent == part then
				return d, a0.CFrame, a1.CFrame
			end
		end
	end
	return nil, CFrame.identity, CFrame.identity
end

-- `character`'s joints for the clips of the pack `pack`, matched to its rig's by the part each moves. A pack without a
-- "Rig" is authored on Roblox's standard R15, whose joints turn as the character's.
function Sequence.rig(character: Model, pack: string): Rig
	local packRig = ReplicatedStorage:WaitForChild(pack):FindFirstChild("Rig")
	local joints = {}
	if not packRig then
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") then
				local instance, c0, c1 = findJoint(character, part.Name, "")
				if instance then
					joints[part.Name] = { instance = instance, before = c0.Rotation:Inverse(), after = c1.Rotation }
				end
			end
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		return { joints = joints, shift = if humanoid then humanoid.HipHeight else 2 }
	end
	for _, motor in packRig:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part1 then
			local name = motor.Part1.Name
			local instance, c0, c1 = findJoint(character, name, motor.Name)
			if instance then
				joints[name] = {
					instance = instance,
					before = c0.Rotation:Inverse() * motor.C0.Rotation,
					after = motor.C1.Rotation:Inverse() * c1.Rotation,
				}
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return { joints = joints, shift = if humanoid then humanoid.HipHeight else 2 }
end

-- Poses `rig` as `clip` at `time`, blended over what it has now by `weight` (0-1); with `only`, just those parts.
function Sequence.apply(rig: Rig, clip: Clip, time: number, weight: number, only: { [string]: boolean }?)
	local grow = rig.shift / math.max(clip.authoredHipHeight, 0.1)
	for name, frame in Sequence.sample(clip, time) do
		local joint = rig.joints[name]
		if joint and (not only or only[name]) then
			local scaled = CFrame.new(frame.Position * grow) * frame.Rotation
			local target = joint.before * scaled * joint.after
			local instance = joint.instance :: any
			instance.Transform = if weight >= 1 then target else instance.Transform:Lerp(target, weight)
		end
	end
end

return Sequence
