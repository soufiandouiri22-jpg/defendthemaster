-- The player's attacks (Config.Heroes[hero].Kit, server: CombatService). Left mouse swings the combo (held, it keeps
-- swinging); right mouse, E and R are held to aim with their indicator on the ground (design 06) and cast when let go.
-- Everything aims at the crosshair (HeroCamera.aim). The client plays its own motion at once and asks the server
-- (Net.HeroAction), which decides the hits; a refused attack is undone. The leap moves the hero itself, from takeoff
-- to landing, to the spot the server works out the same way (HeroKit.leapLanding), and lands in a shockwave of shadow
-- (ShadowEffects), as does every other hero's leap. Other heroes' motions and every
-- thrown dagger come from the server. The crosshair (design 09) turns red on an enemy and blue on an ally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AbilityBar = require(script.Parent.AbilityBar)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroAnimator = require(script.Parent.HeroAnimator)
local HeroCamera = require(script.Parent.HeroCamera)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local HeroSounds = require(script.Parent.HeroSounds)
local Indicators = require(script.Parent.Indicators)
local ShadowEffects = require(script.Parent.ShadowEffects)

local HeroControls = {}

local RECOVER = 0.12
local KEY_OF: { [Enum.KeyCode | Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton2] = "M2",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.R] = "R",
}
local SHADOW = Color3.fromRGB(120, 60, 200)

local player = Players.LocalPlayer
local actionEvent: RemoteEvent
local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Exclude

type Leap = {
	started: number,
	from: Vector3,
	to: Vector3,
	takeoff: number,
	land: number,
	-- A dash starts fast and slows to a stop; a leap eases in and out.
	sharp: boolean,
}

local busyUntil = 0
local combo = 0
local comboUntil = 0
local cooldowns: { [string]: number } = {}
local motionToken = 0
local holdingM1 = false
local aiming: string? = nil
local indicator: Indicators.Indicator? = nil
local leap: Leap? = nil

type Flying = {
	dagger: BasePart,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	started: number,
}
local flying: { [number]: Flying } = {}

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function hero(): (Model?, BasePart?, Humanoid?, any)
	local character = player.Character
	if not character then
		return nil, nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local name = character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	if not root or not humanoid or humanoid.Health <= 0 or not settings then
		return nil, nil, nil, nil
	end
	return character, root, humanoid, settings
end

local function heightOf(root: BasePart, humanoid: Humanoid): number
	return humanoid.HipHeight + root.Size.Y / 2
end

local function slow(humanoid: Humanoid, length: number, speed: number)
	motionToken += 1
	local token = motionToken
	humanoid.WalkSpeed = speed
	task.delay(length, function()
		if motionToken == token and humanoid.Parent then
			humanoid.WalkSpeed = Config.Combat.WalkSpeed
		end
	end)
end

