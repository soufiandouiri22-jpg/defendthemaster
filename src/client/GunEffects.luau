-- Corvin's shots on the client (Config.Heroes[hero].Projectile.Gun, a kit's `Round`; owner, 2026-11-04): three
-- rounds, each with its own flight, muzzle flash and strike.
-- "Revolver" (his quick shots): a small hot bullet with a thin bright tracer behind it; a short flash, a few sparks
-- and a wisp of smoke at the barrel; sparks and dust where it strikes.
-- "Bomb" (his bomb round): a dark iron shell tumbling through the air, glowing hot inside, its fuse spitting sparks
-- and a trail of fire and thick smoke behind it; a great flash and a cloud of smoke at the barrel. Its burst is the
-- fire blast (FireEffects.blast).
-- "Rifle" (his sniper shot): a long white-hot streak with a pale tracer, a great flash and a ring of smoke blown out
-- round the barrel, and the bullet's whole way left hanging in the air as a fading line once it strikes.
-- The pictures are Tools/gun_textures.py's (Assets.Gun*).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local GunEffects = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local HOT = Color3.fromRGB(255, 240, 200)
local GOLD = Color3.fromRGB(255, 196, 92)
local FLAME = Color3.fromRGB(255, 120, 36)
local EMBER = Color3.fromRGB(190, 48, 12)
local PALE = Color3.fromRGB(236, 246, 255)
local ICE = Color3.fromRGB(150, 205, 255)

-- Per round: the bullet's length and thickness, its tracer's half width and how long it lingers (seconds), its colours
-- (head, tail), its glow's size, the muzzle flash's size, sparks and smoke puffs at the barrel, and the strike's.
local ROUNDS = {
	Revolver = {
		Length = 0.8,
		Thick = 0.12,
		Tracer = 0.07,
		TracerLife = 0.07,
		Head = HOT,
		Tail = FLAME,
		Glow = 1.3,
		Flash = 1.8,
		Sparks = 5,
		Smoke = 3,
		StrikeSparks = 7,
	},
	Bomb = {
		Thick = 0.5,
		Tracer = 0.3,
		TracerLife = 0.18,
		Head = GOLD,
		Tail = EMBER,
		Glow = 2.6,
		Flash = 3.4,
		Sparks = 12,
		Smoke = 9,
		StrikeSparks = 0,
	},
	Rifle = {
		Length = 2.6,
		Thick = 0.1,
		Tracer = 0.06,
		TracerLife = 0.12,
		Head = PALE,
		Tail = ICE,
		Glow = 1.7,
		Flash = 3.6,
		Sparks = 9,
		Smoke = 12,
		StrikeSparks = 14,
	},
}
-- How long the rifle's way hangs in the air after it strikes.
local LINE_LIFE = 0.7
-- How long a flown round's sparks and smoke take to fade after it is gone (its "Linger" attribute, HeroControls'
-- retire).
GunEffects.LINGER = 1.1

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function holder(at: CFrame): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.1
	part.CFrame = at
	part.Parent = effects()
	return part
end

local function sequence(from: number, to: number): NumberSequence
	return NumberSequence.new(from, to)
end

local function glow(part: BasePart, size: number, colour: Color3, transparency: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size, size)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.MaxDistance = 600
	gui.Adornee = part
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = Assets.GunGlow
	image.ImageColor3 = colour
	image.ImageTransparency = transparency
	image.Parent = gui
	gui.Parent = part
	return gui
end

-- Sparks flown out of `part` along its front, `spread` degrees round it, `speed` studs a second.
local function sparks(part: BasePart, colour: Color3, size: number, speed: NumberRange, spread: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Assets.GunSpark
	emitter.Color = ColorSequence.new(HOT, colour)
	emitter.LightEmission = 1
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.3) })
	emitter.Transparency = sequence(0, 1)
	emitter.Lifetime = NumberRange.new(0.08, 0.2)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = part
	return emitter
end

local function smoke(part: BasePart, colour: Color3, from: number, to: number, life: NumberRange): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.3, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = life
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = part
	return emitter
end

local function flashLight(part: BasePart, colour: Color3, range: number, brightness: number, time: number)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	task.delay(time, function()
		light.Enabled = false
	end)
end

