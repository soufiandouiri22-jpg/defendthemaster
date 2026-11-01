-- The loading screen (STYLE): black with two white blades of the Master's greatsword that swing together, clash and
-- turn round together, and LOADING with how far it is and a bar that fills as far (owner, 2026-10-31: no logo); or
-- the colosseum it had before (owner, 2026-10-31: kept for when the new one does not please), one picture with the
-- logo in it, LOADING and a running bar. It lives in ReplicatedFirst
-- so it is up before anything else: on joining (LoadingScreen) it stays until the client has loaded what its first look
-- shows (Loading.ready, from the client once its world and pictures are in), nothing is downloading any more, the
-- world has rendered a moment behind it and every picture and sound the player meets when it goes is in, or after
-- LONGEST seconds; then until the screen after it is there (Loading.hold: in a match the draft, which the server starts
-- once every player's client is ready, Loading.waitReady), so the draft and its music come all at once; and a
-- teleport carries the same screen across (Loading.forTeleport), so going from a match to the lobby or back never
-- shows a half-built world; to a match it carries the match's cards instead (VersusView.travel, Loading.arrived), so
-- a player sees those from the lobby until the fight. The mouse's gauntlet (Loading.pointer) is not on the black screen (owner, 2026-10-31): it
-- comes with a screen over it that takes the mouse (the cards while a match loads, Loading.unshield), else as it goes.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Trace = require(script.Parent:WaitForChild("Trace"))

local Loading = {}

-- Which screen shows: "Blades", or "Colosseum" for the one before.
local STYLE = "Blades"

-- The blades (Tools/loading_blades.py): the Master's greatsword lying flat with its tip to the right, sharp
-- (Art/UI/loading_blade.png) or soft and round like a toy sword (Art/UI/loading_blade_soft.png), and the soft white
-- light behind them (Art/UI/loading_light.png). Sizes are shares of the screen's height.
local BLADES = { Sharp = "rbxassetid://104061655905115", Soft = "rbxassetid://76085931021800" }
local BLADE = BLADES.Soft
local LIGHT = "rbxassetid://87753297282222"
local BLADE_ASPECT = 1024 / 310
local BLADE_LONG = 0.34
local BLADES_AT = 0.44
local LIGHT_SIZE = 0.62
-- One round of the blades in seconds: they swing together until SWUNG, clash, hold until TURN, turn half round
-- together until TURNED and swing apart again until the round's end; OPEN degrees apart at the widest.
local ROUND, SWUNG, TURN, TURNED = 2.6, 0.42, 0.9, 2.05
-- The blades' own clock goes on at most this many seconds a frame: after a frame the game stalled on (the world coming
-- in) they carry on from where they were instead of jumping ahead to catch up.
local STEP = 1 / 20
local OPEN = 58
-- LOADING and the bar under the blades.
local LABEL_AT, LABEL_SIZE = 0.665, 0.034
local BAR_AT, BAR_LONG, BAR_THICK = 0.715, 0.3, 0.006

