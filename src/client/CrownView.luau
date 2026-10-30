-- The Sun Crown on screen (CrownService's attributes on Workspace): its model (ReplicatedStorage.SunCrown, from Meshy,
-- pivot at its middle) turns and bobs where it floats, on the plateau or where its carrier fell, with a warm light and
-- a faint glow rising to it from the floor. While a hero carries it, a smaller one turns the same way over his head.
-- Its fall makes no sound: its clang sounded like a cartoon against the death's boom (owner, 2026-10-30).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local CrownView = {}

local GOLD = Color3.fromRGB(255, 196, 64)
-- It turns this many degrees a second and bobs this many studs.
local TURN, BOB = 60, 0.35
-- Over a carrier's head: this share of its size, this many studs over the top of his head.
local WORN, OVER = 0.36, 1.5

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

-- The glow under the floating crown: a light on the floor shining up at it and a faint column of light that fades
-- out on its way up.
local function glow(): (BasePart, Attachment)
	local base = Instance.new("Part")
	base.Name = "CrownGlow"
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
	spot.Range = Config.Crown.Float + 6
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
		if model:IsA("Model") and model:GetAttribute("Crown") == true and model:FindFirstChild("Head") then
			return model
		end
	end
	return nil
end

function CrownView.start()
	local source = ReplicatedStorage:WaitForChild("SunCrown", 30)
	if not source or not source:IsA("Model") then
		warn("[CrownView] ReplicatedStorage.SunCrown is missing")
		return
	end
	local floating = source:Clone()
	prepare(floating, 16, 2)
	local worn = source:Clone()
	worn:ScaleTo(worn:GetScale() * WORN)
	prepare(worn, 8, 1)
	local base, top = glow()
	local folder = Instance.new("Folder")
	folder.Name = "CrownEffects"
	folder.Parent = Workspace
	local angle = 0

	RunService.RenderStepped:Connect(function(dt)
		angle = (angle + TURN * dt) % 360
		local turn = CFrame.Angles(0, math.rad(angle), 0)
		local bob = math.sin(os.clock() * 2)
		local state = Workspace:GetAttribute("Crown")
		local spot = Workspace:GetAttribute("CrownSpot")
		local shown = (state == "Ready" or state == "Dropped") and typeof(spot) == "Vector3"
		floating.Parent = if shown then folder else nil
		base.Parent = if shown then folder else nil
		if shown then
			floating:PivotTo(CFrame.new(spot + Vector3.new(0, bob * BOB, 0)) * turn)
			base.CFrame = CFrame.new(spot - Vector3.new(0, Config.Crown.Float - 0.1, 0))
			top.WorldPosition = spot + Vector3.new(0, 2, 0)
		end
		local wearer = if state == "Carried" then carrier() else nil
		worn.Parent = if wearer then folder else nil
		if wearer then
			local head = wearer:FindFirstChild("Head") :: BasePart
			local over = head.Position + Vector3.new(0, head.Size.Y / 2 + OVER + bob * BOB * WORN, 0)
			worn:PivotTo(CFrame.new(over) * turn)
		end
	end)
end

return CrownView
