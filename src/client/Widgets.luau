-- The menu's pieces (designs 07 and 10 to 17), in the HUD's look (UiStyle): parchment panels in gold, dark brown bars
-- with gold edges, glossy buttons in gold, blue, green and purple with lettering in an edge, rank badges, and portraits
-- of the heroes. Sizes are for a 1080-pixel-high screen, as everywhere in the interface.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local Widgets = {}

local C = UiStyle.Colors
Widgets.Colors = {
	Brown = Color3.fromRGB(70, 42, 22),
	BrownDark = Color3.fromRGB(40, 24, 13),
	Parchment = Color3.fromRGB(244, 226, 186),
	Stripe = Color3.fromRGB(226, 200, 150),
	Muted = Color3.fromRGB(128, 96, 62),
	Good = Color3.fromRGB(70, 168, 52),
	Bad = Color3.fromRGB(206, 64, 48),
	Purple = Color3.fromRGB(150, 84, 230),
	Locked = Color3.fromRGB(150, 140, 128),
}
local W = Widgets.Colors

-- Each button kind's fill (top, bottom), its edge and its lettering.
local KINDS = {
	Gold = { Color3.fromRGB(255, 214, 104), Color3.fromRGB(214, 138, 36), C.Edge, Color3.fromRGB(255, 248, 230) },
	Blue = {
		Color3.fromRGB(92, 150, 246),
		Color3.fromRGB(30, 78, 186),
		Color3.fromRGB(18, 34, 84),
		Color3.new(1, 1, 1),
	},
	Green = {
		Color3.fromRGB(126, 204, 72),
		Color3.fromRGB(52, 136, 32),
		Color3.fromRGB(24, 64, 16),
		Color3.new(1, 1, 1),
	},
	Purple = {
		Color3.fromRGB(150, 90, 228),
		Color3.fromRGB(78, 36, 150),
		Color3.fromRGB(36, 16, 70),
		Color3.new(1, 1, 1),
	},
	Dark = { Color3.fromRGB(88, 56, 32), Color3.fromRGB(46, 28, 15), C.GoldDark, C.Cream },
	Cream = { C.Cream, C.CreamDark, C.GoldDark, C.Ink },
	Grey = {
		Color3.fromRGB(170, 160, 148),
		Color3.fromRGB(112, 104, 96),
		Color3.fromRGB(60, 54, 48),
		Color3.fromRGB(240, 236, 230),
	},
}
Widgets.Kinds = KINDS

