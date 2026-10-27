-- Plays the clips of a bought animation pack (Config.Heroes[hero].Pack, Docs/Third_Party.md) on a hero, on the client.
-- The pack's own player only drives its included rig with Motor6Ds; a Roblox character has AnimationConstraints since
-- the Avatar Joint Upgrade, and frames of its own at the root. So this samples the pack's clips through its player and
-- turns every joint's pose into one for the hero's joint, so that each body part sits where it would on the pack's
-- rig, standing on the same ground. The weapons (the pack's skinned components, in the character's "Weapons" folder)
-- follow their bones, and fade in and out as the clips say.
--
-- Two layers: the base (standing, running, jumping), which crossfades when it changes, and over it one action (an
-- attack), which fades in, plays once and fades back to the base.
--
-- Cues (Motion.cues, per clip id: { Time = seconds into the clip, ... }) are handed to Motion.onCue as the clips'
-- clocks pass them: the action's, and the base's while no action covers it.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Motion = {}
Motion.__index = Motion

-- The height of the pack rig's root part above the ground: its HipHeight 1.35 plus half its 2 studs.
local PACK_ROOT_HEIGHT = 2.35
local BASE_FADE = 0.15
local ACTION_FADE_IN = 0.08
local ACTION_FADE_OUT = 0.2

type Pose = {
	body: { [string]: CFrame },
	bones: { [string]: CFrame },
	opacity: { [string]: number },
}

type Meta = {
	duration: number,
	loop: boolean,
	markers: any,
}

type Clip = {
	id: string,
	time: number,
	speed: number,
	meta: Meta,
	-- Not stepped since it began, so a cue at its very start still plays.
	fresh: boolean,
	-- Played without the clip carrying the body over the ground (the game moves the hero itself).
	inPlace: boolean,
}

export type Cue = { Time: number, [string]: any }

type Joint = {
	instance: Instance,
	before: CFrame,
	after: CFrame,
}

export type Motion = typeof(setmetatable(
	{} :: {
		character: Model,
		player: any,
		joints: { [string]: Joint },
		-- The part the root joint moves (the pack rig's lower torso).
		rootPart: string?,
		bones: { [string]: Bone },
		meshes: { [string]: { MeshPart } },
		base: Clip?,
		previous: Clip?,
		baseBlend: number,
		action: Clip?,
		actionWeight: number,
		lastAction: Pose?,
		cues: { [string]: { Cue } }?,
		onCue: ((cue: Cue) -> ())?,
	},
	Motion
))

local packs: { [string]: { player: any, config: any } } = {}

local function pack(name: string)
	if not packs[name] then
		local folder = ReplicatedStorage:WaitForChild(name)
		local player = folder:WaitForChild("ComponentPlayer")
		packs[name] = {
			player = require(player) :: any,
			config = HttpService:JSONDecode((player:WaitForChild("Configuration") :: StringValue).Value),
		}
	end
	return packs[name]
end

local function frame(values: { number }): CFrame
	return CFrame.new(table.unpack(values))
end

-- How far the character's root part stands from where the pack rig's would on the same ground, as a CFrame to put
-- in front of the pack's root frame (and its weapons' bindings).
function Motion.rootShift(character: Model): CFrame
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return CFrame.identity
	end
	return CFrame.new(0, PACK_ROOT_HEIGHT - (humanoid.HipHeight + root.Size.Y / 2), 0)
end

-- The character's joint that moves the part named `part1`, with its two frames.
local function findJoint(character: Model, part0: string, part1: string): (Instance?, CFrame, CFrame)
	local part = character:FindFirstChild(part1)
	if not part then
		return nil, CFrame.identity, CFrame.identity
	end
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a1.Parent == part and a0.Parent and a0.Parent.Name == part0 then
				return d, a0.CFrame, a1.CFrame
			end
		elseif d:IsA("Motor6D") and d.Part1 == part and d.Part0 and d.Part0.Name == part0 then
			return d, d.C0, d.C1
		end
	end
	return nil, CFrame.identity, CFrame.identity
end

function Motion.new(character: Model, packName: string): Motion
	local p = pack(packName)
	local self = setmetatable({
		character = character,
		player = p.player,
		joints = {},
		rootPart = nil,
		bones = {},
		meshes = {},
		base = nil,
		previous = nil,
		baseBlend = 1,
		action = nil,
		actionWeight = 0,
		lastAction = nil,
		cues = nil,
		onCue = nil,
	}, Motion)
	local shift = Motion.rootShift(character)
	for _, j in p.config.body_joints do
		local instance, c0, c1 = findJoint(character, j.part0, j.part1)
		if instance then
			local packC0 = frame(j.c0)
			if j.part0 == "HumanoidRootPart" then
				packC0 = shift * packC0
				self.rootPart = j.part1
			end
			self.joints[j.part1] = {
				instance = instance,
				before = c0:Inverse() * packC0,
				after = frame(j.c1):Inverse() * c1,
			}
		else
			warn("[Motion] no joint for", j.part1, "in", character:GetFullName())
		end
	end
	local weapons = character:FindFirstChild("Weapons")
	if weapons then
		for _, component in weapons:GetChildren() do
			local meshes = {}
			for _, d in component:GetDescendants() do
				if d:IsA("Bone") then
					self.bones[d.Name] = d
				elseif d:IsA("MeshPart") then
					table.insert(meshes, d)
				end
			end
			self.meshes[component.Name] = meshes
		end
	end
	return self
end