-- The colosseum in sharp focus (owner, 2026-10-28) with Docs/Designs/Logo/dtm_logo_main.png, LOADING and the bar under
-- it as one block exactly in the middle of the screen, as three pictures made by Tools/loading_art.py and uploaded
-- through Studio: the colosseum (Art/UI/loading_plate.png), covering the screen and cut evenly round its centre; the
-- logo (Art/UI/loading_mark.png), drawn from a texture of its own; and its warm glow and shadow under it
-- (Art/UI/loading_glow.png, GLOW times the logo's size round its centre).
local ART = "rbxassetid://127668674329359"
local MARK = "rbxassetid://109762598787578"
local GLOW = "rbxassetid://90645939656624"
local ART_ASPECT = 16 / 9
local LOGO_ASPECT = 1024 / 532
local GLOW_SIZE = Vector2.new(1.4, 1.77)
-- The block in shares of the screen's height, from the top: the logo, the gap, LOADING, the gap and the bar.
local LOGO_HIGH, LOGO_GAP, LABEL_HIGH, BAR_GAP, BAR_HIGH = 0.318, 0.04, 0.045, 0.03, 0.014
local BAR_WIDE = 0.46
local BLOCK_HIGH = LOGO_HIGH + LOGO_GAP + LABEL_HIGH + BAR_GAP + BAR_HIGH
local CREAM = Color3.fromRGB(252, 242, 214)
local EDGE = Color3.fromRGB(70, 42, 20)
local GOLD = Color3.fromRGB(255, 214, 90)
local GOLD_DARK = Color3.fromRGB(200, 120, 20)
-- The screen goes in any case after this many seconds.
local LONGEST = 30
-- The screen's own pictures get this long before it shows without them.
local PICTURES = 4
-- Downloads count as done when nothing has been asked for this long.
local QUIET = 0.5
-- The world renders at least this long and this many frames behind the screen before it goes.
local SETTLE, SETTLE_FRAMES = 3.5, 150
-- The screen waits at most this long for what holds it (a match waits Config.Draft.Arrive for its players), and then
-- this long for the pictures of the screen under it.
local HELD = 45
local SHOWN = 5
-- The mouse pointer: the game's gold gauntlet (Shared.Assets.Pointer, which Pointer.start passes on; this copy only
-- until it does, as ReplicatedStorage is not here yet), its height on the screen, the picture's size and its fingertip
-- (where it clicks) in it; above every other screen, the loading screen (1000) included.
local POINTER = "rbxassetid://124420581695634"
local POINTER_HIGH = 54
local POINTER_PICTURE = Vector2.new(211, 238)
local POINTER_TIP = Vector2.new(7, 11)
local POINTER_ORDER = 2000
local gauntlet: ImageLabel? = nil
-- Whether the black screen is up with nothing over it that takes the mouse: the gauntlet hides meanwhile.
local covering = false
-- The match's cards (VersusView), which the lobby sends along on the teleport to a match in place of the black screen:
-- the screen that came with the teleport when it has this name, kept until VersusView takes over.
local CARDS = "Versus"
local cards: ScreenGui? = nil

local readyNow = false
local shown: ScreenGui? = nil
local gone = false
local goneSignal = Instance.new("BindableEvent")
local holds = 0
local needs: { Instance } = {}
local readyAll = false
local readySignal = Instance.new("BindableEvent")
-- How far the loading is (0 to 1, never going back), and whether all that is left is waiting for what holds the
-- screen (the other players).
local progress = 0
local waiting = false

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- The picture as large as the screen needs to be covered by it, round the middle.
local function fit(art: GuiObject, screen: Vector2)
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local scale = math.max(screen.X / ART_ASPECT, screen.Y)
	art.Size = UDim2.fromOffset(math.ceil(scale * ART_ASPECT), math.ceil(scale))
end

-- The properties a fade changes, per class.
local FADED = {
	Frame = { "BackgroundTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency" },
	UIStroke = { "Transparency" },
}

-- Fades `root` and everything in it in (to how it was built) or out, over `seconds` (at once with 0). Every piece fades
-- on its own: a CanvasGroup would draw text and the logo from a texture of its own, softer than the screen.
local function fade(root: Instance, visible: boolean, seconds: number): Tween?
	local last = nil
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, item in all do
		for _, property in FADED[item.ClassName] or {} do
			local base = item:GetAttribute(property)
			if base == nil then
				base = (item :: any)[property]
				item:SetAttribute(property, base)
			end
			local goal = if visible then base else 1
			if seconds <= 0 then
				(item :: any)[property] = goal
			else
				last = TweenService:Create(item, TweenInfo.new(seconds), { [property] = goal })
				last:Play()
			end
		end
	end
	return last
end

-- An empty button over it all that takes every click, so nothing of the menu behind it can be pressed. Roblox still
-- tells the buttons behind when the mouse comes over them, which is why UiSound stays silent until the screen goes.
local function shield(group: Frame)
	local button = Instance.new("TextButton")
	button.Name = "Shield"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Selectable = false
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = group
end

