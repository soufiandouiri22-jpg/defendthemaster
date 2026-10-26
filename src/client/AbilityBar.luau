-- The ability bar at the bottom centre (design 05): a slot per key (M1, M2, E, R, Shift) on a parchment panel, each
-- darkening from the top while its cooldown runs with the seconds left on it, and lighting up while it is held to aim.
-- Under M2, E and R a rank pill ("+", the key that raises it, the rank): with a point to spend the "+" glows, and the
-- key (1, 2, 3) or a click on the pill raises the rank through Net.Upgrade (Shared.Leveling).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local UiStyle = require(script.Parent.UiStyle)

local AbilityBar = {}

local C = UiStyle.Colors
local KEYS = { "M1", "M2", "E", "R", "Dash" }
-- What a slot shows when it is not its kit key.
local LABELS = { Dash = "Shift" }
local UPGRADE_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local SLOT = 104
local GAP = 14
local PILL = 30
local SLOT_TOP = Color3.fromRGB(150, 146, 140)
local SLOT_BOTTOM = Color3.fromRGB(70, 66, 66)

type Slot = {
	frame: Frame,
	stroke: UIStroke,
	glyph: TextLabel,
	shade: Frame,
	seconds: TextLabel,
	endsAt: number,
	total: number,
	plus: TextLabel?,
	rank: TextLabel?,
}

local player = Players.LocalPlayer
local slots: { [string]: Slot } = {}
local upgradeEvent: RemoteEvent?

local function upgrade(key: string)
	if upgradeEvent and Leveling.canRaise(player, key) then
		upgradeEvent:FireServer(key)
	end
end

local function slot(parent: Instance, key: string, index: number): Slot
	local x = GAP + (index - 1) * (SLOT + GAP)
	local frame = UiStyle.frame(parent, UDim2.fromOffset(SLOT, SLOT), UDim2.fromOffset(x, GAP))
	frame.Name = key
	frame.ClipsDescendants = true
	UiStyle.corner(frame, 10)
	UiStyle.gradient(frame, SLOT_TOP, SLOT_BOTTOM)
	local edge = UiStyle.stroke(frame, C.Gold, 3)

	local name = LABELS[key] or key
	local glyph = UiStyle.text(frame, name, if #name > 2 then 28 else 40, C.Cream, C.Edge)
	glyph.Size = UDim2.fromScale(1, 1)

	local shade = UiStyle.frame(frame, UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
	shade.Name = "Cooldown"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.ZIndex = 3
	local seconds = UiStyle.text(frame, "", 44, C.Cream, C.Edge)
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.ZIndex = 4

	local s: Slot = {
		frame = frame,
		stroke = edge,
		glyph = glyph,
		shade = shade,
		seconds = seconds,
		endsAt = 0,
		total = 0,
	}
	local upgradeIndex = table.find(Config.Progress.Upgrades, key)
	if upgradeIndex then
		local pill = Instance.new("TextButton")
		pill.Name = "Rank"
		pill.Text = ""
		pill.AutoButtonColor = false
		pill.Size = UDim2.fromOffset(SLOT, PILL)
		pill.Position = UDim2.fromOffset(x, GAP + SLOT + 8)
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.Parent = parent
		UiStyle.corner(pill, PILL // 2)
		UiStyle.gradient(pill, C.CreamDark, Color3.fromRGB(206, 178, 124))
		UiStyle.stroke(pill, C.GoldDark, 2)
		local plus = UiStyle.text(pill, "+", 24, C.GoldDark)
		plus.Size = UDim2.fromOffset(30, PILL)
		plus.Position = UDim2.fromOffset(4, -1)
		local keyLabel = UiStyle.text(pill, tostring(upgradeIndex), 18, C.Ink)
		keyLabel.Size = UDim2.fromScale(1, 1)
		local rank = UiStyle.text(pill, "1", 18, C.Ink)
		rank.Size = UDim2.fromOffset(30, PILL)
		rank.Position = UDim2.new(1, -32, 0, 0)
		pill.Activated:Connect(function()
			upgrade(key)
		end)
		s.plus, s.rank = plus, rank
	end
	return s
end

-- Shows the ranks, and makes the "+" glow on what can be raised.
local function showRanks()
	for _, key in Config.Progress.Upgrades do
		local s = slots[key]
		if s and s.plus and s.rank then
			s.rank.Text = tostring(Leveling.rank(player, key))
			local can = Leveling.canRaise(player, key)
			s.plus.TextColor3 = if can then Color3.fromRGB(255, 200, 40) else C.GoldDark
			s.plus.TextTransparency = if can then 0 else 0.45
		end
	end
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
		s.stroke.Color = if on then Color3.fromRGB(255, 240, 170) else C.Gold
		s.stroke.Thickness = if on then 5 else 3
	end
end

-- A short flash on `key`'s slot when it is used.
function AbilityBar.used(key: string)
	local s = slots[key]
	if s then
		local home = s.frame.Position
		s.frame.Size = UDim2.fromOffset(SLOT - 8, SLOT - 8)
		s.frame.Position = home + UDim2.fromOffset(4, 4)
		local goal = { Size = UDim2.fromOffset(SLOT, SLOT), Position = home }
		TweenService:Create(s.frame, TweenInfo.new(0.15, Enum.EasingStyle.Back), goal):Play()
	end
end

function AbilityBar.start()
	local gui = UiStyle.screen("AbilityBar", player:WaitForChild("PlayerGui"))
	local width = #KEYS * (SLOT + GAP) + GAP
	local _, inner = UiStyle.panel(
		gui,
		UDim2.fromOffset(width + 10, GAP + SLOT + 8 + PILL + GAP + 10),
		UDim2.new(0.5, 0, 1, -18),
		Vector2.new(0.5, 1),
		16,
		5
	)
	inner.Name = "Panel"

	for i, key in KEYS do
		slots[key] = slot(inner, key, i)
	end

	task.spawn(function()
		upgradeEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Upgrade") :: RemoteEvent
	end)
	player.AttributeChanged:Connect(showRanks)
	showRanks()
	UserInputService.InputBegan:Connect(function(input, processed)
		local index = table.find(UPGRADE_KEYS, input.KeyCode)
		if processed or not index then
			return
		end
		upgrade(Config.Progress.Upgrades[index])
	end)

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