function Motion.meta(packName: string, id: string): Meta
	local _, meta = pack(packName).player.Sample(nil, id, 0)
	return meta
end

local function clipTime(clip: Clip): number
	local meta = clip.meta
	if meta.loop and meta.duration > 0 then
		return clip.time % meta.duration
	end
	return math.min(clip.time, meta.duration)
end

function Motion.sample(self: Motion, clip: Clip): Pose
	local sample = self.player.Sample(nil, clip.id, clipTime(clip))
	local body = sample.body
	local root = self.rootPart and body[self.rootPart]
	if clip.inPlace and root then
		body = table.clone(body)
		body[self.rootPart :: string] = CFrame.new(0, root.Position.Y, 0) * root.Rotation
	end
	return { body = body, bones = sample.bones, opacity = sample.opacity }
end

local function blend(a: Pose, b: Pose, w: number): Pose
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local body, bones = {}, {}
	for name, cf in a.body do
		local other = b.body[name]
		body[name] = if other then cf:Lerp(other, w) else cf
	end
	for name, cf in a.bones do
		local other = b.bones[name]
		bones[name] = if other then cf:Lerp(other, w) else cf
	end
	return { body = body, bones = bones, opacity = if w < 0.5 then a.opacity else b.opacity }
end

local function newClip(self: Motion, id: string, speed: number, time: number?): Clip
	local _, meta = self.player.Sample(nil, id, 0)
	return { id = id, time = time or 0, speed = speed, meta = meta, fresh = true, inPlace = false }
end

-- Moves `clip`'s clock on by `delta` seconds and hands over the cues it passes.
local function advance(self: Motion, clip: Clip, delta: number, cued: boolean)
	local from = if clip.fresh then clip.time - 1e-3 else clip.time
	clip.fresh = false
	clip.time += delta
	local cues = self.cues and self.cues[clip.id]
	local onCue = self.onCue
	if not cued or not cues or not onCue then
		return
	end
	local length = clip.meta.duration
	local to = clip.time
	if clip.meta.loop and length > 0 then
		-- Counted in whole cycles: stepping `from` to each cycle's end can round back into the same cycle forever.
		local cycle = math.floor(from / length)
		while cycle * length < to do
			for _, cue in cues do
				local at = cycle * length + cue.Time
				if at > from and at <= to then
					onCue(cue)
				end
			end
			cycle += 1
		end
	else
		for _, cue in cues do
			if cue.Time > from and cue.Time <= to then
				onCue(cue)
			end
		end
	end
end

-- Sets the base clip; a new one crossfades in. `speed` may change every frame.
function Motion.setBase(self: Motion, id: string, speed: number)
	local base = self.base
	if base and base.id == id then
		base.speed = speed
		return
	end
	self.previous = base
	self.baseBlend = if base then 0 else 1
	self.base = newClip(self, id, speed)
end

-- Restarts the base clip from its start (a jump's takeoff).
function Motion.restartBase(self: Motion)
	if self.base then
		self.base.time = 0
		self.base.fresh = true
	end
end

function Motion.baseDone(self: Motion): boolean
	local base = self.base
	return base ~= nil and not base.meta.loop and base.time >= base.meta.duration
end

-- Plays `id` once over the base, from `startTime` seconds in, `inPlace` without the clip's travel over the ground;
-- returns how long it lasts at `speed`.
function Motion.play(self: Motion, id: string, speed: number, startTime: number?, inPlace: boolean?): number
	self.action = newClip(self, id, speed, startTime)
	self.action.inPlace = inPlace == true
	self.actionWeight = if startTime and startTime > 0 then 1 else self.actionWeight
	return self.action.meta.duration / speed
end

function Motion.stop(self: Motion)
	if self.action then
		self.lastAction = self:sample(self.action)
		self.action = nil
	end
end

function Motion.playing(self: Motion): string?
	return if self.action then self.action.id else nil
end

-- Moves the clocks on by `dt` seconds and poses the character.
function Motion.step(self: Motion, dt: number)
	local base = self.base
	if not base then
		return
	end
	advance(self, base, dt * base.speed, self.actionWeight < 0.5)
	local pose = self:sample(base)
	if self.previous and self.baseBlend < 1 then
		self.previous.time += dt * self.previous.speed
		self.baseBlend = math.min(1, self.baseBlend + dt / BASE_FADE)
		pose = blend(self:sample(self.previous), pose, self.baseBlend)
	end

	local action = self.action
	if action then
		advance(self, action, dt * action.speed, true)
		if action.time >= action.meta.duration then
			self:stop()
		else
			self.actionWeight = math.min(1, self.actionWeight + dt / ACTION_FADE_IN)
			pose = blend(pose, self:sample(action), self.actionWeight)
		end
	end
	if not self.action and self.actionWeight > 0 then
		self.actionWeight = math.max(0, self.actionWeight - dt / ACTION_FADE_OUT)
		if self.lastAction then
			pose = blend(pose, self.lastAction, self.actionWeight)
		end
	end
	self:apply(pose)
end

function Motion.apply(self: Motion, pose: Pose)
	for name, transform in pose.body do
		local joint = self.joints[name]
		if joint then
			(joint.instance :: any).Transform = joint.before * transform * joint.after
		end
	end
	for name, bone in self.bones do
		bone.Transform = pose.bones[name] or CFrame.identity
	end
	for name, meshes in self.meshes do
		local opacity = pose.opacity[name] or 0
		for _, mesh in meshes do
			mesh.Transparency = 1 - opacity
		end
	end
end

return Motion
