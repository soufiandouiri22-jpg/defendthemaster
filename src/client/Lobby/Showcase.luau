-- The hero on the hall's podium behind the menu (design 10): the player's showcase hero (Shared.Profile.showcase: his
-- favourite, else the hero he played last), a copy of the server's model (ReplicatedStorage.Showcase) in his showcase
-- pose (Config.Heroes[hero].Showcase.Motion, through Shared.Motion) with his aura round him: wisps of his colour
-- rising, embers, and a glow on the podium. The camera stands still where the hall says (the Workspace attribute
-- "MenuCamera"), breathing a little.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Motion = require(ReplicatedStorage.Shared.Motion)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)

local Showcase = {}

local DEFAULT_AURA = Color3.fromRGB(255, 196, 90)
-- The camera sways this many studs, this slowly.
local SWAY, SWAY_SPEED = 0.12, 0.35

local current: { hero: string, model: Model, motion: any? }? = nil
local wanted = ""

local function aura(model: Model, colour: Color3, at: CFrame)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Aura"
	attachment.Parent = root

	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "Wisps"
	wisps.Texture = "rbxasset://textures/particles/fire_main.dds"
	wisps.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.25), colour)
	wisps.LightEmission = 0.8
	wisps.LightInfluence = 0
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.Lifetime = NumberRange.new(0.9, 1.6)
	wisps.Rate = 26
	wisps.Speed = NumberRange.new(1.2, 2.4)
	wisps.SpreadAngle = Vector2.new(25, 25)
	wisps.Acceleration = Vector3.new(0, 2.2, 0)
	wisps.RotSpeed = NumberRange.new(-80, 80)
	wisps.Rotation = NumberRange.new(0, 360)
	wisps.Shape = Enum.ParticleEmitterShape.Cylinder
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	wisps.Parent = attachment

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 150, 60))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1.8, 3)
	embers.Rate = 14
	embers.Speed = NumberRange.new(0.6, 1.4)
	embers.SpreadAngle = Vector2.new(70, 70)
	embers.Acceleration = Vector3.new(0, 1.2, 0)
	embers.Parent = attachment

	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = 1.6
	light.Range = 11
	light.Parent = attachment

	-- A glow on the podium under him.
	local glow = Instance.new("Part")
	glow.Name = "AuraGlow"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Shape = Enum.PartType.Cylinder
	glow.Size = Vector3.new(0.05, 4.6, 4.6)
	glow.CFrame = at * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
	glow.Material = Enum.Material.Neon
	glow.Color = colour
	glow.Transparency = 0.82
	glow.Parent = model
end

-- Puts `hero` on the podium, or keeps him there when he already stands on it.
function Showcase.show(hero: string)
	wanted = hero
	if current and current.hero == hero then
		return
	end
	local folder = ReplicatedStorage:WaitForChild("Showcase", 30)
	local source = folder and folder:WaitForChild(hero, 30)
	if not source or wanted ~= hero or (current and current.hero == hero) then
		return
	end
	if current then
		current.model:Destroy()
		current = nil
	end
	local at = Workspace:GetAttribute("ShowcaseAt") :: CFrame
	local model = (source :: Model):Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root then
		-- Standing on the podium facing the camera (+Z).
		local height = humanoid.HipHeight + root.Size.Y / 2
		model:PivotTo(at * CFrame.new(0, height, 0) * CFrame.Angles(0, math.pi, 0))
	end
	model.Parent = Workspace
	local settings = Config.Heroes[hero]
	local showcase = settings.Showcase
	local motion = nil
	if settings.Pack then
		motion = Motion.new(model, settings.Pack)
		local idle = showcase and showcase.Motion or settings.Motions.Idle
		if idle then
			motion:setBase(idle, 1)
		end
	end
	aura(model, if showcase and showcase.Aura then showcase.Aura else DEFAULT_AURA, at)
	current = { hero = hero, model = model, motion = motion }
end

-- The hero standing on the podium, nil until the first one is there.
function Showcase.model(): Model?
	return if current then current.model else nil
end

function Showcase.start()
	local camera = Workspace.CurrentCamera
	while not Workspace:GetAttribute("MenuCamera") do
		Workspace:GetAttributeChangedSignal("MenuCamera"):Wait()
	end
	local base = Workspace:GetAttribute("MenuCamera") :: CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 40
	camera.CFrame = base
	RunService.RenderStepped:Connect(function(dt)
		camera.CameraType = Enum.CameraType.Scriptable
		local t = os.clock() * SWAY_SPEED
		camera.CFrame = base * CFrame.new(math.sin(t) * SWAY, math.sin(t * 1.3) * SWAY * 0.5, 0)
		local c = current
		if c and c.motion then
			c.motion:step(dt)
		end
	end)
	ProfileClient.watch(function(data)
		task.spawn(Showcase.show, Profile.showcase(data))
	end)
	if not ProfileClient.get() then
		task.spawn(Showcase.show, Config.DefaultHero)
	end
end

return Showcase