-- A frame sized and placed in shares of the screen's height, round its middle at `x` of the width and `y` of the
-- height.
local function tall(
	parent: Instance,
	name: string,
	class: string,
	x: number,
	y: number,
	wide: number,
	high: number
): any
	local item = Instance.new(class)
	item.Name = name
	item.BackgroundTransparency = 1
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromScale(x, y)
	item.SizeConstraint = Enum.SizeConstraint.RelativeYY
	item.Size = UDim2.fromScale(wide, high)
	item.Parent = parent
	return item
end

-- The black screen with the blades.
local function buildBlades(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local group = Instance.new("Frame")
	group.Name = "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BorderSizePixel = 0
	back.Parent = group
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = group

	local light = tall(content, "Light", "ImageLabel", 0.5, BLADES_AT, LIGHT_SIZE, LIGHT_SIZE)
	light.Image = LIGHT
	light.ImageTransparency = 0.9
	local ring = tall(content, "Ring", "Frame", 0.5, BLADES_AT, 0.1, 0.1)
	corner(ring, UDim.new(0.5, 0))
	local ringEdge = Instance.new("UIStroke")
	ringEdge.Color = Color3.new(1, 1, 1)
	ringEdge.Thickness = 3
	ringEdge.Transparency = 1
	ringEdge.Parent = ring
	for _, name in { "BladeBack", "BladeFront" } do
		local blade = tall(content, name, "ImageLabel", 0.5, BLADES_AT, BLADE_LONG, BLADE_LONG / BLADE_ASPECT)
		blade.Image = BLADE
	end

	local label = tall(content, "Label", "TextLabel", 0.5, LABEL_AT, 1, LABEL_SIZE)
	label.Font = Enum.Font.FredokaOne
	label.Text = "LOADING"
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local track = tall(content, "Track", "Frame", 0.5, BAR_AT, BAR_LONG, BAR_THICK)
	track.BackgroundTransparency = 0.82
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	corner(track, UDim.new(0.5, 0))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, UDim.new(0.5, 0))

	shield(group)
	return gui
end

-- The colosseum screen that came before.
local function buildColosseum(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local group = Instance.new("Frame")
	group.Name = "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui
	-- The dark hall behind, a frame of its own: a gradient on the group would darken everything in it.
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.Parent = group
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(56, 36, 26), Color3.fromRGB(14, 9, 7))
	shade.Parent = back
	-- Everything over the dark, which comes in as one once its pictures have loaded.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = group
	-- The picture at full strength, only darker at the foot so LOADING and the bar read.
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = ART
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	local camera = workspace.CurrentCamera
	fit(art, if camera then camera.ViewportSize else Vector2.new(1920, 1080))
	art.Parent = content
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(14, 9, 7)
	dim.BorderSizePixel = 0
	dim.Parent = content
	local fall = Instance.new("UIGradient")
	fall.Rotation = 90
	fall.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	fall.Parent = dim

	-- The logo, LOADING and the bar as one block, sized by the screen's height, in the middle of the screen.
	local logoWide = LOGO_HIGH * LOGO_ASPECT
	local wide = math.max(logoWide, BAR_WIDE)
	local block = Instance.new("Frame")
	block.Name = "Block"
	block.BackgroundTransparency = 1
	block.AnchorPoint = Vector2.new(0.5, 0.5)
	block.Position = UDim2.fromScale(0.5, 0.5)
	block.SizeConstraint = Enum.SizeConstraint.RelativeYY
	block.Size = UDim2.fromScale(wide, BLOCK_HIGH)
	block.Parent = content
	local logoSize = UDim2.fromScale(logoWide / wide, LOGO_HIGH / BLOCK_HIGH)
	local logoMiddle = UDim2.fromScale(0.5, LOGO_HIGH / 2 / BLOCK_HIGH)
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = GLOW
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = logoMiddle
	glow.Size = UDim2.fromScale(logoSize.X.Scale * GLOW_SIZE.X, logoSize.Y.Scale * GLOW_SIZE.Y)
	glow.Parent = block
	local logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.BackgroundTransparency = 1
	logo.Image = MARK
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = logoMiddle
	logo.Size = logoSize
	logo.Parent = block

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "LOADING"
	label.TextScaled = true
	label.TextColor3 = CREAM
	label.Position = UDim2.fromScale(0, (LOGO_HIGH + LOGO_GAP) / BLOCK_HIGH)
	label.Size = UDim2.fromScale(1, LABEL_HIGH / BLOCK_HIGH)
	label.Parent = block
	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.fromScale(BAR_WIDE / wide, BAR_HIGH / BLOCK_HIGH)
	track.BackgroundColor3 = Color3.fromRGB(36, 24, 18)
	track.ClipsDescendants = true
	track.Parent = block
	corner(track, UDim.new(0.5, 0))
	local edge = Instance.new("UIStroke")
	edge.Color = GOLD_DARK
	edge.Thickness = 2
	edge.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.3, 1)
	fill.Position = UDim2.fromScale(-0.3, 0)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, UDim.new(0.5, 0))
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(GOLD, GOLD_DARK)
	shine.Parent = fill

	shield(group)
	return gui
