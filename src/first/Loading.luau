-- The loading screen: one picture of a fight in the colosseum with the game's logo in it, LOADING and a running bar under
-- it. It lives in ReplicatedFirst
-- so it is up before anything else: on joining (LoadingScreen) it stays until the client has loaded what its first look
-- shows (Loading.ready, from the client once its world and pictures are in), nothing is downloading any more and the
-- world has rendered a moment behind it, or after LONGEST seconds; and a teleport carries
-- the same screen across (Loading.forTeleport), so going from a match to the lobby or back never shows a half-built
-- world.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Loading = {}

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

local readyNow = false
local shown: ScreenGui? = nil
local gone = false
local goneSignal = Instance.new("BindableEvent")

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

-- A new loading screen.
function Loading.build(): ScreenGui
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
	return gui
end

-- Shows the screen that came with a teleport, or a new one, in place of Roblox's own, with its bar running.
function Loading.show()
	local gui = TeleportService:GetArrivingTeleportGui() or Loading.build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
	-- The picture, the logo, LOADING and the bar come in together once the pictures have loaded (at once when they came
	-- along with a teleport), or after PICTURES seconds.
	local content = gui:FindFirstChild("Content", true)
	local art = gui:FindFirstChild("Art", true) :: ImageLabel?
	local logo = gui:FindFirstChild("Logo", true) :: ImageLabel?
	local glow = gui:FindFirstChild("Glow", true) :: ImageLabel?
	if art then
		fit(art, gui.AbsoluteSize)
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fit(art, gui.AbsoluteSize)
		end)
	end
	if content and art and logo and glow and not (art.IsLoaded and logo.IsLoaded and glow.IsLoaded) then
		fade(content, false, 0)
		task.spawn(function()
			local done = false
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, { art, logo, glow })
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
	if fill then
		fill.Position = UDim2.fromScale(-0.3, 0)
		TweenService:Create(
			fill,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
			{ Position = UDim2.fromScale(1, 0) }
		):Play()
	end
	shown = gui
end

-- Takes this screen along on any teleport from here.
function Loading.forTeleport()
	TeleportService:SetTeleportGui(Loading.build())
end

-- Loads `instances` (and everything in them) and the pictures of the content ids among them, or gives up after
-- `seconds`.
function Loading.preload(instances: { Instance | string }, seconds: number)
	local done = false
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, instances)
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < seconds do
		task.wait(0.1)
	end
end

-- The client has what its first look shows: the screen may go.
function Loading.ready()
	readyNow = true
end

-- Waits until the screen starts to fade away (at once when it already has): what comes after it, the music, starts
-- then.
function Loading.waitGone()
	if not gone then
		goneSignal.Event:Wait()
	end
end

-- Waits for the game, the client (Loading.ready) and every download, then lets the world render a while behind the
-- screen (its lights take a moment to settle where the camera now stands), at most LONGEST seconds, and fades out.
function Loading.finish()
	local started = os.clock()
	local function late(): boolean
		return os.clock() - started >= LONGEST
	end
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	while not readyNow and not late() do
		task.wait(0.1)
	end
	local emptySince = nil
	while not late() do
		if ContentProvider.RequestQueueSize > 0 then
			emptySince = nil
		elseif not emptySince then
			emptySince = os.clock()
		elseif os.clock() - emptySince >= QUIET then
			break
		end
		task.wait(0.1)
	end
	local frames, since = 0, os.clock()
	while (frames < SETTLE_FRAMES or os.clock() - since < SETTLE) and not late() do
		RunService.RenderStepped:Wait()
		frames += 1
	end
	local gui = shown
	shown = nil
	gone = true
	goneSignal:Fire()
	if not gui then
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
