-- A sniper's scope (Config's Kind "Snipe", HeroControls; owner, 2026-11-04): the eyepiece over the screen as he looks
-- through his rifle, zoomed in by HeroCamera.scope. The world stays in sight round it, dimmed: the round lens with its
-- gunmetal housing (Assets.ScopeHousing, drawn by Tools/scope_textures.py) and its crosshair (Assets.ScopeReticle)
-- with a red dot in the middle, and beside it a small panel with the distance to what it is on, the zoom, and the time
-- left before it fires itself. It comes to his eye with a short slide as the camera zooms in.
-- Everyone else sees a thin red line from a hero aiming through a scope to where he aims (his "Scope" attribute,
-- CombatService), with a red dot where it ends; and the shooter sees HEADSHOT when his bullet strikes a head.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local HeroCamera = require(script.Parent.HeroCamera)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local UiSound = require(script.Parent.UiSound)

local Scope = {}

-- The housing's width as a share of the screen's height, all of it on the screen with a little room above and below
-- (owner, 2026-11-04: it was taller than the screen); its lens is HOUSING_LENS of that (Tools/scope_textures.py's
-- LENS).
local HOUSING = 0.92
local HOUSING_LENS = 0.74
local LENS = HOUSING * HOUSING_LENS
-- How dark the world round the scope is (0 black, 1 clear), and how far the black reaches round the lens.
local DIM = 0.5
local DARK = 4000
-- The slide to his eye: how much larger it starts, and how long it takes.
local GROW = 1.22
local EASE = 0.24
local INK = Color3.fromRGB(8, 8, 10)
local RED = Color3.fromRGB(255, 46, 46)
local PALE = Color3.fromRGB(236, 240, 236)
local MUTED = Color3.fromRGB(170, 178, 176)
local ORANGE = Color3.fromRGB(255, 150, 40)
-- Below this share of the hold left, the time bar turns red.
local HURRY = 0.3
-- The red line others see: how far it reaches and how thick it is.
local LASER_REACH = 1000
local LASER_WIDTH = 0.07
local HEADSHOT_TIME = 1.1

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local lens: Frame? = nil
local scale: UIScale? = nil
local shade: UIStroke? = nil
local fade: { ImageLabel } = {}
local distance: TextLabel? = nil
local zoom: TextLabel? = nil
local fill: Frame? = nil
local prompt: TextLabel? = nil
local banner: TextLabel? = nil
local readyAt, endsAt = 0, 0
local open = false

type Laser = { from: Attachment, to: Attachment, beam: Beam, dot: BasePart }
local lasers: { [Model]: Laser } = {}
local laserRay = RaycastParams.new()
laserRay.FilterType = Enum.RaycastFilterType.Exclude
local extents: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any

