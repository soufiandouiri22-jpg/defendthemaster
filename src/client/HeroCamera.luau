-- The camera over the hero's right shoulder (design 05): the mouse is held in the middle of the screen and turns the
-- camera, the hero faces where the camera looks, and the crosshair in the middle (design 09) marks what he aims at.
-- The scroll wheel zooms; through a sniper's scope (HeroCamera.scope) it looks from his eyes, zoomed in. HeroCamera.aim() is the point under the crosshair (far along the look at the sky), up and
-- down too, which every attack aims at (owner, 2026-10-29): a shot or swing hits what the crosshair is on. While his
-- hero is dead it follows his killer until he is back (watch), the mouse still turning it; once the one it follows falls
-- too, a living enemy hero picked at random (owner, 2026-11-03).

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
local AIM_REACH = 400
-- Through a sniper's scope (HeroCamera.scope): the camera at his eyes, this high above the root part, easing in and
-- out over SCOPE_EASE seconds; the crosshair sees across the whole arena; the view sways a little, by SWAY degrees.
local EYE = 1.6
local SCOPE_EASE = 0.22
local SCOPE_REACH = 1200
local SWAY = 0.12
local NORMAL_FOV = 70

local player = Players.LocalPlayer
local yaw, pitch, zoom = 0, -12, 12
local aimPoint = Vector3.zero
local aimInstance: Instance? = nil
local enabled = true
local shakeStrength, shakeTime, shakeLeft = 0, 0, 0
-- How far the camera has moved from where it was to the one it follows now (0 to 1), over FOLLOW_EASE seconds.
local following = 0
local FOLLOW_EASE = 0.6
-- Whom the camera follows while his hero is dead, where it came from to him, and the point it was round last frame.
local watched: Model? = nil
local watchFrom = Vector3.zero
local lastAround: Vector3? = nil
-- The scope's field of view while he looks through it, how far in it the camera is (0 to 1), and whether his own
-- hero is hidden for it.
local scopeFov: number? = nil
local zoomFov = NORMAL_FOV
local scoping = 0
local hidden = false

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

-- Looks through a sniper's scope zoomed to `fov` degrees, or (nil) back over the shoulder.
function HeroCamera.scope(fov: number?)
	scopeFov = fov
end

-- How far the camera is into the scope: 0 over the shoulder, 1 through it.
function HeroCamera.scoping(): number
	return scoping
end

-- Lets the mouse go (a menu is open) or takes it back.
function HeroCamera.setEnabled(on: boolean)
	enabled = on
end

-- Whether the camera has the mouse (no menu open).
function HeroCamera.isEnabled(): boolean
	return enabled
end

local function rootOf(model: Model): BasePart?
	local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if part and part:IsA("BasePart") then part else nil
end