-- Shakes the camera when `at` is near the player's hero, harder the closer.
local function shakeNear(at: Vector3, strength: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local closeness = 1 - math.clamp((root.Position - at).Magnitude / 35, 0, 1)
		if closeness > 0 then
			HeroCamera.shake(strength * closeness, 0.35)
		end
	end
end

-- The sound of `character`'s hero striking the ground.
local function slamSound(character: Model)
	local settings = Config.Heroes[character:GetAttribute("Hero") or ""]
	if settings and settings.Pack then
		HeroSounds.event(character, settings.Pack, "Slam")
	end
end

-- The leap's shockwave at `landing` (where the root part comes down) when the hero lands.
local function landLater(character: Model, landing: Vector3, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	task.delay(kit.Land, function()
		if humanoid.Health > 0 then
			groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
			local below = Workspace:Raycast(landing, Vector3.new(0, -(height + 2), 0), groundRay)
			local ground = if below then below.Position else landing - Vector3.new(0, height, 0)
			ShadowEffects.shockwave(ground, kit.Radius)
			shakeNear(ground, 0.4)
			slamSound(character)
		end
	end)
end

-- The ultimate's slam where the hero stands when he comes down, `kit.Slam` seconds from now.
local function slamLater(character: Model, kit: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local height = heightOf(root, humanoid)
	task.delay(kit.Slam, function()
		if humanoid.Health <= 0 or not root.Parent then
			return
		end
		groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
		local below = Workspace:Raycast(root.Position, Vector3.new(0, -(height + 2), 0), groundRay)
		local ground = if below then below.Position else root.Position - Vector3.new(0, height, 0)
		ShadowEffects.slam(ground, kit.Range)
		shakeNear(ground, 0.9)
		slamSound(character)
	end)
end

-- The dash's lunge in place while the hero is carried from `from` to `to`, its trail, and the lunge cut off at its end.
local function dashMotion(character: Model, from: Vector3, to: Vector3, kit: any)
	HeroAnimator.play(character, kit.Motion, kit.Speed, nil, true)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local drop = if root and humanoid then Vector3.new(0, heightOf(root, humanoid), 0) else Vector3.zero
	task.delay(kit.Start, function()
		ShadowEffects.dash(from - drop, to - drop, kit.Move - kit.Start)
	end)
	task.delay(kit.Stop, function()
		if HeroAnimator.playing(character) == kit.Motion then
			HeroAnimator.stop(character)
		end
	end)
end

local function canAct(key: string, now: number): boolean
	return now >= busyUntil and now >= (cooldowns[key] or 0)
end

local function stopAiming()
	if indicator then
		Indicators.destroy(indicator)
		indicator = nil
	end
	if aiming then
		AbilityBar.aiming(aiming, false)
	end
	aiming = nil
end

local function cast(key: string)
	local character, root, humanoid, settings = hero()
	if not character or not root or not humanoid then
		return
	end
	local kit = settings.Kit[key]
	local now = os.clock()
	if not kit or not canAct(key, now) then
		return
	end
	local aim = HeroCamera.aim()
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	actionEvent:FireServer(key, aim)
	AbilityBar.used(key)

	if kit.Kind == "Combo" then
		local step = if now <= comboUntil then combo % #kit.Hits + 1 else 1
		local hit = kit.Hits[step]
		combo, comboUntil = step, now + kit.Reset
		busyUntil = now + hit.Hit / kit.Speed + RECOVER
		local length = HeroAnimator.play(character, hit.Motion, kit.Speed)
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
		return
	end

	comboUntil = 0
	cooldowns[key] = now + kit.Cooldown
	AbilityBar.cooldown(key, kit.Cooldown)
	if kit.Kind == "Dash" then
		local from = root.Position
		local to = HeroKit.dashEnd(from, direction, kit.Range, HeroKit.leapIgnore())
		busyUntil = now + kit.Move + RECOVER
		leap = { started = now, from = from, to = to, takeoff = kit.Start, land = kit.Move, sharp = true }
		slow(humanoid, kit.Move, 0)
		dashMotion(character, from, to, kit)
		return
	end
	local length = HeroAnimator.play(character, kit.Motion, 1)
	if kit.Kind == "Leap" then
		busyUntil = now + kit.Land + RECOVER
		local to = HeroKit.leapLanding(root.Position, aim, kit.Range, heightOf(root, humanoid), HeroKit.leapIgnore())
		leap = { started = now, from = root.Position, to = to, takeoff = kit.Takeoff, land = kit.Land, sharp = false }
		slow(humanoid, kit.Land + RECOVER, 0)
		landLater(character, to, kit)
	elseif kit.Kind == "Throw" then
		busyUntil = now + kit.Release + RECOVER
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
	else
		busyUntil = now + length
		slow(humanoid, length, Config.Combat.AttackWalkSpeed)
		if kit.Slam then
			slamLater(character, kit)
		end
	end
end

local function startAiming(key: string)
	local _, _, _, settings = hero()
	local kit = settings and settings.Kit[key]
	if not kit or os.clock() < (cooldowns[key] or 0) then
		return
	end
	stopAiming()
	aiming = key
	AbilityBar.aiming(key, true)
	if kit.Indicator == "Arrow" then
		indicator = Indicators.arrow()
	elseif kit.Indicator == "Zone" then
		indicator = Indicators.zone()
	elseif kit.Indicator == "Cone" then
		indicator = Indicators.cone()
	end
end

local function updateIndicator()
	local character, root, humanoid, settings = hero()
	if not aiming or not indicator then
		return
	end
	if not character or not root or not humanoid then
		stopAiming()
		return
	end
	local kit = settings.Kit[aiming]
	local aim = HeroCamera.aim()
	local height = heightOf(root, humanoid)
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local below = Workspace:Raycast(root.Position, Vector3.new(0, -(height + 2), 0), groundRay)
	local feet = if below then below.Position else root.Position - Vector3.new(0, height, 0)
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	if indicator.kind == "Arrow" then
		Indicators.placeArrow(indicator, feet + direction * 1.2, direction, kit.Range, kit.Width)
	elseif indicator.kind == "Zone" then
		local to = HeroKit.leapLanding(root.Position, aim, kit.Range, height, HeroKit.leapIgnore())
		local landing = Workspace:Raycast(to, Vector3.new(0, -(height + 2), 0), groundRay)
		local spot = if landing then landing.Position else to - Vector3.new(0, height, 0)
		Indicators.placeZone(indicator, feet, kit.Range, spot, kit.Radius)
	elseif indicator.kind == "Cone" then
		Indicators.placeCone(indicator, feet, direction, kit.Range)
	end
end

local function updateLeap()
	local l = leap
	local character, root = hero()
	if not l then
		return
	end
	if not character or not root then
		leap = nil
		return
	end
	local t = os.clock() - l.started
	if t < l.takeoff then
		return
	end
	local alpha = math.clamp((t - l.takeoff) / (l.land - l.takeoff), 0, 1)
	alpha = if l.sharp then 1 - (1 - alpha) ^ 2 else alpha * alpha * (3 - 2 * alpha)
	local position = l.from:Lerp(l.to, alpha)
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		leap = nil
	end
end

local function undo(key: string)
	local character, _, humanoid = hero()
	busyUntil = 0
	cooldowns[key] = 0
	AbilityBar.cooldown(key, 0)
	leap = nil
	if character and humanoid then
		HeroAnimator.stop(character)
		motionToken += 1
		humanoid.WalkSpeed = Config.Combat.WalkSpeed
	end
end

local function onMotion(character: Model, key: string, step: number, landing: Vector3?)
	if character == player.Character or not character.Parent then
		return
	end
	local name = character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	local kit = settings and settings.Kit[key]
	if not kit then
		return
	end
	if kit.Kind == "Combo" then
		HeroAnimator.play(character, kit.Hits[step].Motion, kit.Speed)
	elseif kit.Kind == "Dash" then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and landing then
			dashMotion(character, root.Position, landing, kit)
		end
		return
	else
		HeroAnimator.play(character, kit.Motion, 1)
	end
	if kit.Kind == "Leap" and landing then
		landLater(character, landing, kit)
	elseif kit.Slam then
		slamLater(character, kit)
	end
end

-- The thrown shadow dagger: the pack's dagger, spinning end over end, with a trail of shadow behind it.
local function dagger(pack: string): BasePart
	local template = ReplicatedStorage[pack].Rig.Components.DaggerLeft:FindFirstChildWhichIsA("MeshPart", true)
	local part = template:Clone() :: MeshPart
	for _, d in part:GetChildren() do
		if d:IsA("JointInstance") then
			d:Destroy()
		end
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, part.Size.Y * 0.3, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -part.Size.Y * 0.3, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(SHADOW, Color3.fromRGB(20, 10, 40))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = part
	local light = Instance.new("PointLight")
	light.Color = SHADOW
	light.Range = 6
	light.Brightness = 1.5
	light.Parent = part
	part.Parent = effects()
	return part
end

local function onProjectile(
	id: number,
	character: Model,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	range: number
)
	local name = character and character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	if not settings then
		return
	end
	flying[id] = {
		dagger = dagger(settings.Pack),
		origin = origin,
		direction = direction,
		speed = speed,
		range = range,
		started = os.clock(),
	}
	HeroSounds.event(character, settings.Pack, "Release")
end

local function onProjectileEnd(id: number, at: Vector3, hit: boolean)
	local f = flying[id]
	if f then
		f.dagger:Destroy()
		flying[id] = nil
	end
	if hit then
		ShadowEffects.burst(at)
	end
end

local function updateFlying()
	local now = os.clock()
	for id, f in flying do
		local travelled = (now - f.started) * f.speed
		if travelled > f.range + 10 then
			f.dagger:Destroy()
			flying[id] = nil
			continue
		end
		local position = f.origin + f.direction * math.min(travelled, f.range)
		local spin = CFrame.Angles(-(now - f.started) * 22, 0, 0)
		f.dagger.CFrame = CFrame.lookAt(position, position + f.direction) * spin * CFrame.Angles(-math.pi / 2, 0, 0)
	end
end

-- The crosshair: neutral, or the colour of the team under it.
local function crosshair(): ImageLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(46, 46)
	image.BackgroundTransparency = 1
	image.Image = Assets.CrosshairNeutral
	image.Parent = gui
	return image
end

local function teamOf(instance: Instance?): string?
	while instance and instance ~= Workspace do
		local team = instance:GetAttribute("Team")
		if team then
			return team
		end
		instance = instance.Parent
	end
	return nil
end

function HeroControls.start()
	local net = ReplicatedStorage:WaitForChild("Net")
	actionEvent = net:WaitForChild("HeroAction") :: RemoteEvent
	(net:WaitForChild("HeroMotion") :: RemoteEvent).OnClientEvent:Connect(onMotion);
	(net:WaitForChild("HeroRefused") :: RemoteEvent).OnClientEvent:Connect(undo);
	(net:WaitForChild("HeroProjectile") :: RemoteEvent).OnClientEvent:Connect(onProjectile);
	(net:WaitForChild("HeroProjectileEnd") :: RemoteEvent).OnClientEvent:Connect(onProjectileEnd)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingM1 = true
			cast("M1")
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			cast("Dash")
			return
		end
		local key = KEY_OF[input.KeyCode] or KEY_OF[input.UserInputType]
		if key then
			startAiming(key)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingM1 = false
			return
		end
		local key = KEY_OF[input.KeyCode] or KEY_OF[input.UserInputType]
		if key and key == aiming then
			stopAiming()
			cast(key)
		end
	end)

	player.CharacterAdded:Connect(function()
		stopAiming()
		busyUntil, combo, comboUntil, leap = 0, 0, 0, nil
		table.clear(cooldowns)
		for _, key in { "M1", "M2", "E", "R", "Dash" } do
			AbilityBar.cooldown(key, 0)
		end
	end)

	local cross = crosshair()
	RunService.PreSimulation:Connect(updateLeap)
	RunService.RenderStepped:Connect(function()
		if holdingM1 and not aiming then
			cast("M1")
		end
		updateIndicator()
		updateFlying()
		local character = player.Character
		local own = character and character:GetAttribute("Team")
		local team = teamOf(HeroCamera.target())
		cross.Image = if team == nil
			then Assets.CrosshairNeutral
			elseif team == own then Assets.CrosshairAlly
			else Assets.CrosshairEnemy
	end)
end

return HeroControls