-- The round `kind` in flight, `scale` times its size (a kit's OrbScale), lying along its flight (its -Z forward):
-- not yet in the world. A tumbling round spins (Spin, turns a second).
function GunEffects.round(kind: string, scale: number): (BasePart, number)
	local look = ROUNDS[kind] or ROUNDS.Revolver
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local spin = 0
	if kind == "Bomb" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * look.Thick * scale
		part.Material = Enum.Material.Metal
		part.Color = Color3.fromRGB(52, 46, 42)
		spin = 9
	else
		part.Size = Vector3.new(look.Thick, look.Thick, look.Length) * math.sqrt(scale)
		part.Material = Enum.Material.Neon
		part.Color = look.Head
	end
	local half = look.Tracer * scale
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -half, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Texture = Assets.GunStreak
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.Lifetime = look.TracerLife
	trail.Color = ColorSequence.new(look.Head, look.Tail)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = part
	glow(part, look.Glow * math.sqrt(scale), look.Head, 0.25)
	local light = Instance.new("PointLight")
	light.Color = look.Tail
	light.Range = (if kind == "Bomb" then 10 else 6) * math.sqrt(scale)
	light.Brightness = if kind == "Bomb" then 2 else 1.4
	light.Parent = part
	if kind == "Bomb" then
		part:SetAttribute("Linger", GunEffects.LINGER)
		-- The fuse's sparks, flung off as it tumbles, and the smoke it trails.
		local fuse = sparks(part, FLAME, 0.5, NumberRange.new(4, 10), 180)
		fuse.Rate = 70
		fuse.Acceleration = Vector3.new(0, -20, 0)
		fuse.Lifetime = NumberRange.new(0.15, 0.35)
		local trailSmoke = smoke(part, Color3.fromRGB(70, 66, 62), 0.7 * scale, 2.2 * scale, NumberRange.new(0.6, 1.0))
		trailSmoke.Rate = 55
		trailSmoke.Speed = NumberRange.new(0, 1)
		trailSmoke.SpreadAngle = Vector2.new(180, 180)
		trailSmoke.Acceleration = Vector3.new(0, 1.5, 0)
	end
	return part, spin
end

-- The flash at the barrel `at` as a `kind` round leaves it along `direction`.
function GunEffects.muzzle(at: Vector3, direction: Vector3, kind: string)
	local look = ROUNDS[kind] or ROUNDS.Revolver
	local part = holder(CFrame.lookAt(at, at + direction))
	local flash = Instance.new("ParticleEmitter")
	flash.Texture = Assets.GunFlash
	flash.LightEmission = 1
	flash.Orientation = Enum.ParticleOrientation.VelocityParallel
	flash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, look.Flash * 0.7),
		NumberSequenceKeypoint.new(1, look.Flash),
	})
	flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) })
	flash.Lifetime = NumberRange.new(0.06)
	flash.Speed = NumberRange.new(0.05)
	flash.SpreadAngle = Vector2.zero
	flash.EmissionDirection = Enum.NormalId.Front
	flash.ZOffset = 0.5
	flash.Rate = 0
	flash.Parent = part
	flash:Emit(1)
	glow(part, look.Flash * 1.2, look.Tail, 0.35)
	task.delay(0.07, function()
		local gui = part:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Enabled = false
		end
	end)
	flashLight(part, GOLD, look.Flash * 4, 3, 0.07)
	sparks(part, look.Tail, 0.35 * look.Flash / 2, NumberRange.new(14, 34), 22):Emit(look.Sparks)
	local puff =
		smoke(part, Color3.fromRGB(150, 146, 140), 0.25 * look.Flash, 0.9 * look.Flash, NumberRange.new(0.4, 0.9))
	puff.Speed = NumberRange.new(2, 6)
	puff.SpreadAngle = Vector2.new(if kind == "Rifle" then 80 else 30, if kind == "Rifle" then 80 else 30)
	puff.Acceleration = Vector3.new(0, 1, 0)
	puff:Emit(look.Smoke)
	Debris:AddItem(part, 1.2)
end

-- Where a `kind` round flying along `direction` strikes something at `at`: sparks thrown back off it, a puff of dust
-- and a short flash.
function GunEffects.strike(at: Vector3, direction: Vector3, kind: string)
	local look = ROUNDS[kind] or ROUNDS.Revolver
	if look.StrikeSparks <= 0 then
		return
	end
	local part = holder(CFrame.lookAt(at, at - direction))
	local size = if kind == "Rifle" then 1.6 else 1
	sparks(part, look.Tail, 0.4 * size, NumberRange.new(10, 26), 70):Emit(look.StrikeSparks)
	local dust = smoke(part, Color3.fromRGB(196, 176, 140), 0.4 * size, 1.6 * size, NumberRange.new(0.35, 0.7))
	dust.Speed = NumberRange.new(1, 4)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust:Emit(if kind == "Rifle" then 6 else 3)
	glow(part, 2.2 * size, look.Head, 0.2)
	task.delay(0.08, function()
		local gui = part:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Enabled = false
		end
	end)
	flashLight(part, look.Head, 6 * size, 2, 0.08)
	Debris:AddItem(part, 1)
end

-- The rifle's way from `from` to `to`, hanging in the air as a thin pale line that fades.
function GunEffects.line(from: Vector3, to: Vector3)
	local part = holder(CFrame.new(from))
	local a0 = Instance.new("Attachment")
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = to - from
	a1.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Texture = Assets.GunStreak
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.Color = ColorSequence.new(ICE, PALE)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0, beam.Width1 = 0.22, 0.3
	beam.Parent = part
	local started = os.clock()
	local step
	step = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / LINE_LIFE
		if t >= 1 or not part.Parent then
			step:Disconnect()
			part:Destroy()
			return
		end
		-- Fades from the shooter's end first, and widens a little as it drifts apart.
		local near = math.clamp(0.35 + t * 1.4, 0, 1)
		local far = math.clamp(0.25 + t * 0.9, 0, 1)
		beam.Transparency = NumberSequence.new(near, far)
		beam.Width0, beam.Width1 = 0.22 + t * 0.3, 0.3 + t * 0.4
	end)
end

return GunEffects