end

-- A new loading screen.
function Loading.build(): ScreenGui
	return if STYLE == "Colosseum" then buildColosseum() else buildBlades()
end

-- 0 at `from`, 1 at `to`, eased in and out.
local function ease(t: number, from: number, to: number): number
	local x = math.clamp((t - from) / (to - from), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Runs the blades, the light, the clash's ring, the bar and LOADING with its share every frame until the screen goes.
-- The blades turn on from where the last round left them (half a turn each round), so no round starts with a jump.
local function animate(gui: ScreenGui)
	local front = gui:FindFirstChild("BladeFront", true) :: ImageLabel
	local back = gui:FindFirstChild("BladeBack", true) :: ImageLabel
	local light = gui:FindFirstChild("Light", true) :: ImageLabel?
	local ring = gui:FindFirstChild("Ring", true) :: Frame?
	local ringEdge = ring and ring:FindFirstChildOfClass("UIStroke")
	local fill = gui:FindFirstChild("Fill", true) :: Frame?
	local label = gui:FindFirstChild("Label", true) :: TextLabel?
	local bladeSize = front.Size
	local clock = 0
	local seen = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not gui.Parent then
			connection:Disconnect()
			return
		end
		local step = math.min(dt, STEP)
		clock += step
		local round = math.floor(clock / ROUND)
		local t = clock - round * ROUND
		-- Apart at the round's start and end, together from SWUNG (overshooting a little as they strike) to TURNED.
		local closing = math.clamp(t / SWUNG, 0, 1)
		local strike = 1 - closing ^ 2.4
		local spread = if t < SWUNG then strike else ease(t, TURNED, ROUND) ^ 1.6
		local bounce = if t >= SWUNG then math.sin(math.min(1, (t - SWUNG) / 0.22) * math.pi) * -0.08 else 0
		local turn = (round + ease(t, TURN, TURNED)) * 180
		local open = OPEN * (spread + bounce)
		front.Rotation = turn - 45 + open
		back.Rotation = turn - 135 - open
		-- The clash: the blades jump a little, a ring races out and the light flares.
		local since = t - SWUNG
		local pop = if since >= 0 then math.exp(-since * 9) else 0
		local grow = 1 + 0.07 * pop
		front.Size = UDim2.fromScale(bladeSize.X.Scale * grow, bladeSize.Y.Scale * grow)
		back.Size = front.Size
		-- Once the screen fades out the ring is left to the fade.
		if ring and ringEdge and not gone then
			local out = if since >= 0 then math.clamp(since / 0.55, 0, 1) else 1
			local wide = 0.12 + 0.36 * (1 - (1 - out) ^ 3)
			ring.Size = UDim2.fromScale(wide, wide)
			ringEdge.Transparency = 0.35 + 0.65 * out
		end
		if light then
			local size = LIGHT_SIZE * (1 + 0.18 * pop)
			light.Size = UDim2.fromScale(size, size)
		end
		seen += (progress - seen) * step * 5
		if fill then
			fill.Size = UDim2.fromScale(seen, 1)
		end
		if label then
			label.Text = if waiting then "WAITING FOR PLAYERS" else `LOADING  {math.floor(seen * 100 + 0.5)}%`
		end
	end)
