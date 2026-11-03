-- The settings (design 17, Preferences) over the whole screen: the SETTINGS ribbon with a close button, the four
-- sections on the left (Audio: the volumes and the menu's music; Controls: the mouse's speed and the keys; Graphics:
-- the shadows; Interface: the damage numbers) and the chosen one on the right, with RESET TO DEFAULT and SAVE under it.
-- Every change is heard and seen at once (Preferences.preview); SAVE keeps it in the profile (MenuService's Settings),
-- closing without saving goes back to what was saved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(ReplicatedStorage.Shared.Profile)
local Preferences = require(script.Parent.Parent.Preferences)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local SettingsPage = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local SECTIONS = { "Audio", "Controls", "Graphics", "Interface" }
local VOLUMES = {
	{ "Master", "MASTER VOLUME" },
	{ "Music", "MUSIC" },
	{ "Effects", "SOUND EFFECTS" },
	{ "Interface", "INTERFACE" },
}
-- The keys of a match (HeroControls, AbilityBar, ItemBar, Shop, Scoreboard).
local KEYS = {
	{ "MOVE", "W A S D" },
	{ "BASIC ATTACK", "LEFT CLICK" },
	{ "ABILITY", "RIGHT CLICK" },
	{ "ABILITY", "E" },
	{ "ULTIMATE", "R" },
	{ "DASH", "SHIFT" },
	{ "RAISE AN ABILITY", "1  2  3" },
	{ "HEALTH POTION", "Q" },
	{ "ARMORY", "B  /  HOLD F" },
	{ "SCOREBOARD", "HOLD TAB" },
}

local openNow: Frame? = nil

type Control = { set: (value: any) -> () }

-- A heading over a row in the section.
local function heading(parent: Instance, text: string, order: number, height: number): Frame
	local row = UiStyle.frame(parent, UDim2.new(1, 0, 0, height))
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	local label = Widgets.label(row, text, 30, C.Ink, "Left")
	label.Size = UDim2.new(0.7, 0, 0, 36)
	return row
end

local function percentOf(v: number): string
	return math.round(v * 100) .. "%"
end

-- A slider row for the setting `key` (0 to 1), its value shown on the right by `show` (a percentage by default).
local function sliderRow(
	parent: Instance,
	key: string,
	text: string,
	order: number,
	values: any,
	changed: () -> (),
	show: ((v: number) -> string)?
): Control
	local shown = show or percentOf
	local row = heading(parent, text, order, 92)
	local value = Widgets.label(row, "", 32, C.Ink, "Right")
	value.Size = UDim2.fromOffset(110, 40)
	value.Position = UDim2.new(1, -4, 0, 44)
	value.AnchorPoint = Vector2.new(1, 0)
	local _, set = Widgets.slider(row, UDim2.new(1, -150, 0, 24), UDim2.fromOffset(4, 52), values[key], function(v)
		values[key] = v
		value.Text = shown(v)
		changed()
	end)
	value.Text = shown(values[key])
	return {
		set = function(v: number)
			set(v)
			value.Text = shown(v)
		end,
	}
end

local function toggleRow(
	parent: Instance,
	key: string,
	text: string,
	order: number,
	values: any,
	changed: () -> ()
): Control
	local row = heading(parent, text, order, 70)
	local label = row:FindFirstChildOfClass("TextLabel") :: TextLabel
	label.Position = UDim2.fromOffset(0, 17)
	local _, set = Widgets.toggle(row, UDim2.new(1, -4, 0.5, 0), Vector2.new(1, 0.5), values[key], function(on)
		values[key] = on
		changed()
	end)
	return { set = set }
end

local function note(parent: Instance, text: string, order: number)
	local label = Widgets.label(parent, text, 24, W.Muted, "Left")
	label.Size = UDim2.new(1, 0, 0, 60)
	label.TextWrapped = true
	label.LayoutOrder = order
end

local function rule(parent: Instance, order: number)
	local line = UiStyle.frame(parent, UDim2.new(1, 0, 0, 2))
	line.BackgroundColor3 = C.GoldDark
	line.BackgroundTransparency = 0.5
	line.LayoutOrder = order
end

-- Opens the settings over `gui`; `api` asks the server (`ask`) and shows its answer (`notice`).
function SettingsPage.open(gui: Instance, api: any)
	if openNow and openNow.Parent then
		return
	end
	local values = table.clone(Profile.defaultSettings()) :: any
	for key in values do
		local current = Preferences.get(key)
		if current ~= nil then
			values[key] = current
		end
	end
	local saved = false

	local holder = Widgets.popup(gui, "Settings")
	openNow = holder
	Widgets.veil(holder, 0.45)
	local outer, inner =
		UiStyle.panel(holder, UDim2.fromOffset(1350, 860), UDim2.new(0.5, 0, 0.5, 30), Vector2.new(0.5, 0.5), 18, 6)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = outer
	Widgets.tween(scale, 0.2, { Scale = 1 })
	UiSound.play("ShopOpen", 0.8)

	Widgets.ribbon(outer, "SETTINGS", UDim2.fromOffset(620, 96), UDim2.new(0.5, 0, 0, -52), Vector2.new(0.5, 0))

	local close =
		Widgets.button(outer, "X", "Gold", UDim2.fromOffset(84, 84), UDim2.new(1, 22, 0, -22), Vector2.new(1, 0), 44)
	local fill = close:FindFirstChild("Fill") :: UIGradient
	fill.Color = ColorSequence.new(Color3.fromRGB(232, 84, 64), Color3.fromRGB(160, 30, 24))
	local round = close:FindFirstChildOfClass("UICorner") :: UICorner
	round.CornerRadius = UDim.new(0.5, 0)
	-- The shine as a rounded band inside the circle, so it keeps within the round button.
	local shine = close:FindFirstChild("Shine") :: Frame
	shine.Size = UDim2.fromScale(0.62, 0.3)
	shine.Position = UDim2.fromScale(0.19, 0.09)
	local shineRound = shine:FindFirstChildOfClass("UICorner") :: UICorner
	shineRound.CornerRadius = UDim.new(0.5, 0)

	-- The sections on the left.
	local menu = UiStyle.frame(inner, UDim2.fromOffset(300, 520), UDim2.fromOffset(40, 96))
	menu.BackgroundTransparency = 1
	Widgets.list(menu, "Vertical", 22)
	local content = UiStyle.frame(inner, UDim2.new(1, -420, 1, -250), UDim2.fromOffset(380, 96))
	UiStyle.corner(content, 12)
	content.BackgroundColor3 = W.Parchment
	content.BackgroundTransparency = 0.2
	UiStyle.stroke(content, C.GoldDark, 2)

	local controls: { [string]: Control } = {}
	local function changed()
		Preferences.preview(values)
	end
	local pages: { [string]: Frame } = {}
	for _, name in SECTIONS do
		local p = Instance.new("ScrollingFrame")
		p.BackgroundTransparency = 1
		p.BorderSizePixel = 0
		p.Size = UDim2.new(1, -60, 1, -40)
		p.Position = UDim2.fromOffset(30, 20)
		p.ScrollBarThickness = 6
		p.ScrollBarImageColor3 = C.GoldDark
		p.AutomaticCanvasSize = Enum.AutomaticSize.Y
		p.CanvasSize = UDim2.new()
		p.Visible = false
		p.Parent = content
		-- The rows keep clear of the scroll bar on the right.
		local gap = Instance.new("UIPadding")
		gap.PaddingRight = UDim.new(0, 28)
		gap.Parent = p
		Widgets.list(p, "Vertical", 14)
		pages[name] = p
	end

	for i, volume in VOLUMES do
		controls[volume[1]] = sliderRow(pages.Audio, volume[1], volume[2], i, values, changed)
	end
	rule(pages.Audio, 10)
	controls.MenuMusic = toggleRow(pages.Audio, "MenuMusic", "MUSIC IN MENU", 11, values, changed)
	-- The credit the menu music's licence (CC BY 4.0) asks for.
	note(pages.Audio, 'Menu music: "Ancient God" by Gary Boudreaux, licensed under CC BY 4.0.', 12)

	controls.Sensitivity = sliderRow(
		pages.Controls,
		"Sensitivity",
		"MOUSE SENSITIVITY",
		-2,
		values,
		changed,
		function(v)
			return string.format("%.2fx", Preferences.sensitivity(v))
		end
	)
	rule(pages.Controls, -1)
	for i, key in KEYS do
		local row = UiStyle.frame(pages.Controls, UDim2.new(1, 0, 0, 52))
		row.LayoutOrder = i
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.6
		row.BackgroundColor3 = W.Stripe
		UiStyle.corner(row, 6)
		local action = Widgets.label(row, key[1], 28, C.Ink, "Left")
		action.Size = UDim2.new(0.55, -16, 1, 0)
		action.Position = UDim2.fromOffset(16, 0)
		local keyBox = Widgets.dark(row, UDim2.new(0.4, 0, 0, 40), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5), 8)
		Widgets.label(keyBox, key[2], 24, C.Cream)
	end

	controls.Shadows = toggleRow(pages.Graphics, "Shadows", "SHADOWS", 1, values, changed)
	note(pages.Graphics, "Shadows look best, but turning them off makes the game run smoother on slower computers.", 2)

	controls.DamageNumbers = toggleRow(pages.Interface, "DamageNumbers", "DAMAGE NUMBERS", 1, values, changed)
	note(pages.Interface, "The numbers that rise from what your hero hits in a match.", 2)

	local sectionButtons: { [string]: TextButton } = {}
	local function choose(name: string)
		for section, p in pages do
			p.Visible = section == name
		end
		for section, b in sectionButtons do
			Widgets.paint(b, if section == name then "Gold" else "Dark")
		end
	end
	for i, name in SECTIONS do
		local b = Widgets.button(menu, string.upper(name), "Dark", UDim2.new(1, 0, 0, 104), nil, nil, 32)
		b.LayoutOrder = i
		sectionButtons[name] = b
		b.Activated:Connect(function()
			UiSound.play("Tab", 0.6)
			choose(name)
		end)
	end
	choose("Audio")

	local function shut()
		if not saved then
			Preferences.restore()
		end
		UiSound.play("ShopClose", 0.8)
		openNow = nil
		holder:Destroy()
	end

	local reset = Widgets.button(
		inner,
		"RESET TO DEFAULT",
		"Blue",
		UDim2.fromOffset(330, 100),
		UDim2.new(1, -364, 1, -36),
		Vector2.new(1, 1),
		30
	)
	local save = Widgets.button(
		inner,
		"SAVE",
		"Green",
		UDim2.fromOffset(300, 100),
		UDim2.new(1, -40, 1, -36),
		Vector2.new(1, 1),
		46
	)
	reset.Activated:Connect(function()
		local defaults = Profile.defaultSettings() :: any
		for key, value in defaults do
			values[key] = value
			local control = controls[key]
			if control then
				control.set(value)
			end
		end
		changed()
	end)
	save.Activated:Connect(function()
		if not save.Active then
			return
		end
		save.Active = false
		local answer = api.ask("Settings", values)
		save.Active = true
		if answer.ok then
			saved = true
			api.notice("Settings saved.")
			shut()
		end
	end)
	close.Activated:Connect(shut)
end

return SettingsPage
