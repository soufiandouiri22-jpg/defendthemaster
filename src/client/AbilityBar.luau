-- The ability bar at the bottom centre (design 05): a slot per key (M1, M2, E, R, Shift) in a dark wooden panel with gold
-- trim, each darkening from the top while its cooldown runs with the seconds left on it, lighting up while it is held
-- to aim, and over a small rank row ("+", the key, the rank). The ranks come with the upgrades (1, 2, 3).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AbilityBar = {}

local KEYS = { "M1", "M2", "E", "R", "Dash" }
-- What a slot shows when it is not its kit key.
local LABELS = { Dash = "Shift" }
local SLOT = 78
local GAP = 12
local GOLD = Color3.fromRGB(226, 182, 92)
local GOLD_DARK = Color3.fromRGB(122, 86, 34)
local WOOD = Color3.fromRGB(58, 40, 26)
local WOOD_DARK = Color3.fromRGB(32, 22, 15)
local INK = Color3.fromRGB(250, 238, 210)

type Slot = {
	frame: Frame,
	stroke: UIStroke,
	glyph: TextLabel,
	shade: Frame,
	seconds: TextLabel,
	endsAt: number,
	total: number,
}

local slots: { [string]: Slot } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, colour: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
end

local function text(parent: Instance, value: string, size: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = value
	label.TextSize = size
	label.TextColor3 = colour
	label.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Color = WOOD_DARK
	outline.Thickness = 1.5
	outline.Parent = label
	return label
end

local function slot(parent: Instance, key: string, index: number): Slot
	local x = (index - 1) * (SLOT + GAP) + GAP
	local frame = Instance.new("Frame")
	frame.Name = key
	frame.Size = UDim2.fromOffset(SLOT, SLOT)
	frame.Position = UDim2.fromOffset(x, 12)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.ClipsDescendants = true
	frame.Parent = parent
	corner(frame, 8)
	gradient(frame, Color3.fromRGB(96, 92, 88), Color3.fromRGB(36, 34, 34))
	local edge = stroke(frame, GOLD, 2)

	local name = LABELS[key] or key
	local glyph = text(frame, name, if #name > 2 then 20 else 30, INK)
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.TextTransparency = 0.1

	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.Parent = frame
	local seconds = text(frame, "", 26, INK)
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.ZIndex = 3

	local row = Instance.new("Frame")
	row.Name = "Rank"
	row.Size = UDim2.fromOffset(SLOT, 22)
	row.Position = UDim2.fromOffset(x, 12 + SLOT + 6)
	row.BackgroundColor3 = WOOD_DARK
	row.Parent = parent
	corner(row, 11)
	stroke(row, GOLD_DARK, 1.5)
	local plus = text(row, "+", 16, GOLD)
	plus.Size = UDim2.fromOffset(22, 22)
	local label = text(row, name, if #name > 2 then 12 else 14, INK)
	label.Size = UDim2.new(1, -44, 1, 0)
	label.Position = UDim2.fromOffset(22, 0)
	local rank = text(row, "1", 14, GOLD)
	rank.Size = UDim2.fromOffset(22, 22)
	rank.Position = UDim2.new(1, -22, 0, 0)

	return { frame = frame, stroke = edge, glyph = glyph, shade = shade, seconds = seconds, endsAt = 0, total = 0 }
end

-- The cooldown of `key` ends `seconds` from now.
function AbilityBar.cooldown(key: string, seconds: number)
	local s = slots[key]
	if s then
		s.endsAt = os.clock() + seconds
		s.total = seconds
	end
end

-- Lights `key`'s slot while it is held to aim.
function AbilityBar.aiming(key: string, on: boolean)
	local s = slots[key]
	if s then
		s.stroke.Color = if on then Color3.fromRGB(255, 236, 170) else GOLD
		s.stroke.Thickness = if on then 3.5 else 2
	end
end

-- A short flash on `key`'s slot when it is used.
function AbilityBar.used(key: string)
	local s = slots[key]
	if s then
		s.frame.Size = UDim2.fromOffset(SLOT - 6, SLOT - 6)
		s.frame.Position += UDim2.fromOffset(3, 3)
		local goal = { Size = UDim2.fromOffset(SLOT, SLOT), Position = s.frame.Position - UDim2.fromOffset(3, 3) }
		TweenService:Create(s.frame, TweenInfo.new(0.15, Enum.EasingStyle.Back), goal):Play()
	end
end

function AbilityBar.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AbilityBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local width = #KEYS * (SLOT + GAP) + GAP
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -18)
	panel.Size = UDim2.fromOffset(width, SLOT + 46)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BackgroundTransparency = 0.05
	panel.Parent = gui
	corner(panel, 12)
	gradient(panel, WOOD, WOOD_DARK)
	stroke(panel, GOLD, 2.5)

	for i, key in KEYS do
		slots[key] = slot(panel, key, i)
	end

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, s in slots do
			local left = s.endsAt - now
			if left > 0 and s.total > 0 then
				s.shade.Size = UDim2.fromScale(1, left / s.total)
				s.seconds.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
				s.glyph.Visible = false
			else
				s.shade.Size = UDim2.fromScale(1, 0)
				s.seconds.Text = ""
				s.glyph.Visible = true
			end
		end
	end)
end

return AbilityBar