end

-- The mouse as the game's gold gauntlet, a picture following the hidden system mouse every frame (Roblox's own
-- MouseIcon falls back to its arrow over every button and on every click), set up with the loading screen's first
-- frame; not on the black screen, nor while the camera holds the mouse in the middle (HeroCamera's crosshair) or where
-- there is no mouse. The screen does not wait for its picture. Once only; `image` replaces the
-- picture.
function Loading.pointer(image: string?)
	if gauntlet then
		gauntlet.Image = image or gauntlet.Image
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Pointer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- After parenting: a ScreenGui created at runtime can ignore DisplayOrder set before it has a parent.
	gui.DisplayOrder = POINTER_ORDER
	local picture = Instance.new("ImageLabel")
	picture.Name = "Gauntlet"
	picture.BackgroundTransparency = 1
	picture.Image = image or POINTER
	picture.Size = UDim2.fromOffset(math.round(POINTER_HIGH * POINTER_PICTURE.X / POINTER_PICTURE.Y), POINTER_HIGH)
	picture.AnchorPoint = POINTER_TIP / POINTER_PICTURE
	picture.Active = false
	picture.Parent = gui
	gauntlet = picture
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { picture })
	end)
	RunService:BindToRenderStep("Pointer", Enum.RenderPriority.Last.Value, function()
		-- The draft and the end screen switch every other screen off while they are up.
		gui.Enabled = true
		local free = UserInputService.MouseEnabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		local at = UserInputService:GetMouseLocation()
		picture.Position = UDim2.fromOffset(at.X, at.Y)
		local visible = free and not covering
		if visible ~= picture.Visible then
			Trace.mark("pointer", { visible = visible, free = free, covering = covering })
		end
		picture.Visible = visible
		UserInputService.MouseIconEnabled = false
	end)
end

-- Shows the screen that came with a teleport, or a new one, in place of Roblox's own, with its blades turning (or the
-- colosseum's bar running).
function Loading.show()
	local arriving = TeleportService:GetArrivingTeleportGui()
	local gui = arriving or Loading.build()
	if gui.Name == CARDS then
		cards = gui
	end
	covering = cards == nil
	Trace.mark("loading.show", { teleported = arriving ~= nil, cards = cards ~= nil })
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	Loading.pointer()
	if gui == cards then
		shown = gui
		-- A click on a card till the match's own cards take its place (VersusView.start, which turns it then): these
		-- came as a picture, without their buttons (owner, 2026-11-01: the first clicks did nothing).
		local clicks = UserInputService.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			local at = UserInputService:GetMouseLocation()
			local inset = GuiService:GetGuiInset()
			local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
			for _, item in if playerGui then playerGui:GetGuiObjectsAtPosition(at.X - inset.X, at.Y - inset.Y) else {} do
				local card: Instance? = item
				while card and card ~= gui and not card:GetAttribute("Card") do
					card = card.Parent
				end
				if card and card ~= gui and card:IsDescendantOf(gui) then
					card:SetAttribute("Turned", not card:GetAttribute("Turned"))
					return
				end
			end
		end)
		gui.Destroying:Connect(function()
			clicks:Disconnect()
		end)
		return
	end
	-- Everything on it comes in together once its pictures have loaded (at once when they came along with a
	-- teleport), or after PICTURES seconds.
	local content = gui:FindFirstChild("Content", true)
	local art = gui:FindFirstChild("Art", true) :: ImageLabel?
	if art then
		fit(art, gui.AbsoluteSize)
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fit(art, gui.AbsoluteSize)
		end)
	end
	local pictures = {}
	local missing = false
	for _, item in if content then content:GetDescendants() else {} do
		if item:IsA("ImageLabel") then
			table.insert(pictures, item)
			missing = missing or not item.IsLoaded
		end
	end
	if content and missing then
		fade(content, false, 0)
		task.spawn(function()
			local done = false
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, pictures)
				done = true
			end)
			local started = os.clock()
			while not done and os.clock() - started < PICTURES do
				task.wait(0.05)
			end
			fade(content, true, 0.4)
		end)
	end
	local fill = gui:FindFirstChild("Fill", true) :: Frame?
	if gui:FindFirstChild("BladeFront", true) then
		animate(gui)
	elseif fill then
		fill.Position = UDim2.fromScale(-0.3, 0)
		TweenService:Create(
			fill,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
			{ Position = UDim2.fromScale(1, 0) }
		):Play()
	end
	shown = gui
