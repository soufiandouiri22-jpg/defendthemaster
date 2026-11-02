-- The boost in play on screen (Shared.Boosts): its model (ReplicatedStorage[boost.Model], from Meshy, pivot at its
-- middle) turns and bobs where it floats, on the plateau or where its carrier fell, with the Sun Crown's warm light for
-- every boost (owner, 2026-11-02) and a faint glow rising to it from the floor. While a hero carries it, a smaller one
-- (its `Worn` share) turns the same way over his head. A boost whose model is not in ReplicatedStorage yet floats as a
-- glowing ball in its colour.
-- Its fall makes no sound: the crown's clang sounded like a cartoon against the death's boom (owner, 2026-10-30).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local BoostView = {}

local GOLD = Color3.fromRGB(255, 196, 64)
-- It turns this many degrees a second and bobs this many studs.
local TURN, BOB = 60, 0.35
-- Over a carrier's head, its foot this many studs over the top of his head.
local OVER = 1.2
-- The stand-in ball's size.
local BALL = 2.6

local function prepare(model: Model, range: number, brightness: number)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		end
	end
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function ball(colour: Color3): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(BALL, BALL, BALL)
	part.Material = Enum.Material.Neon
	part.Color = colour
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function source(boost: Boosts.Boost): Model
	local model = ReplicatedStorage:FindFirstChild(boost.Model)
	return if model and model:IsA("Model") then model:Clone() else ball(boost.Color)
end

-- The floating and the worn model of `boost`.
local function models(boost: Boosts.Boost): (Model, Model)
	local base = source(boost)
	local floating = base:Clone()
	prepare(floating, 16, 2)
	local worn = base
	worn:ScaleTo(worn:GetScale() * boost.Worn)
	prepare(worn, 8, 1)
	return floating, worn
end

local heights: { [string]: number } = {}

-- How high `boost` stands over its carrier's head, from the top of his head to its own top (HeroBars lifts his bar
-- over it).
function BoostView.wornTop(boost: Boosts.Boost): number
	local height = heights[boost.Model]
	if not height then
		local model = source(boost)
		height = model:GetExtentsSize().Y * boost.Worn
		model:Destroy()
		heights[boost.Model] = height
	end
	return OVER + height :: number
end

-- The glow under the floating boost: a light on the floor shining up at it and a faint column of light that fades
-- out on its way up.
local function glow(): (BasePart, Attachment)
	local base = Instance.new("Part")
	base.Name = "BoostGlow"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Transparency = 1
	base.Size = Vector3.new(1, 1, 1)
	local bottom = Instance.new("Attachment")
	bottom.Parent = base
	local top = Instance.new("Attachment")
	top.Parent = base
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Top
	spot.Color = GOLD
	spot.Angle = 50
	spot.Range = Config.Boosts.Float + 6
	spot.Brightness = 1.5
	spot.Shadows = false
	spot.Parent = base
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.Width0 = 4
	beam.Width1 = 1.5
	beam.Color = ColorSequence.new(GOLD)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Segments = 4
	beam.Parent = base
	return base, top
end

local function carrier(): Model?
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Boost") == true and model:FindFirstChild("Head") then
			return model
		end
	end
	return nil
end

function BoostView.start()
	-- The boosts' models live in the place, not in the project: the first may still be on its way.
	ReplicatedStorage:WaitForChild(Config.Boosts.List[Config.Boosts.First].Model, 30)
	local base, top = glow()
	local folder = Instance.new("Folder")
	folder.Name = "BoostEffects"
	folder.Parent = Workspace
	local angle = 0
	local shownKind: string? = nil
	local floating: Model? = nil
	local worn: Model? = nil
	local wornHalf, wornBob = 0, 0

	RunService.RenderStepped:Connect(function(dt)
		local boost, kind = Boosts.current()
		if kind ~= shownKind then
			shownKind = kind
			if floating then
				floating:Destroy()
			end
			if worn then
				worn:Destroy()
			end
			floating, worn = nil, nil
			if boost then
				floating, worn = models(boost)
				wornHalf = (worn :: Model):GetExtentsSize().Y / 2
				wornBob = boost.Worn
			end
		end
		angle = (angle + TURN * dt) % 360
		local turn = CFrame.Angles(0, math.rad(angle), 0)
		local bob = math.sin(os.clock() * 2)
		local state = Workspace:GetAttribute("Boost")
		local at = Workspace:GetAttribute("BoostSpot")
		local shown = floating ~= nil and (state == "Ready" or state == "Dropped") and typeof(at) == "Vector3"
		base.Parent = if shown then folder else nil
		if floating then
			floating.Parent = if shown then folder else nil
			if shown then
				floating:PivotTo(CFrame.new(at + Vector3.new(0, bob * BOB, 0)) * turn)
				base.CFrame = CFrame.new(at - Vector3.new(0, Config.Boosts.Float - 0.1, 0))
				top.WorldPosition = at + Vector3.new(0, 2, 0)
			end
		end
		local wearer = if state == "Carried" then carrier() else nil
		if worn then
			worn.Parent = if wearer then folder else nil
			if wearer then
				local head = wearer:FindFirstChild("Head") :: BasePart
				local over = head.Position + Vector3.new(0, head.Size.Y / 2 + OVER + wornHalf + bob * BOB * wornBob, 0)
				worn:PivotTo(CFrame.new(over) * turn)
			end
		end
	end)
end

return BoostView
