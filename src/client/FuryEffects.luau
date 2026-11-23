-- A hero in a Fury (his "Fury" attribute, from a kit of Kind "Fury" on the server) burns in an aura of that kit's
-- `Color` as long as it lasts, like a super saiyan's: flames licking up all round his body, a fainter blaze round them,
-- sparks rising, a glow over him and a light, flaring up at once as it starts. It stands beside him, not in him, as
-- what is put in a hero makes Roblox fit his layered clothing again; it follows his root part every frame.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local FuryEffects = {}

local FLAME = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local RED = Color3.fromRGB(235, 40, 30)
-- The space the flames rise from round him (a cylinder about his body), from a little below his root part's centre.
local BODY, BELOW = Vector3.new(4.4, 5.8, 3.4), 0.4
-- How long the last flames take to die away after the fury ends.
local FADE = 0.8

type Aura = { shell: BasePart, highlight: Highlight, emitters: { ParticleEmitter } }

local auras: { [Model]: Aura } = {}
local folder: Folder? = nil

local function colourOf(model: Model): Color3
	local settings = Config.Heroes[model:GetAttribute("Hero") or ""]
	for _, kit in if settings then settings.Kit else {} do
		if kit.Kind == "Fury" and kit.Color then
			return kit.Color
		end
	end
	return RED
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LockedToPart = true
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.EmissionDirection = Enum.NormalId.Top
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function build(model: Model): Aura
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "FuryAuras"
		f.Parent = Workspace
		folder = f
	end
	local colour = colourOf(model)
	local shell = Instance.new("Part")
	shell.Name = model.Name
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Transparency = 1
	shell.Size = BODY
	shell.Parent = folder

	local flames = emitter(shell, {
		Name = "Flames",
		Texture = FLAME,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colour:Lerp(WHITE, 0.55)),
			ColorSequenceKeypoint.new(0.35, colour),
			ColorSequenceKeypoint.new(1, colour:Lerp(BLACK, 0.45)),
		}),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(0.4, 1.7),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.35, 0.6),
		Rate = 140,
		Speed = NumberRange.new(1, 2.5),
		Acceleration = Vector3.new(0, 16, 0),
		RotSpeed = NumberRange.new(-120, 120),
		Rotation = NumberRange.new(0, 360),
	})
	local blaze = emitter(shell, {
		Name = "Blaze",
		Texture = FLAME,
		Color = ColorSequence.new(colour, colour:Lerp(BLACK, 0.3)),
		LightEmission = 0.8,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.2),
			NumberSequenceKeypoint.new(0.5, 3),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.5, 0.8),
		Rate = 40,
		Speed = NumberRange.new(2, 3.5),
		Acceleration = Vector3.new(0, 10, 0),
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
	})
	local sparks = emitter(shell, {
		Name = "Sparks",
		Texture = SPARK,
		Color = ColorSequence.new(colour:Lerp(WHITE, 0.6), colour),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 30,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, 6, 0),
	})

	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = 3
	light.Range = 14
	light.Parent = shell

	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = colour
	highlight.FillTransparency = 0.78
	highlight.OutlineColor = colour:Lerp(WHITE, 0.3)
	highlight.OutlineTransparency = 0.25
	highlight.Parent = folder

	flames:Emit(60)
	blaze:Emit(20)
	sparks:Emit(30)
	return { shell = shell, highlight = highlight, emitters = { flames, blaze, sparks } }
end

-- The aura dies away: its flames stop and those already up burn out.
local function drop(aura: Aura)
	for _, e in aura.emitters do
		e.Enabled = false
	end
	aura.highlight:Destroy()
	local light = aura.shell:FindFirstChildOfClass("PointLight")
	if light then
		light:Destroy()
	end
	task.delay(FADE, function()
		aura.shell:Destroy()
	end)
end

local function burning(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return model.Parent ~= nil
		and model:GetAttribute("Fury") == true
		and humanoid ~= nil
		and humanoid.Health > 0
		and model:FindFirstChild("HumanoidRootPart") ~= nil
end

function FuryEffects.start()
	RunService.RenderStepped:Connect(function()
		for model, aura in auras do
			if not burning(model) then
				drop(aura)
				auras[model] = nil
			end
		end
		for _, model in CollectionService:GetTagged("Combatant") do
			if model:IsA("Model") and not auras[model] and burning(model) then
				auras[model] = build(model)
			end
		end
		for model, aura in auras do
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
			aura.shell.CFrame = root.CFrame * CFrame.new(0, -BELOW, 0)
		end
	end)
end

return FuryEffects
