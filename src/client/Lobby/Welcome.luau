-- The welcome screen, for a player who has not chosen his hero yet: the hall's podium in the left half of the screen
-- with his own Roblox avatar on it (Lobby.Showcase), a greeting over it, and on the right a parchment panel with his
-- heroes as cards, the hero he looks at large (his name, class, line and five abilities) and a big button to become
-- him. Becoming him slides the panel away and plays the transformation on the podium (the menu's `become`), after
-- which the Play page waits with PLAY ready. There is no way to close it without choosing: PLAY needs a hero.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)
local Showcase = require(script.Parent.Showcase)

local Welcome = {}

local C = UiStyle.Colors
local KEYS = { "M1", "M2", "E", "R", "Dash" }
local LABELS = { Dash = "Shift" }
-- The mouse's buttons show as the mouse with that button lit.
local MOUSE = { M1 = Assets.MouseLeft, M2 = Assets.MouseRight }
-- Where the podium stands on the screen while the welcome screen is open (a share of its width), and the camera's
-- field of view then: a little wider than the menu's, so the greeting fits over the avatar's head.
local PODIUM_AT, PODIUM_FOV = 0.3, 48
local PANEL_WIDTH, PANEL_HEIGHT = 760, 860
local CARD_WIDTH, CARD_HEIGHT = 208, 262

