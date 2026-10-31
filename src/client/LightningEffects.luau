-- Brontar's lightning on the client (a kit of Kind "Strike", Config.Heroes.Brontar), golden yellow (owner,
-- 2026-10-31): the warning on the spot it will strike, a flickering ring of light crackling round its edge while he
-- raises his sword, and each strike, a jagged bolt with two forks falling from high above, a flash that lights
-- everything round it, rings racing out over the ground, sparks flung up, and a scorched mark that glows and cools.
-- And the small bolts that crackle all over him now and then (Look.Crackle).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local LightningEffects = {}

local WHITE = Color3.fromRGB(255, 236, 150)
-- Deeper than it looks: neon glows towards white, so a pale yellow would read as white.
local BOLT = Color3.fromRGB(255, 190, 0)
local DEEP = Color3.fromRGB(255, 160, 20)
local SCORCH = Color3.fromRGB(28, 22, 12)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
-- How high above the ground the bolt starts.
local SKY = 90

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
	part.Parent = effects()
	return part
end

-- A flat image on the ground at `at`, `size` studs across.
local function decal(at: Vector3, image: string, colour: Color3, transparency: number, size: number): (Part, ImageLabel)
	local part = holder(at + Vector3.new(0, 0.15, 0), Vector3.new(size, 0.05, size))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Adornee = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageColor3 = colour
	label.ImageTransparency = transparency
	label.Parent = gui
	gui.Parent = part
	return part, label
end

local function sparks(parent: Instance, speed: NumberRange, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK
	emitter.Color = ColorSequence.new(WHITE, BOLT)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.25, 0.6)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

-- The warning on `ground` that a strike reaching `radius` studs falls there in `duration` seconds: a ring that
-- flickers faster as the strike nears, a faint glow inside it, and sparks crackling round its edge.
function LightningEffects.warn(ground: Vector3, radius: number, duration: number)
	local ring, ringLabel = decal(ground, Assets.IndicatorRing, BOLT, 0.2, radius * 2)
	local glow, glowLabel = decal(ground + Vector3.new(0, 0.02, 0), Assets.IndicatorDisc, DEEP, 0.75, radius * 2)
	local edge = holder(ground + Vector3.new(0, 0.4, 0), Vector3.new(radius * 2, 0.5, radius * 2))
	local crackle = sparks(edge, NumberRange.new(2, 6), 0.4)
	crackle.Shape = Enum.ParticleEmitterShape.Cylinder
	crackle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	crackle.Rate = 40
	crackle.Enabled = true
	local light = Instance.new("PointLight")
	light.Color = BOLT
	light.Range = radius * 1.5
	light.Brightness = 0.5
	light.Parent = edge
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 2.5 }):Play()
	TweenService:Create(glowLabel, TweenInfo.new(duration), { ImageTransparency = 0.45 }):Play()

	local started = os.clock()
	task.spawn(function()
		while os.clock() - started < duration do
			local left = duration - (os.clock() - started)
			ringLabel.ImageTransparency = if ringLabel.ImageTransparency < 0.3 then 0.6 else 0.05
			task.wait(math.clamp(left / 6, 0.04, 0.14))
		end
		ring:Destroy()
		glow:Destroy()
		edge:Destroy()
	end)
end

-- One jagged line of neon from `from` to `to`, `segments` pieces each pushed aside up to `jitter` studs, `width` thick.
local function jagged(from: Vector3, to: Vector3, segments: number, jitter: number, width: number): { Part }
	local parts = {}
	local last = from
	for i = 1, segments do
		local point = from:Lerp(to, i / segments)
		if i < segments then
			point += Vector3.new((math.random() * 2 - 1) * jitter, 0, (math.random() * 2 - 1) * jitter)
		end
		local length = (point - last).Magnitude
		local part = holder((last + point) / 2, Vector3.new(width, width, length))
		part.CFrame = CFrame.lookAt((last + point) / 2, point)
		part.Material = Enum.Material.Neon
		part.Color = BOLT
		part.Transparency = 0
		table.insert(parts, part)
		last = point
	end
	return parts
end