end

-- Takes this screen along on any teleport from here (VersusView.travel sends the match's cards instead).
function Loading.forTeleport()
	TeleportService:SetTeleportGui(Loading.build())
end

-- The match's cards that came with the teleport in place of the black screen, if they did.
function Loading.arrived(): ScreenGui?
	return if cards and cards.Parent then cards else nil
end

-- Loads `instances` (and everything in them) and the pictures of the content ids among them, or gives up after
-- `seconds`.
function Loading.preload(instances: { Instance | string }, seconds: number)
	local done = false
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, instances)
		done = true
	end)
	-- PreloadAsync can be done with a picture that is already on its way for something else still loading.
	local function loading(): boolean
		for _, root in instances do
			if typeof(root) == "Instance" then
				for _, item in root:GetDescendants() do
					if
						(item:IsA("ImageLabel") or item:IsA("ImageButton"))
						and item.Image ~= ""
						and ContentProvider:GetAssetFetchStatus(item.Image) == Enum.AssetFetchStatus.Loading
					then
						return true
					end
				end
			end
		end
		return false
	end
	local started = os.clock()
	while (not done or loading()) and os.clock() - started < seconds do
		task.wait(0.1)
	end
	-- A loaded picture still takes a moment the first time it is drawn (the welcome screen's ability icons came in
	-- late, owner 2026-10-31); once drawn it shows at once, so each is drawn here, small, under this screen.
	local any = false
	for _, root in instances do
		any = any or typeof(root) == "string"
	end
	if not any then
		return
	end
	local warm = Instance.new("ScreenGui")
	warm.Name = "WarmPictures"
	warm.IgnoreGuiInset = true
	warm.ResetOnSpawn = false
	warm.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	warm.DisplayOrder = 999
	local drawn = {}
	for _, root in instances do
		if typeof(root) == "string" then
			local picture = Instance.new("ImageLabel")
			picture.BackgroundTransparency = 1
			picture.ImageTransparency = 0.99
			picture.Size = UDim2.fromOffset(4, 4)
			picture.Image = root
			picture.Parent = warm
			table.insert(drawn, picture)
		end
	end
	local function undrawn(): boolean
		for _, picture in drawn do
			if
				not picture.IsLoaded
				and ContentProvider:GetAssetFetchStatus(picture.Image) ~= Enum.AssetFetchStatus.Failure
			then
				return true
			end
		end
		return false
	end
	while undrawn() and os.clock() - started < seconds do
		task.wait(0.05)
	end
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	warm:Destroy()
end

-- The client has what its first look shows: the screen may go.
function Loading.ready()
	Trace.mark("loading.ready")
	readyNow = true
end

-- Waits until the screen starts to fade away (at once when it already has): what comes after it, the music, starts
-- then.
function Loading.waitGone()
	if not gone then
		goneSignal.Event:Wait()
	end
end

-- Whether the screen has started to fade away.
function Loading.isGone(): boolean
	return gone
end

-- How far the loading is, 0 to 1 (the bar), and whether the client has everything in (Loading.waitReady).
function Loading.progress(): (number, boolean)
	return progress, readyAll
