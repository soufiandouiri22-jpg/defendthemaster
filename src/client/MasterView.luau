-- The Masters on the client (MasterService): their motions after their "State" attribute (sitting on the throne,
-- standing, walking, falling when they die), their swings, and their ground slam (Net.MasterAction): working himself
-- up and swinging down while the red circle that warns where it lands grows, then a ring of dust racing out, gold
-- sparks and a shake of the camera for heroes near it. The attacks and the fall are the clips of his animation pack
-- (Config.Master.Pack), played over Roblox's own R15 sitting and standing, his steps those of a second pack
-- (Config.Master.Walk). Once he stands up he reaches over his shoulder and draws his sword from his back into his guard
-- (Config.Master.Draw), stands in his battle stance between his swings (Config.Master.Stance), and back before his
-- throne he lowers his guard and puts it back there (Config.Master.Sheath);
-- this side switches the sword between its two welds (MasterService). His clips sound as his pack's sound add-on times
-- them (Shared.PackSounds, HeroSounds), and as he walks each foot that comes down sounds a step.
-- A deep boom sounds over the arena when a Master falls (UiSound).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Sequence = require(ReplicatedStorage.Shared.Sequence)
local HeroCamera = require(script.Parent.HeroCamera)
local HeroSounds = require(script.Parent.HeroSounds)
local UiSound = require(script.Parent.UiSound)

local MasterView = {}

local ANIMATIONS = {
	Idle = "rbxassetid://507766388",
	Sit = "rbxassetid://2506281703",
}
local SETTINGS = Config.Master
local WALK = SETTINGS.Walk
local STEPS = { WALK.Forward, WALK.Back, WALK.Left, WALK.Right, WALK.TurnLeft, WALK.TurnRight }
-- How quickly his measured speed follows his steps (per second), and the most he moves in one frame by walking.
local MOVE_SMOOTH, MOVE_JUMP = 12, 4
local DRAW = SETTINGS.Draw
local SHEATH = SETTINGS.Sheath
-- How long the guard takes to come over his reach as he draws, and his reach to leave.
local DRAW_FADE = 0.25
-- Where his elbow points as he reaches for the sword on his back, from his upper torso: out to his right and up.
local ELBOW_OUT = Vector3.new(1, 0.7, -0.3).Unit
local WARN = Color3.fromRGB(230, 40, 32)
local WARN_EDGE = Color3.fromRGB(255, 90, 70)
local DUST = Color3.fromRGB(214, 186, 140)
local GOLD = Color3.fromRGB(255, 206, 110)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
-- How long a clip takes to come over the walking or standing, and to leave it again.
local FADE_IN, FADE_OUT = 0.1, 0.25
-- The joint of the weapon in his hand, which only his clips move.
local WEAPON = "Greataxe"
-- The parts his steps move while he walks armed; his arms keep his stance. His chest and head go with his steps too:
-- the stance turns his hips aside and his chest and head back towards his foe, so on hips walking ahead they would look
-- aside.
local STEPPED = {
	LowerTorso = true,
	UpperTorso = true,
	Head = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}
local SWORD = { [WEAPON] = true }
-- In the guard the pack's right hand lets go of the axe, its haft along the forearm, where his sword's pommel would
-- come out of his wrist: in the guard, and as he takes it up or lowers it, his fist holds the sword as at the start of
-- his first swing, across it.
-- The least and most angle (degrees) between his blade and his forearm, from elbow to fist: the axe's haft runs closer
-- along his forearm than a sword can, whose long grip and pommel would come through his sleeve, or its blade through
-- his arm. His fist turns the sword just enough to keep it between them.
local CLEAR = { Min = 80, Max = 105 }
-- A foot is off the ground once it has risen this far (studs at size 1) over where it stood, and has come down when it
-- has sunk this far below its highest and falls slower than this (studs a second at size 1).
local LIFT, LANDED = 0.1, 0.4