-- Whether `model` is in the world, standing (a Master without a Humanoid always is) and has a root part.
local function standing(model: Instance?): boolean
	if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) or not rootOf(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health > 0
end

-- The enemy heroes of `character` standing, players' and bots'.
local function enemies(character: Model): { Model }
	local team = character:GetAttribute("Team")
	local found: { Model } = {}
	local seen: { [Model]: boolean } = {}
	local function add(model: Instance?)
		if
			model
			and model:IsA("Model")
			and not seen[model]
			and model:GetAttribute("Hero") ~= nil
			and model:GetAttribute("Team") ~= nil
			and model:GetAttribute("Team") ~= team
			and standing(model)
		then
			seen[model] = true
			table.insert(found, model)
		end
	end
	for _, other in Players:GetPlayers() do
		add(other.Character)
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		add(model)
	end
	return found
end

-- Dead, the camera follows whoever killed him (the "Killer" his body carries, ProgressService.heroDied: the enemy hero
-- or the Master) until he is back; when that one falls or is gone, a standing enemy hero at random, and so on. Without
-- a killer, or with no enemy standing, it stays on his own body.
local function watch(character: Model): Model?
	if standing(watched) then
		return watched
	end
	local value = character:FindFirstChild("Killer")
	local killer = if value and value:IsA("ObjectValue") then value.Value else nil
	if not killer then
		return nil
	end
	if standing(killer) then
		return killer :: Model
	end
	local options = enemies(character)
	return if #options > 0 then options[math.random(#options)] else nil
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

	local target = if humanoid.Health <= 0 then watch(character) else nil
	if target ~= watched then
		watched = target
		watchFrom = lastAround or root.Position
		following = 0
	end
	local followed = if watched then rootOf(watched) else nil
	following = if followed then math.min(1, following + dt / FOLLOW_EASE) else 0
	local around = root.Position
	if followed then
		around = watchFrom:Lerp(followed.Position, following * following * (3 - 2 * following))
	end
	lastAround = around
	local inScope = if scopeFov and humanoid.Health > 0 then 1 else 0
	local was = scoping
	scoping = if inScope > scoping
		then math.min(inScope, scoping + dt / SCOPE_EASE)
		else math.max(inScope, scoping - dt / SCOPE_EASE)
	local ease = scoping * scoping * (3 - 2 * scoping)
	if scopeFov then
		zoomFov = scopeFov
	end
	if scoping > 0 or was > 0 then
		camera.FieldOfView = NORMAL_FOV + (zoomFov - NORMAL_FOV) * ease
	end
	if (ease > 0.5) ~= hidden then
		hidden = ease > 0.5
		for _, part in (character :: Model):GetDescendants() do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
	local clock = os.clock()
	local swayYaw = ease * SWAY * math.sin(clock * 1.3)
	local swayPitch = ease * SWAY * math.sin(clock * 1.9 + 1)
	local rotation = CFrame.Angles(0, math.rad(yaw + swayYaw), 0) * CFrame.Angles(math.rad(pitch + swayPitch), 0, 0)
	local focus = around + rotation:VectorToWorldSpace(Vector3.new(SHOULDER.X, 0, 0)) + Vector3.new(0, SHOULDER.Y, 0)
	local back = rotation.LookVector * -zoom
	local exclude = HeroKit.leapIgnore()
	if followed then
		exclude = table.clone(exclude)
		table.insert(exclude, followed.Parent :: Instance)
	end
	camRay.FilterDescendantsInstances = exclude
	local hit = Workspace:Spherecast(focus, 0.6, back, camRay)
	local distance = if hit then math.max(1.5, hit.Distance - 0.2) else zoom
	local shake = Vector3.zero
	if shakeLeft > 0 then
		shakeLeft = math.max(0, shakeLeft - dt)
		local amount = shakeStrength * (shakeLeft / shakeTime) ^ 2
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
	end
	local shoulder = CFrame.new(focus + rotation.LookVector * -distance + shake) * rotation
	local eyes = CFrame.new(around + Vector3.new(0, EYE, 0) + shake) * rotation
	camera.CFrame = if ease > 0 then shoulder:Lerp(eyes, ease) else shoulder
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
	local scoped = scoping > 0.5
	local result = Workspace:Raycast(from, ray.Direction * (if scoped then SCOPE_REACH else AIM_REACH), aimRay)
	aimInstance = if result then result.Instance else nil
	-- The point under the crosshair, else one far along the camera's line: the hero stands left of that line, so
	-- aiming along the look from him would fly past what the crosshair is on.
	aimPoint = if result then result.Position else from + ray.Direction * (if scoped then SCOPE_REACH else AIM_ALONG)
end

function HeroCamera.start()
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and enabled then
			-- Through a scope the mouse turns the view as much less as it is zoomed.
			local zoomed = if scoping > 0 then Workspace.CurrentCamera.FieldOfView / NORMAL_FOV else 1
			local speed = SENSITIVITY * Preferences.sensitivity() * zoomed
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
