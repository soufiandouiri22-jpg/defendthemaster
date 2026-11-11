-- The ability bar at the bottom centre (design 05): a slot per key (M1, M2, E, R, Shift) on a parchment panel, with the
-- hero's icon for it (Config.Heroes[hero].Icons) over the key (M1 and M2 as the mouse with that button lit), each darkening from the top while its cooldown runs with the seconds left on it, and lighting up while it is held to aim.
-- Under M2, E and R a pill with the ability's rank as pips; with a point to spend it lights up with the key that
-- raises it (1, 2, 3) and the slot pulses in a gold glow, which, or a click on the pill, raises the rank through Net.Upgrade (Shared.Leveling). An
-- ability not learned yet shows its icon greyed out. A rank raised rings like an anvil, and the ultimate (R) coming off
-- its cooldown sounds a blade drawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local AbilityBar = {}

local C = UiStyle.Colors
local KEYS = { "M1", "M2", "E", "R", "Dash" }
-- What a slot shows when it is not its kit key; the mouse's buttons show as the mouse with that button lit.
local LABELS = { Dash = "Shift" }
local MOUSE = { M1 = Assets.MouseLeft, M2 = Assets.MouseRight }
local UPGRADE_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local SLOT = 104
local GAP = 14
local PILL = 30
-- A rank pip, and the step from one to the next.
local PIP, PIP_STEP = 11, 13
local SLOT_TOP = Color3.fromRGB(250, 238, 206)
local SLOT_BOTTOM = Color3.fromRGB(222, 196, 146)

type Slot = {
	frame: Frame,
	-- Where the slot belongs on the panel, which the flash of `used` always returns it to.
	home: UDim2,
	stroke: UIStroke,
	glyph: TextLabel,
	icon: ImageLabel,
	shade: Frame,
	seconds: TextLabel,
	endsAt: number,
	total: number,
	cooling: boolean,
	rank: Rank?,
}

-- The pill under a slot that can be raised: its rank as pips (Progress.MaxRank); with a point to spend it lights up gold, with the
-- key that raises it on the left and a "+" on the right.
type Rank = {
	pill: TextButton,
	gradient: UIGradient,
	stroke: UIStroke,
	pips: { Frame },
	key: Frame,
	plus: TextLabel,
	glow: Frame,
	flash: Frame,
	ready: boolean,
}