local function tween(object: Instance, seconds: number, goal: { [string]: any })
	local t = TweenService:Create(object, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end
Widgets.tween = tween

-- Lettering at `size` in `colour`, `align` "Left", "Right" or centred, filling its frame unless given a size.
function Widgets.label(
	parent: Instance,
	value: string,
	size: number,
	colour: Color3?,
	align: string?,
	outline: Color3?
): TextLabel
	local label = UiStyle.text(parent, value, size, colour or C.Ink, outline)
	label.Size = UDim2.fromScale(1, 1)
	if align == "Left" then
		label.TextXAlignment = Enum.TextXAlignment.Left
	elseif align == "Right" then
		label.TextXAlignment = Enum.TextXAlignment.Right
	end
	return label
end

-- A list layout in `parent`: "Vertical" or "Horizontal", `padding` pixels apart.
function Widgets.list(parent: Instance, direction: string, padding: number, align: string?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if direction == "Horizontal"
		then Enum.FillDirection.Horizontal
		else Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if align == "Center" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

function Widgets.padding(parent: Instance, pixels: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, pixels)
	p.PaddingRight = UDim.new(0, pixels)
	p.PaddingTop = UDim.new(0, pixels)
	p.PaddingBottom = UDim.new(0, pixels)
	p.Parent = parent
end

-- A dark brown bar with a gold edge, as the tab bar and the coin counter.
function Widgets.dark(parent: Instance, size: UDim2, position: UDim2?, anchor: Vector2?, radius: number?): Frame
	local f = UiStyle.frame(parent, size, position, anchor)
	UiStyle.corner(f, radius or 10)
	UiStyle.gradient(f, W.Brown, W.BrownDark)
	UiStyle.stroke(f, C.GoldDark, 2.5)
	return f
end

-- A parchment panel (UiStyle.panel) with an optional title strip across its top; returns the panel, its inside, and
-- the space under the title.
function Widgets.panel(
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	title: string?,
	titleSize: number?
): (Frame, Frame, Frame)
	local outer, inner = UiStyle.panel(parent, size, position, anchor, 14, 5)
	local body = inner
	if title then
		local strip = UiStyle.frame(inner, UDim2.new(1, 0, 0, (titleSize or 30) + 14))
		strip.BackgroundTransparency = 1
		local line = UiStyle.frame(strip, UDim2.new(1, -24, 0, 2), UDim2.new(0.5, 0, 1, -1), Vector2.new(0.5, 0))
		line.BackgroundColor3 = C.GoldDark
		line.BackgroundTransparency = 0.4
		local text = Widgets.label(strip, string.upper(title), titleSize or 30, C.Ink)
		text.Name = "Title"
		body = UiStyle.frame(
			inner,
			UDim2.new(1, 0, 1, -((titleSize or 30) + 14)),
			UDim2.fromOffset(0, (titleSize or 30) + 14)
		)
		body.BackgroundTransparency = 1
		body.Name = "Body"
	end
	return outer, inner, body
end

-- A brown ribbon with gold edges and a title in cream (the settings' and the ladder's headings).
function Widgets.ribbon(parent: Instance, value: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local f = Widgets.dark(parent, size, position, anchor, 8)
	f.ZIndex = 5
	local text = Widgets.label(f, value, math.floor(size.Y.Offset * 0.58), C.Cream, nil, C.Edge)
	text.ZIndex = 6
	return f
end

-- Plays the hover cue and grows `button` a little while the mouse is over it, and the pick cue on a click.
function Widgets.feel(button: GuiButton, quiet: boolean?)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		if button.Active then
			tween(scale, 0.1, { Scale = 1.04 })
			UiSound.play("Hover", 0.6)
		end
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			tween(scale, 0.06, { Scale = 0.97 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.1, { Scale = 1.04 })
	end)
	if not quiet then
		button.Activated:Connect(function()
			if button.Active then
				UiSound.play("Pick", 0.8)
			end
		end)
	end
end

-- Paints `button` as the kind `kind` (KINDS).
function Widgets.paint(button: GuiObject, kind: string)
	local k = KINDS[kind] or KINDS.Gold
	local gradient = button:FindFirstChild("Fill") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(k[1], k[2])
	end
	local stroke = button:FindFirstChild("Edge") :: UIStroke?
	if stroke then
		stroke.Color = k[3]
	end
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextColor3 = k[4]
		local edge = label:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = k[3]
			-- Dark ink on cream reads sharpest bare: an edge round it blurs the letters.
			edge.Transparency = if kind == "Cream" then 1 else 0
		end
	end
end

-- A glossy button of `kind` (Gold, Blue, Green, Purple, Dark, Cream, Grey) with `value` on it in lettering `textSize`
-- high. Returns the button and its lettering.
function Widgets.button(
	parent: Instance,
	value: string,
	kind: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?
): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = size
	b.Position = position or UDim2.new()
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Parent = parent
	UiStyle.corner(b, 12)
	local fill = UiStyle.gradient(b, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	fill.Name = "Fill"
	local edge = UiStyle.stroke(b, C.Edge, 3)
	edge.Name = "Edge"
	local shine = UiStyle.frame(b, UDim2.new(1, -12, 0.36, 0), UDim2.new(0, 6, 0.06, 0))
	shine.BackgroundTransparency = if kind == "Dark" or kind == "Cream" then 0.92 else 0.72
	shine.Name = "Shine"
	UiStyle.corner(shine, 8)
	local fontSize = textSize or math.floor(size.Y.Offset * 0.5)
	local label = UiStyle.text(b, value, fontSize, Color3.new(1, 1, 1), C.Edge)
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = math.max(2, fontSize / 12)
	Widgets.paint(b, kind)
	Widgets.feel(b)
	return b, label
end

-- Turns `button` on or off: off it is grey and does nothing.
function Widgets.enable(button: GuiButton, on: boolean, kind: string)
	button.Active = on
	button.AutoButtonColor = false
	Widgets.paint(button, if on then kind else "Grey")
end

-- A square dark button with an image (the back arrow, the settings gear).
function Widgets.iconButton(
	parent: Instance,
	image: string,
	size: number,
	position: UDim2,
	anchor: Vector2?,
	glyph: string?
): ImageButton
	local b = Instance.new("ImageButton")
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(size, size)
	b.Position = position
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Image = ""
	b.Parent = parent
	UiStyle.corner(b, 10)
	UiStyle.gradient(b, W.Brown, W.BrownDark)
	UiStyle.stroke(b, C.GoldDark, 2.5)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.68, 0.68)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Image = image
	icon.Name = "Icon"
	icon.Parent = b
	if image == "" and glyph then
		local text = Widgets.label(b, glyph, math.floor(size * 0.62), C.Cream)
		text.Name = "Glyph"
	end
	Widgets.feel(b)
	return b
end

-- The coins in a dark pill with the coin's image: returns the pill and a function that shows a number.
function Widgets.coins(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): (Frame, (n: number) -> ())
	local pill = Widgets.dark(parent, size, position, anchor, size.Y.Offset // 2)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = require(ReplicatedStorage.Shared.Assets).HudCoin
	icon.Size = UDim2.fromOffset(size.Y.Offset - 14, size.Y.Offset - 14)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Parent = pill
	local text = Widgets.label(pill, "0", math.floor(size.Y.Offset * 0.56), C.Cream, "Left")
	text.Size = UDim2.new(1, -(size.Y.Offset + 8), 1, 0)
	text.Position = UDim2.fromOffset(size.Y.Offset + 2, 0)
	return pill, function(n: number)
		text.Text = UiStyle.thousands(n)
	end
end

-- A row of tabs in a dark bar; `onSelect` runs with a tab's name when it is clicked. Returns the bar and a function
-- that marks a tab chosen.
function Widgets.tabs(
	parent: Instance,
	names: { string },
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	onSelect: (name: string) -> ()
): (Frame, (name: string) -> ())
	local bar = Widgets.dark(parent, size, position, anchor, 10)
	bar.Name = "Tabs"
	local inner = UiStyle.frame(bar, UDim2.new(1, -10, 1, -10), UDim2.fromOffset(5, 5))
	inner.Name = "Row"
	inner.BackgroundTransparency = 1
	Widgets.list(inner, "Horizontal", 4)
	local buttons: { [string]: TextButton } = {}
	local width = 1 / #names
	local textSize = math.floor(size.Y.Offset * 0.44)
	for i, name in names do
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Text = ""
		b.Name = name
		b.LayoutOrder = i
		b.Size = UDim2.new(width, -4 + 4 / #names, 1, 0)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Parent = inner
		UiStyle.corner(b, 7)
		local fill = UiStyle.gradient(b, Color3.fromRGB(255, 210, 104), Color3.fromRGB(206, 130, 36))
		fill.Name = "Fill"
		local text = Widgets.label(b, string.upper(name), textSize, C.Cream)
		text.Name = "Label"
		b.MouseEnter:Connect(function()
			if b.BackgroundTransparency == 1 then
				text.TextColor3 = C.Gold
				UiSound.play("Hover", 0.5)
			end
		end)
		b.MouseLeave:Connect(function()
			if b.BackgroundTransparency == 1 then
				text.TextColor3 = C.Cream
			end
		end)
		b.Activated:Connect(function()
			onSelect(name)
		end)
		buttons[name] = b
	end
	return bar,
		function(chosen: string)
			for name, b in buttons do
				local on = name == chosen
				b.BackgroundTransparency = if on then 0 else 1
				local text = b:FindFirstChild("Label") :: TextLabel
				text.TextColor3 = if on then C.Ink else C.Cream
			end
		end
end

-- A rank's badge: its image from Config.Ranked (the art), or until that exists a shield of the tier's colours.
local TIER_COLOURS = {
	Color3.fromRGB(150, 98, 56),
	Color3.fromRGB(176, 112, 70),
	Color3.fromRGB(150, 150, 156),
	Color3.fromRGB(46, 84, 196),
	Color3.fromRGB(232, 180, 60),
	Color3.fromRGB(176, 44, 40),
	Color3.fromRGB(80, 96, 140),
	Color3.fromRGB(44, 140, 70),
	Color3.fromRGB(240, 140, 40),
	Color3.fromRGB(30, 26, 30),
}

-- A tier's own colour (its badge's) light, as text on a dark plate, and dark; the black Master's are gold.
function Widgets.tierColours(tier: number): (Color3, Color3)
	if tier >= #TIER_COLOURS then
		return C.Gold, C.GoldDark
	end
	local colour = TIER_COLOURS[tier] or C.Gold
	return colour:Lerp(Color3.new(1, 1, 1), 0.4), colour:Lerp(Color3.new(0, 0, 0), 0.3)
end

function Widgets.badge(parent: Instance, tier: number, size: number, position: UDim2?, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(size, size)
	image.Position = position or UDim2.new()
	image.AnchorPoint = anchor or Vector2.zero
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = parent
	local function show(t: number)
		local badge = Ranks.badge(t)
		image.Image = badge
		local fallback = image:FindFirstChild("Fallback")
		if fallback then
			fallback:Destroy()
		end
		if badge == "" then
			local shield =
				UiStyle.frame(image, UDim2.fromScale(0.78, 0.86), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
			shield.Name = "Fallback"
			UiStyle.corner(shield, UDim.new(0.3, 0))
			UiStyle.gradient(
				shield,
				TIER_COLOURS[t] or C.Gold,
				(TIER_COLOURS[t] or C.Gold):Lerp(Color3.new(0, 0, 0), 0.45)
			)
			UiStyle.stroke(shield, C.Gold, math.max(2, size / 22))
			local n = Widgets.label(shield, tostring(t), math.floor(size * 0.42), C.Cream, nil, C.Edge)
			n.Name = "Tier"
		end
	end
	show(tier)
	image:SetAttribute("Tier", tier)
	image:GetAttributeChangedSignal("Tier"):Connect(function()
		show(image:GetAttribute("Tier") :: number)
	end)
	return image
end

-- A Roblox player's head shot.
function Widgets.avatar(parent: Instance, userId: number, size: number, position: UDim2?, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromOffset(size, size)
	image.Position = position or UDim2.new()
	image.AnchorPoint = anchor or Vector2.zero
	image.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
	image.BorderSizePixel = 0
	image.Parent = parent
	UiStyle.corner(image, 8)
	UiStyle.stroke(image, C.GoldDark, 2.5)
	if userId > 0 then
		task.spawn(function()
			local ok, content = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
			if ok then
				image.Image = content
			end
		end)
	end
	return image
end

-- The colours behind a hero's portrait, by his role.
local ROLE_COLOURS: { [string]: { Color3 } } = {
	Assassin = { Color3.fromRGB(96, 50, 150), Color3.fromRGB(28, 16, 46) },
	Mage = { Color3.fromRGB(190, 70, 40), Color3.fromRGB(60, 20, 14) },
	Warrior = { Color3.fromRGB(70, 96, 150), Color3.fromRGB(20, 28, 50) },
	Archer = { Color3.fromRGB(70, 130, 60), Color3.fromRGB(20, 40, 18) },
	Tank = { Color3.fromRGB(60, 130, 190), Color3.fromRGB(16, 36, 60) },
}
function Widgets.roleColour(role: string?): Color3
	local colours = ROLE_COLOURS[role or ""]
	return if colours then colours[1]:Lerp(Color3.new(1, 1, 1), 0.25) else C.Gold
end

-- A hero's painted portrait (Config.Heroes[hero].Portrait, the same as in the HUD and the kill feed): the whole
-- picture, or with `face` only the square round his head and shoulders. Before his role's colours while it loads, or
-- when he has none yet.
local PORTRAIT_SIZE = 1024
function Widgets.portrait(parent: Instance, hero: string, size: UDim2, position: UDim2?, face: boolean?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Size = size
	image.Position = position or UDim2.new()
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Crop
	image.Parent = parent
	local settings = Config.Heroes[hero]
	-- A plain colour: a UIGradient would tint the picture itself as well.
	local colours = ROLE_COLOURS[settings and settings.Role or ""] or { C.Gold, C.GoldDark }
	image.BackgroundColor3 = colours[1]:Lerp(colours[2], 0.5)
	local portrait = settings and settings.Portrait
	if portrait then
		image.Image = portrait.Image
		if face and portrait.Face then
			local x, y, side = table.unpack(portrait.Face)
			image.ImageRectOffset = Vector2.new(x, y)
			image.ImageRectSize = Vector2.new(side, side)
		else
			image.ImageRectSize = Vector2.new(PORTRAIT_SIZE, PORTRAIT_SIZE)
		end
	end
	return image
end

-- What a pass reward (Shared.Pass) is, filling `parent`: coins with their amount, a boost of double XP, or a hero's
-- portrait with his name. Returns a function that shows another reward.
function Widgets.reward(parent: GuiObject): (reward: { [string]: any }) -> ()
	local holder = UiStyle.frame(parent, UDim2.fromScale(1, 1))
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	return function(reward)
		for _, child in holder:GetChildren() do
			child:Destroy()
		end
		if reward.Hero then
			local picture = Widgets.portrait(holder, reward.Hero, UDim2.fromScale(1, 1))
			UiStyle.corner(picture, 6)
			local name = Widgets.label(holder, string.upper(reward.Hero), 24, C.Cream, nil, C.Edge)
			name.Size = UDim2.new(1, 0, 0, 30)
			name.Position = UDim2.new(0, 0, 1, -34)
			name.ZIndex = 3
		elseif reward.Boost then
			local potion = Instance.new("ImageLabel")
			potion.BackgroundTransparency = 1
			potion.Image = require(ReplicatedStorage.Shared.Assets).MenuBoost
			potion.ScaleType = Enum.ScaleType.Fit
			potion.Size = UDim2.fromScale(0.62, 0.46)
			potion.Position = UDim2.fromScale(0.5, 0.1)
			potion.AnchorPoint = Vector2.new(0.5, 0)
			potion.Parent = holder
			local double = Widgets.label(holder, "2X XP", 24, C.Cream, nil, C.Edge)
			double.Size = UDim2.fromScale(1, 0.16)
			double.Position = UDim2.fromScale(0, 0.58)
			local hours = reward.Boost / 3600
			local span = if hours % 1 == 0
				then hours .. (if hours == 1 then " HOUR" else " HOURS")
				else math.round(reward.Boost / 60) .. " MIN"
			local text = Widgets.label(holder, span, 20, C.Cream)
			text.Size = UDim2.fromScale(1, 0.16)
			text.Position = UDim2.fromScale(0, 0.74)
		else
			local coin = Instance.new("ImageLabel")
			coin.BackgroundTransparency = 1
			coin.Image = require(ReplicatedStorage.Shared.Assets).HudCoin
			coin.ScaleType = Enum.ScaleType.Fit
			coin.Size = UDim2.fromScale(0.62, 0.5)
			coin.Position = UDim2.fromScale(0.5, 0.12)
			coin.AnchorPoint = Vector2.new(0.5, 0)
			coin.Parent = holder
			local text = Widgets.label(holder, UiStyle.thousands(reward.Coins or 0), 28, C.Cream, nil, C.Edge)
			text.Size = UDim2.fromScale(1, 0.24)
			text.Position = UDim2.fromScale(0, 0.68)
		end
	end
end

-- How far down the menu's tab bar ends (Lobby.Menu: 64 high, 22 from the top).
Widgets.MenuBarBottom = 86

-- An empty full-width frame `height` high for a screen's blocks, its middle in the middle of the room between `top`
-- (the menu's tab bar unless given) and the bottom of the screen, on every screen.
function Widgets.middle(page: Instance, height: number, top: number?): Frame
	local above = top or Widgets.MenuBarBottom
	local frame = UiStyle.frame(page, UDim2.new(1, 0, 0, height), UDim2.new(0, 0, 0.5, (above - height) / 2))
	frame.BackgroundTransparency = 1
	frame.Name = "Middle"
	return frame
end

-- A frame that only shows while `parent` is visible: a full-screen dark veil behind pop-ups.
function Widgets.veil(parent: Instance, transparency: number?): TextButton
	local veil = Instance.new("TextButton")
	veil.AutoButtonColor = false
	veil.Text = ""
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = transparency or 0.45
	veil.BorderSizePixel = 0
	veil.Parent = parent
	return veil
end

-- A full-screen holder for a pop-up over `gui`, in a ScreenGui of its own just above it: the menu's ScreenGui draws its
-- pieces by one global ZIndex, so inside it a page's raised texts (filters, button lettering) would show through the
-- pop-up. Destroying the holder takes its ScreenGui with it.
function Widgets.popup(gui: Instance, name: string): Frame
	local base = if gui:IsA("ScreenGui") then gui else gui:FindFirstAncestorOfClass("ScreenGui")
	local parent = if base and base.Parent then base.Parent else Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = UiStyle.screen(name, parent, (if base then base.DisplayOrder else 0) + 5)
	local holder = UiStyle.frame(screen, UDim2.fromScale(1, 1))
	holder.BackgroundTransparency = 1
	holder.Name = name
	holder.Destroying:Connect(function()
		screen:Destroy()
	end)
	return holder
end

-- A question over the whole screen of `gui` (buying a hero): `title`, `text`, and a `yes` button of `kind` beside
-- CANCEL; `onYes` runs when it is clicked. Clicking the veil or CANCEL closes it.
function Widgets.confirm(gui: Instance, title: string, text: string, yes: string, kind: string, onYes: () -> ())
	local holder = Widgets.popup(gui, "Confirm")
	local veil = Widgets.veil(holder, 0.4)
	local outer, _, body =
		Widgets.panel(holder, UDim2.fromOffset(620, 320), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), title, 34)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = outer
	tween(scale, 0.18, { Scale = 1 })
	local message = Widgets.label(body, text, 30, C.Ink)
	message.Size = UDim2.new(1, -60, 0, 120)
	message.Position = UDim2.fromOffset(30, 6)
	message.TextWrapped = true
	local function close()
		holder:Destroy()
	end
	local cancel = Widgets.button(
		body,
		"CANCEL",
		"Cream",
		UDim2.fromOffset(240, 76),
		UDim2.new(0.5, -12, 1, -24),
		Vector2.new(1, 1),
		32
	)
	local ok =
		Widgets.button(body, yes, kind, UDim2.fromOffset(240, 76), UDim2.new(0.5, 12, 1, -24), Vector2.new(0, 1), 32)
	veil.Activated:Connect(close)
	cancel.Activated:Connect(close)
	ok.Activated:Connect(function()
		close()
		onYes()
	end)
end

-- A small gold padlock (Assets.MenuLock) on what is locked.
function Widgets.lock(parent: Instance, size: number, position: UDim2, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = require(ReplicatedStorage.Shared.Assets).MenuLock
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromOffset(size, size)
	image.Position = position
	image.AnchorPoint = anchor or Vector2.zero
	image.Name = "Lock"
	image.ZIndex = 4
	image.Parent = parent
	return image
end

-- A coin with a number after it (a price), filling `parent` in a row, centred.
function Widgets.price(parent: Instance, amount: number, size: number, colour: Color3?): Frame
	local row = UiStyle.frame(parent, UDim2.fromScale(1, 1))
	row.BackgroundTransparency = 1
	local layout = Widgets.list(row, "Horizontal", 6, "Center")
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local coin = Instance.new("ImageLabel")
	coin.BackgroundTransparency = 1
	coin.Image = require(ReplicatedStorage.Shared.Assets).HudCoin
	coin.Size = UDim2.fromOffset(size, size)
	coin.LayoutOrder = 1
	coin.Parent = row
	local text = UiStyle.text(row, UiStyle.thousands(amount), size, colour or C.Ink)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, size)
	text.LayoutOrder = 2
	return row
end

-- A slider from 0 to 1 at `value`; `onChange` runs with each new value. Returns the frame and a function to set it.
function Widgets.slider(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	value: number,
	onChange: (value: number) -> ()
): (Frame, (value: number) -> ())
	local track = UiStyle.frame(parent, size, position)
	track.BackgroundColor3 = W.BrownDark
	UiStyle.corner(track, size.Y.Offset // 2)
	UiStyle.stroke(track, C.Edge, 2)
	local fill = UiStyle.frame(track, UDim2.fromScale(value, 1))
	UiStyle.corner(fill, size.Y.Offset // 2)
	UiStyle.gradient(fill, Color3.fromRGB(255, 210, 90), Color3.fromRGB(222, 150, 30))
	local knob = UiStyle.frame(
		track,
		UDim2.fromOffset(size.Y.Offset + 14, size.Y.Offset + 14),
		UDim2.fromScale(value, 0.5),
		Vector2.new(0.5, 0.5)
	)
	knob.ZIndex = 3
	UiStyle.corner(knob, 6)
	UiStyle.gradient(knob, Color3.fromRGB(255, 220, 110), Color3.fromRGB(214, 140, 30))
	UiStyle.stroke(knob, C.Edge, 2.5)
	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 20, 1, 24)
	hit.Position = UDim2.fromOffset(-10, -12)
	hit.ZIndex = 4
	hit.Parent = track
	local current = value
	local function set(v: number)
		current = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		knob.Position = UDim2.fromScale(current, 0.5)
	end
	local dragging = false
	local function follow(x: number)
		local share = (x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
		share = math.round(math.clamp(share, 0, 1) * 100) / 100
		if share ~= current then
			set(share)
			onChange(share)
		end
	end
	hit.MouseButton1Down:Connect(function(x)
		dragging = true
		follow(x)
	end)
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			follow(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	return track, set
end

-- An on/off switch; `onChange` runs with each new state. Returns the switch and a function to set it.
function Widgets.toggle(
	parent: Instance,
	position: UDim2,
	anchor: Vector2?,
	on: boolean,
	onChange: (on: boolean) -> ()
): (TextButton, (on: boolean) -> ())
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.fromOffset(110, 46)
	b.Position = position
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Parent = parent
	UiStyle.corner(b, 23)
	local fill = UiStyle.gradient(b, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	UiStyle.stroke(b, C.Edge, 2.5)
	local text = Widgets.label(b, "ON", 24, Color3.new(1, 1, 1), nil, C.Edge)
	text.Size = UDim2.new(1, -46, 1, 0)
	local knob = UiStyle.frame(b, UDim2.fromOffset(36, 36), UDim2.new(1, -5, 0.5, 0), Vector2.new(1, 0.5))
	UiStyle.corner(knob, 18)
	knob.BackgroundColor3 = Color3.fromRGB(250, 246, 236)
	local state = on
	local function set(v: boolean)
		state = v
		local k = if v then KINDS.Green else KINDS.Grey
		fill.Color = ColorSequence.new(k[1], k[2])
		text.Text = if v then "ON" else "OFF"
		text.Position = if v then UDim2.fromOffset(4, 0) else UDim2.fromOffset(42, 0)
		knob.AnchorPoint = if v then Vector2.new(1, 0.5) else Vector2.new(0, 0.5)
		knob.Position = if v then UDim2.new(1, -5, 0.5, 0) else UDim2.new(0, 5, 0.5, 0)
	end
	set(on)
	b.Activated:Connect(function()
		set(not state)
		UiSound.play("Pick", 0.7)
		onChange(state)
	end)
	return b, set
end

-- Runs `callback` every `seconds` while `instance` is in the game.
function Widgets.every(instance: Instance, seconds: number, callback: () -> ())
	task.spawn(function()
		while instance.Parent do
			callback()
			task.wait(seconds)
		end
	end)
end

-- "2d 14h", "8h 42m", "3:05".
function Widgets.left(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return string.format("%dD %dH", s // 86400, (s % 86400) // 3600)
	elseif s >= 3600 then
		return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- A shimmer that moves over `frame` again and again (a reward ready to claim, the PLAY button).
function Widgets.shimmer(frame: GuiObject)
	local glint = UiStyle.frame(frame, UDim2.fromScale(0.25, 1), UDim2.fromScale(-0.3, 0))
	glint.BackgroundTransparency = 0.75
	glint.ZIndex = (frame.ZIndex or 1) + 1
	glint.Rotation = 12
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = glint
	frame.ClipsDescendants = true
	task.spawn(function()
		while glint.Parent do
			glint.Position = UDim2.fromScale(-0.3, 0)
			local t = TweenService:Create(
				glint,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine),
				{ Position = UDim2.fromScale(1.1, 0) }
			)
			t:Play()
			t.Completed:Wait()
			task.wait(2.2)
		end
	end)
end

Widgets.heartbeat = RunService.Heartbeat

-- A hero's mastery crest (Assets.MasteryCrests: one per level up to Config.Mastery.Title, the last one after it) with
-- the level on its wooden plate.
function Widgets.crest(parent: Instance, level: number, size: number, position: UDim2?, anchor: Vector2?): ImageLabel
	local crests = Assets.MasteryCrests
	local image = Instance.new("ImageLabel")
	image.Name = "Crest"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(size, size)
	image.Position = position or UDim2.new()
	image.AnchorPoint = anchor or Vector2.zero
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = crests[math.clamp(level, 1, #crests)]
	image.Parent = parent
	local number = Widgets.label(image, tostring(level), math.max(12, math.floor(size * 0.2)), C.Cream, nil, C.Edge)
	number.Name = "Level"
	number.Size = UDim2.fromScale(0.5, 0.17)
	number.AnchorPoint = Vector2.new(0.5, 0.5)
	number.Position = UDim2.fromScale(0.5, 0.875)
	number.ZIndex = image.ZIndex + 1
	return image
end

return Widgets
