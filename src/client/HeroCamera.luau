-- The camera over the hero's right shoulder (design 05): the mouse is held in the middle of the screen and turns the
-- camera, the hero faces where the camera looks, and the crosshair in the middle (design 09) marks what he aims at.
-- The scroll wheel zooms. HeroCamera.aim() is the point under the crosshair (far along the look at the sky), up and
-- down too, which every attack aims at (owner, 2026-10-29): a shot or swing hits what the crosshair is on.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local HeroKit = require(game:GetService("ReplicatedStorage").Shared.HeroKit)
local Preferences = require(script.Parent.Preferences)

local HeroCamera = {}

-- Degrees the camera turns per pixel the mouse moves, at the usual speed (the player's own: Preferences.sensitivity).
local SENSITIVITY = 0.22
local PITCH_MIN, PITCH_MAX = -55, 35
local ZOOM_MIN, ZOOM_MAX = 7, 20
-- Where the camera looks from, relative to the root part: over the right shoulder, a little up.
local SHOULDER = Vector3.new(2.2, 1.5, 0)
-- How quickly the hero turns to where the camera looks (the share of the way per 1/60 s).
local TURN = 0.35
-- How far along the look the aim point sits when the crosshair points at the sky: past every kit's range.
local AIM_ALONG = 200

local player = Players.LocalPlayer
local yaw, pitch, zoom = 0, -12, 12
local aimPoint = Vector3.zero
local aimInstance: Instance? = nil
local enabled = true
local shakeStrength, shakeTime, shakeLeft = 0, 0, 0

local camRay = RaycastParams.new()
camRay.FilterType = Enum.RaycastFilterType.Exclude
local aimRay = RaycastParams.new()
aimRay.FilterType = Enum.RaycastFilterType.Exclude

-- What the crosshair looks through: the hero himself, the effects, and everyone on his team (heroes, bots, minions and
-- his Master), as every shot flies through them (owner, 2026-11-02), so it finds the enemy behind one.
local function aimIgnore(character: Model): { Instance }
	local ignore: { Instance } = { character }
	local effects = Workspace:FindFirstChild("Effects")
	if effects then
		table.insert(ignore, effects)
	end
	local team = character:GetAttribute("Team")
	if not team then
		return ignore
	end
	local function add(instance: Instance)
		if instance ~= character and instance:GetAttribute("Team") == team then
			table.insert(ignore, instance)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			add(other.Character)
		end
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		add(model)
	end
	for _, name in { "Minions", "MinionViews", "Masters" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			for _, child in folder:GetChildren() do
				add(child)
			end
		end
	end
	return ignore
end

function HeroCamera.aim(): Vector3
	return aimPoint
end

-- The instance under the crosshair (a part of a character or a minion's view), if any.
function HeroCamera.target(): Instance?
	return aimInstance
end

function HeroCamera.yaw(): number
	return yaw
end

-- Shakes the camera for `duration` seconds, `strength` studs at first and fading out.
function HeroCamera.shake(strength: number, duration: number)
	shakeStrength, shakeTime, shakeLeft = strength, duration, duration
end

-- Lets the mouse go (a menu is open) or takes it back.
function HeroCamera.setEnabled(on: boolean)
	enabled = on
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- Held only by a hero with no menu open: without one (the draft, the end of a match) the mouse is free.
	UserInputService.MouseBehavior = if enabled
			and root
			and humanoid
		then Enum.MouseBehavior.LockCenter
		else Enum.MouseBehavior.Default
	if not root or not humanoid then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	local focus = root.Position
		+ rotation:VectorToWorldSpace(Vector3.new(SHOULDER.X, 0, 0))
		+ Vector3.new(0, SHOULDER.Y, 0)
	local back = rotation.LookVector * -zoom
	local exclude = HeroKit.leapIgnore()
	camRay.FilterDescendantsInstances = exclude
	local hit = Workspace:Spherecast(focus, 0.6, back, camRay)
	local distance = if hit then math.max(1.5, hit.Distance - 0.2) else zoom
	local shake = Vector3.zero
	if shakeLeft > 0 then
		shakeLeft = math.max(0, shakeLeft - dt)
		local amount = shakeStrength * (shakeLeft / shakeTime) ^ 2
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
	end
	camera.CFrame = CFrame.new(focus + rotation.LookVector * -distance + shake) * rotation
	camera.Focus = CFrame.new(focus)

	if humanoid.Health > 0 and not humanoid.Sit then
		humanoid.AutoRotate = false
		local _, current, _ = root.CFrame:ToEulerAnglesYXZ()
		local goal = math.rad(yaw)
		local delta = (goal - current + math.pi) % (2 * math.pi) - math.pi
		local turned = current + delta * (1 - (1 - TURN) ^ (dt * 60))
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, turned, 0)
	end

	aimRay.FilterDescendantsInstances = aimIgnore(character)
	local centre = camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(centre.X, centre.Y)
	-- The ray starts level with the hero, so nothing between the camera and him (a banner, a pillar's edge) is aimed at.
	local start = math.max(0, (HeroKit.muzzle(root.Position) - ray.Origin):Dot(ray.Direction))
	local from = ray.Origin + ray.Direction * start
	local result = Workspace:Raycast(from, ray.Direction * 400, aimRay)
	aimInstance = if result then result.Instance else nil
	-- The point under the crosshair, else one far along the camera's line: the hero stands left of that line, so
	-- aiming along the look from him would fly past what the crosshair is on.
	aimPoint = if result then result.Position else from + ray.Direction * AIM_ALONG
end

function HeroCamera.start()
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and enabled then
			local speed = SENSITIVITY * Preferences.sensitivity()
			yaw -= input.Delta.X * speed
			pitch = math.clamp(pitch - input.Delta.Y * speed, PITCH_MIN, PITCH_MAX)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom - input.Position.Z * 1.5, ZOOM_MIN, ZOOM_MAX)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart") :: BasePart
		local _, y, _ = root.CFrame:ToEulerAnglesYXZ()
		yaw = math.deg(y)
	end)
	RunService:BindToRenderStep("HeroCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return HeroCamera