end

-- Keeps the screen up until the returned function is called (the screen that comes after it is there, Draft), at
-- most HELD seconds.
function Loading.hold(): () -> ()
	holds += 1
	local released = false
	return function()
		if not released then
			released = true
			holds -= 1
		end
	end
end

-- Lets clicks through to a screen shown over this one (Versus), and shows the mouse for it: the shield takes them from
-- every screen, also from those with a higher DisplayOrder.
function Loading.unshield()
	Trace.mark("loading.unshield")
	covering = false
	local guard = shown and shown:FindFirstChild("Shield", true)
	if guard and guard:IsA("GuiObject") then
		guard.Visible = false
	end
end

-- Keeps the screen up until `instance` (a Sound) has loaded, so it can start the moment the screen goes.
function Loading.need(instance: Instance)
	table.insert(needs, instance)
end

-- Waits until the client has everything in (Loading.finish), while the screen is still up: the moment to tell the
-- server it may start (the draft waits for it).
function Loading.waitReady()
	if not readyAll then
		readySignal.Event:Wait()
	end
end

local function failed(id: string): boolean
	local ok, status = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, id)
	return ok and (status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut)
end

-- Whether `a` and `b` (GuiObjects) overlap on the screen.
local function overlap(a: GuiObject, b: GuiObject): boolean
	local aMin, bMin = a.AbsolutePosition, b.AbsolutePosition
	local aMax, bMax = aMin + a.AbsoluteSize, bMin + b.AbsoluteSize
	return aMin.X < bMax.X and bMin.X < aMax.X and aMin.Y < bMax.Y and bMin.Y < aMax.Y
end

-- Whether `item` is drawn: shown, on the screen and not cut away by what clips it (a card scrolled out of sight is
-- never drawn, so its picture never loads, owner 2026-11-01).
local function seen(item: GuiObject): boolean
	local at: Instance? = item
	while at and not at:IsA("LayerCollector") do
		if
			at:IsA("GuiObject") and (not at.Visible or (at ~= item and at.ClipsDescendants and not overlap(item, at)))
		then
			return false
		end
		at = at.Parent
	end
	if not at or not (at :: LayerCollector).Enabled then
		return false
	end
	local screen = (Workspace.CurrentCamera :: Camera).ViewportSize
	local min, max = item.AbsolutePosition, item.AbsolutePosition + item.AbsoluteSize
	return max.X > 0 and max.Y > 0 and min.X < screen.X and min.Y < screen.Y
end

-- How much of what the player will see when the screen goes is not in yet: every picture shown on the screens under
-- it (Roblox draws a picture only once it is shown, so these load now, under the screen), and every sound needed.
-- With `names` the names of what is not in yet go into it, for the log.
local function left(names: { string }?): number
	local count = 0
	for _, sound in needs do
		if sound.Parent and sound:IsA("Sound") and not sound.IsLoaded and not failed(sound.SoundId) then
			count += 1
			if names then
				table.insert(names, sound:GetFullName())
			end
		end
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	for _, gui in if playerGui then playerGui:GetChildren() else {} do
		if
			gui == shown
			or gui == (gauntlet and gauntlet.Parent)
			or not gui:IsA("LayerCollector")
			or not gui.Enabled
		then
			continue
		end
		for _, item in gui:GetDescendants() do
			if
				(item:IsA("ImageLabel") or item:IsA("ImageButton"))
				and item.Image ~= ""
				and not item.IsLoaded
				and seen(item)
				and not failed(item.Image)
			then
				count += 1
				if names then
					table.insert(names, `{item:GetFullName()} {item.Image}`)
				end
			end
		end
	end
	return count
end

local function allIn(): boolean
	return left(nil) == 0
end

-- The bar never goes back.
local function reach(share: number)
	progress = math.max(progress, math.clamp(share, 0, 1))
end

-- The share of a stage that runs from `from` to `to` done, as `done` (0 to 1) of it.
local function stage(from: number, to: number, done: number)
	reach(from + (to - from) * math.clamp(done, 0, 1))