-- The glow round a slot that can be raised: how far it reaches past the slot, its colour, and its pulses a second.
local GLOW = 7
local GLOW_COLOUR = Color3.fromRGB(255, 214, 80)
local GLOW_RATE = 1.2

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
	local upgradeIndex = table.find(Config.Progress.Upgrades, key)
	-- Made before the slot, so it lies behind it and shows only as a rim round it.
	local glow = nil
	if upgradeIndex then
		glow = UiStyle.frame(
			parent,
			UDim2.fromOffset(SLOT + GLOW * 2, SLOT + GLOW * 2),
			UDim2.fromOffset(x - GLOW, GAP - GLOW)
		)
		glow.Name = "Glow"
		glow.BackgroundColor3 = GLOW_COLOUR
		glow.BackgroundTransparency = 1
		UiStyle.corner(glow, 10 + GLOW)
	end
	local frame = UiStyle.frame(parent, UDim2.fromOffset(SLOT, SLOT), UDim2.fromOffset(x, GAP))
	frame.Name = key
	frame.ClipsDescendants = true
	UiStyle.corner(frame, 10)
	UiStyle.gradient(frame, SLOT_TOP, SLOT_BOTTOM)
	local edge = UiStyle.stroke(frame, C.GoldDark, 3)

	local name = LABELS[key] or key
	-- Until the hero's icon is known, the key stands large in the slot; then small at its foot, under the icon.
	local glyph = UiStyle.text(frame, name, if #name > 2 then 28 else 40, C.Ink, C.Cream)
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.ZIndex = 5
	if MOUSE[key] then
		glyph.Text = ""
		local mouse = Instance.new("ImageLabel")
		mouse.Name = "Mouse"
		mouse.BackgroundTransparency = 1
		mouse.Image = MOUSE[key]
		mouse.ScaleType = Enum.ScaleType.Fit
		mouse.Size = UDim2.fromScale(1, 0.7)
		mouse.Position = UDim2.fromScale(0.5, 0.5)
		mouse.AnchorPoint = Vector2.one / 2
		mouse.ZIndex = 5
		mouse.Parent = glyph
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, -12, 1, -12)
	icon.Position = UDim2.fromOffset(6, 2)
	icon.Visible = false
	icon.Parent = frame

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
		home = frame.Position,
		stroke = edge,
		glyph = glyph,
		icon = icon,
		shade = shade,
		seconds = seconds,
		endsAt = 0,
		total = 0,
		cooling = false,
	}
	if upgradeIndex and glow then
		-- A gold field over the icon that blinks while it can be raised.
		local flash = UiStyle.frame(frame, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
		flash.Name = "Flash"
		flash.BackgroundColor3 = GLOW_COLOUR
		flash.BackgroundTransparency = 1
		flash.ZIndex = 2
		local pill = Instance.new("TextButton")
		pill.Name = "Rank"
		pill.Text = ""
		pill.AutoButtonColor = false
		pill.Size = UDim2.fromOffset(SLOT, PILL)
		pill.Position = UDim2.fromOffset(x, GAP + SLOT + 8)
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.Parent = parent
		UiStyle.corner(pill, PILL // 2)
		local gradient = UiStyle.gradient(pill, C.CreamDark, Color3.fromRGB(206, 178, 124))
		local stroke = UiStyle.stroke(pill, C.GoldDark, 2)
		local pips = {}
		local most = Config.Progress.MaxRank
		for i = 1, most do
			local along = (i - (most + 1) / 2) * PIP_STEP
			local pip = UiStyle.frame(pill, UDim2.fromOffset(PIP, PIP), UDim2.new(0.5, along, 0.5, 0), Vector2.one / 2)
			UiStyle.corner(pip, UDim.new(0.5, 0))
			UiStyle.stroke(pip, C.Edge, 1.5)
			table.insert(pips, pip)
		end
		local keycap = UiStyle.frame(pill, UDim2.fromOffset(22, 22), UDim2.new(0, 5, 0.5, 0), Vector2.new(0, 0.5))
		keycap.BackgroundColor3 = C.Cream
		UiStyle.corner(keycap, 5)
		UiStyle.stroke(keycap, C.Edge, 1.5)
		local keyLabel = UiStyle.text(keycap, tostring(upgradeIndex), 16, C.Ink)
		keyLabel.Size = UDim2.fromScale(1, 1)
		local plus = UiStyle.text(pill, "+", 26, C.Cream, C.Edge)
		plus.Size = UDim2.fromOffset(24, PILL)
		plus.Position = UDim2.new(1, -27, 0, -1)
		pill.Activated:Connect(function()
			upgrade(key)
		end)
		s.rank = {
			pill = pill,
			gradient = gradient,
			stroke = stroke,
			pips = pips,
			key = keycap,
			plus = plus,
			glow = glow,
			flash = flash,
			ready = false,
		}
	end
	return s
end

-- Shows the ranks, greys out what is not learned yet, and lights up what can be raised.
local function showRanks()
	for _, key in Config.Progress.Upgrades do
		local r = slots[key] and slots[key].rank
		if r then
			local rank = Leveling.rank(player, key)
			local s = slots[key]
			s.icon.ImageColor3 = if rank >= 1 then Color3.new(1, 1, 1) else Color3.fromRGB(90, 84, 78)
			s.icon.ImageTransparency = if rank >= 1 then 0 else 0.35
			for i, pip in r.pips do
				pip.BackgroundColor3 = if i <= rank then Color3.fromRGB(255, 196, 48) else Color3.fromRGB(120, 96, 70)
			end
			local can = Leveling.canRaise(player, key)
			r.key.Visible, r.plus.Visible = can, can
			r.gradient.Color = if can
				then ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(226, 150, 30))
				else ColorSequence.new(C.CreamDark, Color3.fromRGB(206, 178, 124))
			r.stroke.Color = if can then Color3.fromRGB(255, 244, 200) else C.GoldDark
			r.stroke.Thickness = if can then 3 else 2
			r.ready = can
			if not can then
				r.glow.BackgroundTransparency = 1
				r.flash.BackgroundTransparency = 1
			end
		end
	end
end

-- Puts the icons of `hero`'s kit in the slots.
local function showIcons(hero: string?)
	local icons = hero and Config.Heroes[hero] and Config.Heroes[hero].Icons or {}
	for key, s in slots do
		local image = icons[key]
		s.icon.Image = image or ""
		s.icon.Visible = image ~= nil
		local name = LABELS[key] or key
		local mouse = s.glyph:FindFirstChild("Mouse") :: ImageLabel?
		if mouse then
			mouse.Size = if image then UDim2.fromScale(1, 1.25) else UDim2.fromScale(1, 0.7)
		end
		if image then
			s.glyph.TextSize = 18
			s.glyph.Size = UDim2.new(1, 0, 0, 22)
			s.glyph.Position = UDim2.new(0, 0, 1, -24)
		else
			s.glyph.TextSize = if #name > 2 then 28 else 40
			s.glyph.Size = UDim2.fromScale(1, 1)
			s.glyph.Position = UDim2.new()
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
		s.stroke.Color = if on then Color3.fromRGB(255, 226, 120) else C.GoldDark
		s.stroke.Thickness = if on then 5 else 3
	end
end

-- A short flash on `key`'s slot when it is used.
function AbilityBar.used(key: string)
	local s = slots[key]
	if s then
		s.frame.Size = UDim2.fromOffset(SLOT - 8, SLOT - 8)
		s.frame.Position = s.home + UDim2.fromOffset(4, 4)
		local goal = { Size = UDim2.fromOffset(SLOT, SLOT), Position = s.home }
		TweenService:Create(s.frame, TweenInfo.new(0.15, Enum.EasingStyle.Back), goal):Play()
	end
end

function AbilityBar.start()
	local gui = UiStyle.screen("AbilityBar", player:WaitForChild("PlayerGui"))
	local width = #KEYS * (SLOT + GAP) + GAP
	local outer, inner = UiStyle.panel(
		gui,
		UDim2.fromOffset(width + 10, GAP + SLOT + 8 + PILL + GAP + 10),
		UDim2.new(0.5, 0, 1, -18),
		Vector2.new(0.5, 1),
		16,
		5
	)
	UiStyle.shrink(outer, UiStyle.BottomScale)
	inner.Name = "Panel"

	for i, key in KEYS do
		slots[key] = slot(inner, key, i)
	end

	task.spawn(function()
		upgradeEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Upgrade") :: RemoteEvent
	end)
	local ranks: { [string]: number } = {}
	for _, key in Config.Progress.Upgrades do
		ranks[key] = Leveling.rank(player, key)
	end
	player.AttributeChanged:Connect(function(name)
		local key = name:match("^Rank(.+)")
		if key and ranks[key] then
			local rank = Leveling.rank(player, key)
			if rank > ranks[key] then
				UiSound.play("RankUp")
			end
			ranks[key] = rank
		end
		showRanks()
	end)
	showRanks()
	local function added(character: Model)
		showIcons(character:GetAttribute("Hero"))
		character:GetAttributeChangedSignal("Hero"):Connect(function()
			showIcons(character:GetAttribute("Hero"))
		end)
	end
	player.CharacterAdded:Connect(added)
	if player.Character then
		added(player.Character)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		local index = table.find(UPGRADE_KEYS, input.KeyCode)
		if processed or not index then
			return
		end
		upgrade(Config.Progress.Upgrades[index])
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		-- What can be raised pulses, so a point to spend is not forgotten.
		local pulse = (math.sin(now * GLOW_RATE * 2 * math.pi) + 1) / 2
		for _, s in slots do
			local r = s.rank
			if r and r.ready then
				r.glow.BackgroundTransparency = 0.7 - 0.55 * pulse
				r.flash.BackgroundTransparency = 0.95 - 0.6 * pulse
				r.stroke.Thickness = 2 + 2 * pulse
			end
		end
		for key, s in slots do
			local left = s.endsAt - now
			if left > 0 then
				s.cooling = true
			elseif s.cooling then
				s.cooling = false
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if key == "R" and humanoid and humanoid.Health > 0 then
					UiSound.play("UltimateReady")
				end
			end
			if left > 0 and s.total > 0 then
				s.shade.Size = UDim2.fromScale(1, left / s.total)
				s.seconds.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
				s.glyph.Visible = s.icon.Visible
			else
				s.shade.Size = UDim2.fromScale(1, 0)
				s.seconds.Text = ""
				s.glyph.Visible = true
			end
		end
	end)
end

return AbilityBar
