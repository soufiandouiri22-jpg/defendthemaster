-- The Rune Gates' light (Config.RuneGates, RuneGateService). Over each gate a ring of gold runes turns slowly with a
-- soft light; while a hero stands on it to go through (its "ChannelAt") a column of gold light rises out of it and
-- the light grows. A jump (Net.RuneGateJump) makes both gates flare, sounding at both; the player who goes through
-- sees a gold flash over his screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local UiSound = require(script.Parent.UiSound)

local RuneGateView = {}

local SETTINGS = Config.RuneGates
local GOLD = Color3.fromRGB(255, 206, 96)
-- Seconds a full turn of the runes takes; the light at rest, how far its breath swings, and what a flare adds.
local RUNES_TURN = 30
local LIGHT_REST, LIGHT_SWING, LIGHT_FLARE = 0.4, 0.1, 2.5
-- How long a flare lasts, and how tall the column stands once a hero has stood his whole Channel.
local FLARE, COLUMN = 0.8, 9

type Gate = {
	model: Model,
	at: Vector3,
	runes: ImageLabel,
	light: PointLight,
	column: Part,
	flared: number,
}

local gates: { [string]: Gate } = {}
local effects: Folder

local function part(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	return p
end

local function dress(model: Model)
	local name = model:GetAttribute("Gate")
	if type(name) ~= "string" then
		return
	end
	local _, size = model:GetBoundingBox()
	local at = model:GetPivot().Position + Vector3.new(0, size.Y + 0.04, 0)
	local width = SETTINGS.Width * 0.9
	local plate = part("RuneGateRunes", Vector3.new(width, 0.05, width), CFrame.new(at))
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = 1.5
	surface.CanvasSize = Vector2.new(512, 512)
	surface.Parent = plate
	local runes = Instance.new("ImageLabel")
	runes.BackgroundTransparency = 1
	runes.Size = UDim2.fromScale(1, 1)
	runes.Image = Assets.PadRunes
	runes.ImageColor3 = GOLD
	runes.ImageTransparency = 0.45
	runes.Parent = surface
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 12
	light.Brightness = LIGHT_REST
	light.Shadows = false
	light.Parent = plate
	plate.Parent = effects
	local column = part("RuneGateColumn", Vector3.new(0.1, SETTINGS.Middle * 2, SETTINGS.Middle * 2), CFrame.new(at))
	column.Shape = Enum.PartType.Cylinder
	column.Material = Enum.Material.Neon
	column.Color = GOLD
	column.Parent = effects
	gates[name] = { model = model, at = at, runes = runes, light = light, column = column, flared = -math.huge }
end

local function flash()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RuneGateFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BorderSizePixel = 0
	cover.BackgroundColor3 = GOLD
	cover.BackgroundTransparency = 0.35
	cover.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	TweenService:Create(cover, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.6, function()
		gui:Destroy()
	end)
end

local function jumped(from: string, to: string, character: Model?)
	for _, name in { from, to } do
		local gate = gates[name]
		if gate then
			gate.flared = os.clock()
			UiSound.at("RuneGate", gate.at)
		end
	end
	if character and character == Players.LocalPlayer.Character then
		flash()
	end
end

local function update(dt: number)
	local clock = os.clock()
	local now = Workspace:GetServerTimeNow()
	for _, gate in gates do
		gate.runes.Rotation = (gate.runes.Rotation + 360 / RUNES_TURN * dt) % 360
		local since = gate.model:GetAttribute("ChannelAt")
		local filling = if type(since) == "number" then math.clamp((now - since) / SETTINGS.Channel, 0, 1) else 0
		local flaring = math.clamp(1 - (clock - gate.flared) / FLARE, 0, 1)
		local height = COLUMN * math.max(filling, flaring)
		if height > 0.05 then
			gate.column.Size = Vector3.new(height, SETTINGS.Middle * 2, SETTINGS.Middle * 2)
			gate.column.CFrame = CFrame.new(gate.at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			gate.column.Transparency = 1 - 0.55 * math.max(filling, flaring)
		else
			gate.column.Transparency = 1
		end
		gate.runes.ImageTransparency = 0.45 - 0.35 * math.max(filling, flaring)
		gate.light.Brightness = LIGHT_REST
			+ math.sin(clock * 2) * LIGHT_SWING
			+ filling * LIGHT_FLARE * 0.5
			+ flaring * LIGHT_FLARE
	end
end

function RuneGateView.start()
	if not SETTINGS.Enabled then
		return
	end
	local map = Workspace:WaitForChild("Map", 30)
	local features = map and map:WaitForChild("Features", 30)
	local folder = features and features:WaitForChild("RuneGates", 10)
	if not folder then
		return
	end
	effects = Instance.new("Folder")
	effects.Name = "RuneGateEffects"
	effects.Parent = Workspace
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			dress(model)
		end
	end
	local jump = ReplicatedStorage:WaitForChild("Net"):WaitForChild("RuneGateJump") :: RemoteEvent
	jump.OnClientEvent:Connect(jumped)
	RunService.RenderStepped:Connect(update)
end

return RuneGateView