local function round(frame: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
end

local function image(parent: Instance, id: string, size: number, z: number): ImageLabel
	local picture = Instance.new("ImageLabel")
	picture.AnchorPoint = Vector2.new(0.5, 0.5)
	picture.Position = UDim2.fromScale(0.5, 0.5)
	picture.Size = UDim2.fromScale(size, size)
	picture.SizeConstraint = Enum.SizeConstraint.RelativeYY
	picture.BackgroundTransparency = 1
	picture.Image = id
	picture.ZIndex = z
	picture.Parent = parent
	return picture
end

local function label(parent: Instance, text: string, size: number, colour: Color3, font: Enum.Font): TextLabel
	local words = Instance.new("TextLabel")
	words.BackgroundTransparency = 1
	words.Size = UDim2.new(1, 0, 0, size + 4)
	words.Font = font
	words.TextSize = size
	words.TextColor3 = colour
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 1.2
	stroke.Transparency = 0.45
	stroke.Parent = words
	words.Parent = parent
	return words
end

-- The panel beside the housing: the distance, the zoom, and the time bar with its hint.
local function panel(housing: ImageLabel): (TextLabel, TextLabel, Frame, TextLabel)
	local side = Instance.new("Frame")
	side.Name = "Panel"
	side.AnchorPoint = Vector2.new(0, 0.5)
	side.Position = UDim2.fromScale(0.95, 0.5)
	side.Size = UDim2.fromOffset(170, 150)
	side.BackgroundTransparency = 1
	side.ZIndex = 4
	side.Parent = housing
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = side

	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = ORANGE
	accent.BorderSizePixel = 0
	accent.Size = UDim2.fromOffset(26, 3)
	accent.LayoutOrder = 1
	accent.Parent = side
	label(side, "RANGE", 12, MUTED, Enum.Font.GothamBold).LayoutOrder = 2
	local reading = label(side, "- - -", 30, PALE, Enum.Font.GothamBlack)
	reading.LayoutOrder = 3
	local power = label(side, "", 14, MUTED, Enum.Font.GothamBold)
	power.LayoutOrder = 4

	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.fromOffset(1, 8)
	gap.LayoutOrder = 5
	gap.Parent = side
	label(side, "AUTO FIRE", 12, MUTED, Enum.Font.GothamBold).LayoutOrder = 6
	local track = Instance.new("Frame")
	track.BackgroundColor3 = INK
	track.BackgroundTransparency = 0.35
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(150, 5)
	track.LayoutOrder = 7
	track.Parent = side
	round(track, UDim.new(0.5, 0))
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = PALE
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.Parent = track
	round(bar, UDim.new(0.5, 0))
	local hint = label(side, "", 14, PALE, Enum.Font.GothamBold)
	hint.LayoutOrder = 8
	return reading, power, bar, hint
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Scope"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 5
	screen.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.Name = "Lens"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = false
	holder.Parent = screen
	local grow = Instance.new("UIScale")
	grow.Parent = holder

	-- The dimmed world round the lens: the lens's outline, far wider than any screen.
	local hole = Instance.new("Frame")
	hole.Name = "Hole"
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromScale(LENS, LENS)
	hole.SizeConstraint = Enum.SizeConstraint.RelativeYY
	hole.BackgroundTransparency = 1
	hole.Parent = holder
	round(hole, UDim.new(0.5, 0))
	local dim = Instance.new("UIStroke")
	dim.Color = Color3.new(0, 0, 0)
	dim.Thickness = DARK
	dim.Transparency = DIM
	dim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pcall(function()
		(dim :: any).BorderStrokePosition = Enum.BorderStrokePosition.Outer
	end)
	dim.Parent = hole

	local housing = image(holder, Assets.ScopeHousing, HOUSING, 2)
	housing.Name = "Housing"
	local reticle = image(holder, Assets.ScopeReticle, LENS, 3)
	reticle.Name = "Reticle"

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(5, 5)
	dot.BackgroundColor3 = RED
	dot.BorderSizePixel = 0
	dot.ZIndex = 4
	dot.Parent = holder
	round(dot, UDim.new(0.5, 0))
	local glow = Instance.new("UIStroke")
	glow.Color = RED
	glow.Thickness = 2
	glow.Transparency = 0.6
	glow.Parent = dot

	local reading, power, bar, hint = panel(housing)

	local headshot = Instance.new("TextLabel")
	headshot.BackgroundTransparency = 1
	headshot.AnchorPoint = Vector2.new(0.5, 0.5)
	headshot.Position = UDim2.fromScale(0.5, 0.36)
	headshot.Size = UDim2.fromOffset(400, 44)
	headshot.Font = Enum.Font.GothamBlack
	headshot.TextSize = 38
	headshot.TextColor3 = RED
	headshot.Text = "HEADSHOT"
	headshot.Visible = false
	headshot.ZIndex = 5
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 2
	edge.Transparency = 0.2
	edge.Parent = headshot
	headshot.Parent = screen

	gui, lens, scale, shade = screen, holder, grow, dim
	fade = { housing, reticle }
	distance, zoom, fill, prompt, banner = reading, power, bar, hint, headshot
end

-- Looks through the scope of `kit` (a Snipe): it comes to his eye as the camera zooms in, ready to fire `kit.Ready`
-- seconds from now, firing itself `kit.Hold` seconds after that.
function Scope.enter(kit: any)
	if not gui then
		build()
	end
	local now = os.clock()
	readyAt, endsAt = now + kit.Ready, now + kit.Ready + kit.Hold
	open = true
	local camera = Workspace.CurrentCamera
	local wide = if camera then camera.FieldOfView else 70
	(zoom :: TextLabel).Text =
		string.format("%.1fx ZOOM", math.tan(math.rad(wide / 2)) / math.tan(math.rad(kit.Zoom / 2)))
	HeroCamera.scope(kit.Zoom)
	UiSound.play("ScopeIn")
	local holder, grow, dim = lens :: Frame, scale :: UIScale, shade :: UIStroke
	holder.Visible = true
	local info = TweenInfo.new(EASE, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	grow.Scale = GROW
	TweenService:Create(grow, info, { Scale = 1 }):Play()
	dim.Transparency = 1
	TweenService:Create(dim, info, { Transparency = DIM }):Play()
	for _, picture in fade do
		picture.ImageTransparency = 1
		TweenService:Create(picture, TweenInfo.new(EASE * 0.6), { ImageTransparency = 0 }):Play()
	end
end

-- Takes the scope from his eye (he fired, or the attack ended).
function Scope.leave()
	if not open then
		return
	end
	open = false
	HeroCamera.scope(nil)
	if lens then
		lens.Visible = false
	end
end

-- Whether he looks through a scope now.
function Scope.open(): boolean
	return open
end

-- Shows HEADSHOT for a moment.
function Scope.headshot()
	if not gui then
		build()
	end
	local text = banner :: TextLabel
	text.Visible = true
	text.TextTransparency = 0
	UiSound.play("Headshot")
	TweenService:Create(text, TweenInfo.new(HEADSHOT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
	task.delay(HEADSHOT_TIME, function()
		if text.TextTransparency >= 1 then
			text.Visible = false
		end
	end)
end

local function updateLens()
	if not open or not distance then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local target = HeroCamera.target()
		local metres = (HeroCamera.aim() - root.Position).Magnitude;
		(distance :: TextLabel).Text = if target then string.format("%d m", math.round(metres)) else "- - -"
	end
	local now = os.clock()
	local ready = now >= readyAt
	local left = if ready then math.clamp((endsAt - now) / math.max(endsAt - readyAt, 0.01), 0, 1) else 1
	local bar = fill :: Frame
	bar.Size = UDim2.fromScale(left, 1)
	bar.BackgroundColor3 = if ready and left < HURRY then RED else PALE;
	(prompt :: TextLabel).Text = if ready then "CLICK TO FIRE" else "STEADY..."
end

local function dropLaser(model: Model)
	local laser = lasers[model]
	if laser then
		laser.from:Destroy()
		laser.to:Destroy()
		laser.beam:Destroy()
		laser.dot:Destroy()
		lasers[model] = nil
	end
end

local function newLaser(): Laser
	local terrain = Workspace.Terrain
	local from = Instance.new("Attachment")
	from.Name = "ScopeLaserFrom"
	from.Parent = terrain
	local to = Instance.new("Attachment")
	to.Name = "ScopeLaserTo"
	to.Parent = terrain
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.Color = ColorSequence.new(RED)
	beam.Transparency = NumberSequence.new(0.15, 0.35)
	beam.Width0, beam.Width1 = LASER_WIDTH, LASER_WIDTH
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = terrain
	local dot = Instance.new("Part")
	dot.Name = "ScopeLaserDot"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * 0.35
	dot.Material = Enum.Material.Neon
	dot.Color = RED
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	local effects = Workspace:FindFirstChild("Effects")
	dot.Parent = effects or Workspace
	return { from = from, to = to, beam = beam, dot = dot }
end

-- The red line from every other hero aiming through a scope to the first thing in his aim's way.
local function updateLasers()
	local seen: { [Model]: boolean } = {}
	for _, model in CollectionService:GetTagged("Combatant") do
		if not model:IsA("Model") or model == player.Character then
			continue
		end
		local aim = model:GetAttribute("Scope")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if typeof(aim) ~= "Vector3" or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		seen[model] = true
		local laser = lasers[model] or newLaser()
		lasers[model] = laser
		local muzzle = HeroKit.muzzle(root.Position)
		local direction = HeroKit.aimDirection(muzzle, aim, root.CFrame.LookVector)
		local from = muzzle + direction * 1.5
		local ignore = HeroKit.leapIgnore()
		table.insert(ignore, laser.dot)
		laserRay.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(from, direction * LASER_REACH, laserRay)
		local ends = if hit then hit.Position else from + direction * LASER_REACH
		-- The line stops at the first of his enemies in its way too, as the bullet would strike him.
		for _, foe in HeroKit.foes(model:GetAttribute("Team") or "", extents) do
			local along = HeroKit.shotTouch(from, ends, 0.2, foe.body)
			if along then
				ends = from:Lerp(ends, along)
			end
		end
		laser.from.WorldPosition = from
		laser.to.WorldPosition = ends
		laser.dot.CFrame = CFrame.new(ends)
	end
	for model in lasers do
		if not seen[model] then
			dropLaser(model)
		end
	end
end

function Scope.start()
	RunService.RenderStepped:Connect(function()
		updateLens()
		updateLasers()
	end)
	player.CharacterAdded:Connect(function()
		Scope.leave()
	end)
end

return Scope