-- Lightning shot from `from` (his weapon's point) to `to`: a jagged bolt with a fork, crackling twice and fading, a
-- flash at both ends and sparks where it strikes.
function LightningEffects.zap(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local segments = math.clamp(math.floor(length / 1.5), 4, 10)
	local bolt = jagged(from, to, segments, 0.9, 0.35)
	local fork = math.random(2, math.max(2, segments - 2))
	local out = (to - from).Unit:Cross(Vector3.yAxis)
	if out.Magnitude < 0.1 then
		out = Vector3.xAxis
	end
	local start = bolt[fork].Position
	local side = if math.random() < 0.5 then -1 else 1
	for _, part in jagged(start, start:Lerp(to, 0.5) + out.Unit * side * length * 0.15, 3, 0.5, 0.18) do
		table.insert(bolt, part)
	end

	local ends = {}
	for i, at in { from, to } do
		local spot = holder(at, Vector3.new(1, 1, 1))
		local light = Instance.new("PointLight")
		light.Color = BOLT
		light.Range = if i == 1 then 10 else 16
		light.Brightness = if i == 1 then 2 else 4
		light.Parent = spot
		TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
		if i == 2 then
			sparks(spot, NumberRange.new(10, 26), 0.45):Emit(30)
		end
		table.insert(ends, spot)
	end

	task.spawn(function()
		-- It flickers off and on once, then fades.
		task.wait(0.06)
		for _, part in bolt do
			part.Transparency = 0.7
		end
		task.wait(0.04)
		for _, part in bolt do
			part.Transparency = 0
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
		task.wait(0.35)
		for _, part in bolt do
			part:Destroy()
		end
		task.wait(0.5)
		for _, spot in ends do
			spot:Destroy()
		end
	end)
end

-- The trail of a dash from `from` to `to` (on the ground) over `duration` seconds: crackling bolts along the way as he
-- passes, sparks thrown off them, and a flash where he leaves and where he arrives.
function LightningEffects.dash(from: Vector3, to: Vector3, duration: number)
	local steps = 6
	local lift = Vector3.new(0, 1.4, 0)
	for i = 0, steps do
		local alpha = i / steps
		task.delay(duration * alpha, function()
			local at = from:Lerp(to, alpha) + lift
			local spot = holder(at, Vector3.new(1, 1, 1))
			local ends = i == 0 or i == steps
			sparks(spot, NumberRange.new(6, if ends then 20 else 12), 0.35):Emit(if ends then 30 else 12)
			if ends then
				local flash = Instance.new("PointLight")
				flash.Color = BOLT
				flash.Range = 16
				flash.Brightness = 3
				flash.Parent = spot
				TweenService:Create(flash, TweenInfo.new(0.35), { Brightness = 0 }):Play()
			end
			local bolt = {}
			if i > 0 then
				bolt = jagged(from:Lerp(to, (i - 1) / steps) + lift, at, 4, 0.9, 0.3)
			end
			task.wait(0.08)
			for _, part in bolt do
				TweenService:Create(part, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
			task.wait(0.9)
			spot:Destroy()
			for _, part in bolt do
				part:Destroy()
			end
		end)
	end
end

-- The strike on `ground`, reaching `radius` studs.
function LightningEffects.strike(ground: Vector3, radius: number)
	local top = ground + Vector3.new((math.random() * 2 - 1) * 6, SKY, (math.random() * 2 - 1) * 6)
	local bolt = jagged(top, ground, 12, 3.2, 0.9)
	-- Two forks from part way down, ending short of the ground.
	for _ = 1, 2 do
		local from = bolt[math.random(3, 7)].Position
		local angle = math.random() * math.pi * 2
		local to = from:Lerp(ground, 0.55) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.9
		for _, part in jagged(from, to, 5, 2, 0.4) do
			table.insert(bolt, part)
		end
	end
	-- It flickers off and on once and fades.
	task.spawn(function()
		task.wait(0.06)
		for _, part in bolt do
			part.Transparency = 0.8
		end
		task.wait(0.05)
		for _, part in bolt do
			part.Transparency = 0
			TweenService:Create(part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
		task.wait(0.4)
		for _, part in bolt do
			part:Destroy()
		end
	end)

	local centre = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius * 0.5, 0.5, radius * 0.5))
	local flash = Instance.new("PointLight")
	flash.Color = BOLT
	flash.Range = 50
	flash.Brightness = 5
	flash.Parent = centre
	TweenService:Create(flash, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	sparks(centre, NumberRange.new(18, 40), 0.6):Emit(70)

	local quick = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	for i, delay in { 0, 0.08 } do
		task.delay(delay, function()
			local size = radius * (if i == 1 then 2 else 2.8)
			local ring, label = decal(ground, Assets.IndicatorRing, if i == 1 then WHITE else BOLT, 0, 2)
			TweenService:Create(ring, quick, { Size = Vector3.new(size, 0.05, size) }):Play()
			TweenService:Create(label, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
			task.delay(0.6, function()
				ring:Destroy()
			end)
		end)
	end

	local scorch, scorchLabel = decal(ground, Assets.IndicatorDisc, SCORCH, 0.15, radius * 1.6)
	TweenService:Create(scorchLabel, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		ImageTransparency = 1,
	}):Play()
	local glow, glowLabel = decal(ground + Vector3.new(0, 0.02, 0), Assets.IndicatorDisc, DEEP, 0.2, radius * 1.2)
	TweenService:Create(glowLabel, TweenInfo.new(1), { ImageTransparency = 1 }):Play()

	task.delay(2.6, function()
		centre:Destroy()
		scorch:Destroy()
		glow:Destroy()
	end)
end

-- How far from the camera a hero still crackles, and how far apart the parts a bolt leaps between may be. He crackles
-- only now and then, a hint of it (owner, 2026-10-31): for CRACKLE_BURST seconds a bolt or two every CRACKLE_STEP,
-- then still for CRACKLE_PAUSE.
local CRACKLE_SEEN = 150
local CRACKLE_LEAP = 3
local CRACKLE_BURST = NumberRange.new(0.1, 0.2)
local CRACKLE_STEP = 0.06
local CRACKLE_BOLTS = NumberRange.new(2, 3)
local CRACKLE_PAUSE = NumberRange.new(0.6, 1.1)
local CRACKLE_LIFT = 0.15
local CRACKLE_RUN = 2

local surfaceRay = RaycastParams.new()
surfaceRay.FilterType = Enum.RaycastFilterType.Include

-- A point on the outside of `character` over `part`, seen from `direction` (a unit vector out of its centre), lifted
-- a little off it: on his armour and clothes rather than the body hidden under them. A model rays cannot find (the
-- podium's, without CanQuery) gets the point on `part`'s box instead.
local function surface(character: Model, part: BasePart, direction: Vector3): Vector3?
	surfaceRay.FilterDescendantsInstances = { character }
	local from = part.Position + direction * (part.Size.Magnitude + 4)
	local found = Workspace:Raycast(from, part.Position - from, surfaceRay)
	if found then
		return found.Position + found.Normal * CRACKLE_LIFT
	end
	if part.CanQuery then
		return nil
	end
	local inside = part.CFrame:VectorToObjectSpace(direction)
	local reach = math.huge
	for _, axis in { "X", "Y", "Z" } do
		local d = math.abs((inside :: any)[axis])
		if d > 1e-3 then
			reach = math.min(reach, (part.Size :: any)[axis] / 2 / d)
		end
	end
	return part.Position + direction * (reach + CRACKLE_LIFT)
end

local function around(): Vector3
	return Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1).Unit
end

-- One bolt leaping over the hero whose root part is `root`, from `part` to `other` (or over `part` alone): between a
-- point on the outside of each, facing away from him, its middle arched out off him, in lines of light held to
-- `part` with a little golden glow, flickering once and gone.
local function crackleBolt(character: Model, root: BasePart, part: BasePart, other: BasePart)
	local axis = Vector3.new(root.Position.X, 0, root.Position.Z)
	local function outward(at: Vector3): Vector3
		local flat = Vector3.new(at.X, 0, at.Z) - axis
		return if flat.Magnitude > 0.05 then flat.Unit else around()
	end
	local a, b = surface(character, part, (outward(part.Position) + around() * 0.8).Unit), nil
	if other ~= part then
		b = surface(character, other, (outward(other.Position) + around() * 0.8).Unit)
	else
		b = surface(character, part, (outward(part.Position) + around()).Unit)
	end
	if not a or not b or (a - b).Magnitude < 0.5 then
		return
	end
	local points = { a }
	local segments = math.clamp(math.floor((a - b).Magnitude / 0.6), 3, 6)
	for i = 1, segments - 1 do
		local at = a:Lerp(b, i / segments)
		local arch = math.sin(math.pi * i / segments)
		table.insert(points, at + outward(at) * (0.25 + math.random() * 0.45) * arch + around() * 0.18)
	end
	table.insert(points, b)
	local lines = {}
	for i = 2, #points do
		local from, to = points[i - 1], points[i]
		local line = Instance.new("Part")
		line.Anchored = false
		line.Massless = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		line.Material = Enum.Material.Neon
		line.Color = BOLT
		line.Size = Vector3.new(0.13, 0.13, (to - from).Magnitude)
		line.CFrame = CFrame.lookAt((from + to) / 2, to)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = line
		weld.Parent = line
		line.Parent = effects()
		table.insert(lines, line)
	end
	local glow = Instance.new("PointLight")
	glow.Color = BOLT
	glow.Range = 6
	glow.Brightness = 2.5
	glow.Parent = lines[math.ceil(#lines / 2)]
	task.spawn(function()
		task.wait(0.06)
		for _, line in lines do
			line.Transparency = 0.75
		end
		task.wait(0.03)
		for _, line in lines do
			line.Transparency = 0
		end
		task.wait(0.06)
		for _, line in lines do
			TweenService:Create(line, TweenInfo.new(0.08), { Transparency = 1 }):Play()
		end
		TweenService:Create(glow, TweenInfo.new(0.08), { Brightness = 0 }):Play()
		task.wait(0.1)
		for _, line in lines do
			line:Destroy()
		end
	end)
end

-- What of `character` can crackle: every part of him that shows, his clothes and weapons too, but not what stands
-- loose by him (the podium's glow under his feet).
local function shown(character: Model): { BasePart }
	local parts = {}
	for _, part in character:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.Transparency < 0.9
			and part.Name ~= "HumanoidRootPart"
			and not part.Anchored
		then
			table.insert(parts, part)
		end
	end
	return parts
end

-- Lets small bolts crackle all over `character` while he lives, when his hero's look has Crackle and he is near: a
-- hero in the fight, or on the menu's podium (Lobby.Showcase).
function LightningEffects.crackle(character: Instance)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	if not character:IsA("Model") or not settings or not (settings.Look and settings.Look.Crackle) then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local function alive(): boolean
			return root ~= nil and character.Parent ~= nil and (not humanoid or humanoid.Health > 0)
		end
		local bursts = 0
		while alive() do
			-- Two bursts, then one skipped (owner, 2026-10-31).
			bursts += 1
			if bursts % (CRACKLE_RUN + 1) == 0 then
				task.wait(CRACKLE_PAUSE.Min + math.random() * (CRACKLE_PAUSE.Max - CRACKLE_PAUSE.Min))
				continue
			end
			local camera = Workspace.CurrentCamera
			if root and camera and (camera.CFrame.Position - root.Position).Magnitude < CRACKLE_SEEN then
				local parts = shown(character)
				local ends = os.clock() + CRACKLE_BURST.Min + math.random() * (CRACKLE_BURST.Max - CRACKLE_BURST.Min)
				-- At least one step, however short the burst.
				local first = true
				while #parts > 0 and (first or os.clock() < ends) and alive() do
					first = false
					for _ = 1, math.random(CRACKLE_BOLTS.Min, CRACKLE_BOLTS.Max) do
						-- It leaps to another part near the first, or over the first alone.
						local part = parts[math.random(#parts)]
						local near = {}
						for _, candidate in parts do
							if (candidate.Position - part.Position).Magnitude <= CRACKLE_LEAP then
								table.insert(near, candidate)
							end
						end
						crackleBolt(character :: Model, root :: BasePart, part, near[math.random(#near)])
					end
					task.wait(CRACKLE_STEP)
				end
			end
			task.wait(CRACKLE_PAUSE.Min + math.random() * (CRACKLE_PAUSE.Max - CRACKLE_PAUSE.Min))
		end
	end)
end

-- Starts the crackling on every hero that is or comes into the fight.
function LightningEffects.start()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(LightningEffects.crackle)
	for _, character in CollectionService:GetTagged("Combatant") do
		LightningEffects.crackle(character)
	end
end

return LightningEffects
