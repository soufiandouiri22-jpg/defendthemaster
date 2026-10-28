-- The look of the HUD (design 05): cream parchment panels in a gold frame with a dark brown edge, dark bars with a
-- glossy fill, and FredokaOne lettering in dark brown. Sizes are for a 1080-pixel-high screen; `scaled` fits a
-- ScreenGui to the real one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local UiStyle = {}

UiStyle.Font = Enum.Font.FredokaOne
UiStyle.Colors = {
	Cream = Color3.fromRGB(252, 242, 214),
	CreamDark = Color3.fromRGB(232, 210, 164),
	Gold = Color3.fromRGB(228, 178, 84),
	GoldDark = Color3.fromRGB(156, 104, 38),
	Edge = Color3.fromRGB(70, 42, 20),
	Ink = Color3.fromRGB(64, 40, 22),
	Night = Color3.fromRGB(30, 28, 36),
	Health = Color3.fromRGB(112, 222, 72),
	HealthDark = Color3.fromRGB(46, 160, 40),
	Xp = Color3.fromRGB(255, 214, 64),
	XpDark = Color3.fromRGB(226, 150, 20),
	-- What a hit takes off a health bar, for a moment (UiStyle.bar's trail).
	Trail = Color3.fromRGB(255, 92, 72),
	Blue = Config.Teams.Blue.Color,
	BlueDark = Config.Teams.Blue.DarkColor,
	Red = Config.Teams.Red.Color,
	RedDark = Config.Teams.Red.DarkColor,
}
local C = UiStyle.Colors

local REFERENCE_HEIGHT = 1080

-- Scales everything in `gui` with the screen's height.
function UiStyle.scaled(gui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function fit()
		local camera = Workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
		scale.Scale = math.clamp(height / REFERENCE_HEIGHT, 0.55, 1.25)
	end
	fit()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

-- The blocks along the bottom (the hero's panel, the ability bar) at this share of their drawn size.
UiStyle.BottomScale = 0.76

-- Draws `frame` at `scale` of its size, round its anchor point.
function UiStyle.shrink(frame: GuiObject, scale: number)
	local s = Instance.new("UIScale")
	s.Scale = scale
	s.Parent = frame
end

function UiStyle.screen(name: string, parent: Instance, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = order or 0
	gui.Parent = parent
	UiStyle.scaled(gui)
	return gui
end

function UiStyle.corner(parent: Instance, radius: number | UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius)
	c.Parent = parent
end

function UiStyle.stroke(parent: Instance, colour: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UiStyle.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

function UiStyle.frame(parent: Instance, size: UDim2, position: UDim2?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position or UDim2.new()
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- Lettering in the HUD's font; `outline` draws a dark edge round it.
function UiStyle.text(parent: Instance, value: string, size: number, colour: Color3, outline: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UiStyle.Font
	label.Text = value
	label.TextSize = size
	label.TextColor3 = colour
	label.Parent = parent
	if outline then
		local edge = Instance.new("UIStroke")
		edge.Color = outline
		edge.Thickness = math.max(1.5, size / 14)
		edge.Parent = label
	end
	return label
end

-- A parchment panel in a gold frame: returns the frame and the cream inside, `border` pixels in.
function UiStyle.panel(
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	radius: number?,
	border: number?
): (Frame, Frame)
	local r, b = radius or 14, border or 5
	local outer = UiStyle.frame(parent, size, position, anchor)
	UiStyle.corner(outer, r)
	UiStyle.gradient(outer, C.Gold, C.GoldDark)
	UiStyle.stroke(outer, C.Edge, 2.5)
	local inner = UiStyle.frame(outer, UDim2.new(1, -2 * b, 1, -2 * b), UDim2.fromOffset(b, b))
	UiStyle.corner(inner, math.max(2, r - b))
	UiStyle.gradient(inner, C.Cream, C.CreamDark)
	return outer, inner
end

export type Bar = {
	frame: Frame,
	fill: Frame,
	set: (self: Bar, share: number) -> (),
}

-- A health bar's lost part stays in `trail` colour this long after a hit, then drains in TRAIL_DRAIN seconds.
local TRAIL_HOLD, TRAIL_DRAIN = 0.35, 0.4

-- A dark bar with a glossy fill from `top` to `bottom` and a dark edge; `set` fills a share of it. With `trail`, what
-- the fill loses shows in that colour for a moment before it drains away (a hit on a health bar).
function UiStyle.bar(
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	top: Color3,
	bottom: Color3,
	anchor: Vector2?,
	rightToLeft: boolean?,
	trail: Color3?
): Bar
	local frame = UiStyle.frame(parent, size, position, anchor)
	frame.BackgroundColor3 = C.Night
	frame.ClipsDescendants = true
	UiStyle.corner(frame, 6)
	UiStyle.stroke(frame, C.Edge, 3)
	local lag: Frame? = nil
	if trail then
		local made = UiStyle.frame(frame, UDim2.fromScale(1, 1))
		made.Name = "Trail"
		made.BackgroundColor3 = trail
		UiStyle.corner(made, 5)
		lag = made
	end
	local fill = UiStyle.frame(frame, UDim2.fromScale(1, 1))
	fill.Name = "Fill"
	for _, f in { fill, lag } do
		if rightToLeft then
			f.AnchorPoint = Vector2.new(1, 0)
			f.Position = UDim2.fromScale(1, 0)
		end
	end
	UiStyle.corner(fill, 5)
	UiStyle.gradient(fill, top, bottom)
	local shine = UiStyle.frame(fill, UDim2.new(1, -8, 0.32, 0), UDim2.new(0, 4, 0.1, 0))
	shine.BackgroundTransparency = 0.6
	UiStyle.corner(shine, 4)
	local bar = { frame = frame, fill = fill }
	local current = 1
	local drain: Tween? = nil
	function bar.set(self: Bar, share: number)
		local s = math.clamp(share, 0, 1)
		self.fill.Size = UDim2.fromScale(s, 1)
		self.fill.Visible = s > 0
		if lag and s ~= current then
			if drain then
				drain:Cancel()
			end
			if s > current or lag.Size.X.Scale < s then
				lag.Size = UDim2.fromScale(s, 1)
			else
				local info =
					TweenInfo.new(TRAIL_DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, TRAIL_HOLD)
				drain = TweenService:Create(lag, info, { Size = UDim2.fromScale(s, 1) })
				drain:Play()
			end
			lag.Visible = s > 0 or lag.Size.X.Scale > 0
		end
		current = s
	end
	return bar :: Bar
end

-- "1,250".
function UiStyle.thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "4:12".
function UiStyle.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return UiStyle
