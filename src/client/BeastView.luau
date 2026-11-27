-- The beast coming out of the ground (Config.Beast, the server's BeastService), by Workspace.Beast's attributes. For
-- `Rumble` seconds the ground at its "Hole" trembles: cracks run out from the spot one after the other with the
-- crystals' light in them, pebbles hop, dust rises, the camera shakes more and more and the rumble grows; in the last
-- half second the ground bulges up. Then it bursts: a real hole opens in the sand (the floor cut by CSG, with a shaft
-- of earth and rock under it and the torn crust standing up round its edge), clods and crystals fly up and fall back
-- round it, dust shoots up, and the beast flies out of it nose first, in an arc `Height` studs high that hangs for a
-- moment at its top, legs tucked, to slam down on all fours at its "Land", where the dust rings out and the camera
-- jolts. Then it roars. The hole stays `Crater` seconds; then its clods sink and the sand closes. The beast is
-- ReplicatedStorage.Beast, its joints (bones or Motor6Ds) posed here every frame: its own Idle and Roar from its
-- KeyframeSequences, and the flight and the landing made here for its rig, the model's "Rig" attribute ("Serpent",
-- "Beetle" or "Burrower"); its "Front" attribute is the side of its pivot its head is on (1 for +Z, -1 for -Z). Landed,
-- it lies round its coil's middle ("Centre"), turns to the server's "Look", plays its Attack clip from each "Bite" and
-- shows its name and health over it; dead ("DiedAt"), it falls with its Death clip and sinks into the sand.

local Debris = game:GetService("Debris")
local GeometryService = game:GetService("GeometryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroCamera = require(script.Parent.HeroCamera)
local Preferences = require(script.Parent.Preferences)
local Side = require(script.Parent.Side)
local UiStyle = require(script.Parent.UiStyle)

local BeastView = {}

local SETTINGS = Config.Beast
local SCALE = SETTINGS.Scale
local HOLE = SETTINGS.Hole
local CRYSTAL = Color3.fromRGB(120, 230, 255)
local CRACK = Color3.fromRGB(78, 56, 38)
local EARTH = Color3.fromRGB(122, 88, 58)
local DEEP = Color3.fromRGB(46, 34, 26)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
-- The shaft under the hole, and how many pieces of wall go round it.
local DEPTH, WALLS = 44, 30
-- The cracks: how many run out from the spot, the share of the rumble over which they all appear, and how much of a
-- crack's width its light fills.
local CRACKS, CRACK_SPREAD, GLOW_WIDTH = 10, 0.85, 0.3
-- The ground bulges up this high over the rumble's last `BULGE` seconds.
local BULGE, BULGE_HEIGHT = 0.55, 1.4
-- The flight's time warp: hanging at the top and fast into the slam (0 is an even arc), and slower at first, as the
-- beast breaks out of the hole, by how much and for about what share of the flight.
local HANG, BREACH = 0.6, { 1.2, 0.07 }
-- The nose's highest pitch, out of the hole, and its lowest, coming down.
local PITCH_UP, PITCH_DOWN = math.rad(80), math.rad(-50)
-- The landing's dip and how fast it springs back, and the crossfade into a clip.
local DIP, SPRING, BLEND = 0.35, 7, 0.25
-- How far the shaking reaches.
local SHAKE_FAR = 140
-- Where the rocks' first crash is in the burst's recording, and where the roar swells in the roars' (measured by
-- PlaybackLoudness).
local BURST_FROM, ROAR_FROM = 1, 0.5
-- How fast it turns to the server's "Look" and slides to its "Centre" (the share left each second is e^-TURN, e^-SLIDE).
local TURN, SLIDE = 10, 12
-- What of the bases it lies on besides the floor (the Masters' stairs, which it climbs to bite him, owner 2026-11-26),
-- how far along its length it feels for them from its middle, each way, and how fast it rises or sinks to them.
local CLIMBS, FEEL, CLIMB = { "dais", "dais_blue" }, 0.4, 10
-- The serpent lies on them part by part, as a snake does (owner, 2026-11-27: no part of it in the air): its base, where
-- its neck rises, tilts with what is under it BASE_FEEL studs before and behind, at most BASE_TILT (radians), its neck
-- kept upright; each joint of its coil bends up or down, at most DRAPE, so the next lies as high over what is under it
-- (LINK_FEEL studs either way) as on flat ground; and its neck rises or sinks with what is under its head, at most
-- NECK_RISE studs.
local BASE_FEEL, BASE_TILT, LINK_FEEL, DRAPE, NECK_RISE = 4, math.rad(35), 1.5, math.rad(55), 6
-- Its bar, as a hero's (HeroBars, owner 2026-11-26): the size, how high over its top, its colours (the earth's,
-- neither team's) and how far off it shows.
local BAR_WIDTH, BAR_HEIGHT, BAR_NAME, BAR_OVER, BAR_FAR = 132, 16, 18, 3, 75
-- Up close it comes down to stay this many pixels below the screen's top (clear of the score and the tip under it),
-- never lower than BAR_LOWEST studs over the floor, easing there (the share left each second is e^-BAR_EASE).
local BAR_MARGIN, BAR_LOWEST, BAR_EASE = 170, 6, 8
-- Its dying cry's speed: lower and slower, a giant's.
local DEATH_PITCH = 0.7
local BAR_TOP, BAR_BOTTOM = Color3.fromRGB(196, 222, 110), Color3.fromRGB(96, 132, 44)

type Pose = { [string]: CFrame }
type Clip = { length: number, loop: boolean, times: { number }, poses: { Pose } }
type Body = {
	part: BasePart,
	velocity: Vector3,
	spin: Vector3,
	resting: boolean,
	half: number,
}
type Segment = {
	from: Vector3,
	way: Vector3,
	length: number,
	width: number,
	appear: number,
	dark: BasePart,
	glow: BasePart?,
}
-- A joint of the serpent's coil: the tip of the part it bends (the next joint, or the tail's end) in that part's frame,
-- how high over the ground the tip lies on flat ground, and the ground under the tip now.
type Link = { joint: Motor6D, tip: Vector3, rest: number, ground: number? }
-- How the serpent lies on what is under it: the joint its coil and neck hang from, its coil's links from the base out,
-- its neck's first joint, the joints from there to its head, and the ground under its head now.
type Drape = { root: Motor6D, links: { Link }, neck: Motor6D?, head: { Motor6D }, ground: number? }
type Show = {
	beast: Model,
	centre: Vector3,
	offset: Vector3,
	look: Vector3,
	height: number,
	bar: BillboardGui,
	-- What the bar hangs on, and how high over the floor it is now.
	barAt: BasePart,
	barHeight: number,
	-- How long its rumble and its flight last (a beast let loose comes quicker), and its headbutt's shown.
	rumbleFor: number,
	flightFor: number,
	rammed: number?,
	bitten: number?,
	dead: boolean,
	diedAt: number,
	sank: boolean,
	hole: Vector3,
	land: Vector3,
	burst: number,
	top: number,
	-- The floor or stairs it lies on now, easing to what is under it; what it lies on, and how the serpent drapes on it.
	ground: number?,
	under: RaycastParams?,
	drape: Drape?,
	-- How far its base tilts up (radians) with what is under it, easing there.
	tilt: number?,
	holder: Folder,
	model: Model,
	mesh: BasePart,
	joints: { [string]: Bone | Motor6D },
	rig: string,
	clips: { [string]: Clip },
	lift: number,
	length: number,
	front: number,
	facing: CFrame,
	segments: { Segment },
	pebbles: { Body },
	flying: { Body },
	light: PointLight,
	dust: ParticleEmitter,
	sparks: ParticleEmitter,
	trail: ParticleEmitter,
	bulge: BasePart?,
	rumble: Sound?,
	floor: { cut: { BasePart }, whole: { BasePart }, hidden: { BasePart } }?,
	pit: { BasePart },
	burstDone: boolean,
	landed: boolean,
	roared: boolean,
	closed: boolean,
	lastShake: number,
	last: Pose,
	clip: string?,
	clipAt: number,
	from: Pose?,
	fromAt: number,
}