type Action = {
	clip: Sequence.Clip,
	time: number,
	weight: number,
	-- Kept at its last pose when it ends (the fall).
	hold: boolean,
	-- How long it takes to come over what he does (FADE_IN unless given), whether it draws his sword, and whether it
	-- leaves the sword in his fist as it is (the guard's clips).
	fade: number,
	draw: boolean,
	bare: boolean,
	-- Its sounds, by their time in it, and how many of them have played.
	cues: { any },
	heard: number,
}

-- A joint of his right arm: the part it hangs from and its two frames.
type Joint = {
	instance: any,
	part0: BasePart,
	c0: CFrame,
	c1: CFrame,
}

-- One of his feet as he walks: its height under his root last frame, the lowest it stood and the highest it rose
-- since, and whether it is off the ground.
type Foot = {
	part: BasePart,
	height: number?,
	low: number,
	top: number,
	up: boolean,
}

-- His right arm, for reaching to his sword's grip: shoulder and elbow, and the bones from each to the next (in the
-- upper and lower arm's frames, to the hand's middle); and his wrist, which the sword in his fist keeps clear of.
type Arm = {
	shoulder: Joint,
	elbow: Joint,
	wrist: Joint,
	upper: Vector3,
	lower: Vector3,
}

type View = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	playing: string?,
	rig: Sequence.Rig,
	-- His joints for the walks' pack, how far through its cycle his steps are (0-1), each step clip's weight, and
	-- where he faced and stood last frame, and how fast he moves over the ground (a client does not get his velocity).
	walkRig: Sequence.Rig,
	stride: number,
	steps: { [string]: number },
	facing: Vector3,
	place: Vector3,
	velocity: Vector3,
	feet: { Foot },
	weapon: Motor6D?,
	-- His sword, its weld on his back and the one in his hand, whether it is in his hand, and how its joint holds it
	-- where it was when he took it (until the guard has it).
	sword: BasePart?,
	rest: Weld?,
	grip: Weld?,
	inHand: boolean,
	keep: CFrame?,
	arm: Arm?,
	-- When he stood up to draw, and when he came back before his throne to put it away.
	drawAt: number?,
	sheathAt: number?,
	action: Action?,
	-- Bumped by every new action, so a slam's swing no longer starts after something else began.
	serial: number,
	-- His state in the last frame, and whether his sword is in his hand.
	state: string?,
	armed: boolean,
	-- When he may reel from a hit again.
	nextFlinch: number,
}

