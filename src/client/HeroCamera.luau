-- The camera over the hero's right shoulder (design 05): the mouse is held in the middle of the screen and turns the
-- camera, the hero faces where the camera looks, and the crosshair in the middle (design 09) marks what he aims at.
-- The scroll wheel zooms. HeroCamera.aim() gives the point under the crosshair, which every attack aims at.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local HeroKit = require(game:GetService("ReplicatedStorage").Shared.HeroKit)

local HeroCamera = {}

-- Degrees the camera turns per pixel the mouse moves.
local SENSITIVITY = 0.22
local PITCH_MIN, PITCH_MAX = -55, 35
local ZOOM_MIN, ZOOM_MAX = 7, 20
-- Where the camera looks from, relative to the root part: over the right shoulder, a little up.
local SHOULDER = Vector3.new(2.2, 1.5, 0)
-- How quickly the hero turns to where the camera looks (the share of the way per 1/60 s).
local TURN = 0.35
-- How far the crosshair reaches when it points at the sky.
local AIM_REACH = 80

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
	if not root or not humanoid then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = if enabled then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not enabled

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

	aimRay.FilterDescendantsInstances = { character, Workspace:FindFirstChild("Effects") :: Instance }
	local centre = camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(centre.X, centre.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 400, aimRay)
	if result then
		aimPoint = result.Position
		aimInstance = result.Instance
	else
		aimPoint = ray.Origin + ray.Direction * AIM_REACH
		aimInstance = nil
	end
end

function HeroCamera.start()
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and enabled then
			yaw -= input.Delta.X * SENSITIVITY
			pitch = math.clamp(pitch - input.Delta.Y * SENSITIVITY, PITCH_MIN, PITCH_MAX)
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
