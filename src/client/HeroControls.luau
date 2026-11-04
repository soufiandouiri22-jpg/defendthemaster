-- The player's attacks (Config.Heroes[hero].Kit, server: CombatService). Left mouse swings the combo (held, it keeps
-- swinging); right mouse, E and R are held to aim with their indicator on the ground (design 06) and cast when let go;
-- a sniper's R (Kind "Snipe") brings up his scope at once (Scope), and a click through it fires.
-- Everything aims where the player looks (HeroCamera.aim), up and down too. The client plays its own motion at once and asks the server
-- (Net.HeroAction), which decides the hits; a refused attack is undone. The leap moves the hero itself, from takeoff
-- to landing, to the spot the server works out the same way (HeroKit.leapLanding), and lands in a shockwave of shadow
-- (ShadowEffects), or of fire for a hero whose `Effects` are "Fire" (FireEffects), as does every other hero's leap; an Ascend holds him up in the air till it ends (HeroKit.lift),
-- and its great orb bursts where it stops. A jump pad's throw (HeroControls.launch) carries him the same way, every
-- attack his to use in the air. Other heroes' motions and every thrown dagger and shot arrow come
-- from the server; while an attack plays, the client keeps telling the server where the crosshair points, as every
-- hit but a leap's landing and a dash's path goes there (HeroKit.follows). The crosshair (design 09) turns red on an
-- enemy the next left click would hit (owner, 2026-10-31: out of reach it stays as it is), while an ability is aimed
-- once any enemy stands where it would strike (its indicator's ring, line, cone or slam), and blue on an ally.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AbilityBar = require(script.Parent.AbilityBar)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local FireEffects = require(script.Parent.FireEffects)
local GunEffects = require(script.Parent.GunEffects)
local HeroAnimator = require(script.Parent.HeroAnimator)
local HeroCamera = require(script.Parent.HeroCamera)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local HeroSounds = require(script.Parent.HeroSounds)
local Indicators = require(script.Parent.Indicators)
local Items = require(ReplicatedStorage.Shared.Items)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local LightningEffects = require(script.Parent.LightningEffects)
local Scope = require(script.Parent.Scope)
local ShadowEffects = require(script.Parent.ShadowEffects)
local UiSound = require(script.Parent.UiSound)

local HeroControls = {}

local RECOVER = 0.12
-- Seconds a combo's hit that starts part-way in (its kit's `Follow`) is eased into from the last one's pose.
local FOLLOW_FADE = 0.1
local THUNDER_CRACK = 0.6
-- How often an attack that follows the crosshair (HeroKit.follows) tells the server where it points while it plays.
local AIM_EVERY = 0.05
local KEY_OF: { [Enum.KeyCode | Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton2] = "M2",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.R] = "R",
}
local player = Players.LocalPlayer
local actionEvent: RemoteEvent
local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Exclude
-- How far down a hero in the air looks for the ground under him.
local AIR_DEPTH = 200