local views: { [Model]: View } = {}

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function holder(at: Vector3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Position = at
	return part
end

-- A flat image on the ground at `at`, `size` studs across.
local function decal(at: Vector3, image: string, colour: Color3, transparency: number, size: number): (Part, ImageLabel)
	local part = holder(at + Vector3.new(0, 0.15, 0), Vector3.new(size, 0.05, size))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.Adornee = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageColor3 = colour
	label.ImageTransparency = transparency
	label.Parent = gui
	gui.Parent = part
	part.Parent = effects()
	return part, label
end

-- The ground under `at`, past everyone who fights.
local function groundAt(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = HeroKit.leapIgnore()
	local hit = Workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else at
end

local function play(view: View, name: string, fade: number?)
	if view.playing == name then
		return
	end
	if view.playing then
		view.tracks[view.playing]:Stop(fade or 0.3)
	end
	view.playing = name
	view.tracks[name]:Play(fade or 0.3)
end

-- Plays the pack's clip `name` on `view` once.
local function act(view: View, name: string, hold: boolean?)
	view.serial += 1
	local weight = if view.action then view.action.weight else 0
	local bank = HeroSounds.bank(SETTINGS.Pack)
	view.action = {
		clip = Sequence.clip(SETTINGS.Pack, name, SETTINGS.PackHipHeight),
		time = 0,
		weight = weight,
		hold = hold == true,
		fade = FADE_IN,
		draw = false,
		bare = name == SETTINGS.Guard or name == SETTINGS.Unguard,
		cues = bank and bank.Cues[name] or {},
		heard = 0,
	}
end

-- Plays the sounds of `view`'s clip that its time has reached.
local function sound(view: View, action: Action)
	local bank = HeroSounds.bank(SETTINGS.Pack)
	local cue = action.cues[action.heard + 1]
	while bank and cue and cue.Time <= action.time do
		action.heard += 1
		HeroSounds.cue(view.model, bank, cue)
		cue = action.cues[action.heard + 1]
	end
end

-- How his fist holds the sword in his guard: as his first swing begins.
local function ready(): CFrame
	local swing = Sequence.clip(SETTINGS.Pack, SETTINGS.Swing.Motions[1], SETTINGS.PackHipHeight)
	local frame = Sequence.sample(swing, 0)[WEAPON]
	return if frame then frame.Rotation else CFrame.identity
end

local bodies: { [Sequence.Clip]: { [string]: boolean } } = {}

-- Every part `clip` moves but the sword.
local function bodyOf(clip: Sequence.Clip): { [string]: boolean }
	local body = bodies[clip]
	if not body then
		body = {}
		for name in clip.tracks do
			body[name] = name ~= WEAPON
		end
		bodies[clip] = body
	end
	return body
end

local uppers: { [Sequence.Clip]: { [string]: boolean } } = {}

-- Every part `clip` moves but those his steps move and the sword.
local function upperOf(clip: Sequence.Clip): { [string]: boolean }
	local upper = uppers[clip]
	if not upper then
		upper = {}
		for name in clip.tracks do
			upper[name] = name ~= WEAPON and not STEPPED[name]
		end
		uppers[clip] = upper
	end
	return upper
end

-- How long he takes to lower his guard.
local function lowering(): number
	return Sequence.clip(SETTINGS.Pack, SETTINGS.Unguard, SETTINGS.PackHipHeight).duration
end

-- The joint of `model` that moves `part`.
local function jointOf(model: Model, part: BasePart): Joint?
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 == part and d.Part0 then
			return { instance = d, part0 = d.Part0, c0 = d.C0, c1 = d.C1 }
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a1.Parent == part and a0.Parent and a0.Parent:IsA("BasePart") then
				return { instance = d, part0 = a0.Parent :: BasePart, c0 = a0.CFrame, c1 = a1.CFrame }
			end
		end
	end
	return nil
end

local function armOf(model: Model): Arm?
	local upper = model:FindFirstChild("RightUpperArm") :: BasePart?
	local lower = model:FindFirstChild("RightLowerArm") :: BasePart?
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	if not upper or not lower or not hand then
		return nil
	end
	local shoulder, elbow, wrist = jointOf(model, upper), jointOf(model, lower), jointOf(model, hand)
	if not shoulder or not elbow or not wrist then
		return nil
	end
	return {
		shoulder = shoulder,
		elbow = elbow,
		wrist = wrist,
		upper = elbow.c0.Position - shoulder.c1.Position,
		lower = wrist.c0.Position - wrist.c1.Position - elbow.c1.Position,
	}
end

-- The turn that takes direction `from` onto `to`.
local function turnOnto(from: Vector3, to: Vector3): CFrame
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.atan2(axis.Magnitude, from:Dot(to)))
end

-- Where his fist holds `sword`, in its own frame.
local function gripOf(sword: BasePart): Vector3
	return Vector3.new(-sword.Size.X * SETTINGS.Sword.Grip, 0, 0)
end

-- Where his sword lies on his back, and so where its grip is, in the world.
local function onBack(view: View): (CFrame?, Vector3?)
	local sword, rest = view.sword, view.rest
	local torso = view.model:FindFirstChild("UpperTorso") :: BasePart?
	if not sword or not rest or not torso then
		return nil, nil
	end
	local frame = torso.CFrame * rest.C0 * rest.C1:Inverse()
	return frame, frame:PointToWorldSpace(gripOf(sword))
end

-- How far his arm is bent to his back `since` seconds after it began to reach, for `length` seconds: up to all the
-- way, then letting go again.
local function reaching(since: number, length: number): number
	if since < length then
		local rise = math.clamp(since / length, 0, 1)
		return rise * rise * (3 - 2 * rise)
	end
	return 1 - math.clamp((since - length) / DRAW_FADE, 0, 1)
end

-- Bends his right arm, by `weight` over its pose now, so his hand comes to `grip` on his back.
local function reach(view: View, weight: number, grip: Vector3)
	local arm = view.arm
	local torso = view.model:FindFirstChild("UpperTorso") :: BasePart?
	if not arm or not torso or weight <= 0 then
		return
	end
	local shoulderAt = arm.shoulder.part0.CFrame * arm.shoulder.c0
	local from = shoulderAt.Position
	local long, short = arm.upper.Magnitude, arm.lower.Magnitude
	local toGrip = grip - from
	local far = math.clamp(toGrip.Magnitude, math.abs(long - short) + 0.01, (long + short) * 0.999)
	local ahead = toGrip.Unit
	local along = (long * long - short * short + far * far) / (2 * far)
	local out = torso.CFrame:VectorToWorldSpace(ELBOW_OUT)
	local side = out - ahead * out:Dot(ahead)
	side = if side.Magnitude > 1e-4 then side.Unit else torso.CFrame.RightVector
	local elbowAt = from + ahead * along + side * math.sqrt(math.max(0, long * long - along * along))

	local upperRest = shoulderAt.Rotation * arm.shoulder.c1.Rotation:Inverse()
	local upper = turnOnto(upperRest * arm.upper, elbowAt - from) * upperRest
	local lowerRest = upper * arm.elbow.c0.Rotation * arm.elbow.c1.Rotation:Inverse()
	local lower = turnOnto(lowerRest * arm.lower, grip - elbowAt) * lowerRest
	local shoulderTurn = shoulderAt.Rotation:Inverse() * upper * arm.shoulder.c1.Rotation
	local elbowTurn = (upper * arm.elbow.c0.Rotation):Inverse() * lower * arm.elbow.c1.Rotation
	arm.shoulder.instance.Transform = arm.shoulder.instance.Transform:Lerp(shoulderTurn, weight)
	arm.elbow.instance.Transform = arm.elbow.instance.Transform:Lerp(elbowTurn, weight)
end

-- Puts his sword in his hand or on his back. Taken in hand it keeps the turn it had on his back, and the guard turns
-- it into his grip as it comes over his reach.
local function take(view: View, inHand: boolean, draw: boolean)
	view.inHand = inHand
	local sword, rest, grip, joint = view.sword, view.rest, view.grip, view.weapon
	if not sword or not rest or not grip or not joint then
		return
	end
	if inHand then
		local hand = joint.Part0 :: BasePart
		local carrier = sword.CFrame * grip.C0:Inverse()
		view.keep = ((hand.CFrame * joint.C0):Inverse() * carrier * joint.C1).Rotation
		if draw then
			act(view, SETTINGS.Guard)
			local guard = view.action :: Action
			guard.fade = DRAW_FADE
			guard.draw = true
		end
	else
		view.keep = nil
	end
	grip.Enabled = inHand
	rest.Enabled = not inHand
end

local function watch(instance: Instance)
	if not instance:IsA("Model") or not instance:GetAttribute("Master") or views[instance] then
		return
	end
	local model = instance :: Model
	local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end
	local tracks = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = if track.Looped then Enum.AnimationPriority.Core else Enum.AnimationPriority.Action
		tracks[name] = track
	end
	local hand = model:FindFirstChild("RightHand")
	local sword = model:WaitForChild("MasterSword", 10) :: BasePart?
	local feet = {}
	for _, name in { "LeftFoot", "RightFoot" } do
		local part = model:FindFirstChild(name) :: BasePart?
		if part then
			table.insert(feet, { part = part, height = nil, low = 0, top = 0, up = false })
		end
	end
	views[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		tracks = tracks,
		playing = nil,
		rig = Sequence.rig(model, SETTINGS.Pack),
		walkRig = Sequence.rig(model, WALK.Pack),
		stride = 0,
		steps = {},
		facing = root.CFrame.LookVector,
		place = root.Position,
		velocity = Vector3.zero,
		feet = feet,
		weapon = hand and hand:FindFirstChild(WEAPON) :: Motor6D?,
		sword = sword,
		rest = sword and sword:FindFirstChild("SwordRest") :: Weld?,
		grip = sword and sword:FindFirstChild("SwordHold") :: Weld?,
		inHand = false,
		keep = nil,
		arm = armOf(model),
		drawAt = nil,
		sheathAt = nil,
		action = nil,
		serial = 0,
		state = nil,
		armed = false,
		nextFlinch = 0,
	}
	local view = views[model]
	local health = humanoid.Health
	humanoid.HealthChanged:Connect(function(now)
		local lost = health - now
		health = now
		local state = model:GetAttribute("State")
		local flinch = SETTINGS.Flinch
		if lost < flinch.Least or view.action or (state ~= "Fight" and state ~= "Returning") then
			return
		end
		local clock = os.clock()
		if clock >= view.nextFlinch then
			view.nextFlinch = clock + flinch.Every
			act(view, flinch.Motion)
		end
	end)
	model.Destroying:Connect(function()
		views[model] = nil
		HeroSounds.forget(model)
	end)
end

local function step()
	for model, view in views do
		local state = model:GetAttribute("State")
		local was = view.state
		view.state = state
		local clock = os.clock()
		if state == "Drawing" and was ~= "Drawing" then
			view.drawAt = clock
		elseif state ~= "Drawing" then
			view.drawAt = nil
		end
		if state == "Sheathing" and was ~= "Sheathing" then
			view.sheathAt = clock
			act(view, SETTINGS.Unguard)
			-- It comes over his stance.
			local lower = view.action :: Action
			lower.weight = 0
			lower.fade = DRAW_FADE
		elseif state ~= "Sheathing" then
			view.sheathAt = nil
		end
		local drawn = view.drawAt ~= nil and clock - view.drawAt >= DRAW.Pause + DRAW.Reach
		local sheathing = view.sheathAt ~= nil and clock - view.sheathAt < lowering() + SHEATH.Reach
		local inHand = if state == "Dead"
			then view.inHand
			else state == "Fight" or state == "Returning" or drawn or sheathing
		if inHand ~= view.inHand then
			take(view, inHand, state ~= "Dead")
		end
		view.armed = state == "Fight" or state == "Returning" or drawn
		if state == "Dead" then
			if view.playing then
				for _, track in view.tracks do
					track:Stop(0.2)
				end
				view.playing = nil
				act(view, SETTINGS.Death, true)
				UiSound.play("MasterFalls")
			end
		elseif state == "Seated" or state == "Rising" then
			play(view, "Sit")
		else
			play(view, "Idle")
		end
	end
end

-- The step clip for how `view` moves and turns now, and how fast it plays.
local function stepping(view: View, dt: number): (string?, number)
	local root = view.root
	local shift = HeroKit.flat(root.Position - view.place)
	view.place = root.Position
	if dt > 0 then
		-- A jump of more than a few studs is him being set on or off his throne, not a step.
		local now = if shift.Magnitude > MOVE_JUMP then Vector3.zero else shift / dt
		view.velocity = view.velocity:Lerp(now, math.min(1, dt * MOVE_SMOOTH))
	end
	local moving = root.CFrame:VectorToObjectSpace(view.velocity)
	local facing = HeroKit.flat(root.CFrame.LookVector)
	local turn = if dt > 0
			and facing.Magnitude > 0
			and view.facing.Magnitude > 0
		then math.atan2(view.facing:Cross(facing).Y, view.facing:Dot(facing)) / dt
		else 0
	view.facing = facing
	local speed = moving.Magnitude
	if speed > 1 then
		local rate = speed / (WALK.Pace * SETTINGS.Scale)
		if math.abs(moving.Z) >= math.abs(moving.X) then
			return if moving.Z < 0 then WALK.Forward else WALK.Back, rate
		end
		return if moving.X < 0 then WALK.Left else WALK.Right, rate
	elseif math.abs(turn) > WALK.Turning then
		return if turn > 0 then WALK.TurnLeft else WALK.TurnRight, 1
	end
	return nil, 0
end

-- His steps over Roblox's standing: the clip for how he moves comes in, the others go.
local function walk(view: View, dt: number)
	local current, rate = stepping(view, dt)
	if current then
		local clip = Sequence.clip(WALK.Pack, current, WALK.HipHeight)
		view.stride = (view.stride + dt * rate / math.max(clip.duration, 0.1)) % 1
	end
	for _, name in STEPS do
		local weight = view.steps[name] or 0
		local goal = if name == current then 1 else 0
		weight = if goal > weight
			then math.min(goal, weight + dt / WALK.Blend)
			else math.max(goal, weight - dt / WALK.Blend)
		view.steps[name] = weight
		if weight > 0 then
			local clip = Sequence.clip(WALK.Pack, name, WALK.HipHeight)
			Sequence.apply(view.walkRig, clip, view.stride * clip.duration, weight)
		end
	end
end

-- Sounds a step for each foot of `view` that came down since last frame, while he walks (`walking`).
local function footfalls(view: View, dt: number, walking: boolean)
	local bank = HeroSounds.bank(SETTINGS.Pack)
	local lift, landed = LIFT * SETTINGS.Scale, LANDED * SETTINGS.Scale
	for _, foot in view.feet do
		local height = view.root.CFrame:PointToObjectSpace(foot.part.Position).Y
		local last = foot.height
		foot.height = if walking then height else nil
		if not walking or not last or dt <= 0 then
			foot.up, foot.low = false, height
			continue
		end
		if not foot.up then
			foot.low = math.min(foot.low, height)
			if height > foot.low + lift then
				foot.up, foot.top = true, height
			end
			continue
		end
		foot.top = math.max(foot.top, height)
		if height < foot.top - lift and (height - last) / dt > -landed then
			foot.up, foot.low = false, height
			if bank then
				HeroSounds.step(view.model, view.root, bank, WALK.Steps)
			end
		end
	end
end

-- Moves every Master's clip on by `dt` and poses him, after Roblox's own motions have posed him for this frame.
local function pose(dt: number)
	for _, view in views do
		local action = view.action
		local drawing = action ~= nil and action.draw
		if view.keep and not drawing then
			view.keep = nil
		end
		if view.weapon then
			local keep = view.keep
			view.weapon.Transform = if keep and action
				then keep:Lerp(ready(), action.weight)
				elseif view.inHand then ready()
				else CFrame.identity
		end
		if view.armed then
			walk(view, dt)
			-- His clips sound their own steps.
			local moving = false
			for _, weight in view.steps do
				moving = moving or weight > 0
			end
			footfalls(view, dt, moving and action == nil)
		else
			footfalls(view, dt, false)
			table.clear(view.steps)
			view.facing = HeroKit.flat(view.root.CFrame.LookVector)
			view.place = view.root.Position
			view.velocity = Vector3.zero
		end
		local sword = view.sword
		if view.drawAt and sword then
			reach(
				view,
				reaching(os.clock() - view.drawAt - DRAW.Pause, DRAW.Reach),
				sword.CFrame:PointToWorldSpace(gripOf(sword))
			)
		elseif view.sheathAt then
			local _, grip = onBack(view)
			if grip then
				reach(view, reaching(os.clock() - view.sheathAt - lowering(), SHEATH.Reach), grip)
			end
		end
		-- His stance, under his swings: from the end of his draw, until lowering his guard has taken over.
		local drawn = not drawing or (action :: Action).time >= (action :: Action).clip.duration
		local putting = view.sheathAt ~= nil and action ~= nil and action.weight < 1
		if (view.armed and drawn) or putting then
			local stance = Sequence.clip(SETTINGS.Pack, SETTINGS.Stance, SETTINGS.PackHipHeight)
			local at = os.clock() % stance.duration
			local walking = 0
			for _, weight in view.steps do
				walking = math.max(walking, weight)
			end
			Sequence.apply(view.rig, stance, at, 1, upperOf(stance))
			Sequence.apply(view.rig, stance, at, 1 - walking, STEPPED)
			-- The guard's clips leave the sword in his fist as in his guard: it turns there from his stance's hold
			-- as they come over it, and back as they go.
			local guarding = if action and action.bare then action.weight else 0
			Sequence.apply(view.rig, stance, at, 1 - guarding, SWORD)
		end
		if not action then
			continue
		end
		local length = action.clip.duration
		action.time += dt
		sound(view, action)
		if action.time < length or action.hold then
			action.weight = math.min(1, action.weight + dt / action.fade)
		else
			action.weight -= dt / FADE_OUT
			if action.weight <= 0 then
				view.action = nil
				continue
			end
		end
		local only = if action.bare then bodyOf(action.clip) else nil
		Sequence.apply(view.rig, action.clip, math.min(action.time, length), action.weight, only)
	end
	-- The pack's hand slides along the axe's haft; his fist keeps hold of the grip, so the clips only turn the sword in
	-- it. Putting it away, he turns it in his fist to lie as it will on his back.
	for _, view in views do
		local joint, grip = view.weapon, view.grip
		if not joint then
			continue
		end
		local turn = joint.Transform.Rotation
		local wrist = view.arm and view.arm.wrist
		if view.inHand and wrist then
			local drawing = view.action ~= nil and view.action.draw
			local weight = if drawing and view.keep then (view.action :: Action).weight else 1
			local blade = (joint.C0.Rotation * turn * joint.C1.Rotation:Inverse()):VectorToWorldSpace(Vector3.yAxis)
			local hand = wrist.c0.Rotation * wrist.instance.Transform.Rotation * wrist.c1.Rotation:Inverse()
			local forearm = hand:VectorToObjectSpace(-Vector3.yAxis)
			local angle = math.deg(math.acos(math.clamp(blade:Dot(forearm), -1, 1)))
			local goal = math.clamp(angle, CLEAR.Min, CLEAR.Max)
			local axis = forearm:Cross(blade)
			if goal ~= angle and axis.Magnitude > 1e-4 then
				local fist = CFrame.fromAxisAngle(axis.Unit, math.rad(goal - angle) * weight)
				turn = joint.C0.Rotation:Inverse() * fist * joint.C0.Rotation * turn
			end
		end
		local back = onBack(view)
		if view.sheathAt and view.inHand and back and grip then
			local hand = joint.Part0 :: BasePart
			local laid = ((hand.CFrame * joint.C0):Inverse() * back * grip.C0:Inverse() * joint.C1).Rotation
			local since = os.clock() - view.sheathAt - lowering()
			turn = turn:Lerp(laid, reaching(math.min(since, SHEATH.Reach), SHEATH.Reach))
		end
		joint.Transform = turn
	end
end

-- The red circle round `ground` that grows to `radius` over `windup` seconds, a pale red area and its edge already
-- showing the full reach.
local function warn(ground: Vector3, radius: number, windup: number)
	local size = radius * 2
	local area, areaLabel = decal(ground, Assets.IndicatorDisc, WARN, 1, size)
	TweenService:Create(areaLabel, TweenInfo.new(0.15), { ImageTransparency = 0.72 }):Play()
	local edge, edgeLabel = decal(ground, Assets.IndicatorRing, WARN_EDGE, 1, size)
	TweenService:Create(edgeLabel, TweenInfo.new(0.15), { ImageTransparency = 0 }):Play()
	local fill, fillLabel = decal(ground, Assets.IndicatorDisc, WARN, 0.45, size)
	fill.Size = Vector3.new(1, 0.05, 1)
	TweenService:Create(fill, TweenInfo.new(windup, Enum.EasingStyle.Linear), { Size = Vector3.new(size, 0.05, size) })
		:Play()
	TweenService:Create(fillLabel, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		ImageTransparency = 0.2,
	}):Play()
	task.delay(windup, function()
		area:Destroy()
		edge:Destroy()
		fill:Destroy()
	end)