end

-- How far the downloads are: what has come in of the most that waited at once since the returned function was made.
local function downloads(): () -> number
	local most = 0
	return function()
		local size = ContentProvider.RequestQueueSize
		most = math.max(most, size)
		return if most > 0 then 1 - size / most else 0
	end
end

-- Waits for the game, the client (Loading.ready) and every download, lets the world render a while behind the screen
-- (its lights take a moment to settle where the camera now stands) and waits until all it will show is in, at most
-- LONGEST seconds; then for whatever holds it (Loading.hold) and again until the screen under it is in, at most HELD
-- seconds; and fades out. The bar shows how far: the game in (to LOADED), the client's own loading by its downloads (to
-- CLIENT), the last downloads (to FETCHED), the world settling (to SETTLED) and the pictures under it (to the end).
local LOADED, CLIENT, FETCHED, SETTLED = 0.1, 0.6, 0.7, 0.85
function Loading.finish()
	local started = os.clock()
	local function late(): boolean
		return os.clock() - started >= LONGEST
	end
	-- Each stage passed into the log, with the seconds since the screen came and whether it gave up waiting.
	local function passed(name: string, data: { [string]: any }?)
		local entry = data or {}
		entry.stage = name
		entry.after = math.floor((os.clock() - started) * 100) / 100
		entry.late = late()
		entry.queue = ContentProvider.RequestQueueSize
		Trace.mark("loading.stage", entry)
	end
	local fetched = downloads()
	while not game:IsLoaded() do
		stage(0, LOADED, fetched())
		task.wait(0.1)
	end
	reach(LOADED)
	passed("loaded")
	fetched = downloads()
	while not readyNow and not late() do
		stage(LOADED, CLIENT, fetched())
		task.wait(0.1)
	end
	reach(CLIENT)
	passed("client")
	fetched = downloads()
	local emptySince = nil
	while not late() do
		stage(CLIENT, FETCHED, fetched())
		if ContentProvider.RequestQueueSize > 0 then
			emptySince = nil
		elseif not emptySince then
			emptySince = os.clock()
		elseif os.clock() - emptySince >= QUIET then
			break
		end
		task.wait(0.1)
	end
	reach(FETCHED)
	passed("fetched")
	local frames, since = 0, os.clock()
	while (frames < SETTLE_FRAMES or os.clock() - since < SETTLE) and not late() do
		RunService.RenderStepped:Wait()
		frames += 1
		stage(FETCHED, SETTLED, math.min(frames / SETTLE_FRAMES, (os.clock() - since) / SETTLE))
	end
	reach(SETTLED)
	passed("settled", { frames = frames })
	local most = 0
	while not late() do
		local count = left(nil)
		most = math.max(most, count)
		if count == 0 then
			break
		end
		stage(SETTLED, 1, 1 - count / most)
		task.wait(0.1)
	end
	reach(1)
	local missing = {}
	passed("pictures", { most = most, left = left(missing), first = missing[1], second = missing[2] })
	readyAll = true
	readySignal:Fire()
	local heldSince = os.clock()
	waiting = holds > 0
	while holds > 0 and os.clock() - heldSince < HELD do
		task.wait(0.05)
	end
	waiting = false
	passed("held", { held = math.floor((os.clock() - heldSince) * 100) / 100, holds = holds })
	local shownSince = os.clock()
	while not allIn() and os.clock() - shownSince < SHOWN do
		task.wait(0.05)
	end
	missing = {}
	passed("gone", { left = left(missing), first = missing[1] })
	local gui = shown
	shown = nil
	gone = true
	covering = false
	goneSignal:Fire()
	-- The cards that came along stay until VersusView puts its own in their place.
	if not gui or gui == cards then
		return
	end
	local group = gui:FindFirstChild("Group")
	local out = group and fade(group, false, 0.5)
	if out then
		out.Completed:Wait()
	end
	gui:Destroy()
end

return Loading
