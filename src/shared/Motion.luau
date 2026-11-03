-- Plays the clips of a bought animation pack (Config.Heroes[hero].Pack, Docs/Third_Party.md) on a hero, on the client.
-- The pack's own player only drives its included rig with Motor6Ds; a Roblox character has AnimationConstraints since
-- the Avatar Joint Upgrade, and frames of its own at the root. So this samples the pack's clips through its player and
-- turns every joint's pose into one for the hero's joint, so that each body part sits where it would on the pack's
-- rig, standing on the same ground. The weapons (the pack's components, in the character's "Weapons" folder) follow
-- the clips as on the pack's rig: a skinned one (a bow, a dagger) by its bones, a rigid one (a quiver) by its
-- ComponentBinding Motor6D on the root part (or on a hand, the Elementalist's staff); and they fade in and out as the
-- clips say. The newest packs (the Katana Swordsman) bind each rigid weapon to a body part, the sword to the right hand
-- and its scabbard to the hips, and grow and shrink its mesh (Geometry, welded beneath it) as the clips say.
--
-- Two layers: the base (standing, running, jumping), which crossfades when it changes, and over it one action (an
-- attack), which fades in, plays once and fades back to the base.
--
-- Cues (Motion.cues, per clip id: { Time = seconds into the clip, ... }) are handed to Motion.onCue as the clips'
-- clocks pass them: the action's, and the base's while no action covers it.
--
-- A clip of another pack (Motion.lend: the emotes' dances) plays on any hero through that pack's player: every pack's
-- rig is the same R15 rig, so its poses fit the hero's joints as his own pack's do.
--
-- The clips in Motion.mirrored play mirrored, left for right: the packs' rigs are symmetric (each left joint's frames
-- the right one's reflected across the body's middle), so the left joint takes the right one's pose reflected, and the
-- other way round. Only the body is mirrored, not the pack's weapons; a hero whose weapons are his own, held in a hand
-- (HeroLook's Held), keeps it in that hand.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Motion = {}
Motion.__index = Motion

-- The height of the pack rig's root part above the ground: its HipHeight 1.35 plus half its 2 studs.
local PACK_ROOT_HEIGHT = 2.35
local BASE_FADE = 0.15
local ACTION_FADE_IN = 0.08
local ACTION_FADE_OUT = 0.2
-- A foot stepping into the base pose (Motion.stepInto) lifts its knee up to this many degrees.
local STEP_LIFT = 28
-- Breathing (Motion.breathe): one breath in this many seconds, the chest and the head tipping this many degrees, coming
-- in over BREATH_IN seconds.
local BREATH, BREATH_CHEST, BREATH_HEAD, BREATH_IN = 3.6, 1.6, 1, 0.6

-- A rigid weapon's joint pose and size; in the newest packs also where its mesh sits within it (`geometry`).
type Prop = { world: CFrame, scale: Vector3, geometry: CFrame? }

type Pose = {
	body: { [string]: CFrame },
	bones: { [string]: CFrame },
	props: { [string]: Prop },
	opacity: { [string]: number },
	-- Sampled from a lending pack's clip (Motion.lend: a dance), which shows none of the hero's weapons.
	lent: boolean?,
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
	-- In place without its rise into the air either (the game lifts him itself).
	grounded: boolean,
	-- Kept at its last pose once it ends (a fall), instead of fading back to the base.
	hold: boolean,
	-- Where it stands still, short of its end (Motion.stopAt).
	stopAt: number?,
	-- Played left for right (Motion.mirrored).
	mirror: boolean,
	-- Played over and over until stopped, when it loops (Motion.keepPlaying).
	repeating: boolean,
	-- The pack player it is sampled from.
	player: any,
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
		-- The part the root joint moves (the pack rig's lower torso), and how the pack turns that joint's frame.
		rootPart: string?,
		rootTurn: CFrame,
		bones: { [string]: Bone },
		meshes: { [string]: { MeshPart } },
		-- The rigid components' joints by their part's name, with the part's size as made (and its mesh's, in the
		-- newest packs).
		props: { [string]: { motor: Motor6D, size: Vector3, meshSize: Vector3? } },
		base: Clip?,
		previous: Clip?,
		baseBlend: number,
		action: Clip?,
		actionWeight: number,
		lastAction: Pose?,
		-- Stepping from the pose the clip over the base ended in into the base (Motion.stepInto).
		stepping: { from: Pose, time: number, left: number, right: number }?,
		-- Seconds since he began to breathe (Motion.breathe).
		breathing: number?,
		-- Never standing taller than the base clip (Motion.keepLow).
		low: boolean,
		-- The pose last put on the body, and one being faded out of (Motion.crossfade).
		applied: Pose?,
		fading: { from: Pose, time: number, seconds: number }?,
		cues: { [string]: { Cue } }?,
		onCue: ((cue: Cue) -> ())?,
		-- The clips played mirrored, by id.
		mirrored: { [string]: boolean }?,
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

-- The packs that lend their clips to every hero, by the start of their clips' ids.
local lent: { [string]: string } = {}

-- Lets every hero play the clips of `packName` whose ids start with `prefix`.
function Motion.lend(prefix: string, packName: string)
	lent[prefix] = packName
end

-- The player that samples clip `id` for `self`: a lending pack's, or the hero's own.
local function playerOf(self: Motion, id: string): any
	for prefix, name in lent do
		if string.sub(id, 1, #prefix) == prefix then
			return pack(name).player
		end
	end
	return self.player
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

-- Switches the body joints of the dead `character` back on, so a clip can lay him down: the Humanoid lets go of them
-- when he dies, for Roblox's ragdoll.
function Motion.holdJoints(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			d.Enabled = true
		end
	end
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

-- Takes `d` into what the clips move if it is a bone or mesh of one of the character's weapons.
local function takeWeapon(self: Motion, d: Instance)
	local weapons = self.character:FindFirstChild("Weapons")
	if not weapons or not d:IsDescendantOf(weapons) then
		return
	end
	local component = d
	while component.Parent ~= weapons do
		component = component.Parent :: Instance
	end
	if d:IsA("Bone") then
		self.bones[d.Name] = d
	elseif d:IsA("Motor6D") and d.Name == "ComponentBinding" and d.Part1 then
		self.props[d.Part1.Name] = { motor = d, size = d.Part1.Size }
	elseif d:IsA("MeshPart") then
		local meshes = self.meshes[component.Name] or {}
		self.meshes[component.Name] = meshes
		if not table.find(meshes, d) then
			table.insert(meshes, d)
		end
	end
end

function Motion.new(character: Model, packName: string): Motion
	local p = pack(packName)
	local self = setmetatable({
		character = character,
		player = p.player,
		joints = {},
		rootPart = nil,
		rootTurn = CFrame.identity,
		bones = {},
		meshes = {},
		props = {},
		base = nil,
		previous = nil,
		baseBlend = 1,
		action = nil,
		actionWeight = 0,
		lastAction = nil,
		stepping = nil,
		breathing = nil,
		low = false,
		applied = nil,
		fading = nil,
		cues = nil,
		onCue = nil,
		mirrored = nil,
	}, Motion)
	local shift = Motion.rootShift(character)
	for _, j in p.config.body_joints do
		local instance, c0, c1 = findJoint(character, j.part0, j.part1)
		if instance then
			local packC0 = frame(j.c0)
			if j.part0 == "HumanoidRootPart" then
				packC0 = shift * packC0
				self.rootPart = j.part1
				self.rootTurn = packC0.Rotation
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
	-- A hero who just (re)spawned can reach the client a piece at a time, his weapons after the rest of him, so their
	-- bones and meshes are taken in as they arrive.
	for _, d in character:GetDescendants() do
		takeWeapon(self, d)
	end
	character.DescendantAdded:Connect(function(d)
		takeWeapon(self, d)
	end)
	return self
end

function Motion.meta(packName: string, id: string): Meta
	local _, meta = pack(packName).player.Sample(nil, id, 0)
	return meta
end

-- `cf` reflected across the body's middle (its X): what the joint on the other side does in a mirrored clip.
local function reflect(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- The body part on the other side of `name` (LeftHand for RightHand), or `name` itself in the middle.
local function across(name: string): string
	if string.sub(name, 1, 4) == "Left" then
		return "Right" .. string.sub(name, 5)
	elseif string.sub(name, 1, 5) == "Right" then
		return "Left" .. string.sub(name, 6)
	end
	return name
end

local function clipTime(clip: Clip): number
	local meta = clip.meta
	if meta.loop and meta.duration > 0 then
		return clip.time % meta.duration
	end
	return math.min(clip.time, meta.duration)
end

function Motion.sample(self: Motion, clip: Clip): Pose
	local sample = clip.player.Sample(nil, clip.id, clipTime(clip))
	local body, bones, props, opacity = sample.body, sample.bones or {}, sample.props or {}, sample.opacity
	if not opacity then
		-- The newest packs give each weapon its joint's transform, one scale, its own opacity and its mesh's place.
		local converted = {}
		opacity = {}
		for name, p in props do
			converted[name] = { world = p.transform, scale = Vector3.one * p.scale, geometry = p.geometry }
			opacity[name] = p.opacity
		end
		props = converted
	end
	local root = self.rootPart and body[self.rootPart]
	if clip.inPlace and root then
		body = table.clone(body)
		local rise = if clip.grounded then math.min(root.Position.Y, 0) else root.Position.Y
		body[self.rootPart :: string] = CFrame.new(0, rise, 0) * root.Rotation
		-- The weapons hang from the root part, not the body, so their bones lose the same travel over the ground.
		local travel = self.rootTurn * Vector3.new(-root.Position.X, 0, -root.Position.Z)
		bones = table.clone(bones)
		for name, bone in self.bones do
			local mesh = bone.Parent
			local binding = mesh and mesh:FindFirstChild("ComponentBinding")
			local pose = bones[name]
			if pose and mesh and mesh:IsA("BasePart") and binding and binding:IsA("Weld") then
				local turn = (binding.C0 * binding.C1:Inverse() * bone.CFrame).Rotation
				bones[name] = CFrame.new(turn:VectorToObjectSpace(travel)) * pose
			end
		end
		props = table.clone(props)
		for name, prop in self.props do
			local pose = props[name]
			-- A weapon held in a hand (Shared.KeyframePlayer) moves with the body already.
			local onRoot = prop.motor.Part0 ~= nil and prop.motor.Part0.Name == "HumanoidRootPart"
			if pose and onRoot then
				local shifted = CFrame.new(prop.motor.C0.Rotation:VectorToObjectSpace(travel)) * pose.world
				props[name] = { world = shifted, scale = pose.scale, geometry = pose.geometry }
			end
		end
	end
	if clip.mirror then
		local mirrored = {}
		for name, cf in body do
			mirrored[across(name)] = reflect(cf)
		end
		body = mirrored
	end
	return { body = body, bones = bones, props = props, opacity = opacity, lent = clip.player ~= self.player }
end

local function mixProp(a: Prop, b: Prop, w: number): Prop
	return {
		world = a.world:Lerp(b.world, w),
		scale = a.scale:Lerp(b.scale, w),
		geometry = if a.geometry and b.geometry then a.geometry:Lerp(b.geometry, w) else b.geometry,
	}
end

local function blend(a: Pose, b: Pose, w: number): Pose
	if w <= 0 then
		return a
	elseif w >= 1 then
		return b
	end
	local body, bones, props = {}, {}, {}
	for name, cf in a.body do
		local other = b.body[name]
		body[name] = if other then cf:Lerp(other, w) else cf
	end
	for name, cf in a.bones do
		local other = b.bones[name]
		bones[name] = if other then cf:Lerp(other, w) else cf
	end
	for name, prop in a.props do
		local other = b.props[name]
		props[name] = if other then mixProp(prop, other, w) else prop
	end
	return {
		body = body,
		bones = bones,
		props = props,
		opacity = if w < 0.5 then a.opacity else b.opacity,
		lent = if w < 0.5 then a.lent else b.lent,
	}
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local LEGS = {
	LeftUpperLeg = "Left",
	LeftLowerLeg = "Left",
	LeftFoot = "Left",
	RightUpperLeg = "Right",
	RightLowerLeg = "Right",
	RightFoot = "Right",
}

-- `from` eased into `to`: the body by `w`, each leg by its side's weight in `feet`.
local function stepped(from: Pose, to: Pose, w: number, feet: { [string]: number }): Pose
	local body, bones, props = {}, {}, {}
	for name, cf in to.body do
		local old = from.body[name]
		local side = LEGS[name]
		body[name] = if old then old:Lerp(cf, if side then feet[side] else w) else cf
	end
	for name, cf in to.bones do
		local old = from.bones[name]
		bones[name] = if old then old:Lerp(cf, w) else cf
	end
	for name, prop in to.props do
		local old = from.props[name]
		props[name] = if old then mixProp(old, prop, w) else prop
	end
	return { body = body, bones = bones, props = props, opacity = to.opacity, lent = to.lent }
end

local function newClip(self: Motion, id: string, speed: number, time: number?): Clip
	local player = playerOf(self, id)
	local _, meta = player.Sample(nil, id, 0)
	return {
		player = player,
		repeating = false,
		id = id,
		time = time or 0,
		speed = speed,
		meta = meta,
		fresh = true,
		inPlace = false,
		grounded = false,
		hold = false,
		mirror = self.mirrored ~= nil and self.mirrored[id] == true,
	}
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

-- Plays `id` once over the base, from `startTime` seconds in, `inPlace` without the clip's travel over the ground (with
-- "Grounded" without its rise into the air either, for a jump the game lifts him in itself), `hold` keeping its last
-- pose when it ends; returns how long it lasts at `speed`.
function Motion.play(
	self: Motion,
	id: string,
	speed: number,
	startTime: number?,
	inPlace: (boolean | string)?,
	hold: boolean?
): number
	self.action = newClip(self, id, speed, startTime)
	self.action.inPlace = inPlace == true or inPlace == "Grounded"
	self.action.grounded = inPlace == "Grounded"
	self.action.hold = hold == true
	self.actionWeight = if startTime and startTime > 0 then 1 else self.actionWeight
	return self.action.meta.duration / speed
end

-- Keeps the clip played over the base playing over and over, when it loops, until it is stopped or another is played
-- (a dance).
function Motion.keepPlaying(self: Motion)
	if self.action then
		self.action.repeating = self.action.meta.loop
	end
end

-- Plays the clip played over the base on at `speed` from now (a held moment in it: Kit's `Hold`).
function Motion.setSpeed(self: Motion, speed: number)
	if self.action then
		self.action.speed = speed
	end
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

-- Lets the clip played over the base stand still `seconds` in.
function Motion.stopAt(self: Motion, seconds: number)
	if self.action then
		self.action.stopAt = seconds
	end
end

-- Whether the clip played over the base stands still where Motion.stopAt said.
function Motion.reached(self: Motion): boolean
	local action = self.action
	return action ~= nil and action.stopAt ~= nil and action.time >= action.stopAt
end

-- Ends the clip played over the base by stepping into the base: the left foot lifted and set down in its place in
-- `left` seconds, then the right in `right`, the body easing over all of it, instead of sliding there (the menu's
-- podium).
function Motion.stepInto(self: Motion, left: number, right: number)
	local action = self.action
	if not action then
		return
	end
	self.stepping = { from = self:sample(action), time = 0, left = left, right = right }
	self.action = nil
	self.actionWeight = 0
	self.lastAction = nil
end

-- Eases over `seconds` from the pose he stands in now into whatever is played from now on (a dance and back), instead
-- of jumping to it.
function Motion.crossfade(self: Motion, seconds: number)
	if self.applied then
		self.fading = { from = self.applied, time = 0, seconds = seconds }
	end
end

-- Breathes from now on, the chest rising and falling over whatever pose he holds (the menu's podium).
function Motion.breathe(self: Motion)
	self.breathing = 0
end

-- Keeps him from now on no taller than the base clip stands, whatever is played over it: a clip standing straight
-- sinks to the height of a lower stance (Mavorak on the menu's podium, owner 2026-11-01).
function Motion.keepLow(self: Motion)
	self.low = true
end

-- Moves the clocks on by `dt` seconds and poses the character.
function Motion.step(self: Motion, dt: number)
	local base = self.base
	if not base then
		return
	end
	advance(self, base, dt * base.speed, self.actionWeight < 0.5)
	local pose = self:sample(base)
	local rootPart = self.rootPart
	local low = if self.low and rootPart and pose.body[rootPart] then pose.body[rootPart].Y else nil
	if self.previous and self.baseBlend < 1 then
		self.previous.time += dt * self.previous.speed
		self.baseBlend = math.min(1, self.baseBlend + dt / BASE_FADE)
		pose = blend(self:sample(self.previous), pose, self.baseBlend)
	end

	local action = self.action
	if action then
		advance(self, action, dt * action.speed, true)
		if action.stopAt and action.time >= action.stopAt then
			action.time = action.stopAt
			action.speed = 0
		end
		if action.time >= action.meta.duration and not action.hold and not action.repeating then
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
	local stepping = self.stepping
	local lifts: { [string]: number }? = nil
	if stepping then
		stepping.time += dt
		local left, right = stepping.time / stepping.left, (stepping.time - stepping.left) / stepping.right
		local seconds = stepping.left + stepping.right
		pose = stepped(stepping.from, pose, ease(stepping.time / seconds), { Left = ease(left), Right = ease(right) })
		lifts = { Left = left, Right = right }
		if stepping.time >= seconds then
			self.stepping = nil
		end
	end
	if low and rootPart then
		local root = pose.body[rootPart]
		if root and root.Y > low then
			pose = table.clone(pose)
			pose.body = table.clone(pose.body)
			pose.body[rootPart] = root - Vector3.new(0, root.Y - low, 0)
		end
	end
	local fading = self.fading
	if fading then
		fading.time += dt
		pose = blend(fading.from, pose, ease(fading.time / fading.seconds))
		if fading.time >= fading.seconds then
			self.fading = nil
		end
	end
	self.applied = pose
	self:apply(pose)
	if lifts then
		for side, w in lifts do
			if w > 0 and w < 1 then
				local k = math.sin(w * math.pi) * math.rad(STEP_LIFT)
				local upper = self.joints[side .. "UpperLeg"]
				local lower = self.joints[side .. "LowerLeg"]
				if upper and lower then
					local a, b = upper.instance :: any, lower.instance :: any
					a.Transform *= CFrame.Angles(k, 0, 0)
					b.Transform *= CFrame.Angles(-2 * k, 0, 0)
				end
			end
		end
	end
	if self.breathing then
		self.breathing += dt
		local b = math.sin(self.breathing * 2 * math.pi / BREATH) * math.min(1, self.breathing / BREATH_IN)
		local chest = self.joints.UpperTorso
		local head = self.joints.Head
		if chest then
			(chest.instance :: any).Transform *= CFrame.Angles(math.rad(-BREATH_CHEST * b), 0, 0)
		end
		if head then
			(head.instance :: any).Transform *= CFrame.Angles(math.rad(BREATH_HEAD * b), 0, 0)
		end
	end
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
	for name, prop in self.props do
		local p = pose.props[name]
		if p then
			prop.motor.Transform = p.world
			local scale = Vector3.new(math.max(p.scale.X, 1e-4), math.max(p.scale.Y, 1e-4), math.max(p.scale.Z, 1e-4))
			local part = prop.motor.Part1 :: BasePart
			local mesh = part:FindFirstChild("Geometry")
			local weld = part:FindFirstChild("GeometryBinding")
			if p.geometry and mesh and mesh:IsA("BasePart") and weld and weld:IsA("Weld") then
				-- The newest packs' weapon part only holds its mesh, which is what grows and shrinks.
				prop.meshSize = prop.meshSize or mesh.Size
				local size = (prop.meshSize :: Vector3) * scale
				if (mesh.Size - size).Magnitude > 1e-3 then
					mesh.Size = size
				end
				weld.C0 = p.geometry
			else
				local size = prop.size * scale
				if (part.Size - size).Magnitude > 1e-3 then
					part.Size = size
				end
			end
		end
	end
	for name, meshes in self.meshes do
		local opacity = pose.opacity[name] or 0
		for _, mesh in meshes do
			mesh.Transparency = 1 - opacity
		end
	end
	-- His own weapon held in a hand (HeroLook's Held, Korrund's axe) is put away for a dance as the packs' weapons are.
	local held = self.character:FindFirstChild("Held")
	if held then
		local away = if pose.lent then 1 else 0
		for _, part in held:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency ~= away then
				part.Transparency = away
			end
		end
	end
end

return Motion