local rng = Random.new()
local show: Show? = nil

local function part(parent: Instance, props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function sound(id: string, at: Vector3, volume: number, start: number?, length: number?): Sound
	local spot = Instance.new("Attachment")
	spot.WorldPosition = at
	spot.Parent = Workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.SoundGroup = Preferences.group("Effects")
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 500
	s.TimePosition = start or 0
	s.Parent = spot
	s:Play()
	if length then
		task.delay(length, function()
			TweenService:Create(s, TweenInfo.new(0.4), { Volume = 0 }):Play()
		end)
		Debris:AddItem(spot, length + 0.5)
	else
		Debris:AddItem(spot, 20)
	end
	return s
end

-- Shakes the camera by `strength` (HeroCamera's studs) at `at`'s distance, for `duration` seconds.
local function shake(at: Vector3, strength: number, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local away = (camera.CFrame.Position - at).Magnitude
	local near = math.clamp(1 - away / SHAKE_FAR, 0.15, 1)
	HeroCamera.shake(strength * near, duration)
end

-- A dust emitter on a flat invisible part `size` studs across at `at`.
local function emitter(parent: Instance, at: CFrame, size: Vector3, props: { [string]: any }): ParticleEmitter
	local base = part(parent, { Transparency = 1, Size = size, CFrame = at })
	local p = Instance.new("ParticleEmitter")
	p.Enabled = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = base
	return p
end

local function dustProps(color: Color3): { [string]: any }
	return {
		Texture = SMOKE,
		Color = ColorSequence.new(color),
		LightInfluence = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
	}
end

-- A puff of `count` dust from a ring `radius` studs round `at`, blown outwards along the ground.
local function dustRing(holder: Instance, at: Vector3, radius: number, count: number, speed: number, color: Color3)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local way = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local spot = at + way * radius + Vector3.new(0, 0.8, 0)
		local p = emitter(holder, CFrame.lookAt(spot, spot + way) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.one, {
			Texture = SMOKE,
			Color = ColorSequence.new(color),
			LightInfluence = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2.5 * SCALE * 0.6),
				NumberSequenceKeypoint.new(1, 7 * SCALE * 0.6),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.6, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(speed * 0.6, speed),
			Drag = 3,
			SpreadAngle = Vector2.new(15, 8),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			EmissionDirection = Enum.NormalId.Top,
		})
		p:Emit(2)
		Debris:AddItem(p.Parent :: Instance, 3)
	end
end

-- A flat ring of sand sweeping out from `at` to `radius` studs.
local function shockwave(holder: Instance, at: Vector3, radius: number, time: number)
	local ring = part(holder, {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Sand,
		Color = Color3.fromRGB(236, 212, 168),
		Transparency = 0.35,
		CastShadow = false,
		Size = Vector3.new(0.3, 4, 4),
		CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	})
	TweenService:Create(ring, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, time + 0.1)
end

-- The clip `sequence` as poses by joint name, its moves scaled with the beast.
local function readClip(sequence: KeyframeSequence): Clip
	local frames = sequence:GetKeyframes()
	table.sort(frames, function(a, b)
		return (a :: Keyframe).Time < (b :: Keyframe).Time
	end)
	local times, poses = {}, {}
	for _, frame in frames do
		local pose: Pose = {}
		for _, item in frame:GetDescendants() do
			if item:IsA("Pose") and item.Weight > 0 then
				local cf = item.CFrame
				pose[item.Name] = CFrame.new(cf.Position * SCALE) * cf.Rotation
			end
		end
		table.insert(times, (frame :: Keyframe).Time)
		table.insert(poses, pose)
	end
	return { length = times[#times], loop = sequence.Loop, times = times, poses = poses }
end

local function sample(clip: Clip, t: number): Pose
	local length = clip.length
	t = if clip.loop then t % length else math.clamp(t, 0, length)
	local i = 1
	while i < #clip.times and clip.times[i + 1] <= t do
		i += 1
	end
	local a, b = clip.poses[i], clip.poses[math.min(i + 1, #clip.poses)]
	local span = (clip.times[math.min(i + 1, #clip.times)] - clip.times[i])
	local alpha = if span > 0 then (t - clip.times[i]) / span else 0
	local out: Pose = {}
	for name, cf in a do
		out[name] = cf:Lerp(b[name] or cf, alpha)
	end
	return out
end

local function blend(from: Pose, to: Pose, alpha: number): Pose
	local out: Pose = {}
	for name, cf in to do
		out[name] = (from[name] or CFrame.identity):Lerp(cf, alpha)
	end
	for name, cf in from do
		if not out[name] then
			out[name] = cf:Lerp(CFrame.identity, alpha)
		end
	end
	return out
end

local function apply(s: Show, pose: Pose)
	for name, joint in s.joints do
		joint.Transform = pose[name] or CFrame.identity
	end
	s.last = pose
end

local function rx(degrees: number): CFrame
	return CFrame.Angles(math.rad(degrees), 0, 0)
end

local function ry(degrees: number): CFrame
	return CFrame.Angles(0, math.rad(degrees), 0)
end

local function rz(degrees: number): CFrame
	return CFrame.Angles(0, 0, math.rad(degrees))
end

-- How far into the flight at `u` (0 out of the hole, 1 landing) the beast is: going down, reaching for the ground,
-- and still tucked.
local function phases(u: number): (number, number, number)
	local down = smooth((u - 0.45) / 0.4)
	local reach = smooth((u - 0.55) / 0.3) * (1 - smooth((u - 0.9) / 0.1))
	return down, reach, 1 - down
end

-- The landing's dip `q` seconds after it.
local function dipAt(q: number): number
	return if q < 0.08 then q / 0.08 else math.exp(-(q - 0.08) * SPRING)
end

-- The beetle's six legs by side (1 right, -1 left) and place (1 front, 0 middle, -1 hind). Its joints turn in its
-- root's frame, whose front is -Z: +X lifts the nose, +Z lifts a right leg (and lowers a left one), +Y swings a right
-- leg forward (and a left one back).
local BEETLE_LEGS = {
	{ "Right", "Front", 1, 1 },
	{ "Right", "Mid", 1, 0 },
	{ "Right", "Hind", 1, -1 },
	{ "Left", "Front", -1, 1 },
	{ "Left", "Mid", -1, 0 },
	{ "Left", "Hind", -1, -1 },
}

-- The beetle in flight `t` seconds after the burst: legs drawn up and folded under on the way up, mandibles wide,
-- abdomen hanging; legs spreading and reaching forward for the ground on the way down.
local function beetleFlight(u: number, t: number): Pose
	local down, reach, tuck = phases(u)
	local flutter = math.sin(t * 24)
	local pose: Pose = {
		Thorax = rx(5 * tuck - 4 * down),
		Head = rx(14 * tuck - 10 * down),
		Abdomen = rx(16 * tuck - 4 * down + 2 * flutter),
		RightMandible = ry(-28 * tuck - 18 * reach + 5 * flutter),
		LeftMandible = ry(28 * tuck + 18 * reach - 5 * flutter),
	}
	for i, leg in BEETLE_LEGS do
		local side, place = leg[3], leg[4]
		local kick = flutter * (if i % 2 == 0 then 1 else -1) * 5
		local swing = (-18 * place * tuck + 24 * math.max(place, 0) * reach) * side
		pose[leg[1] .. leg[2] .. "Upper"] = ry(swing) * rz((34 * tuck - 12 * reach + kick) * side)
		pose[leg[1] .. leg[2] .. "Lower"] = rz((-46 * tuck + 14 * reach) * side)
	end
	return pose
end

-- The beetle `q` seconds after landing: its body dropping under its weight between its legs, which splay out, the
-- mandibles snapping; springing back.
local function beetleLanding(q: number): Pose
	local dip = dipAt(q)
	local pose: Pose = {
		Thorax = CFrame.new(0, -DIP * SCALE * 2 * dip, 0) * rx(-4 * dip),
		Head = rx(-10 * dip),
		Abdomen = rx(-6 * dip),
		RightMandible = ry(-20 * dip),
		LeftMandible = ry(20 * dip),
	}
	for _, leg in BEETLE_LEGS do
		local side = leg[3]
		pose[leg[1] .. leg[2] .. "Upper"] = rz(16 * dip * side)
		pose[leg[1] .. leg[2] .. "Lower"] = rz(10 * dip * side)
	end
	return pose
end

-- The serpent's coil from its base to its tail.
local SERPENT_COIL = { "Body1", "Body2", "Body3", "Body4", "Tail1", "Tail2" }

-- The serpent in flight `t` seconds after the burst, like a sandworm: its neck stretched forward so its head leads,
-- jaw wide, its coil waving behind it; drawing its coil back in and rearing up as it comes down.
local function serpentFlight(u: number, t: number): Pose
	local down, reach, tuck = phases(u)
	local stretch = 1 - smooth((u - 0.78) / 0.22)
	local flutter = math.sin(t * 24)
	local pose: Pose = {
		Neck1 = rx(-42 * stretch + 4 * math.sin(t * 7)),
		Neck2 = rx(-30 * stretch),
		Head = rx(12 * tuck - 14 * down),
		Jaw = rx(-34 * tuck - 22 * reach - 4 * flutter),
	}
	for i, name in SERPENT_COIL do
		pose[name] = ry(24 * stretch * math.sin(t * 9 - i * 1.1)) * rx(4 * stretch * math.sin(t * 6 - i))
	end
	return pose
end

-- The serpent `q` seconds after landing: its base dropping into the sand, its neck bowing under the blow and the
-- coil shivering; springing back up.
local function serpentLanding(q: number): Pose
	local dip = dipAt(q)
	local pose: Pose = {
		Base = CFrame.new(0, -DIP * SCALE * dip, 0),
		Neck1 = rx(-20 * dip),
		Neck2 = rx(12 * dip),
		Head = rx(-10 * dip),
		Jaw = rx(-16 * dip),
	}
	for i, name in SERPENT_COIL do
		pose[name] = ry(8 * dip * math.sin(q * 30 + i))
	end
	return pose
end

-- The mole in flight: legs tucked back on the way up, jaw wide, back arched; reaching forward for the ground on the
-- way down.
local function burrowerFlight(u: number, t: number): Pose
	local down, reach, tuck = phases(u)
	local flutter = math.sin(t * 22)
	return {
		Body = rx(-10 * tuck + 6 * down),
		Chest = rx(-8 * tuck - 4 * reach),
		Head = rx(-18 * tuck - 14 * down),
		Jaw = rx(32 * tuck + 10 * reach + 3 * flutter),
		LegFL = rx(55 * tuck - 45 * reach + 4 * flutter),
		LegFR = rx(50 * tuck - 42 * reach - 4 * flutter),
		LegBL = rx(65 * tuck - 22 * reach + 3 * flutter),
		LegBR = rx(60 * tuck - 18 * reach - 3 * flutter),
		Tail = CFrame.Angles(math.rad(25 * tuck - 15 * down + 8 * flutter), math.rad(6 * flutter), 0),
	}
end

-- The mole after landing: the body dipping under its weight, legs spread, springing back.
local function burrowerLanding(q: number): Pose
	local dip = dipAt(q)
	return {
		Body = CFrame.new(0, -DIP * SCALE * dip, 0) * rx(6 * dip),
		Chest = rx(8 * dip),
		Head = rx(-10 * dip),
		Jaw = rx(8 * dip),
		LegFL = rx(-18 * dip),
		LegFR = rx(-16 * dip),
		LegBL = rx(20 * dip),
		LegBR = rx(18 * dip),
		Tail = rx(-12 * dip),
	}
end

local POSES: { [string]: { flight: (number, number) -> Pose, landing: (number) -> Pose } } = {
	Serpent = { flight = serpentFlight, landing = serpentLanding },
	Beetle = { flight = beetleFlight, landing = beetleLanding },
	Burrower = { flight = burrowerFlight, landing = burrowerLanding },
}

-- The floor's top at `at`.
local function floorTop(at: Vector3): number
	local map = Workspace:FindFirstChild("Map")
	local floor = map and map:FindFirstChild("Floor")
	if not floor then
		return at.Y
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { floor }
	local hit = Workspace:Raycast(Vector3.new(at.X, 60, at.Z), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position.Y else at.Y
end

-- What it lies on: the floor and the bases' stairs.
local function lyingOn(): RaycastParams?
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	local under = {}
	local floor = map:FindFirstChild("Floor")
	if floor then
		table.insert(under, floor)
	end
	for _, base in map:GetChildren() do
		for _, name in CLIMBS do
			for _, piece in base:GetChildren() do
				if piece.Name == name then
					table.insert(under, piece)
				end
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = under
	return params
end

-- The highest of what it lies on at `at` and `feel` studs either way along `way`.
local function groundAt(params: RaycastParams, at: Vector3, way: Vector3, feel: number, fallback: number): number
	local top = -math.huge
	for _, along in { -feel, 0, feel } do
		local spot = at + way * along
		local hit = Workspace:Raycast(Vector3.new(spot.X, 60, spot.Z), Vector3.new(0, -120, 0), params)
		if hit then
			top = math.max(top, hit.Position.Y)
		end
	end
	return if top > -math.huge then top else fallback
end

-- The serpent's coil and neck laid on what is under them, over the pose just shown, its base on `s.ground` and
-- `sink` studs into it.
local function drape(s: Show, dt: number, sink: number)
	local d, params, root = s.drape, s.under, s.model.PrimaryPart
	if not d or not params or not root then
		return
	end
	local ease = 1 - math.exp(-CLIMB * dt)
	local base = s.ground :: number
	local function settle(old: number?, new: number): number
		return if old then old + (new - old) * ease else new
	end
	local tilt = s.tilt or 0
	local pitchAxis = s.look:Cross(Vector3.yAxis)
	local seat = root.CFrame * d.root.C0
	local held = seat * d.root.Transform
	held = CFrame.new(held.Position) * CFrame.fromAxisAngle(pitchAxis, tilt) * held.Rotation
	d.root.Transform = seat:Inverse() * held
	local hung = held * d.root.C1:Inverse()
	local parent = hung
	for _, link in d.links do
		local joint = link.joint
		local hinge = parent * joint.C0
		local turned = hinge * joint.Transform
		local tip = turned * joint.C1:Inverse() * link.tip
		local arm = tip - turned.Position
		local flat = Vector3.new(arm.X, 0, arm.Z)
		local along = if flat.Magnitude > 0.1 then flat.Unit else s.look
		local ground = settle(link.ground, groundAt(params, tip, along, LINK_FEEL, base))
		link.ground = ground
		local length = arm.Magnitude
		if flat.Magnitude > 0.1 and length > 0.1 then
			local pitch = math.asin(math.clamp(arm.Y / length, -1, 1))
			local wanted = math.asin(math.clamp((ground + link.rest - sink - turned.Position.Y) / length, -1, 1))
			local bend = math.clamp(wanted - pitch, -DRAPE, DRAPE)
			turned = CFrame.new(turned.Position)
				* CFrame.fromAxisAngle(along:Cross(Vector3.yAxis), bend)
				* turned.Rotation
			joint.Transform = hinge:Inverse() * turned
		end
		parent = turned * joint.C1:Inverse()
	end
	local neck = d.neck
	if neck then
		local hinge = hung * neck.C0
		local upright = hinge * neck.Transform
		upright = CFrame.new(upright.Position) * CFrame.fromAxisAngle(pitchAxis, -tilt) * upright.Rotation
		neck.Transform = hinge:Inverse() * upright
		local head = upright * neck.C1:Inverse()
		for _, joint in d.head do
			head = head * joint.C0 * joint.Transform * joint.C1:Inverse()
		end
		local ground = settle(d.ground, groundAt(params, head.Position, s.look, LINK_FEEL, base))
		d.ground = ground
		local rise = math.clamp(ground - base, -NECK_RISE, NECK_RISE)
		neck.Transform = CFrame.new(hinge:VectorToObjectSpace(Vector3.new(0, rise, 0))) * neck.Transform
	end
end

-- How the serpent drapes (`drape`), from its rig at rest at the origin, `lift` over the ground.
local function drapeOf(model: Model, joints: { [string]: Bone | Motor6D }, lift: number): Drape?
	local root, hung = model.PrimaryPart, joints.Base
	if not root or not hung or not hung:IsA("Motor6D") then
		return nil
	end
	local function motor(name: string?): Motor6D?
		local joint = if name then joints[name] else nil
		return if joint and joint:IsA("Motor6D") then joint else nil
	end
	local links: { Link } = {}
	local at = root.CFrame * hung.C0 * hung.C1:Inverse()
	for i, name in SERPENT_COIL do
		local joint = motor(name)
		if not joint then
			break
		end
		at = at * joint.C0 * joint.C1:Inverse()
		local after = motor(SERPENT_COIL[i + 1])
		local tip = if after then after.C0.Position else -joint.C1.Position
		table.insert(links, { joint = joint, tip = tip, rest = (at * tip).Y + lift, ground = nil })
	end
	local head: { Motor6D } = {}
	for _, name in { "Neck2", "Head" } do
		local joint = motor(name)
		if joint then
			table.insert(head, joint)
		end
	end
	return { root = hung, links = links, neck = motor("Neck1"), head = head, ground = nil }
end

-- The cracks running out from `at` over the floor's top `top`.
local function buildCracks(holder: Instance, at: Vector3, top: number, glowing: boolean, spread: number): { Segment }
	local segments: { Segment } = {}
	local function run(start: Vector3, angle: number, steps: number, width: number, appear: number, step: number)
		local point = start
		for k = 1, steps do
			angle += rng:NextNumber(-0.55, 0.55)
			local way = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local length = rng:NextNumber(1.3, 2.6) * spread
			local w = width * (1 - 0.6 * (k - 1) / steps)
			local dark = part(holder, {
				Material = Enum.Material.SmoothPlastic,
				Color = CRACK,
				Transparency = 1,
				CastShadow = false,
				Size = Vector3.new(w, 0.06, 0.1),
				CFrame = CFrame.new(point),
			})
			local glow = if glowing
				then part(holder, {
					Material = Enum.Material.Neon,
					Color = CRYSTAL,
					Transparency = 1,
					CastShadow = false,
					Size = Vector3.new(w * GLOW_WIDTH, 0.07, 0.1),
					CFrame = CFrame.new(point),
				})
				else nil
			table.insert(segments, {
				from = point,
				way = way,
				length = length,
				width = w,
				appear = appear + (k - 1) * step,
				dark = dark,
				glow = glow,
			})
			point += way * length
		end
		return point, angle
	end
	for i = 1, CRACKS do
		local angle = (i / CRACKS) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local start = Vector3.new(at.X, top + 0.03, at.Z) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 0.6
		local steps = rng:NextInteger(5, 8)
		local first = rng:NextNumber(0, 0.25) * CRACK_SPREAD
		local step = (CRACK_SPREAD - first) / (steps + 2)
		local point = start
		local direction = angle
		for k = 1, steps do
			point, direction = run(point, direction, 1, 0.42 * (1 - 0.6 * k / steps), first + (k - 1) * step, step)
			if k > 1 and k < steps and rng:NextNumber() < 0.3 then
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				run(point, direction + side * rng:NextNumber(0.6, 1.1), 3, 0.2, first + k * step, step)
			end
		end
	end
	return segments
end

local function showCracks(segments: { Segment }, progress: number, glow: number)
	for _, seg in segments do
		local grow = math.clamp((progress - seg.appear) / 0.06, 0, 1)
		if grow > 0 then
			local length = seg.length * grow
			local middle = seg.from + seg.way * length / 2
			local cf = CFrame.lookAt(middle, middle + seg.way)
			seg.dark.Size = Vector3.new(seg.width, 0.06, length)
			seg.dark.CFrame = cf
			seg.dark.Transparency = 0
			if seg.glow then
				seg.glow.Size = Vector3.new(seg.width * GLOW_WIDTH, 0.07, length)
				seg.glow.CFrame = cf + Vector3.new(0, 0.01, 0)
				seg.glow.Transparency = 1 - glow * grow
			end
		end
	end
end

-- The floor's sand and grass with the hole cut out, hidden till the burst; the whole floor stays for walking on.
local function cutFloor(s: Show)
	local map = Workspace:FindFirstChild("Map")
	local floor = map and map:FindFirstChild("Floor")
	if not floor then
		return
	end
	local cutter = part(s.holder, {
		Shape = Enum.PartType.Cylinder,
		Transparency = 1,
		Size = Vector3.new(30, HOLE * 2, HOLE * 2),
		CFrame = CFrame.new(s.hole.X, s.top, s.hole.Z) * CFrame.Angles(0, 0, math.pi / 2),
	})
	local cut, whole, hidden = {}, {}, {}
	for _, name in { "Sand", "Grass" } do
		local piece = floor:FindFirstChild(name)
		if piece and piece:IsA("BasePart") then
			local ok, result = pcall(function()
				return GeometryService:SubtractAsync(piece, { cutter }, {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Precise,
					SplitApart = false,
				})
			end)
			local union = ok and result and result[1]
			if union and union:IsA("BasePart") then
				union.Anchored = true
				union.CanCollide = false
				union.CanQuery = false
				union.CanTouch = false
				union.Color = piece.Color
				union.Material = piece.Material
				if union:IsA("PartOperation") then
					union.UsePartColor = true
				end
				union.Transparency = 1
				union.Parent = s.holder
				table.insert(cut, union)
				table.insert(whole, piece)
			else
				warn("[BeastView] could not cut the hole:", result)
			end
		end
	end
	-- The sand's patches over the hole go with it.
	for _, patch in floor:GetChildren() do
		if patch:IsA("BasePart") and patch.Name ~= "Sand" and patch.Name ~= "Grass" then
			local away = Vector3.new(patch.Position.X - s.hole.X, 0, patch.Position.Z - s.hole.Z).Magnitude
			if away < HOLE + patch.Size.Y / 2 then
				table.insert(hidden, patch)
			end
		end
	end
	cutter:Destroy()
	s.floor = { cut = cut, whole = whole, hidden = hidden }
end

local function openFloor(s: Show, open: boolean)
	local floor = s.floor
	if not floor or #floor.cut == 0 then
		return
	end
	for _, union in floor.cut do
		union.Transparency = if open then 0 else 1
	end
	for _, piece in floor.whole do
		piece.LocalTransparencyModifier = if open then 1 else 0
	end
	for _, patch in floor.hidden do
		patch.LocalTransparencyModifier = if open then 1 else 0
	end
end

-- The shaft under the hole: walls of earth, darker deeper down, and the torn crust standing up round its edge.
local function buildPit(s: Show)
	local centre = Vector3.new(s.hole.X, s.top, s.hole.Z)
	-- Inside the cut, so they cover its edges.
	local radius = HOLE - 0.7
	local around = 2 * math.pi * radius / WALLS * 1.15
	local bands = {
		{ 0, 4, EARTH, Enum.Material.Ground },
		{ 4, 14, EARTH:Lerp(DEEP, 0.55), Enum.Material.Ground },
		{ 14, DEPTH, DEEP, Enum.Material.Slate },
	}
	for i = 1, WALLS do
		local angle = (i / WALLS) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		for _, band in bands do
			local high, low = band[1] :: number, band[2] :: number
			local at = centre + out * radius - Vector3.new(0, (high + low) / 2 - 0.05, 0)
			table.insert(
				s.pit,
				part(s.holder, {
					Material = band[4],
					Color = band[3],
					Transparency = 1,
					Size = Vector3.new(around, low - high, 1.6),
					CFrame = CFrame.lookAt(at, at - out),
				})
			)
		end
	end
	table.insert(
		s.pit,
		part(s.holder, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(14, 11, 9),
			Transparency = 1,
			Size = Vector3.new(1, HOLE * 2 + 4, HOLE * 2 + 4),
			CFrame = CFrame.new(centre - Vector3.new(0, DEPTH, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		})
	)
end

-- The crust torn up round the hole's edge at the burst, rising into place.
local function tearCrust(s: Show)
	local sand = s.floor and s.floor.whole[1]
	local color = if sand then sand.Color else Color3.fromRGB(226, 190, 132)
	local centre = Vector3.new(s.hole.X, s.top, s.hole.Z)
	local count = 16
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local size = Vector3.new(rng:NextNumber(4.5, 6.5), rng:NextNumber(0.7, 1.2), rng:NextNumber(3, 5))
		local at = centre + out * (HOLE - 0.6 + size.Z * 0.45)
		-- Torn up from below: the edge at the hole raised, the outer one still in the sand.
		local tilt = math.rad(rng:NextNumber(18, 38))
		local goal = CFrame.lookAt(at, at + out)
				* CFrame.Angles(-tilt, rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.12, 0.12))
			+ Vector3.new(0, math.sin(tilt) * size.Z * 0.35, 0)
		local slab = part(s.holder, {
			Material = Enum.Material.Sand,
			Color = color,
			Size = size,
			CFrame = goal - Vector3.new(0, 3, 0),
		})
		-- Its broken side, earth under the sand.
		local under = part(s.holder, {
			Material = Enum.Material.Ground,
			Color = EARTH,
			Size = size - Vector3.new(0.2, size.Y * 0.4, 0.2),
			CFrame = goal * CFrame.new(0, -size.Y * 0.35, 0) - Vector3.new(0, 3, 0),
		})
		TweenService:Create(under, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = goal * CFrame.new(0, -size.Y * 0.35, 0),
		}):Play()
		table.insert(s.pit, under)
		TweenService:Create(slab, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = goal,
		}):Play()
		table.insert(s.pit, slab)
		if rng:NextNumber() < 0.5 then
			local rock = part(s.holder, {
				Material = Enum.Material.Slate,
				Color = EARTH:Lerp(DEEP, rng:NextNumber(0, 0.6)),
				Size = Vector3.new(rng:NextNumber(0.8, 1.8), rng:NextNumber(0.6, 1.2), rng:NextNumber(0.8, 1.8)),
				CFrame = CFrame.new(at + out * rng:NextNumber(2.5, 5) + Vector3.new(0, 0.3, 0))
					* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			})
			table.insert(s.pit, rock)
		end
	end
end

-- Clods of sand and earth, rocks and crystals thrown up out of the hole.
local function throwClods(s: Show, at: Vector3, count: number, crystals: number, power: number)
	local sand = s.floor and s.floor.whole[1]
	local color = if sand then sand.Color else Color3.fromRGB(226, 190, 132)
	for i = 1, count + crystals do
		local crystal = i > count
		local size = if crystal
			then Vector3.new(rng:NextNumber(0.3, 0.6), rng:NextNumber(0.9, 1.8), rng:NextNumber(0.3, 0.6))
			else Vector3.new(rng:NextNumber(1, 3), rng:NextNumber(0.5, 1.4), rng:NextNumber(1, 3)) * power
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local earth = rng:NextNumber() < 0.4
		local clod = part(s.holder, {
			Material = if crystal then Enum.Material.Neon elseif earth then Enum.Material.Ground else Enum.Material.Sand,
			Color = if crystal then CRYSTAL elseif earth then EARTH:Lerp(DEEP, rng:NextNumber(0, 0.4)) else color,
			Transparency = if crystal then 0.2 else 0,
			Size = size,
			CFrame = CFrame.new(at + out * rng:NextNumber(0, HOLE * 0.8) + Vector3.new(0, 0.5, 0))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
		}, if not crystal and rng:NextNumber() < 0.5 then "WedgePart" else nil)
		if crystal then
			-- The crystals' light dies out and they crumble away.
			local die = rng:NextNumber(2, 3.5)
			TweenService
				:Create(clod, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, die), {
					Transparency = 1,
					Size = size * 0.3,
				})
				:Play()
			Debris:AddItem(clod, die + 0.7)
		end
		table.insert(s.flying, {
			part = clod,
			velocity = out * rng:NextNumber(10, 34) * power
				+ Vector3.new(0, rng:NextNumber(45, 95) * math.sqrt(power), 0),
			spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			resting = false,
			half = size.Y / 2,
		})
	end
end

local function stepBodies(s: Show, bodies: { Body }, dt: number, gravity: number)
	for _, b in bodies do
		if b.resting or not b.part.Parent then
			continue
		end
		b.velocity -= Vector3.new(0, gravity * dt, 0)
		local cf = b.part.CFrame + b.velocity * dt
		cf *= CFrame.Angles(b.spin.X * dt, b.spin.Y * dt, b.spin.Z * dt)
		local away = Vector3.new(cf.Position.X - s.hole.X, 0, cf.Position.Z - s.hole.Z).Magnitude
		local overHole = s.burstDone and not s.closed and away < HOLE + 0.3
		local ground = s.top + b.half * 0.8
		if not overHole and cf.Position.Y < ground and b.velocity.Y < 0 then
			cf = cf + Vector3.new(0, ground - cf.Position.Y, 0)
			if math.abs(b.velocity.Y) < 9 then
				b.resting = true
			else
				b.velocity = Vector3.new(b.velocity.X * 0.5, -b.velocity.Y * 0.3, b.velocity.Z * 0.5)
				b.spin *= 0.5
			end
		elseif overHole and cf.Position.Y < s.top - DEPTH + 2 then
			b.part:Destroy()
			continue
		end
		b.part.CFrame = cf
	end
end

local function clipAt(s: Show, name: string, now: number, again: boolean?)
	if (s.clip == name and not again) or not s.clips[name] then
		return
	end
	s.from = s.last
	s.fromAt = now
	s.clip = name
	s.clipAt = now
end

-- The beast's place on the flight at `t` seconds after the burst: where its middle is, and its pitch.
local function flight(s: Show, t: number): (CFrame, number)
	local x = math.clamp(t / s.flightFor, 0, 1)
	local held = BREACH[1] * BREACH[2]
	local u = (x + HANG * math.sin(2 * math.pi * x) / (2 * math.pi) - held * (1 - math.exp(-x / BREACH[2])))
		/ (1 - held * (1 - math.exp(-1 / BREACH[2])))
	local landY = s.top + s.lift
	local startY = s.top - (s.length / 2) * math.sin(PITCH_UP) - 1
	local rise = 4 * (s.top + SETTINGS.Height - (startY + landY) / 2)
	local y = startY * (1 - u) + landY * u + rise * u * (1 - u)
	local flat = s.hole:Lerp(s.land, u)
	local climb = (landY - startY) + rise * (1 - 2 * u)
	local pitch = math.clamp(math.atan2(climb, (s.land - s.hole).Magnitude), PITCH_DOWN, PITCH_UP)
	pitch *= 1 - smooth((u - 0.68) / 0.27)
	local roll = math.rad(14) * math.sin(math.pi * u)
	local at = CFrame.new(flat.X, y, flat.Z) * s.facing.Rotation * CFrame.Angles(-pitch * s.front, 0, roll)
	return at, u
end

local function burst(s: Show)
	s.burstDone = true
	local centre = Vector3.new(s.hole.X, s.top, s.hole.Z)
	if s.bulge then
		s.bulge:Destroy()
		s.bulge = nil
	end
	openFloor(s, true)
	for _, piece in s.pit do
		piece.Transparency = 0
	end
	tearCrust(s)
	for _, seg in s.segments do
		local middle = seg.from + seg.way * seg.length / 2
		if Vector3.new(middle.X - centre.X, 0, middle.Z - centre.Z).Magnitude < HOLE + 0.6 then
			seg.dark.Transparency = 1
			if seg.glow then
				seg.glow.Transparency = 1
			end
		end
	end
	for _, b in s.pebbles do
		b.part:Destroy()
	end
	s.pebbles = {}
	throwClods(s, centre, 26, 12, 1)
	-- The dust shooting up out of the hole, and rolling out over the sand.
	local sand = s.floor and s.floor.whole[1]
	local sandColor = if sand then sand.Color else EARTH
	local column = emitter(
		s.holder,
		CFrame.new(centre),
		Vector3.new(HOLE * 1.6, 1, HOLE * 1.6),
		dustProps(sandColor:Lerp(EARTH, 0.4))
	)
	column.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 13),
	})
	column.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	column.Lifetime = NumberRange.new(1, 2.2)
	column.Speed = NumberRange.new(30, 75)
	column.SpreadAngle = Vector2.new(18, 18)
	column.Drag = 3
	column.Acceleration = Vector3.new(0, -4, 0)
	column:Emit(40)
	dustRing(s.holder, centre, HOLE + 1, 22, 40, sandColor)
	s.sparks:Emit(80)
	s.dust.Enabled = false
	s.sparks.Enabled = false
	s.light.Brightness = 5
	s.light.Range = 28
	TweenService:Create(s.light, TweenInfo.new(1.2), { Brightness = 0, Range = 10 }):Play()
	if s.rumble then
		TweenService:Create(s.rumble, TweenInfo.new(2.5), { Volume = 0 }):Play()
	end
	sound(Assets.BeastBurst, centre, 2.2, BURST_FROM, 4)
	sound(Assets.FightBoom, centre, 1.4)
	sound(Assets.RockBreak, centre, 1.8)
	sound(Assets.GlassShards, centre, 0.9)
	shake(centre, 2.2, 0.9)
	s.model.Parent = s.holder
	s.trail.Enabled = true
end

local function land(s: Show)
	s.landed = true
	s.trail.Enabled = false
	local at = Vector3.new(s.land.X, s.top, s.land.Z)
	local sand = s.floor and s.floor.whole[1]
	local color = if sand then sand.Color else EARTH
	dustRing(s.holder, at, 5 * SCALE * 0.6, 26, 55, color)
	shockwave(s.holder, at, SETTINGS.Slam, 0.5)
	throwClods(s, at, 10, 0, 0.6)
	for _, seg in buildCracks(s.holder, at, s.top, false, 0.7) do
		local middle = seg.from + seg.way * seg.length / 2
		if Vector3.new(middle.X - s.hole.X, 0, middle.Z - s.hole.Z).Magnitude < HOLE + 1 then
			seg.dark:Destroy()
			continue
		end
		seg.appear = 0
		table.insert(s.segments, seg)
	end
	showCracks(s.segments, 1, 0)
	sound(Assets.DeepThud, at, 2)
	sound(Assets.RockBreak, at, 1.4)
	sound(Assets.FightBoom, at, 1)
	shake(at, 2.6, 0.7)
end

local function roar(s: Show)
	s.roared = true
	local at = Vector3.new(s.land.X, s.top, s.land.Z)
	sound(Assets.BeastRoar, at, 2, ROAR_FROM, 2.8)
	shake(at, 0.9, 1.4)
	dustRing(s.holder, at, 4, 16, 30, EARTH)
end

-- The sand closes over the hole: its clods sink, the floor is whole again.
local function close(s: Show)
	s.closed = true
	for _, piece in s.pit do
		TweenService:Create(piece, TweenInfo.new(1.2), { CFrame = piece.CFrame - Vector3.new(0, 4, 0) }):Play()
	end
	for _, b in s.flying do
		if b.part.Parent then
			TweenService:Create(b.part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			Debris:AddItem(b.part, 1.6)
		end
	end
	for _, seg in s.segments do
		TweenService:Create(seg.dark, TweenInfo.new(1.5), { Transparency = 1 }):Play()
	end
	dustRing(s.holder, Vector3.new(s.hole.X, s.top, s.hole.Z), HOLE * 0.6, 14, 14, EARTH)
	task.delay(1.2, function()
		openFloor(s, false)
		for _, piece in s.pit do
			piece:Destroy()
		end
	end)
end

-- The bar over the coil's middle, over its top; up close, where that is above the screen, as much lower as keeps it
-- on it, but never lower than BAR_LOWEST over the floor (owner, 2026-11-26).
local function placeBar(s: Show, ground: number, dt: number)
	local camera = Workspace.CurrentCamera
	local highest = s.height + BAR_OVER
	local function onScreen(height: number): boolean
		local point, ahead = camera:WorldToViewportPoint(Vector3.new(s.centre.X, ground + height, s.centre.Z))
		return ahead and point.Y >= BAR_MARGIN
	end
	local want = highest
	if not onScreen(highest) and onScreen(BAR_LOWEST) then
		local low, high = BAR_LOWEST, highest
		for _ = 1, 10 do
			local mid = (low + high) / 2
			if onScreen(mid) then
				low = mid
			else
				high = mid
			end
		end
		want = low
	end
	s.barHeight += (want - s.barHeight) * (1 - math.exp(-BAR_EASE * dt))
	s.barAt.CFrame = CFrame.new(s.centre.X, ground + s.barHeight, s.centre.Z)
end

local function step(s: Show, dt: number)
	local now = Workspace:GetServerTimeNow()
	local t = now - s.burst
	local centre = Vector3.new(s.hole.X, s.top, s.hole.Z)

	if t < 0 then
		-- The rumble.
		local progress = math.clamp(1 + t / s.rumbleFor, 0, 1)
		local flicker = 0.75 + 0.25 * math.sin(now * 31) * math.sin(now * 13)
		showCracks(s.segments, progress, 0.85 * smooth(progress * 1.3) * flicker)
		s.light.Brightness = 4 * progress * flicker
		s.light.Range = 6 + 22 * progress
		s.dust.Rate = 4 + 30 * progress
		s.sparks.Rate = 25 * progress
		if now - s.lastShake > 0.25 then
			s.lastShake = now
			shake(centre, 0.12 + 0.5 * progress, 0.4)
		end
		for _, b in s.pebbles do
			if b.resting and rng:NextNumber() < dt * (1 + 9 * progress) then
				b.resting = false
				b.velocity =
					Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 13) * (0.4 + progress), rng:NextNumber(-2, 2))
				b.spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
			end
		end
		stepBodies(s, s.pebbles, dt, Workspace.Gravity)
		local bulging = math.clamp((t + BULGE) / BULGE, 0, 1)
		if bulging > 0 then
			if not s.bulge then
				local sand = s.floor and s.floor.whole[1]
				s.bulge = part(s.holder, {
					Shape = Enum.PartType.Cylinder,
					Material = Enum.Material.Sand,
					Color = if sand then sand.Color else Color3.fromRGB(226, 190, 132),
					Size = Vector3.new(1.6, HOLE * 1.9, HOLE * 1.9),
				})
			end
			local jitter = Vector3.new(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
			local bulge = s.bulge :: BasePart
			bulge.CFrame = CFrame.new(centre + jitter + Vector3.new(0, -0.82 + BULGE_HEIGHT * bulging ^ 1.6, 0))
				* CFrame.Angles(rng:NextNumber(-0.03, 0.03), 0, math.pi / 2 + rng:NextNumber(-0.03, 0.03))
		end
		return
	end

	if not s.burstDone then
		burst(s)
	end
	stepBodies(s, s.flying, dt, Workspace.Gravity)

	if t < s.flightFor then
		local at, u = flight(s, t)
		s.model:PivotTo(at)
		apply(s, POSES[s.rig].flight(u, t))
		return
	end
	if not s.landed then
		land(s)
	end
	local q = t - s.flightFor
	if q >= SETTINGS.Roar and not s.roared then
		roar(s)
		clipAt(s, "Roar", now)
	end
	local beast = s.beast
	if beast:GetAttribute("Phase") == "Dead" and not s.dead then
		s.dead = true
		s.diedAt = beast:GetAttribute("DiedAt") or now
		s.bar.Enabled = false
		clipAt(s, "Death", s.diedAt)
		if now - s.diedAt < 1 then
			local cry = sound(Assets.BeastDeath, s.centre + Vector3.new(0, s.height / 2, 0), 2.6)
			cry.PlaybackSpeed = DEATH_PITCH
		end
	end
	-- Its headbutt on the Master: the ground shakes and bursts where its head strikes.
	local ram = beast:GetAttribute("Ram")
	if type(ram) == "number" and ram ~= s.rammed and now >= ram + SETTINGS.Bite.Hit then
		s.rammed = ram
		local at = Vector3.new(s.centre.X, s.ground or s.top, s.centre.Z) + s.look * SETTINGS.Bite.Reach
		sound(Assets.BeastBurst, at, 3, 1)
		sound(Assets.RockBreak, at, 2)
		shake(at, 2.2, 0.8)
		shockwave(s.holder, at, SETTINGS.Radius * 1.4, 0.45)
		dustRing(s.holder, at, SETTINGS.Radius * 0.6, 24, 34, EARTH)
	end
	local bite = beast:GetAttribute("Bite")
	if not s.dead and type(bite) == "number" and bite ~= s.bitten then
		s.bitten = bite
		clipAt(s, "Attack", bite, true)
	end
	local playing = if s.clip then s.clips[s.clip] else nil
	if s.roared and not s.dead and not (playing and not playing.loop and now - s.clipAt < playing.length) then
		clipAt(s, if beast:GetAttribute("Moving") then "Walk" else "Idle", now)
	end
	local clip = if s.clip then s.clips[s.clip] else nil
	local pose = if clip then sample(clip, now - s.clipAt) else POSES[s.rig].landing(q)
	if s.clip and s.from and now - s.fromAt < BLEND then
		pose = blend(s.from, pose, smooth((now - s.fromAt) / BLEND))
	end
	apply(s, pose)

	local want = beast:GetAttribute("Look")
	if typeof(want) == "Vector3" and not s.dead then
		local turned = s.look:Lerp(want, 1 - math.exp(-TURN * dt))
		if turned.Magnitude > 0.01 then
			s.look = turned.Unit
		end
	end
	local coil = beast:GetAttribute("Centre")
	if typeof(coil) == "Vector3" then
		s.centre = s.centre:Lerp(coil, 1 - math.exp(-SLIDE * dt))
	end
	local sink = 0
	if s.dead then
		local death = if s.clips.Death then s.clips.Death.length else 0
		local into = now - s.diedAt - death
		if into > 0 and not s.sank then
			s.sank = true
			local at = Vector3.new(s.centre.X, s.top, s.centre.Z)
			dustRing(s.holder, at, SETTINGS.Radius * 0.7, 20, 24, EARTH)
			sound(Assets.RockBreak, at, 1.4)
			shake(at, 0.8, 0.6)
		end
		sink = s.height * smooth(into / math.max(SETTINGS.Dying - death - 0.3, 0.1))
	end
	local face = CFrame.lookAt(Vector3.zero, -s.look * s.front)
	local base = s.centre - face:VectorToWorldSpace(s.offset)
	local params = s.under
	local below = s.top
	local ease = 1 - math.exp(-CLIMB * dt)
	if params and s.drape then
		local ahead = groundAt(params, base + s.look * BASE_FEEL, s.look, 0, s.top)
		local behind = groundAt(params, base - s.look * BASE_FEEL, s.look, 0, s.top)
		below = math.max(groundAt(params, base, s.look, 0, s.top), (ahead + behind) / 2)
		local tilt = math.clamp(math.atan2(ahead - behind, 2 * BASE_FEEL), -BASE_TILT, BASE_TILT)
		s.tilt = if s.tilt then s.tilt + (tilt - s.tilt) * ease else tilt
	elseif params then
		below = groundAt(params, s.centre, s.look, s.length * FEEL, s.top)
	end
	s.ground = if s.ground then s.ground + (below - s.ground) * ease else below
	local ground = s.ground :: number
	s.model:PivotTo(CFrame.new(base.X, ground + s.lift - sink, base.Z) * face)
	drape(s, dt, sink)
	placeBar(s, ground, dt)
	if t >= SETTINGS.Crater and not s.closed then
		close(s)
	end
end

-- Its name and health over it, shown once it is out.
local function healthBar(s: Show): BillboardGui
	local C = UiStyle.Colors
	local at = Instance.new("Part")
	at.Name = "BarAt"
	at.Anchored = true
	at.CanCollide = false
	at.CanQuery = false
	at.CanTouch = false
	at.Transparency = 1
	at.Size = Vector3.one
	at.Parent = s.holder
	s.barAt = at
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeastBar"
	gui.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT + BAR_NAME)
	gui.LightInfluence = 0
	gui.MaxDistance = BAR_FAR
	gui.Enabled = false
	gui.Adornee = at
	-- Let loose, it fights for a team: its bar in that team's colour on this screen, as a hero's (HeroBars).
	local team = s.beast:GetAttribute("Team")
	local top, bottom = BAR_TOP, BAR_BOTTOM
	if s.beast:GetAttribute("Released") and type(team) == "string" then
		local shown = Side.shown(team)
		local colour = C[shown]
		top, bottom = colour:Lerp(Color3.new(1, 1, 1), 0.2), colour:Lerp(C[shown .. "Dark"], 0.4)
	end
	local bar = UiStyle.bar(
		gui,
		UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
		UDim2.new(0, 0, 1, -BAR_HEIGHT),
		top,
		bottom,
		nil,
		nil,
		C.Trail
	);
	(bar.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 2
	local name = UiStyle.text(gui, SETTINGS.Name, 16, C.Cream, C.Edge)
	name.Size = UDim2.new(1, 0, 0, BAR_NAME)
	local beast = s.beast
	local function update()
		local most = beast:GetAttribute("MaxHealth") or 1
		bar:set((beast:GetAttribute("Health") or 0) / math.max(most, 1))
		local phase = beast:GetAttribute("Phase")
		gui.Enabled = phase == "Out" or phase == "Fight"
	end
	beast:GetAttributeChangedSignal("Health"):Connect(update)
	beast:GetAttributeChangedSignal("Phase"):Connect(update)
	update()
	gui.Parent = s.holder
	return gui
end

local function begin(beast: Model)
	local template = ReplicatedStorage:FindFirstChild("Beast")
	if not template or not template:IsA("Model") then
		warn("[BeastView] ReplicatedStorage.Beast is missing")
		return
	end
	local hole, landAt, burstAt = beast:GetAttribute("Hole"), beast:GetAttribute("Land"), beast:GetAttribute("Burst")
	if typeof(hole) ~= "Vector3" or typeof(landAt) ~= "Vector3" or type(burstAt) ~= "number" then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "BeastView"
	holder.Parent = Workspace

	local model = template:Clone()
	model:ScaleTo(SCALE)
	model:PivotTo(CFrame.identity)
	local box, size = model:GetBoundingBox()
	local lift = -(box.Position.Y - size.Y / 2)
	local joints: { [string]: Bone | Motor6D } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Bone") then
			joints[item.Name] = item
		elseif item:IsA("Motor6D") and item.Part1 then
			joints[item.Part1.Name] = item
		end
	end
	-- Parts hung on Motor6Ds follow their joints only unanchored, on the anchored root.
	local jointed = model.PrimaryPart ~= nil and model:FindFirstChildWhichIsA("Motor6D", true) ~= nil
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = not jointed or item == model.PrimaryPart
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
		end
	end
	local mesh = model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart") :: BasePart
	local front = model:GetAttribute("Front")
	local rig = model:GetAttribute("Rig")
	if type(rig) ~= "string" or not POSES[rig] or (front ~= 1 and front ~= -1) then
		warn("[BeastView] ReplicatedStorage.Beast needs a known Rig attribute and a Front of 1 or -1")
		holder:Destroy()
		return
	end
	local clips: { [string]: Clip } = {}
	local saves = model:FindFirstChild("AnimSaves")
	for _, sequence in if saves then saves:GetChildren() else {} do
		if sequence:IsA("KeyframeSequence") then
			clips[sequence.Name] = readClip(sequence)
		end
	end
	local way = Vector3.new(landAt.X - hole.X, 0, landAt.Z - hole.Z).Unit
	local top = floorTop(hole)

	local centreAt = beast:GetAttribute("Centre")
	local s: Show = {
		beast = beast,
		centre = if typeof(centreAt) == "Vector3" then centreAt else landAt,
		offset = Vector3.new(box.Position.X, 0, box.Position.Z),
		look = way,
		height = size.Y,
		bar = nil :: any,
		barAt = nil :: any,
		barHeight = size.Y + BAR_OVER,
		rumbleFor = beast:GetAttribute("Rumble") or SETTINGS.Rumble,
		flightFor = beast:GetAttribute("Flight") or SETTINGS.Flight,
		rammed = beast:GetAttribute("Ram"),
		bitten = beast:GetAttribute("Bite"),
		dead = false,
		diedAt = 0,
		sank = false,
		hole = Vector3.new(hole.X, top, hole.Z),
		land = Vector3.new(landAt.X, top, landAt.Z),
		burst = burstAt,
		top = top,
		holder = holder,
		model = model,
		mesh = mesh,
		joints = joints,
		rig = rig,
		clips = clips,
		lift = lift,
		under = lyingOn(),
		drape = if rig == "Serpent" then drapeOf(model, joints, lift) else nil,
		length = size.Z,
		front = front,
		facing = CFrame.lookAt(Vector3.zero, -way * front),
		segments = {},
		pebbles = {},
		flying = {},
		light = Instance.new("PointLight"),
		dust = nil :: any,
		sparks = nil :: any,
		trail = nil :: any,
		bulge = nil,
		rumble = nil,
		floor = nil,
		pit = {},
		burstDone = false,
		landed = false,
		roared = false,
		closed = false,
		lastShake = 0,
		last = {},
		clip = nil,
		clipAt = 0,
		from = nil,
		fromAt = 0,
	}
	local centre = Vector3.new(hole.X, top, hole.Z)
	local glowSpot =
		part(holder, { Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(centre + Vector3.new(0, 1, 0)) })
	s.light.Color = CRYSTAL
	s.light.Brightness = 0
	s.light.Range = 6
	s.light.Shadows = false
	s.light.Parent = glowSpot

	local dust = emitter(holder, CFrame.new(centre), Vector3.new(HOLE * 2.4, 0.5, HOLE * 2.4), dustProps(EARTH))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(1.4, 2.6)
	dust.Speed = NumberRange.new(2, 6)
	dust.Drag = 1
	dust.Acceleration = Vector3.new(0, 1, 0)
	dust.Enabled = true
	s.dust = dust

	local sparks = emitter(holder, CFrame.new(centre), Vector3.new(HOLE * 1.8, 0.5, HOLE * 1.8), {
		Texture = SPARKLE,
		Color = ColorSequence.new(CRYSTAL),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(4, 14),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, -10, 0),
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
	})
	sparks.Enabled = true
	s.sparks = sparks

	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SMOKE
	trail.Color = ColorSequence.new(EARTH)
	trail.LightInfluence = 1
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = NumberRange.new(0.8, 1.4)
	trail.Speed = NumberRange.new(1, 4)
	trail.Acceleration = Vector3.new(0, -20, 0)
	trail.Rate = 45
	trail.Rotation = NumberRange.new(0, 360)
	trail.Enabled = false
	trail.Parent = mesh
	s.trail = trail

	for _ = 1, 18 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local pebble = Vector3.new(rng:NextNumber(0.4, 1), rng:NextNumber(0.3, 0.7), rng:NextNumber(0.4, 1))
		local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(1, HOLE * 1.4)
		table.insert(s.pebbles, {
			part = part(holder, {
				Material = Enum.Material.Slate,
				Color = EARTH:Lerp(DEEP, rng:NextNumber(0, 0.5)),
				Size = pebble,
				CFrame = CFrame.new(spot + Vector3.new(0, pebble.Y * 0.4, 0))
					* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			}),
			velocity = Vector3.zero,
			spin = Vector3.zero,
			resting = true,
			half = size.Y / 2,
		})
	end

	s.segments = buildCracks(holder, centre, top, true, 1)
	buildPit(s)
	if Workspace:GetServerTimeNow() < burstAt then
		s.rumble = sound(Assets.BeastRumble, centre, 0, 0, s.rumbleFor + 2.5)
		TweenService
			:Create(s.rumble :: Sound, TweenInfo.new(s.rumbleFor, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Volume = 2.5,
			})
			:Play()
	end
	model:PivotTo(CFrame.new(centre - Vector3.new(0, DEPTH, 0)))
	s.bar = healthBar(s)
	show = s
	task.spawn(cutFloor, s)

	-- Who comes in late sees the beast where it is, without what has gone by.
	if Workspace:GetServerTimeNow() - burstAt > s.flightFor then
		s.burstDone, s.landed, s.roared = true, true, true
		s.dust.Enabled, s.sparks.Enabled = false, false
		s.model.Parent = holder
		s.model:PivotTo(CFrame.new(s.land.X, top + lift, s.land.Z) * s.facing.Rotation)
		clipAt(s, "Idle", Workspace:GetServerTimeNow())
		if Workspace:GetServerTimeNow() - burstAt < SETTINGS.Crater then
			task.delay(1, function()
				openFloor(s, true)
				for _, piece in s.pit do
					piece.Transparency = 0
				end
			end)
		else
			s.closed = true
		end
		for _, seg in s.segments do
			seg.dark:Destroy()
			if seg.glow then
				seg.glow:Destroy()
			end
		end
		s.segments = {}
		for _, b in s.pebbles do
			b.part:Destroy()
		end
		s.pebbles = {}
	end

	beast.AncestryChanged:Connect(function()
		if not beast.Parent and show == s then
			show = nil
			openFloor(s, false)
			holder:Destroy()
		end
	end)
end

-- The model the beast is shown by, while it is (HitFeedback flashes it).
function BeastView.model(): Model?
	return if show then show.model else nil
end

function BeastView.start()
	local function found(child: Instance)
		if child.Name == "Beast" and child:IsA("Model") then
			begin(child)
		end
	end
	Workspace.ChildAdded:Connect(found)
	local existing = Workspace:FindFirstChild("Beast")
	if existing then
		found(existing)
	end
	RunService.RenderStepped:Connect(function(dt)
		if show then
			step(show, dt)
		end
	end)
end

return BeastView