type Leap = {
	started: number,
	from: Vector3,
	to: Vector3,
	takeoff: number,
	land: number,
	-- A dash starts fast and slows to a stop; a leap eases in and out.
	sharp: boolean,
	-- An Ascend's kit, which holds him in the air where he cast it instead (HeroKit.lift).
	lift: any?,
	-- Whether he cast that in the air (a jump pad's flight): known once it lets him down.
	aloft: boolean?,
	-- Where a Grounded dash cast in the air found him: he comes down from there to `from` in its windup.
	down: Vector3?,
}

-- A jump pad's throw (HeroControls.launch): from where to where his root goes, how high over the higher of the two,
-- for how long, and what to run when he comes down or an attack takes over.
type Flight = {
	started: number,
	from: Vector3,
	to: Vector3,
	height: number,
	length: number,
	ended: () -> (),
}

local busyUntil = 0
local combo = 0
local comboUntil = 0
local cooldowns: { [string]: number } = {}
local motionToken = 0
local holdingM1 = false
local aiming: string? = nil
local indicator: Indicators.Indicator? = nil
local leap: Leap? = nil
local flight: Flight? = nil
local following, aimSentAt = false, 0
-- A Snipe he looks through the scope of now (Scope), and from when a click fires it.
local sniping: { kit: any, readyAt: number }? = nil

type Flying = {
	dagger: BasePart,
	origin: Vector3,
	-- Where on him it is seen leaving (weaponFrom: his weapon's "Point" or the "Hand" holding it), coming onto the
	-- server's way over its first WEAPON_BLEND studs; and whether it has been drawn yet.
	from: string?,
	seen: boolean?,
	direction: Vector3,
	speed: number,
	range: number,
	started: number,
	-- Turns a second end over end, how the model lies against its flight, and whether a hit bursts in shadow.
	spin: number,
	turn: CFrame,
	burst: boolean,
	-- How far it bursts round where it stops, and whose it is.
	blast: number?,
	character: Model,
	-- A gun's round (GunEffects) and where it was first seen.
	round: string?,
	start: Vector3,
}
local flying: { [number]: Flying } = {}

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function hero(): (Model?, BasePart?, Humanoid?, any)
	local character = player.Character
	if not character then
		return nil, nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local name = character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	if not root or not humanoid or humanoid.Health <= 0 or not settings then
		return nil, nil, nil, nil
	end
	return character, root, humanoid, settings
end

local function heightOf(root: BasePart, humanoid: Humanoid): number
	return humanoid.HipHeight + root.Size.Y / 2
end

local function slow(humanoid: Humanoid, length: number, speed: number)
	motionToken += 1
	local token = motionToken
	humanoid.WalkSpeed = speed
	task.delay(length, function()
		if motionToken == token and humanoid.Parent then
			humanoid.WalkSpeed = Items.walkSpeed(player)
		end
	end)
end

-- Shakes the camera when `at` is near the player's hero, harder the closer.
local function shakeNear(at: Vector3, strength: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local closeness = 1 - math.clamp((root.Position - at).Magnitude / 35, 0, 1)
		if closeness > 0 then
			HeroCamera.shake(strength * closeness, 0.35)
		end
	end
end

-- The sound of `character`'s hero striking the ground.
local function slamSound(character: Model)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	if settings and settings.Pack then
		HeroSounds.event(character, settings.Pack, "Slam")
	end
end

-- The colours of `settings`' slams, shockwaves and dash trail (Config's Effects), or nil for shadow.
local function paletteOf(settings: any): ShadowEffects.Palette?
	local kind = settings and settings.Effects
	return if kind == "Light"
		then ShadowEffects.Light
		elseif kind == "Red" then ShadowEffects.Red
		elseif kind == "Blue" then ShadowEffects.Blue
		else nil
end

-- The leap's shockwave at `landing` (where the root part comes down) when the hero lands.
local function landLater(character: Model, landing: Vector3, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	task.delay(kit.Land, function()
		if humanoid.Health > 0 then
			groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
			local below = Workspace:Raycast(landing, Vector3.new(0, -(height + 2), 0), groundRay)
			local ground = if below then below.Position else landing - Vector3.new(0, height, 0)
			local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
			if settings and settings.Effects == "Fire" then
				FireEffects.shockwave(ground, kit.Radius)
			else
				ShadowEffects.shockwave(ground, kit.Radius, paletteOf(settings))
			end
			shakeNear(ground, 0.4)
			slamSound(character)
		end
	end)
end

-- A flurry's slams where the hero stands, at each of its `Hits` from `kit.Slam` seconds from now on, and the smaller
-- waves of its `Pulses` after.
local function slamLater(character: Model, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	local palette = paletteOf(settings)
	local function at(time: number, strike: (ground: Vector3) -> ())
		task.delay(time, function()
			if humanoid.Health <= 0 or not root.Parent then
				return
			end
			groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
			local below = Workspace:Raycast(root.Position, Vector3.new(0, -(height + 2), 0), groundRay)
			strike(if below then below.Position else root.Position - Vector3.new(0, height, 0))
		end)
	end
	for _, time in kit.Hits do
		if time >= kit.Slam then
			at(time, function(ground)
				ShadowEffects.slam(ground, kit.Range, palette)
				shakeNear(ground, 0.9)
				slamSound(character)
			end)
		end
	end
	for _, time in kit.Pulses or {} do
		at(time, function(ground)
			ShadowEffects.pulse(ground, kit.SlamRadius, palette)
		end)
	end
end

-- A strike from the sky (`kit`, Kind "Strike") on the spot `spot` (at a hero's root height, HeroKit.leapLanding):
-- its warning there from now till the last bolt, and a bolt at each of `kit.Strikes`, the first in the middle and
-- the others somewhere inside the ring, each cracking as the zap's shocks do, louder, over thunder that cracks with the
-- first bolt and rolls on under the rest (its crack comes THUNDER_CRACK seconds into UiSound's Thunder).
local function strikeLater(character: Model, spot: Vector3, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local below = Workspace:Raycast(spot, Vector3.new(0, -(height + 2), 0), groundRay)
	local ground = if below then below.Position else spot - Vector3.new(0, height, 0)
	LightningEffects.warn(ground, kit.Radius, kit.Strikes[#kit.Strikes])
	task.delay(math.max(0, kit.Strikes[1] - THUNDER_CRACK), UiSound.at, "Thunder", ground)
	for i, at in kit.Strikes do
		task.delay(at, function()
			local angle, out =
				math.random() * math.pi * 2, if i == 1 then 0 else kit.Radius * (0.3 + math.random() * 0.4)
			local where = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * out
			LightningEffects.strike(where, kit.Radius)
			UiSound.at("Zap", where, 1.4)
			shakeNear(ground, 0.7)
			slamSound(character)
		end)
	end
end

local zapExtents: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any

-- The point of `character`'s weapon: the far end of the longest part he holds (up its length), or his chest.
local function weaponPoint(character: Model, root: BasePart): Vector3
	local weapons = character:FindFirstChild("Weapons")
	local longest: BasePart? = nil
	for _, part in if weapons then weapons:GetDescendants() else {} do
		if part:IsA("BasePart") and (not longest or part.Size.Y > longest.Size.Y) then
			longest = part
		end
	end
	if not longest then
		return HeroKit.muzzle(root.Position)
	end
	return (longest.CFrame * CFrame.new(0, longest.Size.Y / 2, 0)).Position
end

local FACES = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

-- The first by name of the bones among `instances`.
local function firstBone(instances: { Instance }): Bone?
	local first: Bone? = nil
	for _, d in instances do
		if d:IsA("Bone") and (not first or d.Name < first.Name) then
			first = d
		end
	end
	return first
end

-- The far end from `root` of the parts of `weapon` he shows, as the clip poses them now: a part skinned to bones stays
-- where it was bound and is seen moved as its first bone moves, its own or else its weapon's (the multitool's are on
-- a part of their own); a gun he holds moves as one. Nil when none shows.
local function weaponTip(root: BasePart, weapon: Instance): Vector3?
	local best, far = nil, -1
	local holder = if weapon:IsA("BasePart") then weapon.Parent else weapon
	local shared = if holder then firstBone(holder:GetDescendants()) else nil
	for _, part in if weapon:IsA("BasePart") then { weapon } else weapon:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 0.5 then
			continue
		end
		local first = firstBone(part:GetChildren()) or shared
		local posed = if first
			then first.TransformedWorldCFrame * first.WorldCFrame:Inverse() * part.CFrame
			else part.CFrame
		for _, face in FACES do
			local point = posed * (face * part.Size / 2)
			local distance = (point - root.Position).Magnitude
			if distance > far then
				best, far = point, distance
			end
		end
	end
	return best
end

-- Where on `character` a shot is seen leaving: his weapon's `Point` (weaponPoint), the `Hand` holding it (what his
-- weapon is bound to), the bone of his weapons by that name, or the far end of what he shows of the part, or else the
-- weapon, of his weapons by that name (weaponTip: a gun's barrel); his chest without one.
local function weaponFrom(character: Model, root: BasePart, from: string): Vector3
	local weapons = character:FindFirstChild("Weapons")
	if from == "Hand" then
		for _, d in if weapons then weapons:GetDescendants() else {} do
			if d:IsA("Motor6D") and d.Name == "ComponentBinding" and d.Part0 then
				return d.Part0.Position
			end
		end
		return HeroKit.muzzle(root.Position)
	end
	local found: Instance? = nil
	for _, d in if from ~= "Point" and weapons then weapons:GetDescendants() else {} do
		if d.Name == from and (d:IsA("BasePart") or d:IsA("Bone")) then
			found = d
			break
		end
	end
	found = found or (if from ~= "Point" and weapons then weapons:FindFirstChild(from, true) else nil)
	if found and found:IsA("Bone") then
		return found.TransformedWorldCFrame.Position
	end
	local tip = if found then weaponTip(root, found) else nil
	return tip or weaponPoint(character, root)
end

-- `kit.Zap`'s lightning at each of the flurry's hits: from his weapon's point to the enemy that shock strikes
-- (HeroKit.zapTarget among those the sweep reaches, as the server measures it), or straight ahead to its reach when
-- it reaches no one; each with a crack from his weapon's point (UiSound's Zap).
local function zapLater(character: Model, kit: any)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for hit, time in kit.Hits do
		task.delay(time, function()
			if not root.Parent or HeroAnimator.playing(character) ~= kit.Motion then
				return
			end
			local muzzle = HeroKit.muzzle(root.Position)
			local facing = root.CFrame.LookVector
			local direction = if character == player.Character
				then HeroKit.aimDirection(muzzle, HeroCamera.aim(), facing)
				else facing
			local range, angle = HeroKit.flurryStrike(kit, time)
			local from = weaponPoint(character, root)
			local reached, positions = {}, {}
			for _, foe in HeroKit.foes(character:GetAttribute("Team"), zapExtents) do
				if HeroKit.swingStrikes(muzzle, direction, range, angle, foe.body) then
					table.insert(reached, foe.body)
					table.insert(positions, foe.body.position)
				end
			end
			local target = HeroKit.zapTarget(kit, hit, muzzle, positions)
			UiSound.at("Zap", from)
			if target then
				local body = reached[target]
				LightningEffects.zap(from, Vector3.new(body.position.X, (body.bottom + body.top) / 2, body.position.Z))
			else
				LightningEffects.zap(from, muzzle + direction * range)
			end
		end)
	end
end

-- How far in front of the middle of his upper body a beam starts.
local BEAM_CHEST = 0.8

-- `kit.Beam`'s laser beam: from the middle of his upper body as his motion moves it, along where he aims (another
-- hero's where he faces) to the flurry's Range or the first wall, from its From to its To unless his motion is cut short, a glowing shell round a bright core
-- in his projectiles' colours with a glow where it strikes, and a crack as it starts.
local function beamLater(character: Model, kit: any)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	if not root or not settings then
		return
	end
	local look = settings.Projectile or {}
	local core = if look.Laser then look.Laser.Color else Color3.new(1, 1, 1)
	local glow = look.Glow or core
	local beam = kit.Beam
	task.delay(beam.From, function()
		if not root.Parent or HeroAnimator.playing(character) ~= kit.Motion then
			return
		end
		local function piece(shape: Enum.PartType, colour: Color3, transparency: number): Part
			local part = Instance.new("Part")
			part.Shape = shape
			part.Material = Enum.Material.Neon
			part.Color = colour
			part.Transparency = transparency
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = effects()
			return part
		end
		local shell = piece(Enum.PartType.Cylinder, glow, 0.45)
		local inner = piece(Enum.PartType.Cylinder, core, 0)
		local spark = piece(Enum.PartType.Ball, glow, 0.3)
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 10
		light.Brightness = 2
		light.Parent = spark
		local walls = RaycastParams.new()
		walls.FilterType = Enum.RaycastFilterType.Exclude
		walls.FilterDescendantsInstances = HeroKit.leapIgnore()
		local torso = character:FindFirstChild("UpperTorso") :: BasePart?
		UiSound.at("Zap", root.Position)
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t > beam.To - beam.From or not root.Parent or HeroAnimator.playing(character) ~= kit.Motion then
				connection:Disconnect()
				shell:Destroy()
				inner:Destroy()
				spark:Destroy()
				return
			end
			local chest = if torso and torso.Parent then torso.Position else HeroKit.muzzle(root.Position)
			local facing = root.CFrame.LookVector
			local direction = if character == player.Character
				then HeroKit.aimDirection(chest, HeroCamera.aim(), facing)
				else facing
			local from = chest + direction * BEAM_CHEST
			local wall = Workspace:Raycast(from, direction * kit.Range, walls)
			local to = if wall then wall.Position else from + direction * kit.Range
			local length = math.max((to - from).Magnitude, 0.1)
			local along = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0)
			-- It flickers a little, as a beam of raw power would.
			local width = beam.Width * (0.9 + 0.2 * math.sin(t * 40))
			shell.Size = Vector3.new(length, width, width)
			shell.CFrame = along
			inner.Size = Vector3.new(length, width * 0.4, width * 0.4)
			inner.CFrame = along
			spark.Size = Vector3.one * width * 1.8
			spark.CFrame = CFrame.new(to)
		end)
	end)
end

-- A moment of `kit`'s motion drawn out (`kit.Hold`): from `From` to `To` seconds into the clip it plays at `Speed`,
-- unless something else plays by then.
local function holdLater(character: Model, kit: any)
	local hold = kit.Hold
	if not hold then
		return
	end
	task.delay(hold.From, function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.setSpeed(character, hold.Speed)
		end
	end)
	task.delay(hold.From + (hold.To - hold.From) / hold.Speed, function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.setSpeed(character, 1)
		end
	end)
end

-- An Ascend's or a Rain's second motion (`kit.Then`), as its first (`length` seconds) ends or at its `ThenAt`, unless
-- that was cut short; a Rain's in place, as he hangs where he is.
local function thenLater(character: Model, kit: any, length: number)
	task.delay(math.max(0, (kit.ThenAt or length) - 0.03), function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.play(character, kit.Then, 1, nil, kit.Kind == "Rain")
		end
	end)
end

-- Seconds between a Rain's beams, how much higher than he hangs they fall from, how long each takes to come down, and
-- how far towards where he faces they lean.
local BEAM_GAP, BEAM_ABOVE, BEAM_FALL, BEAM_LEAN = 0.04, 8, 0.18, 6
-- How far over a Rain's hero leans at most and at least to look down on its spot, and how long he takes to lean over.
local LEAN_MOST, LEAN_LEAST, LEAN_TIME = math.rad(70), math.rad(30), 0.3

-- He leans over from his root as a Rain (`kit`) holds him up, to look down on its `spot` from above, and comes upright
-- again as he falls: his root joint turned by up to the angle he sees it at, at its frame on the root part (an
-- AnimationConstraint's first attachment or a Motor6D's C0, which his motions leave alone).
local function leanLater(character: Model, root: BasePart, spot: Vector3, kit: any)
	local joint: Instance? = nil
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a0.Parent == root and a1.Parent and a1.Parent.Name == "LowerTorso" then
				joint = a0
				break
			end
		elseif d:IsA("Motor6D") and d.Part0 == root and d.Part1 and d.Part1.Name == "LowerTorso" then
			joint = d
			break
		end
	end
	if not joint then
		return
	end
	local frame = joint :: Instance
	local field = if frame:IsA("Motor6D") then "C0" else "CFrame"
	local rest: CFrame = (frame :: any)[field]
	local above = kit.Rise + math.max(0, root.Position.Y - spot.Y)
	local angle = math.clamp(math.atan2(above, HeroKit.flat(spot - root.Position).Magnitude), LEAN_LEAST, LEAN_MOST)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t >= kit.Land or not frame.Parent then
			connection:Disconnect();
			(frame :: any)[field] = rest
			return
		end
		local lean = if t < kit.RiseEnd
			then 0
			elseif t < kit.Fall then math.min((t - kit.RiseEnd) / LEAN_TIME, 1)
			else 1 - (t - kit.Fall) / (kit.Land - kit.Fall)
		lean = lean * lean * (3 - 2 * lean);
		(frame :: any)[field] = CFrame.Angles(-angle * lean, 0, 0) * rest
	end)
end

local STAR_GAP, CARD_GAP, CARD_LIFE = 1.5, 2.5, 0.55
local STAR_SIZE, CARD_SIZE = 1, 1.7
-- A touch brighter than white (owner, 2026-11-01: 2.2 too bright).
local CARD_BRIGHTNESS = 1.3

-- One kind of the twinkles or card suits of his beams (Assets.CardStar, CardSuits; `texture`, `size` studs) on `part`,
-- in `colour`, let out only by Emit. Unlit, so where they overlap they do not grow brighter.
local function cardEmitter(part: BasePart, texture: string, size: number, colour: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(colour)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Brightness = CARD_BRIGHTNESS
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(0.7, size * 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07),
		NumberSequenceKeypoint.new(0.6, 0.22),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(CARD_LIFE * 0.8, CARD_LIFE)
	e.Rate = 0
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(-25, 25)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Parent = part
	return e
end

-- Twinkles and card suits shed by a flying beam (Config's Projectile.Cards), left in the air behind it to fade, in
-- `colour`. Every beam leaves the same (owner, 2026-11-01): shed by the way it goes rather than by time (a twinkle every
-- STAR_GAP studs, a suit every CARD_GAP), so they lie evenly along it from its first stud on and do not heap up where
-- it stands still, till retire stops them; gone within CARD_LIFE, before the next beams along the same line add theirs.
local function shedCards(part: BasePart, colour: Color3)
	local star = cardEmitter(part, Assets.CardStar, STAR_SIZE, colour)
	local suits = {}
	for _, suit in Assets.CardSuits do
		table.insert(suits, cardEmitter(part, suit, CARD_SIZE, colour))
	end
	local last: Vector3? = nil
	local toStar, toCard = 0, 0
	local step
	step = RunService.Heartbeat:Connect(function()
		if not part.Parent or not star.Enabled then
			step:Disconnect()
			return
		end
		local here = part.Position
		local moved = if last then (here - last).Magnitude else 0
		last = here
		-- A jump (the beam set on its way) sheds nothing.
		if moved > 20 then
			return
		end
		toStar += moved
		toCard += moved
		while toStar >= STAR_GAP do
			toStar -= STAR_GAP
			star:Emit(1)
		end
		while toCard >= CARD_GAP do
			toCard -= CARD_GAP
			suits[math.random(#suits)]:Emit(1)
		end
	end)
end

-- Takes a flown beam away: one shedding sparkles and cards (shedCards), or a round's sparks and smoke, is hidden at
-- once and goes once they have faded (CARD_LIFE, or its "Linger" seconds), so they do not vanish with it.
local function retire(part: BasePart)
	local sheds = false
	for _, d in part:GetChildren() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			sheds = true
		elseif d:IsA("PointLight") or d:IsA("Trail") or d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	if not sheds then
		part:Destroy()
		return
	end
	part.Transparency = 1
	task.delay(part:GetAttribute("Linger") or CARD_LIFE, part.Destroy, part)
end

-- A Rain's beams (`kit`, Kind "Rain") on the spot `spot` (at a hero's root height, HeroKit.leapLanding): its circle
-- shining faintly on the ground from now till the last, and from its `From` to its `To` small laser beams of his
-- projectiles' colours falling anywhere in it, each flashing where it strikes, with a crack at every one of its hits
-- (his pack's Release, the sound of his other beams, or else UiSound's Zap).
local function rainLater(character: Model, spot: Vector3, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local below = Workspace:Raycast(spot, Vector3.new(0, -(height + 2), 0), groundRay)
	local ground = if below then below.Position else spot - Vector3.new(0, height, 0)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	local look = settings and settings.Projectile or {}
	local core = if look.Laser then look.Laser.Color else Color3.new(1, 1, 1)
	local glow = look.Glow or core
	local lean = HeroKit.flat(root.CFrame.LookVector) * BEAM_LEAN
	-- Over where he hangs, also when he cast it in the air (a jump pad's flight) high over the spot.
	local fallFrom = kit.Rise + BEAM_ABOVE + math.max(0, root.Position.Y - height - ground.Y)
	leanLater(character, root, spot, kit)

	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.1, kit.Radius * 2, kit.Radius * 2)
	disc.CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Material = Enum.Material.Neon
	disc.Color = glow
	disc.Transparency = 0.85
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = effects()
	task.delay(kit.To + BEAM_FALL + 0.3, disc.Destroy, disc)

	local function beam()
		local angle, out = math.random() * math.pi * 2, kit.Radius * math.sqrt(math.random())
		local landing = ground + Vector3.new(math.cos(angle) * out, 0, math.sin(angle) * out)
		local top = landing + Vector3.new(0, fallFrom, 0) - lean
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.22, 0.22, 4)
		part.Material = Enum.Material.Neon
		part.Color = core
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.lookAt(top, landing)
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 5
		light.Brightness = 1.5
		light.Parent = part
		if look.Cards then
			shedCards(part, glow)
		end
		part.Parent = effects()
		TweenService:Create(part, TweenInfo.new(BEAM_FALL, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(landing + (top - landing).Unit * 2, landing - (top - landing).Unit),
		}):Play()
		task.delay(BEAM_FALL, function()
			retire(part)
			local flash = Instance.new("Part")
			flash.Shape = Enum.PartType.Ball
			flash.Size = Vector3.one * 0.6
			flash.CFrame = CFrame.new(landing + Vector3.new(0, 0.3, 0))
			flash.Material = Enum.Material.Neon
			flash.Color = glow
			flash.Transparency = 0.2
			flash.Anchored = true
			flash.CanCollide = false
			flash.CanQuery = false
			flash.CanTouch = false
			flash.CastShadow = false
			flash.Parent = effects()
			TweenService:Create(flash, TweenInfo.new(0.25), { Size = Vector3.one * 2.6, Transparency = 1 }):Play()
			task.delay(0.25, flash.Destroy, flash)
		end)
	end
	for at = kit.From - BEAM_FALL, kit.To - BEAM_FALL, BEAM_GAP do
		task.delay(math.max(0, at), beam)
	end
	for at = kit.From, kit.To + 1e-3, kit.Every do
		task.delay(at, function()
			if settings and settings.Pack then
				HeroSounds.event(character, settings.Pack, "Release")
			else
				UiSound.at("Zap", ground, 0.8)
			end
		end)
	end
end

-- The dash's lunge in place while the hero is carried from `from` to `to`, its trail, and the lunge cut off at its end.
local function dashMotion(character: Model, from: Vector3, to: Vector3, kit: any)
	HeroAnimator.play(character, kit.Motion, kit.Speed or 1, nil, true)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local drop = if root and humanoid then Vector3.new(0, heightOf(root, humanoid), 0) else Vector3.zero
	if kit.Trail ~= false then
		local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
		local kind = settings and settings.Effects
		task.delay(kit.Start, function()
			if kind == "Fire" then
				FireEffects.dash(from - drop, to - drop, kit.Move - kit.Start)
			elseif kind == "Lightning" then
				LightningEffects.dash(from - drop, to - drop, kit.Move - kit.Start)
			else
				ShadowEffects.dash(from - drop, to - drop, kit.Move - kit.Start, paletteOf(settings))
			end
		end)
	end
	task.delay(kit.Stop, function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.stop(character)
		end
	end)
end

-- A vanishing trick's flick of the hand (`kit`, Kind "Vanish"), cut off at its `Stop`; hiding him is the server's.
local function vanishMotion(character: Model, kit: any)
	HeroAnimator.play(character, kit.Motion, 1)
	task.delay(kit.Stop, function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.stop(character)
		end
	end)
end

-- Whether the buy phase is over (the server's "FightAt" on Workspace, as MatchService has it).
local function fighting(): boolean
	local at = Workspace:GetAttribute("FightAt")
	return at ~= nil and Workspace:GetServerTimeNow() >= at
end

local function canAct(key: string, now: number): boolean
	return fighting() and Leveling.learned(player, key) and now >= busyUntil and now >= (cooldowns[key] or 0)
end

local function stopAiming()
	if indicator then
		Indicators.destroy(indicator)
		indicator = nil
	end
	if aiming then
		AbilityBar.aiming(aiming, false)
	end
	aiming = nil
end

local function cast(key: string)
	local character, root, humanoid, settings = hero()
	if not character or not root or not humanoid then
		return
	end
	local kit = settings.Kit[key]
	local now = os.clock()
	if not kit or not canAct(key, now) then
		return
	end
	local aim = HeroCamera.aim()
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	actionEvent:FireServer(key, aim)
	following, aimSentAt = HeroKit.follows(kit), now
	AbilityBar.used(key)

	if kit.Kind == "Combo" then
		local continuing = now <= comboUntil
		local step = if continuing then combo % #kit.Hits + 1 else 1
		local hit = kit.Hits[step]
		local speed = kit.Speed * (hit.Speed or 1) * Items.attackSpeed(player)
		local start = if continuing and kit.Follow then kit.Follow else 0
		combo, comboUntil = step, now + kit.Reset - start / speed
		busyUntil = now + (hit.Hit + (hit.Recover or 0) + (kit.Follow or 0) - start) / speed + RECOVER
		if start > 0 then
			HeroAnimator.crossfade(character, FOLLOW_FADE)
		end
		local length = HeroAnimator.play(character, hit.Motion, speed, start)
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
		return
	end

	comboUntil = 0
	local cooldown = Leveling.cooldown(Players.LocalPlayer, key, kit.Cooldown)
	cooldowns[key] = now + cooldown
	AbilityBar.cooldown(key, cooldown)
	if kit.Kind == "Dash" then
		local from = root.Position
		local down = nil
		if kit.Grounded then
			from = HeroKit.grounded(from, heightOf(root, humanoid), HeroKit.leapIgnore())
			down = if from ~= root.Position then root.Position else nil
		end
		local to = HeroKit.dashEnd(from, direction, kit.Range, HeroKit.leapIgnore())
		busyUntil = now + kit.Move + RECOVER
		leap = { started = now, from = from, to = to, takeoff = kit.Start, land = kit.Move, sharp = true, down = down }
		slow(humanoid, kit.Move, 0)
		dashMotion(character, from, to, kit)
		return
	elseif kit.Kind == "Vanish" then
		busyUntil = now + kit.Cast + RECOVER
		-- He stands still for the flick, then runs faster while unseen, till it ends or another attack slows him.
		motionToken += 1
		local token = motionToken
		humanoid.WalkSpeed = 0
		task.delay(kit.Cast, function()
			if motionToken == token and humanoid.Parent then
				humanoid.WalkSpeed = Items.walkSpeed(player) * (kit.Haste or 1)
			end
		end)
		task.delay(kit.Duration, function()
			if motionToken == token and humanoid.Parent then
				humanoid.WalkSpeed = Items.walkSpeed(player)
			end
		end)
		vanishMotion(character, kit)
		return
	elseif kit.Kind == "Rain" then
		local length = HeroAnimator.play(character, kit.Motion, 1, nil, "Grounded")
		busyUntil = now + kit.Land + RECOVER
		local spot = HeroKit.leapLanding(root.Position, aim, kit.Range, heightOf(root, humanoid), HeroKit.leapIgnore())
		leap = {
			started = now,
			from = root.Position,
			to = root.Position,
			takeoff = 0,
			land = kit.Land,
			sharp = false,
			lift = kit,
		}
		slow(humanoid, kit.Land + RECOVER, 0)
		thenLater(character, kit, length)
		rainLater(character, spot, kit)
		return
	elseif kit.Kind == "Snipe" then
		-- The rifle comes up and he holds its aim, looking through its scope, till he clicks or it fires itself.
		busyUntil = now + kit.Ready + kit.Hold + RECOVER
		HeroAnimator.play(character, kit.Motion, kit.Raise or 1)
		HeroAnimator.stopAt(character, kit.AimAt)
		slow(humanoid, kit.Ready + kit.Hold, kit.WalkSpeed)
		sniping = { kit = kit, readyAt = now + kit.Ready }
		Scope.enter(kit)
		return
	end
	local length = HeroAnimator.play(character, kit.Motion, 1, nil, kit.InPlace)
	if kit.Kind == "Leap" then
		busyUntil = now + kit.Land + RECOVER
		local to = HeroKit.leapLanding(root.Position, aim, kit.Range, heightOf(root, humanoid), HeroKit.leapIgnore())
		leap = { started = now, from = root.Position, to = to, takeoff = kit.Takeoff, land = kit.Land, sharp = false }
		slow(humanoid, kit.Land + RECOVER, 0)
		landLater(character, to, kit)
	elseif kit.Kind == "Strike" then
		local last = kit.Strikes[#kit.Strikes]
		busyUntil = now + last + RECOVER
		local spot = HeroKit.leapLanding(root.Position, aim, kit.Range, heightOf(root, humanoid), HeroKit.leapIgnore())
		slow(humanoid, last + RECOVER, 0)
		holdLater(character, kit)
		strikeLater(character, spot, kit)
	elseif kit.Kind == "Throw" then
		local releases = HeroKit.releases(kit)
		busyUntil = now + releases[#releases] + RECOVER
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
	elseif kit.Kind == "Ascend" then
		busyUntil = now + kit.Land + RECOVER
		leap = {
			started = now,
			from = root.Position,
			to = root.Position,
			takeoff = 0,
			land = kit.Land,
			sharp = false,
			lift = kit,
		}
		slow(humanoid, kit.Land + RECOVER, 0)
		thenLater(character, kit, length)
	else
		busyUntil = now + length
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
		if kit.Slam then
			slamLater(character, kit)
		end
		if kit.Zap then
			zapLater(character, kit)
		end
		if kit.Beam then
			beamLater(character, kit)
		end
	end
end

-- His Snipe fired (his click, or the server when its Hold ran out): the scope comes from his eye and the rifle kicks.
local function fired()
	local s = sniping
	sniping = nil
	Scope.leave()
	local character, _, humanoid = hero()
	if not s or not character or not humanoid then
		return
	end
	busyUntil = os.clock() + s.kit.Recover
	HeroAnimator.play(character, s.kit.Motion, 1, s.kit.Kick)
	slow(humanoid, s.kit.Recover, Config.Combat.AttackWalkSpeed)
	HeroCamera.shake(0.3, 0.25)
end

-- A click through the scope fires, once it may.
local function fire()
	local s = sniping
	if not s or os.clock() < s.readyAt then
		return
	end
	actionEvent:FireServer("Fire", HeroCamera.aim())
	fired()
end

local function startAiming(key: string)
	local _, _, _, settings = hero()
	local kit = settings and settings.Kit[key]
	if not kit or not Leveling.learned(player, key) or os.clock() < (cooldowns[key] or 0) then
		return
	end
	stopAiming()
	aiming = key
	AbilityBar.aiming(key, true)
	if kit.Indicator == "Arrow" then
		indicator = Indicators.arrow()
	elseif kit.Indicator == "Zone" then
		indicator = Indicators.zone()
	elseif kit.Indicator == "Cone" then
		indicator = Indicators.cone()
	elseif kit.Indicator == "Ring" then
		indicator = Indicators.ring()
	end
end

local function updateIndicator()
	local character, root, humanoid, settings = hero()
	if not aiming or not indicator then
		return
	end
	if not character or not root or not humanoid then
		stopAiming()
		return
	end
	local kit = settings.Kit[aiming]
	local aim = HeroCamera.aim()
	local height = heightOf(root, humanoid)
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local below = Workspace:Raycast(root.Position, Vector3.new(0, -(height + 2), 0), groundRay)
	-- In the air (a jump pad's flight) every indicator lies on the ground under him (owner, 2026-11-02), the arrow as
	-- far over it as his shot towards the crosshair flies before it ends or meets the ground.
	local floor = below or Workspace:Raycast(root.Position, Vector3.new(0, -AIR_DEPTH, 0), groundRay)
	local feet = if floor then floor.Position else root.Position - Vector3.new(0, height, 0)
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	if indicator.kind == "Arrow" and not below then
		local muzzle = HeroKit.muzzle(root.Position)
		local aimed = HeroKit.aimDirection(muzzle, aim, direction)
		local from = HeroKit.shotOrigin(muzzle, aimed)
		local ground = Workspace:Raycast(from, aimed * kit.Range, groundRay)
		local ends = if ground then ground.Position else from + aimed * kit.Range
		local length = HeroKit.flat(ends - root.Position).Magnitude
		Indicators.placeArrow(indicator, feet, direction, math.max(length, 1), kit.Width)
	elseif indicator.kind == "Arrow" then
		Indicators.placeArrow(indicator, feet + direction * 1.2, direction, kit.Range, kit.Width)
	elseif indicator.kind == "Zone" then
		local to = HeroKit.leapLanding(root.Position, aim, kit.Range, height, HeroKit.leapIgnore())
		local landing = Workspace:Raycast(to, Vector3.new(0, -(height + 2), 0), groundRay)
		local spot = if landing then landing.Position else to - Vector3.new(0, height, 0)
		Indicators.placeZone(indicator, feet, kit.Range, spot, kit.Radius)
	elseif indicator.kind == "Cone" then
		Indicators.placeCone(indicator, feet, direction, kit.Range)
	elseif indicator.kind == "Ring" then
		Indicators.placeRing(indicator, feet, kit.SlamRadius)
	end
end

local function endFlight()
	local f = flight
	flight = nil
	if f then
		f.ended()
	end
end

-- The flight's root at share `s` of it, and how fast it moves there: straight on over the ground, and up to its
-- peak halfway and down from it, slowing into the peak and speeding out of it as a thrown body does.
local function flightAt(f: Flight, s: number): (Vector3, Vector3)
	local peak = math.max(f.from.Y, f.to.Y) + f.height
	local flat = f.from:Lerp(f.to, s)
	local y, rate
	if s < 0.5 then
		local u = 1 - 2 * s
		y = f.from.Y + (peak - f.from.Y) * (1 - u * u)
		rate = (peak - f.from.Y) * 4 * u
	else
		local u = 2 * s - 1
		y = f.to.Y + (peak - f.to.Y) * (1 - u * u)
		rate = -(peak - f.to.Y) * 4 * u
	end
	local across = (f.to - f.from) * Vector3.new(1, 0, 1)
	return Vector3.new(flat.X, y, flat.Z), (across + Vector3.new(0, rate, 0)) / f.length
end

local function updateFlight(root: BasePart)
	local f = flight :: Flight
	local s = math.min(1, (os.clock() - f.started) / f.length)
	local position, velocity = flightAt(f, s)
	-- Only where he is: his attacks turn him to their aim, and he turns with his keys as he would in any jump.
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = if s >= 1 then Vector3.zero else velocity
	if s >= 1 then
		endFlight()
	end
end

local function updateLeap()
	local l = leap
	local character, root, humanoid = hero()
	if not character or not root then
		leap = nil
		endFlight()
		return
	end
	-- An attack that moves him takes over from a jump pad's flight once it moves him, from where he is then, and he
	-- falls from where it leaves him; until then the flight carries him through its windup. A Grounded dash takes over
	-- at once and brings him down to the ground in its windup instead.
	if l and flight and l.down then
		endFlight()
	elseif l and flight and (l.lift or os.clock() - l.started >= l.takeoff) then
		local shift = root.Position - l.from
		l.from = root.Position
		if l.sharp then
			l.to += shift
		end
		endFlight()
	end
	if flight then
		updateFlight(root)
		return
	end
	if not l then
		return
	end
	local t = os.clock() - l.started
	if l.lift then
		-- Cast in the air, it would ease him down to a stop where he cast it, in the air, and only then would he fall:
		-- he falls straight from his hang instead, all the way down.
		if t >= l.lift.Fall and l.aloft == nil then
			groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
			local height = heightOf(root, humanoid :: Humanoid)
			l.aloft = not Workspace:Raycast(l.from, Vector3.new(0, -(height + 2), 0), groundRay)
		end
		if l.aloft then
			root.AssemblyLinearVelocity = Vector3.zero
			leap = nil
			return
		end
		root.CFrame = CFrame.new(l.from + Vector3.new(0, HeroKit.lift(l.lift, t), 0)) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		if t >= l.lift.Land then
			leap = nil
		end
		return
	end
	if t < l.takeoff then
		if l.down then
			local fall = math.clamp(t / l.takeoff, 0, 1)
			fall = fall * fall * (3 - 2 * fall)
			root.CFrame = CFrame.new(l.down:Lerp(l.from, fall)) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
		end
		return
	end
	local alpha = math.clamp((t - l.takeoff) / (l.land - l.takeoff), 0, 1)
	alpha = if l.sharp then 1 - (1 - alpha) ^ 2 else alpha * alpha * (3 - 2 * alpha)
	local position = l.from:Lerp(l.to, alpha)
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		leap = nil
	end
end

local function undo(key: string)
	local character, _, humanoid = hero()
	if sniping then
		sniping = nil
		Scope.leave()
	end
	busyUntil = 0
	cooldowns[key] = 0
	AbilityBar.cooldown(key, 0)
	leap = nil
	if character and humanoid then
		HeroAnimator.stop(character)
		motionToken += 1
		humanoid.WalkSpeed = Items.walkSpeed(player)
	end
end

local function onMotion(character: Model, key: string, step: number, landing: Vector3?, startTime: number?)
	if character == player.Character then
		-- The server fired his Snipe itself (its Hold ran out).
		local s = sniping
		local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
		if step == 1 and s and settings and settings.Kit[key] == s.kit then
			fired()
		end
		return
	end
	if not character.Parent then
		return
	end
	local name = character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	local kit = settings and settings.Kit[key]
	if not kit then
		return
	end
	if kit.Kind == "Combo" then
		local hit = kit.Hits[step]
		-- A hit following on from the last may start part-way in (the kit's `Follow`), eased into.
		if startTime and startTime > 0 then
			HeroAnimator.crossfade(character, FOLLOW_FADE)
		end
		HeroAnimator.play(
			character,
			hit.Motion,
			kit.Speed * (hit.Speed or 1) * (character:GetAttribute("AttackSpeed") or 1),
			startTime
		)
	elseif kit.Kind == "Dash" then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and landing then
			local from = root.Position
			if kit.Grounded then
				from = HeroKit.grounded(from, heightOf(root, humanoid), HeroKit.leapIgnore())
			end
			dashMotion(character, from, landing, kit)
		end
		return
	elseif kit.Kind == "Vanish" then
		vanishMotion(character, kit)
		return
	elseif kit.Kind == "Snipe" then
		-- He holds his aim (step 0) till he fires, and the rifle kicks (step 1).
		if step == 1 then
			HeroAnimator.play(character, kit.Motion, 1, kit.Kick)
		else
			HeroAnimator.play(character, kit.Motion, kit.Raise or 1)
			HeroAnimator.stopAt(character, kit.AimAt)
		end
		return
	elseif kit.Kind == "Rain" then
		thenLater(character, kit, HeroAnimator.play(character, kit.Motion, 1, nil, "Grounded"))
		if landing then
			rainLater(character, landing, kit)
		end
		return
	else
		local length = HeroAnimator.play(character, kit.Motion, 1, nil, kit.InPlace)
		if kit.Kind == "Ascend" then
			thenLater(character, kit, length)
		end
	end
	if kit.Kind == "Leap" and landing then
		landLater(character, landing, kit)
	elseif kit.Kind == "Strike" and landing then
		holdLater(character, kit)
		strikeLater(character, landing, kit)
	elseif kit.Slam then
		slamLater(character, kit)
	end
	if kit.Zap then
		zapLater(character, kit)
	end
	if kit.Beam then
		beamLater(character, kit)
	end
end

-- A hero's flying projectile (Config.Heroes[hero].Projectile): the pack's component, or a glowing `Orb` of magic
-- for a pack without one, with a trail behind it; a Shadowren's dagger spins end over end and glows with shadow, a
-- Rowan's arrow flies point first. An orb is `scale` times its usual size (an Ascend's great orb).
-- A swirl image `fraction` of `gui` across, turning once every `turn` seconds (backwards when negative).
local function swirlImage(gui: BillboardGui, image: string, fraction: number, turn: number, transparency: number)
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageTransparency = transparency
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(fraction, fraction)
	label.Parent = gui
	if turn ~= 0 then
		local info = TweenInfo.new(math.abs(turn), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
		TweenService:Create(label, info, { Rotation = if turn > 0 then 360 else -360 }):Play()
	end
end

-- The dark vortex an orb is (Config's Projectile.Orb.Swirl), round the unseen `part`: a faint glow, two vortices
-- turning against each other and the energy crackling round them, all facing the camera, and the dark smoke and
-- violet sparks it leaves behind, `size` studs across.
local function dressOrb(part: BasePart, size: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size * 3.2, size * 3.2)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.MaxDistance = 400
	gui.Adornee = part
	swirlImage(gui, Assets.OrbGlow, 1.1, 0, 0.65)
	swirlImage(gui, Assets.OrbVortex, 0.85, 0.55, 0)
	swirlImage(gui, Assets.OrbVortex, 0.55, -0.9, 0.3)
	swirlImage(gui, Assets.OrbWisps, 1, -1.6, 0)
	gui.Parent = part
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 15, 120), Color3.fromRGB(10, 0, 20))
	smoke.LightEmission = 0
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 1.4),
		NumberSequenceKeypoint.new(1, size * 2.6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.35, 0.6)
	smoke.Rate = 45
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-90, 90)
	smoke.Parent = part
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(230, 110, 255), Color3.fromRGB(110, 30, 220))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Rate = 25
	sparks.Speed = NumberRange.new(size * 2, size * 4)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = part
end

local function projectileModel(settings: any, scale: number): BasePart
	local look = settings.Projectile
	local part: BasePart
	if look.Orb then
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * look.Orb.Size * scale * (if look.Orb.Swirl then 0.55 else 1)
		part.Material = Enum.Material.Neon
		part.Color = look.Orb.Color
		part.CastShadow = false
		if look.Orb.Swirl then
			dressOrb(part, look.Orb.Size * scale)
		end
	elseif look.Laser then
		-- A short bolt of light, lying along its flight.
		part = Instance.new("Part")
		part.Size = Vector3.new(look.Laser.Width, look.Laser.Width, look.Laser.Length) * scale
		part.Material = Enum.Material.Neon
		part.Color = look.Laser.Color
		part.CastShadow = false
		if look.Cards then
			shedCards(part, look.Glow or look.Laser.Color)
		end
	else
		local template =
			ReplicatedStorage[settings.Pack].Rig.Components[look.Component]:FindFirstChildWhichIsA("MeshPart", true)
		part = template:Clone() :: MeshPart
		for _, d in part:GetChildren() do
			if d:IsA("JointInstance") then
				d:Destroy()
			end
		end
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = if look.Orb and look.Orb.Swirl then 1 else 0
	local half = if look.TrailHalf then look.TrailHalf * scale else part.Size.Y * 0.3
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -half, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(look.Trail[1], look.Trail[2])
	trail.Transparency = NumberSequence.new(look.TrailFade or 0.35, 1)
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = part
	if look.Glow then
		local light = Instance.new("PointLight")
		light.Color = look.Glow
		light.Range = (if look.Orb and look.Orb.Swirl then 9 else 6) * scale
		light.Brightness = if look.Orb and look.Orb.Swirl then 1.8 else 1.5
		light.Parent = part
	end
	part.Parent = effects()
	return part
end

local function onProjectile(
	id: number,
	character: Model,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	scale: number?,
	blast: number?
)
	local name = character and character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	if not settings then
		return
	end
	if not settings.Projectile then
		return
	end
	-- The ability he shoots it with may have it leave him elsewhere than his shots do (its `ShotsFrom`), and a gun's
	-- ability its own round (its `Round`).
	local playing = HeroAnimator.playing(character)
	local from = if settings.Projectile.FromWeapon then "Point" else settings.Projectile.From
	local round = settings.Projectile.Gun
	for _, kit in settings.Kit do
		if kit.Motion and kit.Motion == playing then
			from = kit.ShotsFrom or from
			round = if round then kit.Round or round else nil
		end
	end
	local model, spin
	if round then
		model, spin = GunEffects.round(round, scale or 1)
		model.Parent = effects()
	else
		model, spin = projectileModel(settings, scale or 1), settings.Projectile.Spin or 0
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if from and root then weaponFrom(character, root, from) else origin
	flying[id] = {
		dagger = model,
		origin = origin,
		from = from,
		direction = direction,
		speed = speed,
		range = range,
		started = os.clock(),
		spin = spin,
		turn = if round then CFrame.identity else settings.Projectile.Turn or CFrame.identity,
		burst = settings.Projectile.Burst == true,
		blast = blast,
		character = character,
		round = round,
		start = start,
	}
	-- Where it is first drawn, should this frame be drawn before it moves.
	local f = flying[id]
	f.dagger.CFrame = CFrame.lookAt(start, start + direction) * f.turn
	if round then
		GunEffects.muzzle(start, direction, round)
	end
	HeroSounds.event(character, settings.Pack, "Release")
end

-- A great orb bursting at `at` over `radius` studs: a blast of dark magic in the air there (of fire for a hero with
-- Effects "Fire") and, when the ground is near enough below to be reached, the slam's shockwaves over it.
local function blastAt(character: Model, at: Vector3, radius: number)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	local fiery = settings and settings.Effects == "Fire"
	if fiery then
		FireEffects.blast(at, radius)
	else
		ShadowEffects.blast(at, radius)
	end
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local below = Workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -(radius + 1), 0), groundRay)
	if below then
		if fiery then
			FireEffects.shockwave(below.Position, radius)
		else
			ShadowEffects.slam(below.Position, radius)
		end
	end
	shakeNear(at, 0.9)
	if settings and settings.Pack and character.Parent then
		HeroSounds.event(character, settings.Pack, "Blast")
	end
end

local function onProjectileEnd(id: number, at: Vector3, hit: boolean, headshot: boolean?)
	local f = flying[id]
	if f then
		retire(f.dagger)
		flying[id] = nil
		if headshot and f.character == player.Character then
			Scope.headshot()
		end
		if f.blast then
			blastAt(f.character, at, f.blast)
		elseif hit and f.burst then
			ShadowEffects.burst(at)
		end
		-- A round strikes where it stopped short of its reach (an enemy, a wall, the floor).
		if f.round and (hit or (at - f.origin).Magnitude < f.range - 1) then
			if not f.blast then
				GunEffects.strike(at, f.direction, f.round)
			end
			if f.round == "Rifle" then
				GunEffects.line(f.start, at)
			end
		end
	end
end

-- Over how many studs of its way a projectile `FromWeapon` comes from his weapon's point onto the way the server sends
-- it along.
local WEAPON_BLEND = 12

local function updateFlying()
	local now = os.clock()
	for id, f in flying do
		-- One from his weapon is first seen right at its point, however long the frame.
		if f.from and not f.seen then
			f.seen = true
			f.started = now
		end
		local travelled = (now - f.started) * f.speed
		if travelled > f.range + 10 then
			retire(f.dagger)
			flying[id] = nil
			continue
		end
		local fade = if f.from then math.max(1 - travelled / WEAPON_BLEND, 0) else 0
		-- Where it leaves him as he moves now, not where that was as the shot left the server.
		local root = f.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local shift = if fade > 0 and root
			then weaponFrom(f.character, root, f.from :: string) - f.origin
			else Vector3.zero
		local position = f.origin + f.direction * math.min(travelled, f.range) + shift * fade
		-- Coming onto the server's way it points where it moves, not sideways along it.
		local moving = f.direction - shift / WEAPON_BLEND
		local heading = if fade > 0 and moving.Magnitude > 0.1 then moving.Unit else f.direction
		local spin = CFrame.Angles(-(now - f.started) * f.spin, 0, 0)
		f.dagger.CFrame = CFrame.lookAt(position, position + heading) * spin * f.turn
	end
end

-- The crosshair: neutral, or the colour of the team under it.
local function crosshair(): ImageLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(46, 46)
	image.BackgroundTransparency = 1
	image.Image = Assets.CrosshairNeutral
	image.Parent = gui
	return image
end

-- What `instance` belongs to that fights for a team (a hero, a Master, a minion), and that team.
local function teamOf(instance: Instance?): (Instance?, string?)
	while instance and instance ~= Workspace do
		local team = instance:GetAttribute("Team")
		if team then
			return instance, team
		end
		instance = instance.Parent
	end
	return nil, nil
end

local reachRay = RaycastParams.new()
reachRay.FilterType = Enum.RaycastFilterType.Exclude
local extents: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any

-- Whether the hero's next left click (the combo's next hit) would strike `target` where the crosshair is on it, at
-- `aim`: only what the server strikes (a minion's root part or a Combatant), by the server's own measure
-- (HeroKit.body, HeroKit.hitReaches), and a shot only with no wall in its way.
local function reaches(target: Instance, aim: Vector3): boolean
	local _, root, _, settings = hero()
	local kit = settings and settings.Kit.M1
	if not root or not kit or kit.Kind ~= "Combo" then
		return false
	end
	local minions = Workspace:FindFirstChild("Minions")
	if not (minions and target.Parent == minions) and not CollectionService:HasTag(target, "Combatant") then
		return false
	end
	local body = HeroKit.body(target, extents)
	local hit = kit.Hits[if os.clock() <= comboUntil then combo % #kit.Hits + 1 else 1]
	local facing = root.CFrame.LookVector
	if not body or not HeroKit.hitReaches(hit, root.Position, aim, facing, body) then
		return false
	end
	if not hit.ProjectileSpeed then
		return true
	end
	local muzzle = HeroKit.muzzle(root.Position)
	local from = HeroKit.shotOrigin(muzzle, HeroKit.aimDirection(muzzle, aim, facing))
	reachRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	return Workspace:Raycast(from, aim - from, reachRay) == nil
end

-- Whether the ability aimed now (`key`) would strike any enemy where it stands, by the server's own measure
-- (HeroKit.abilityStrikes): in its leap's ring where it lands, on its projectiles' way up to the first wall (and in
-- the burst there), or in its sweeps and slam.
local function abilityStrikes(key: string): boolean
	local character, root, humanoid, settings = hero()
	local kit = settings and settings.Kit[key]
	if not character or not root or not humanoid or not kit then
		return false
	end
	local aim = HeroCamera.aim()
	local facing = root.CFrame.LookVector
	local landing, shots =
		HeroKit.aimed(kit, root.Position, aim, facing, heightOf(root, humanoid), HeroKit.leapIgnore())
	for _, foe in HeroKit.foes(character:GetAttribute("Team"), extents) do
		if HeroKit.abilityStrikes(kit, root.Position, aim, facing, landing, shots, foe.body) then
			return true
		end
	end
	return false
end

-- Throws the player's hero from where he stands so his root comes down on `to`, in an arc `height` studs over the
-- higher of its ends, in `length` seconds, turned the way he flies (a jump pad, JumpPadView). He may attack all the
-- way, turning to his aim; an attack that moves him (a dash, a leap, an Ascend, a Rain) takes over from it. `ended`
-- runs once he is down or taken over. Whether he went: not while an attack moves him, or he is already flying.
function HeroControls.launch(to: Vector3, height: number, length: number, ended: () -> ()): boolean
	local character, root, humanoid = hero()
	if not character or not root or not humanoid or flight then
		return false
	end
	local l = leap
	if l and (l.lift or os.clock() - l.started >= l.takeoff) then
		return false
	end
	local heading = (to - root.Position) * Vector3.new(1, 0, 1)
	if heading.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + heading)
	end
	flight = { started = os.clock(), from = root.Position, to = to, height = height, length = length, ended = ended }
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	return true
end

function HeroControls.start()
	-- Loaded now: a beam is gone before a picture first asked for by its sparkles arrives, so the first beam of a game
	-- would shed none.
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, { Assets.CardStar, table.unpack(Assets.CardSuits) })
	local net = ReplicatedStorage:WaitForChild("Net")
	actionEvent = net:WaitForChild("HeroAction") :: RemoteEvent
	(net:WaitForChild("HeroMotion") :: RemoteEvent).OnClientEvent:Connect(onMotion);
	(net:WaitForChild("HeroRefused") :: RemoteEvent).OnClientEvent:Connect(undo);
	(net:WaitForChild("HeroProjectile") :: RemoteEvent).OnClientEvent:Connect(onProjectile);
	(net:WaitForChild("HeroProjectileEnd") :: RemoteEvent).OnClientEvent:Connect(onProjectileEnd)
	Scope.start()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if sniping then
				fire()
				return
			end
			holdingM1 = true
			cast("M1")
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			cast("Dash")
			return
		end
		local key = KEY_OF[input.KeyCode] or KEY_OF[input.UserInputType]
		if not key then
			return
		end
		-- A Snipe has nothing to aim on the ground: the scope comes up at once.
		local _, _, _, settings = hero()
		local kit = settings and settings.Kit[key]
		if kit and kit.Kind == "Snipe" then
			cast(key)
		else
			startAiming(key)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingM1 = false
			return
		end
		local key = KEY_OF[input.KeyCode] or KEY_OF[input.UserInputType]
		if key and key == aiming then
			stopAiming()
			cast(key)
		end
	end)

	player.CharacterAdded:Connect(function()
		stopAiming()
		endFlight()
		sniping = nil
		busyUntil, combo, comboUntil, leap = 0, 0, 0, nil
		table.clear(cooldowns)
		for _, key in { "M1", "M2", "E", "R", "Dash" } do
			AbilityBar.cooldown(key, 0)
		end
	end)

	local cross = crosshair()
	RunService.PreSimulation:Connect(updateLeap)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		-- A scope he no longer looks through: he died, or no word came that it fired.
		if sniping and (not hero() or now > busyUntil) then
			sniping = nil
			Scope.leave()
		end
		if holdingM1 and not aiming and not sniping then
			cast("M1")
		end
		if following and now < busyUntil and now - aimSentAt >= AIM_EVERY then
			aimSentAt = now
			actionEvent:FireServer("Aim", HeroCamera.aim())
		end
		updateIndicator()
		updateFlying()
		local character = player.Character
		local own = character and character:GetAttribute("Team")
		local target, team = teamOf(HeroCamera.target())
		local red = if aiming
			then abilityStrikes(aiming)
			else target ~= nil and team ~= nil and team ~= own and reaches(target, HeroCamera.aim())
		cross.Image = if red
			then Assets.CrosshairEnemy
			elseif target and team == own then Assets.CrosshairAlly
			else Assets.CrosshairNeutral
		-- The scope has its own crosshair.
		cross.Visible = HeroCamera.scoping() < 0.5
	end)
end

return HeroControls