end

-- The slam landing on `ground`, reaching `radius` studs.
local function impact(ground: Vector3, radius: number)
	local quick = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	for i, delay in { 0, 0.1 } do
		task.delay(delay, function()
			local size = radius * (if i == 1 then 2.4 else 1.7)
			local ring, label = decal(ground, Assets.IndicatorRing, if i == 1 then DUST else GOLD, 0, 2)
			TweenService:Create(ring, quick, { Size = Vector3.new(size, 0.05, size) }):Play()
			TweenService:Create(label, TweenInfo.new(0.7), { ImageTransparency = 1 }):Play()
			task.delay(0.8, function()
				ring:Destroy()
			end)
		end)
	end

	local centre = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius * 0.8, 0.5, radius * 0.8))
	centre.Parent = effects()
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE
	dust.Color = ColorSequence.new(DUST)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	dust.Transparency = NumberSequence.new(0.2, 1)
	dust.Lifetime = NumberRange.new(0.7, 1.3)
	dust.Speed = NumberRange.new(20, 36)
	dust.Drag = 4
	dust.SpreadAngle = Vector2.new(180, 10)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Enabled = false
	dust.Parent = centre
	dust:Emit(70)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(GOLD)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 0.9)
	sparks.Speed = NumberRange.new(24, 44)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -50, 0)
	sparks.Enabled = false
	sparks.Parent = centre
	sparks:Emit(40)

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = radius * 2
	light.Brightness = 3
	light.Parent = centre
	TweenService:Create(light, TweenInfo.new(0.45), { Brightness = 0 }):Play()
	task.delay(2, function()
		centre:Destroy()
	end)

	local character = Players.LocalPlayer.Character
	local body = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if body then
		local closeness = 1 - math.clamp(HeroKit.flat(body.Position - ground).Magnitude / (radius * 2.5), 0, 1)
		if closeness > 0 then
			HeroCamera.shake(0.9 * closeness, 0.5)
		end
	end
end

local function action(model: Model, kind: string, delay: number, detail: any, radius: number?)
	local view = views[model]
	if kind == "Swing" then
		local name = SETTINGS.Swing.Motions[detail]
		if view and name then
			act(view, name)
		end
	elseif kind == "Slam" and typeof(detail) == "Vector3" and radius then
		local ground = groundAt(detail)
		warn(ground, radius, delay)
		if view then
			act(view, SETTINGS.Slam.Frenzy)
			local serial = view.serial
			task.delay(math.max(0, delay - SETTINGS.Slam.Impact), function()
				if view.serial == serial and views[model] then
					act(view, SETTINGS.Slam.Motion)
				end
			end)
		end
		task.delay(delay, impact, ground, radius)
	end
end

function MasterView.start()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(function(instance)
		task.spawn(watch, instance)
	end)
	for _, instance in CollectionService:GetTagged("Combatant") do
		task.spawn(watch, instance)
	end
	RunService.RenderStepped:Connect(step)
	RunService.PreSimulation:Connect(pose)
	local net = ReplicatedStorage:WaitForChild("Net")
	local event = net:WaitForChild("MasterAction") :: RemoteEvent
	event.OnClientEvent:Connect(action)
end

return MasterView