local open: ScreenGui? = nil

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: any?, direction: any?)
	local t = TweenService:Create(
		object,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

-- The heroes he can become, the default hero first, then by name.
local function heroes(data: Profile.Data?): { string }
	local list = {}
	for name in Config.Heroes do
		if not data or Profile.owns(data, name) then
			table.insert(list, name)
		end
	end
	table.sort(list, function(a, b)
		if (a == Config.DefaultHero) ~= (b == Config.DefaultHero) then
			return a == Config.DefaultHero
		end
		return a < b
	end)
	return list
end

-- Opens the welcome screen over the menu `api` (Lobby.Menu); nothing when it is open already.
function Welcome.open(api: any)
	if open then
		return
	end
	local player = Players.LocalPlayer
	local gui = UiStyle.screen("Welcome", player:WaitForChild("PlayerGui"), 30)
	open = gui
	api.chrome(false)

	-- A darker edge on the right under the panel, so the parchment stands out from the hall.
	local shade = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	shade.BackgroundColor3 = Color3.fromRGB(10, 6, 4)
	shade.BackgroundTransparency = 1
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	shadeFade.Parent = shade

	-- The greeting over the podium.
	local greeting = UiStyle.frame(gui, UDim2.fromOffset(900, 150), UDim2.new(PODIUM_AT, 0, 0, 86), Vector2.new(0.5, 0))
	greeting.BackgroundTransparency = 1
	local welcomeTo = UiStyle.text(greeting, "WELCOME TO", 32, C.Cream, C.Edge)
	welcomeTo.Size = UDim2.new(1, 0, 0, 36)
	local name = UiStyle.text(greeting, "DEFEND THE MASTER", 72, Color3.new(1, 1, 1), C.Edge)
	name.Size = UDim2.new(1, 0, 0, 76)
	name.Position = UDim2.fromOffset(0, 30)
	local nameEdge = name:FindFirstChildOfClass("UIStroke") :: UIStroke
	nameEdge.Thickness = 6
	local gold = Instance.new("UIGradient")
	gold.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), C.Gold)
	gold.Rotation = 90
	gold.Parent = name
	local hint = UiStyle.text(greeting, "Pick your hero and transform!", 28, C.Cream, C.Edge)
	hint.Size = UDim2.new(1, 0, 0, 34)
	hint.Position = UDim2.fromOffset(0, 108)
	local greetingScale = Instance.new("UIScale")
	greetingScale.Scale = 0.85
	greetingScale.Parent = greeting
	local greetingLabels = { welcomeTo, name, hint }
	for _, label in greetingLabels do
		label.TextTransparency = 1
		local edge = label:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Transparency = 1
		end
	end

	-- His name on a ribbon under the podium.
	local plate = Widgets.ribbon(
		gui,
		string.upper(player.DisplayName),
		UDim2.fromOffset(360, 60),
		UDim2.new(PODIUM_AT, 0, 1, -70),
		Vector2.new(0.5, 1)
	)
	plate.Visible = false

	-- The panel on the right.
	local holder =
		UiStyle.frame(gui, UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT), UDim2.new(1, -50, 0.5, 0), Vector2.new(1, 0.5))
	holder.BackgroundTransparency = 1
	local shown = holder.Position
	local hidden = UDim2.new(1, PANEL_WIDTH + 80, 0.5, 0)
	local _, side = UiStyle.panel(holder, UDim2.fromScale(1, 1), nil, nil, 16, 6)
	Widgets.ribbon(
		holder,
		"CHOOSE YOUR HERO",
		UDim2.fromOffset(500, 70),
		UDim2.new(0.5, 0, 0, -26),
		Vector2.new(0.5, 0)
	)

	local cards = Instance.new("ScrollingFrame")
	cards.BackgroundTransparency = 1
	cards.BorderSizePixel = 0
	cards.Size = UDim2.new(1, -40, 0, CARD_HEIGHT + 34)
	cards.Position = UDim2.fromOffset(20, 56)
	cards.ScrollBarThickness = 6
	cards.ScrollBarImageColor3 = C.GoldDark
	cards.ScrollingDirection = Enum.ScrollingDirection.X
	cards.AutomaticCanvasSize = Enum.AutomaticSize.X
	cards.CanvasSize = UDim2.new()
	cards.Parent = side
	local cardLayout = Widgets.list(cards, "Horizontal", 22)
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	-- Room at the ends for the chosen card, which grows and gets a thicker edge, and under the cards for the scroll
	-- bar, so it stays clear of that edge.
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingLeft = UDim.new(0, 12)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.PaddingBottom = UDim.new(0, 6)
	cardPadding.Parent = cards
	-- Centred while the cards fit; once they are wider than the panel they start at its left edge, as centring
	-- would cut off the first card.
	local function alignCards()
		local fits = cardLayout.AbsoluteContentSize.X + 24 <= cards.AbsoluteSize.X
		cardLayout.HorizontalAlignment = if fits then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	end
	cardLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(alignCards)
	cards:GetPropertyChangedSignal("AbsoluteSize"):Connect(alignCards)

	local heroName = Widgets.label(side, "", 64, C.Ink)
	heroName.Size = UDim2.new(1, 0, 0, 70)
	heroName.Position = UDim2.fromOffset(0, CARD_HEIGHT + 98)
	local heroRole = Widgets.label(side, "", 32, C.Ink)
	heroRole.Size = UDim2.new(1, 0, 0, 38)
	heroRole.Position = UDim2.fromOffset(0, CARD_HEIGHT + 164)
	local rule = UiStyle.frame(side, UDim2.new(1, -100, 0, 2), UDim2.fromOffset(50, CARD_HEIGHT + 210))
	rule.BackgroundColor3 = C.GoldDark
	rule.BackgroundTransparency = 0.4
	local line = Widgets.label(side, "", 27, C.Ink)
	line.Size = UDim2.new(1, -80, 0, 76)
	line.Position = UDim2.fromOffset(40, CARD_HEIGHT + 212)
	line.TextWrapped = true
	local abilities = UiStyle.frame(side, UDim2.new(1, -60, 0, 128), UDim2.fromOffset(30, CARD_HEIGHT + 296))
	abilities.BackgroundTransparency = 1
	local abilityLayout = Widgets.list(abilities, "Horizontal", 22)
	abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local become, becomeText = Widgets.button(
		side,
		"BECOME",
		"Gold",
		UDim2.new(1, -60, 0, 108),
		UDim2.new(0.5, 0, 1, -24),
		Vector2.new(0.5, 1),
		50
	)
	Widgets.shimmer(become)
	-- A soft glow pulsing round the button.
	local pulse = UiStyle.stroke(become, Color3.fromRGB(255, 236, 150), 0)
	pulse.Transparency = 0.2
	task.spawn(function()
		while become.Parent do
			tween(pulse, 0.7, { Thickness = 7, Transparency = 0.75 }, Enum.EasingStyle.Sine)
			task.wait(0.7)
			tween(pulse, 0.7, { Thickness = 1, Transparency = 0.2 }, Enum.EasingStyle.Sine)
			task.wait(0.7)
		end
	end)

	local selected = Config.DefaultHero
	local buttons: { [string]: { button: TextButton, edge: UIStroke } } = {}

	local function showHero()
		local settings = Config.Heroes[selected]
		heroName.Text = string.upper(selected)
		heroRole.Text = string.upper(settings.Role or "")
		heroRole.TextColor3 = Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.35)
		line.Text = settings.Description or ""
		becomeText.Text = "BECOME " .. string.upper(selected)
		for _, child in abilities:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, key in KEYS do
			local slot = UiStyle.frame(abilities, UDim2.fromOffset(100, 128))
			slot.BackgroundTransparency = 1
			slot.LayoutOrder = i
			local box = UiStyle.frame(slot, UDim2.fromOffset(96, 96), UDim2.fromOffset(2, 0))
			UiStyle.corner(box, 10)
			UiStyle.gradient(box, Color3.fromRGB(60, 44, 70), Color3.fromRGB(24, 18, 30))
			UiStyle.stroke(box, C.Edge, 3)
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.new(1, -8, 1, -8)
			icon.Position = UDim2.fromOffset(4, 4)
			icon.Image = settings.Icons and settings.Icons[key] or ""
			icon.Parent = box
			UiStyle.corner(icon, 8)
			if MOUSE[key] then
				local mouse = Instance.new("ImageLabel")
				mouse.BackgroundTransparency = 1
				mouse.Image = MOUSE[key]
				mouse.ScaleType = Enum.ScaleType.Fit
				mouse.Size = UDim2.new(1, 0, 0, 34)
				mouse.Position = UDim2.fromOffset(0, 97)
				mouse.Parent = slot
			else
				local keyText = Widgets.label(slot, LABELS[key] or key, 26, C.Ink)
				keyText.Size = UDim2.new(1, 0, 0, 30)
				keyText.Position = UDim2.fromOffset(0, 98)
			end
		end
		for hero, b in buttons do
			local chosen = hero == selected
			b.edge.Color = if chosen then C.Xp else C.Gold
			b.edge.Thickness = if chosen then 6 else 3
		end
	end

	local function choose(hero: string)
		selected = hero
		showHero()
	end

	for i, hero in heroes(ProfileClient.get()) do
		local settings = Config.Heroes[hero]
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Text = ""
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = cards
		UiStyle.corner(b, 10)
		UiStyle.gradient(b, C.Cream, C.CreamDark)
		local edge = UiStyle.stroke(b, C.Gold, 3)
		local picture = UiStyle.frame(b, UDim2.new(1, -12, 0, 176), UDim2.fromOffset(6, 6))
		picture.BackgroundTransparency = 1
		picture.ClipsDescendants = true
		UiStyle.corner(picture, 7)
		local portrait = Widgets.portrait(picture, hero, UDim2.fromScale(1, 1), nil, true)
		UiStyle.corner(portrait, 7)
		local cardName = Widgets.label(b, hero, 30, C.Ink)
		cardName.Size = UDim2.new(1, -8, 0, 34)
		cardName.Position = UDim2.fromOffset(4, 186)
		local cardRole =
			Widgets.label(b, string.upper(settings.Role or ""), 22, Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.4))
		cardRole.Size = UDim2.new(1, 0, 0, 26)
		cardRole.Position = UDim2.fromOffset(0, 222)
		Widgets.feel(b)
		buttons[hero] = { button = b, edge = edge }
		b.Activated:Connect(function()
			if selected ~= hero and become.Active then
				choose(hero)
			end
		end)
	end
	if not buttons[selected] then
		selected = next(buttons) or Config.DefaultHero
	end
	alignCards()

	local function arrive()
		Showcase.view(PODIUM_AT, PODIUM_FOV, 1)
		tween(shade, 0.6, { BackgroundTransparency = 0 })
		-- The panel stood in place under the loading screen so Roblox loaded its pictures (it draws, and so loads,
		-- only what is on the screen); it slides in from the side as the screen fades.
		holder.Position = hidden
		tween(holder, 0.7, { Position = shown }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(greetingScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for _, label in greetingLabels do
			tween(label, 0.5, { TextTransparency = 0 })
			local edge = label:FindFirstChildOfClass("UIStroke")
			if edge then
				tween(edge, 0.5, { Transparency = 0 })
			end
		end
		plate.Visible = true
		UiSound.play("Tab", 0.8)
	end

	local function leave()
		tween(holder, 0.45, { Position = hidden }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(shade, 0.5, { BackgroundTransparency = 1 })
		for _, label in greetingLabels do
			tween(label, 0.3, { TextTransparency = 1 })
			local edge = label:FindFirstChildOfClass("UIStroke")
			if edge then
				tween(edge, 0.3, { Transparency = 1 })
			end
		end
		plate.Visible = false
	end

	become.Activated:Connect(function()
		if not become.Active then
			return
		end
		Widgets.enable(become, false, "Gold")
		local hero = selected
		local done = api.become(hero, function()
			leave()
			task.wait(0.45)
		end)
		if done then
			open = nil
			gui:Destroy()
		else
			Widgets.enable(become, true, "Gold")
		end
	end)

	showHero()
	task.spawn(function()
		local Loading = require(ReplicatedFirst:WaitForChild("Loading")) :: any
		Loading.waitGone()
		if gui.Parent then
			arrive()
		end
	end)
end

function Welcome.isOpen(): boolean
	return open ~= nil
end

return Welcome
