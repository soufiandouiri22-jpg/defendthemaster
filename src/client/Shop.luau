-- The armory screen (design 08, server: ShopService): at one of his team's armory stalls the hero holds F on its
-- prompt to open it, or presses B; B also opens it while he is dead. B or the back button closes it, and walking away
-- from the stall does too. The mouse is free while it is open. The back button and ARMORY plaque at the top with the coins on the right; the tabs on the left
-- (Recommended, his class's build (Items.build), then Attack, Defense, Magic and Speed); the grid of item cards in the
-- middle under the class filters (All and Config.Classes, as League's), which keep to the items made for the chosen
-- class and on Recommended show its build, each card with its icon, name and what it costs the hero now (his parts
-- counted), dark while he cannot buy it; on the right
-- the chosen item with its stats, its build path and the green buy button; the bag along the bottom with the undo
-- button. A card is chosen with a click and bought with a right click or the button; a slot of the bag is chosen and
-- sold the same way. The other items in the build path (its parts, or what it builds into) are chosen and bought the
-- same way, the grid turning to their tab and scrolling them into view. Purchases go through Net.Shop, and everything shown comes from the server's attributes (Items).
-- It sounds (UiSound) as the mouse passes over what can be clicked, as a card, slot or tab is chosen, as the board
-- unrolls and rolls up, and as coins change hands, or a dull knock when what is asked cannot be done.
-- Laid out on a 1920 x 1080 board, measured off the design (1024 x 576) at 1.875 times, drawn at SIZE of the screen.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local HeroCamera = require(script.Parent.HeroCamera)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local Shop = {}

local C = UiStyle.Colors
local BOARD = Vector2.new(1920, 1080)
-- What the board's pieces cover (the back button's left to the item sheet's right, the plaque's top to the sheet's
-- foot). Keep it in step when a piece moves past it.
local DRAWN = { Min = Vector2.new(28, 9), Max = Vector2.new(1875, 1050) }
-- Its middle sits midway between the foot of the score board's clock tab and the top of the ability bar, measured on
-- screen when it opens (hudBand); until the HUD is there, HUD_TOP from the top and HUD_BOTTOM from the foot (in the
-- HUD's 1080-high units). On a screen too low for SIZE it shrinks to keep HUD_MARGIN clear of both.
local HUD_TOP, HUD_BOTTOM = 160, 155
local HUD_MARGIN = 14
-- The board's share of the screen, so the arena shows round it.
local SIZE = 0.8
local TABS = {
	{ id = "Recommended", icon = "Kingsbane" },
	{ id = "Attack", icon = "IronSword" },
	{ id = "Defense", icon = "SteelShield" },
	{ id = "Magic", icon = "MagicStaff" },
	{ id = "Speed", icon = "SwiftBoots" },
}
local DARK_TOP, DARK_BOTTOM = Color3.fromRGB(96, 62, 36), Color3.fromRGB(62, 38, 22)
local CARD_TOP, CARD_BOTTOM = Color3.fromRGB(252, 240, 210), Color3.fromRGB(226, 200, 150)
local DIM_TOP, DIM_BOTTOM = Color3.fromRGB(128, 106, 84), Color3.fromRGB(96, 78, 60)
local GOLD_TOP, GOLD_BOTTOM = Color3.fromRGB(255, 218, 96), Color3.fromRGB(230, 156, 36)
local GREEN_TOP, GREEN_BOTTOM = Color3.fromRGB(132, 214, 72), Color3.fromRGB(48, 146, 30)
local SELL_TOP, SELL_BOTTOM = Color3.fromRGB(246, 178, 66), Color3.fromRGB(204, 108, 28)
local GREY_TOP, GREY_BOTTOM = Color3.fromRGB(176, 166, 154), Color3.fromRGB(122, 112, 102)
local PICKED = Color3.fromRGB(255, 232, 92)
local STAT = Color3.fromRGB(44, 136, 38)
local WARN = Color3.fromRGB(176, 58, 36)
local CARD = 197
-- The class filters in the grid's well (931 wide inside its border): their row's top and height, the room at either
-- side (the cards' too) and between them, and where the cards begin below them. All names in one size, the longest
-- (ASSASSIN) still fitting.
local FILTER_TOP, FILTER_HEIGHT, FILTER_TEXT = 30, 62, 24
local FILTER_MARGIN, FILTER_GAP = 38, 12
local GRID_TOP = FILTER_TOP + FILTER_HEIGHT + 8
-- E is the dagger throw, so the stall's prompt is held on F.
local PROMPT_KEY = Enum.KeyCode.F
local PROMPT_HOLD = 0.3

local player = Players.LocalPlayer
local gui: ScreenGui
local shopEvent: RemoteEvent? = nil
local isOpen = false
local prompts: { [Instance]: ProximityPrompt } = {}
local refit: () -> () = function() end
local goTo: (id: string) -> () = function() end
local buy: (id: string) -> () = function() end

-- On screen: the foot of the score board's clock tab, and the top of the ability bar's outline.
local function hudBand(): (number?, number?)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local score = hud and hud:FindFirstChild("Score", true)
	local bars = playerGui and playerGui:FindFirstChild("AbilityBar")
	local panel = bars and bars:FindFirstChild("Panel", true)
	local bar = panel and panel.Parent
	if not score or not score:IsA("GuiObject") or not bar or not bar:IsA("GuiObject") then
		return nil, nil
	end
	local stroke = bar:FindFirstChildOfClass("UIStroke")
	local outline = if stroke then stroke.Thickness * bar.AbsoluteSize.Y / bar.Size.Y.Offset else 0
	return score.AbsolutePosition.Y + score.AbsoluteSize.Y, bar.AbsolutePosition.Y - outline
end
local category = "Recommended"
-- The class filter (nil for All); on Recommended, All is the hero's own build.
local class: string? = nil
-- What the right panel shows: an item of the grid, or a slot of the bag.
local pickedItem: string? = nil
local pickedSlot: number? = nil

local tabs: { [string]: { gradient: UIGradient } } = {}
local filters: { [string]: UIGradient } = {}
local cards: {
	[string]: {
		button: TextButton,
		gradient: UIGradient,
		stroke: UIStroke,
		icon: ImageLabel,
		name: TextLabel,
		price: TextLabel,
	},
} =
	{}
local slots: { { button: TextButton, gradient: UIGradient, stroke: UIStroke, icon: ImageLabel, badge: Frame, count: TextLabel } } =
	{}
local grid: ScrollingFrame
-- In the grid's place when the class filter leaves the tab empty.
local empty: TextLabel
local coinsText: TextLabel
local countdown: Frame
local countdownText: TextLabel
local detail: {
	name: TextLabel,
	icon: ImageLabel,
	lines: Frame,
	pathTitle: TextLabel,
	path: Frame,
	reason: TextLabel,
	button: TextButton,
	buttonGradient: UIGradient,
	buttonLabel: TextLabel,
	buttonCoin: ImageLabel,
	buttonPrice: TextLabel,
}

local function send(action: string, argument: any)
	if shopEvent then
		shopEvent:FireServer(action, argument)
	end
end

local function hero(): string
	local character = player.Character
	return character and character:GetAttribute("Hero") or Config.DefaultHero
end

-- A gold-framed panel whose inside runs from `top` to `bottom`.
local function panel(
	parent: Instance,
	size: Vector2,
	position: Vector2,
	top: Color3,
	bottom: Color3,
	radius: number?,
	border: number?
): (Frame, Frame, UIGradient)
	local outer, inner = UiStyle.panel(
		parent,
		UDim2.fromOffset(size.X, size.Y),
		UDim2.fromOffset(position.X, position.Y),
		nil,
		radius or 18,
		border or 7
	)
	local gradient = inner:FindFirstChildOfClass("UIGradient") :: UIGradient
	gradient.Color = ColorSequence.new(top, bottom)
	return outer, inner, gradient
end

-- Sounds as the mouse comes over `button`.
local function hoverable(button: GuiButton)
	button.MouseEnter:Connect(function()
		UiSound.play("Hover")
	end)
end

-- A click area over all of `frame`.
local function clickable(frame: GuiObject): TextButton
	local button = Instance.new("TextButton")
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 10
	button.Parent = frame
	return button
end

local function image(parent: Instance, id: string, size: number, position: UDim2, anchor: Vector2?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Image = id
	label.ScaleType = Enum.ScaleType.Fit
	label.Size = UDim2.fromOffset(size, size)
	label.Position = position
	label.AnchorPoint = anchor or Vector2.zero
	label.Parent = parent
	return label
end

local function icon(id: string): string
	return Config.Items[id].Icon
end

-- An arrow of `size` round `centre`, pointing left, or right when `right`.
local function arrow(parent: Instance, colour: Color3, size: number, centre: UDim2, right: boolean?): Frame
	local holder = UiStyle.frame(parent, UDim2.fromOffset(size, size), centre, Vector2.new(0.5, 0.5))
	holder.BackgroundTransparency = 1
	holder.Rotation = if right then 180 else 0
	local thick = size * 0.2
	local tip = Vector2.new(size * 0.12, size / 2)
	local shaft = UiStyle.frame(
		holder,
		UDim2.fromOffset(size * 0.74, thick),
		UDim2.fromOffset(tip.X + size * 0.4, tip.Y),
		Vector2.one / 2
	)
	shaft.BackgroundColor3 = colour
	UiStyle.corner(shaft, thick / 2)
	local length = size * 0.56
	for _, sign in { -1, 1 } do
		local centreOf = tip
			+ Vector2.new(math.cos(math.rad(45)), sign * math.sin(math.rad(45))) * (length / 2 - thick / 3)
		local bar = UiStyle.frame(
			holder,
			UDim2.fromOffset(length, thick),
			UDim2.fromOffset(centreOf.X, centreOf.Y),
			Vector2.one / 2
		)
		bar.BackgroundColor3 = colour
		bar.Rotation = sign * 45
		UiStyle.corner(bar, thick / 2)
	end
	return holder
end

-- A coin with `value` beside it.
local function price(parent: Instance, size: number, colour: Color3, outline: Color3?): (Frame, TextLabel, ImageLabel)
	local row = UiStyle.frame(parent, UDim2.new(1, 0, 0, size), UDim2.new())
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, size * 0.15)
	layout.Parent = row
	local coin = image(row, Assets.HudCoin, size, UDim2.new())
	coin.LayoutOrder = 1
	local text = UiStyle.text(row, "", size * 0.9, colour, outline)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.Size = UDim2.fromOffset(0, size)
	text.LayoutOrder = 2
	return row, text, coin
end

local function headline(parent: Instance, value: string, iconId: string, y: number): TextLabel
	image(parent, icon(iconId), 44, UDim2.fromOffset(28, y))
	local label = UiStyle.text(parent, value, 34, C.Ink)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromOffset(380, 44)
	label.Position = UDim2.fromOffset(82, y)
	return label
end

local function divider(parent: Instance, y: number)
	local line = UiStyle.frame(parent, UDim2.new(0.88, 0, 0, 3), UDim2.new(0.5, 0, 0, y), Vector2.new(0.5, 0))
	line.BackgroundColor3 = C.GoldDark
	line.BackgroundTransparency = 0.3
end

-- A small card in the build path: the item's icon, name and price; green-edged when the hero holds it. With `open`
-- it chooses the item on a click and buys it on a right click, its edge lighting up under the mouse.
local function pathCard(parent: Instance, id: string, width: number, x: number, held: boolean, open: boolean)
	local card = UiStyle.frame(parent, UDim2.fromOffset(width, 150), UDim2.fromOffset(x, 0))
	UiStyle.corner(card, 10)
	UiStyle.gradient(card, CARD_TOP, CARD_BOTTOM)
	local edge, thickness = if held then STAT else C.GoldDark, if held then 4 else 2
	local stroke = UiStyle.stroke(card, edge, thickness)
	if open then
		local button = clickable(card)
		hoverable(button)
		button.MouseEnter:Connect(function()
			stroke.Color, stroke.Thickness = PICKED, 5
		end)
		button.MouseLeave:Connect(function()
			stroke.Color, stroke.Thickness = edge, thickness
		end)
		button.Activated:Connect(function()
			UiSound.play("Pick")
			goTo(id)
		end)
		button.MouseButton2Click:Connect(function()
			goTo(id)
			buy(id)
		end)
	end
	local name = UiStyle.text(card, Config.Items[id].Name, 18, C.Ink)
	name.Size = UDim2.new(1, -8, 0, 22)
	name.Position = UDim2.fromOffset(4, 4)
	name.TextScaled = true
	image(card, icon(id), math.min(width - 16, 78), UDim2.new(0.5, 0, 0, 28), Vector2.new(0.5, 0))
	local row, text, coin = price(card, 26, if held then STAT else C.Ink)
	row.Position = UDim2.new(0, 0, 1, -32)
	coin.Visible = not held
	text.Text = if held then "Owned" else tostring(Config.Items[id].Cost)
end

local function sign(parent: Instance, value: string, x: number)
	local label = UiStyle.text(parent, value, 50, STAT, C.Cream)
	label.Size = UDim2.fromOffset(40, 150)
	label.Position = UDim2.fromOffset(x - 20, 0)
end

-- The items that `id` goes into.
local function buildsInto(id: string): { string }
	local list = {}
	for other, item in Config.Items do
		if item.From and table.find(item.From, id) then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		return Config.Items[a].Cost < Config.Items[b].Cost
	end)
	return list
end

local function setButton(mode: string, amount: number?, enabled: boolean)
	local top, bottom = GREEN_TOP, GREEN_BOTTOM
	if mode == "Sell" then
		top, bottom = SELL_TOP, SELL_BOTTOM
	end
	if not enabled then
		top, bottom = GREY_TOP, GREY_BOTTOM
	end
	detail.buttonGradient.Color = ColorSequence.new(top, bottom)
	detail.buttonLabel.Visible = mode == "Sell"
	detail.buttonPrice.Text = if amount then UiStyle.thousands(amount) else ""
	detail.button.Active = enabled
	detail.button:SetAttribute("Mode", mode)
	detail.button:SetAttribute("Enabled", enabled)
end

-- Fills the right panel with the chosen item or slot.
local function showDetail()
	for _, child in detail.lines:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	detail.path:ClearAllChildren()
	local bag = Items.bag(player)
	local slot = pickedSlot and bag[pickedSlot]
	local id = if slot then slot.id else pickedItem
	if not id or not Config.Items[id] then
		detail.name.Text = ""
		detail.icon.Image = ""
		detail.reason.Text = ""
		setButton("Buy", nil, false)
		return
	end
	local item = Config.Items[id]
	detail.name.Text = item.Name
	detail.icon.Image = item.Icon
	local lines = Items.lines(id)
	if item.Text then
		table.insert(lines, item.Text)
	end
	for i, line in lines do
		local isStat = i <= #lines - (if item.Text then 1 else 0)
		local label = UiStyle.text(detail.lines, line, if isStat then 30 else 25, if isStat then STAT else C.Ink)
		label.Size = UDim2.fromScale(1, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = i
	end

	-- The build path: the parts and the item, or what a part goes into.
	local held: { [string]: number } = {}
	for _, s in bag do
		held[s.id] = (held[s.id] or 0) + s.count
	end
	local parts = item.From or {}
	local row: { string } = {}
	if #parts > 0 then
		detail.pathTitle.Text = "BUILD PATH"
		row = table.clone(parts)
		table.insert(row, id)
	else
		detail.pathTitle.Text = if item.Potion then "" else "BUILDS INTO"
		row = buildsInto(id)
		while #row > 3 do
			table.remove(row)
		end
	end
	local n = #row
	local gap = 40
	local width = math.min(124, (480 - (n - 1) * gap) / math.max(n, 1))
	local start = (505 - (n * width + (n - 1) * gap)) / 2
	local used: { [string]: number } = {}
	for i, part in row do
		local x = start + (i - 1) * (width + gap)
		local isPart = #parts > 0 and i < n
		local have = false
		if isPart and (held[part] or 0) > (used[part] or 0) then
			have = true
			used[part] = (used[part] or 0) + 1
		end
		pathCard(detail.path, part, width, x, have, part ~= id)
		if i < n then
			local middle = x + width + gap / 2
			if #parts > 0 and i == n - 1 then
				arrow(detail.path, STAT, 34, UDim2.fromOffset(middle, 75), true)
			elseif #parts > 0 then
				sign(detail.path, "+", middle)
			end
		end
	end

	if slot then
		local refund = Items.refund(slot.id)
		local here = player:GetAttribute("AtShop") == true
		detail.reason.Text = if here then "" else "Go to your armory to sell"
		setButton("Sell", refund, here)
		return
	end
	local ok, why, cost = Items.check(player, id)
	if ok and player:GetAttribute("AtShop") ~= true then
		ok, why = false, "Go to your armory to buy"
	end
	detail.reason.Text = why or ""
	setButton("Buy", cost, ok)
end

-- Brings the cards, the bag and the coins up to date.
local function paint()
	if not gui then
		return
	end
	coinsText.Text = UiStyle.thousands(player:GetAttribute("Coins") or 0)
	for id, card in cards do
		local ok, _, cost = Items.check(player, id)
		local picked = pickedItem == id and not pickedSlot
		card.gradient.Color = if ok
			then ColorSequence.new(CARD_TOP, CARD_BOTTOM)
			else ColorSequence.new(DIM_TOP, DIM_BOTTOM)
		card.icon.ImageColor3 = if ok then Color3.new(1, 1, 1) else Color3.fromRGB(176, 170, 162)
		card.name.TextColor3 = if ok then C.Ink else Color3.fromRGB(240, 228, 204)
		card.price.TextColor3 = if ok then C.Ink else Color3.fromRGB(206, 196, 180)
		card.price.Text = UiStyle.thousands(cost)
		card.stroke.Color = if picked then PICKED else C.GoldDark
		card.stroke.Thickness = if picked then 6 else 3
	end
	local bag = Items.bag(player)
	for i, s in slots do
		local held = bag[i]
		s.icon.Image = if held then Config.Items[held.id].Icon else ""
		s.gradient.Color = if held
			then ColorSequence.new(CARD_TOP, CARD_BOTTOM)
			else ColorSequence.new(DARK_TOP, DARK_BOTTOM)
		s.badge.Visible = held ~= nil and (held.count > 1 or Config.Items[held.id].Potion == true)
		s.count.Text = if held then tostring(held.count) else ""
		local picked = pickedSlot == i
		s.stroke.Color = if picked then PICKED else C.GoldDark
		s.stroke.Thickness = if picked then 6 else 3
	end
	if pickedSlot and not bag[pickedSlot] then
		pickedSlot = nil
	end
	showDetail()
end

local function pickItem(id: string)
	pickedItem, pickedSlot = id, nil
	paint()
end

function buy(id: string)
	pickItem(id)
	local ok = Items.check(player, id)
	UiSound.play(if ok and player:GetAttribute("AtShop") == true then "Buy" else "Denied")
	send("Buy", id)
end

local function sell(index: number)
	UiSound.play(if player:GetAttribute("AtShop") == true then "Sell" else "Denied")
	send("Sell", index)
end

-- Puts the cards of `name`'s items for the class filter in the grid.
local function showCategory(name: string)
	category = name
	for id, tab in tabs do
		tab.gradient.Color = if id == name
			then ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
			else ColorSequence.new(CARD_TOP, CARD_BOTTOM)
	end
	local settings = Config.Heroes[hero()]
	local lit = class or if name == "Recommended" and settings then settings.Role else "All"
	for id, gradient in filters do
		gradient.Color = if id == lit
			then ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
			else ColorSequence.new(CARD_TOP, CARD_BOTTOM)
	end
	for _, card in cards do
		card.button:Destroy()
	end
	table.clear(cards)
	local list = Items.list(name, hero(), class)
	local seen = {}
	for order, id in list do
		if seen[id] or not Config.Items[id] then
			continue
		end
		seen[id] = true
		local item = Config.Items[id]
		local button = Instance.new("TextButton")
		button.Name = id
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.LayoutOrder = order
		button.Parent = grid
		UiStyle.corner(button, 14)
		local gradient = UiStyle.gradient(button, CARD_TOP, CARD_BOTTOM)
		local stroke = UiStyle.stroke(button, C.GoldDark, 3)
		local art = image(button, item.Icon, 118, UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
		local label = UiStyle.text(button, item.Name, 25, C.Ink)
		label.Size = UDim2.new(1, -12, 0, 28)
		label.Position = UDim2.fromOffset(6, 124)
		label.TextScaled = true
		local band = UiStyle.frame(button, UDim2.new(1, -16, 0, 40), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))
		band.BackgroundColor3 = Color3.new(0, 0, 0)
		band.BackgroundTransparency = 0.86
		UiStyle.corner(band, 10)
		local row, text = price(band, 34, C.Ink)
		row.Position = UDim2.fromOffset(0, 3)
		hoverable(button)
		button.Activated:Connect(function()
			UiSound.play("Pick")
			pickItem(id)
		end)
		button.MouseButton2Click:Connect(function()
			buy(id)
		end)
		cards[id] = { button = button, gradient = gradient, stroke = stroke, icon = art, name = label, price = text }
	end
	empty.Visible = #list == 0 and class ~= nil
	empty.Text = "No " .. name .. " items for " .. (class or "") .. "s"
	if not pickedSlot and not (pickedItem and cards[pickedItem]) and list[1] then
		pickedItem = list[1]
	end
	paint()
end

-- Chooses the item `id`, turning the grid to its tab (and the filter to All when it is not made for the class) when
-- the grid does not hold it, and scrolling its card into view.
function goTo(id: string)
	pickedItem, pickedSlot = id, nil
	local tab = Config.Items[id].Category
	if not cards[id] and tab and tabs[tab] then
		if not Items.fits(id, class) then
			class = nil
		end
		showCategory(tab)
	else
		paint()
	end
	-- Once the grid has laid the card out; CanvasPosition is in the same screen pixels as AbsolutePosition.
	RunService.RenderStepped:Once(function()
		local card = cards[id]
		if not card then
			return
		end
		local top = card.button.AbsolutePosition.Y - grid.AbsolutePosition.Y + grid.CanvasPosition.Y
		local bottom = top + card.button.AbsoluteSize.Y
		local window = grid.AbsoluteWindowSize.Y
		local at = grid.CanvasPosition.Y
		if top < at then
			grid.CanvasPosition = Vector2.new(0, top - 12)
		elseif bottom > at + window then
			grid.CanvasPosition = Vector2.new(0, bottom - window + 12)
		end
	end)
end

local function build()
	-- Over the HUD, the kill banners and feed, the buy phase's banner and the damage numbers, so a kill never
	-- writes across the board (owner, 2026-10-29). Under the draft (20) and the match end (30).
	gui = UiStyle.screen("Shop", player:WaitForChild("PlayerGui"), 18)
	gui.Enabled = false

	-- Clicks beside the panels stay in the screen, and the arena behind darkens a little.
	local catcher = clickable(gui)
	catcher.ZIndex = 0
	catcher.BackgroundColor3 = Color3.new(0, 0, 0)
	catcher.BackgroundTransparency = 0.7

	local board = UiStyle.frame(
		gui,
		UDim2.fromOffset(BOARD.X, BOARD.Y),
		UDim2.new(0.5, 0, 0.5, (HUD_TOP - HUD_BOTTOM) / 2),
		(DRAWN.Min + DRAWN.Max) / 2 / BOARD
	)
	board.BackgroundTransparency = 1
	local fit = Instance.new("UIScale")
	fit.Parent = board
	refit = function()
		local camera = Workspace.CurrentCamera
		local scale = gui:FindFirstChildOfClass("UIScale")
		if not camera or not scale or scale.Scale <= 0 then
			return
		end
		fit.Scale = SIZE * math.min(1, camera.ViewportSize.X / scale.Scale / BOARD.X)
		local top, bottom = hudBand()
		if top and bottom then
			local room = (bottom - top) / scale.Scale - 2 * HUD_MARGIN
			fit.Scale = math.min(fit.Scale, room / (DRAWN.Max.Y - DRAWN.Min.Y))
			local middle = gui.AbsolutePosition.Y + gui.AbsoluteSize.Y / 2
			board.Position = UDim2.new(0.5, 0, 0.5, ((top + bottom) / 2 - middle) / scale.Scale)
		end
	end
	refit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(refit)
		end)
	end

	-- The back button.
	local back, backInner = panel(board, Vector2.new(122, 109), Vector2.new(28, 19), DARK_TOP, DARK_BOTTOM, 16, 6)
	arrow(backInner, C.Cream, 64, UDim2.fromScale(0.5, 0.5))
	local backButton = clickable(back)
	hoverable(backButton)
	backButton.Activated:Connect(function()
		Shop.close()
	end)

	-- The ARMORY plaque, and under it the buy phase's countdown.
	local _, plate = panel(board, Vector2.new(778, 122), Vector2.new(534, 9), C.Cream, C.CreamDark, 20, 8)
	local title = UiStyle.text(plate, "ARMORY", 100, C.Edge, C.Cream)
	title.Size = UDim2.new(1, -40, 0.9, 0)
	title.Position = UDim2.fromScale(0.5, 0.52)
	title.AnchorPoint = Vector2.one / 2
	title.TextScaled = true
	local stroke = title:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 4
	countdown = UiStyle.frame(board, UDim2.fromOffset(300, 50), UDim2.fromOffset(923, 116), Vector2.new(0.5, 0))
	countdown.BackgroundColor3 = C.Edge
	countdown.ZIndex = 4
	UiStyle.corner(countdown, 25)
	UiStyle.stroke(countdown, C.Gold, 3)
	countdownText = UiStyle.text(countdown, "", 32, C.Cream)
	countdownText.Size = UDim2.fromScale(1, 1)
	countdownText.ZIndex = 5
	countdown.Visible = false

	-- The coins.
	local _, purse = panel(board, Vector2.new(422, 109), Vector2.new(1453, 22), DARK_TOP, DARK_BOTTOM, 26, 6)
	image(purse, Assets.HudCoin, 92, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
	coinsText = UiStyle.text(purse, "0", 64, C.Cream, C.Edge)
	coinsText.Size = UDim2.new(1, -120, 1, 0)
	coinsText.Position = UDim2.fromOffset(106, 0)

	-- The tabs.
	for i, tab in TABS do
		local outer, inner, gradient =
			panel(board, Vector2.new(319, 100), Vector2.new(28, 172 + (i - 1) * 118), CARD_TOP, CARD_BOTTOM, 14, 5)
		image(inner, icon(tab.icon), 74, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
		local label = UiStyle.text(inner, string.upper(tab.id), 36, C.Ink)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Size = UDim2.new(1, -100, 1, 0)
		label.Position = UDim2.fromOffset(96, 0)
		label.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 38
		limit.Parent = label
		local tabButton = clickable(outer)
		hoverable(tabButton)
		tabButton.Activated:Connect(function()
			if category ~= tab.id or pickedSlot then
				UiSound.play("Tab")
			end
			pickedSlot = nil
			showCategory(tab.id)
		end)
		tabs[tab.id] = { gradient = gradient }
	end

	-- The grid, with the class filters along its top below the buy phase's countdown.
	local _, well = panel(board, Vector2.new(947, 703), Vector2.new(384, 141), DARK_TOP, DARK_BOTTOM, 18, 8)
	local names = { "All" }
	for _, name in Config.Classes do
		table.insert(names, name)
	end
	local filterWidth = (931 - 2 * FILTER_MARGIN - (#names - 1) * FILTER_GAP) / #names
	for i, name in names do
		local outer, inner, gradient = panel(
			well,
			Vector2.new(filterWidth, FILTER_HEIGHT),
			Vector2.new(FILTER_MARGIN + (i - 1) * (filterWidth + FILTER_GAP), FILTER_TOP),
			CARD_TOP,
			CARD_BOTTOM,
			12,
			4
		)
		local label = UiStyle.text(inner, string.upper(name), FILTER_TEXT, C.Ink)
		label.Size = UDim2.fromScale(1, 1)
		local filterButton = clickable(outer)
		hoverable(filterButton)
		filterButton.Activated:Connect(function()
			local chosen = if name == "All" then nil else name
			if class ~= chosen or pickedSlot then
				UiSound.play("Tab")
			end
			class, pickedSlot = chosen, nil
			showCategory(category)
		end)
		filters[name] = gradient
	end
	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.new(1, 0, 1, -GRID_TOP)
	grid.Position = UDim2.fromOffset(0, GRID_TOP)
	empty = UiStyle.text(well, "", 32, C.Cream, C.Edge)
	empty.Size = UDim2.new(1, -2 * FILTER_MARGIN, 0, 60)
	empty.Position = UDim2.new(0.5, 0, 0, GRID_TOP + 120)
	empty.AnchorPoint = Vector2.new(0.5, 0)
	empty.Visible = false
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = C.Gold
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = well
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, FILTER_MARGIN)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 26)
	padding.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD, CARD)
	layout.CellPadding = UDim2.fromOffset(22, 22)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- The chosen item.
	local _, sheet = panel(board, Vector2.new(521, 904), Vector2.new(1354, 146), C.Cream, C.CreamDark, 18, 8)
	local name = UiStyle.text(sheet, "", 46, C.Ink)
	name.Size = UDim2.new(1, -40, 0, 60)
	name.Position = UDim2.fromOffset(20, 14)
	name.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MaxTextSize = 48
	nameLimit.Parent = name
	local big = image(sheet, "", 180, UDim2.new(0.5, 0, 0, 80), Vector2.new(0.5, 0))
	divider(sheet, 272)
	headline(sheet, "STATS", "IronSword", 282)
	local lines = UiStyle.frame(sheet, UDim2.new(1, -60, 0, 150), UDim2.fromOffset(32, 332))
	lines.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = lines
	divider(sheet, 486)
	local pathTitle = headline(sheet, "BUILD PATH", "GreatAxe", 496)
	local path = UiStyle.frame(sheet, UDim2.new(1, 0, 0, 150), UDim2.fromOffset(0, 548))
	path.BackgroundTransparency = 1
	local reason = UiStyle.text(sheet, "", 26, WARN)
	reason.Size = UDim2.new(1, -40, 0, 34)
	reason.Position = UDim2.fromOffset(20, 708)
	reason.TextScaled = true
	local reasonLimit = Instance.new("UITextSizeConstraint")
	reasonLimit.MaxTextSize = 28
	reasonLimit.Parent = reason

	local buyButton = Instance.new("TextButton")
	buyButton.Text = ""
	buyButton.AutoButtonColor = false
	buyButton.BackgroundColor3 = Color3.new(1, 1, 1)
	buyButton.Size = UDim2.fromOffset(394, 126)
	buyButton.Position = UDim2.new(0.5, 0, 0, 748)
	buyButton.AnchorPoint = Vector2.new(0.5, 0)
	buyButton.Parent = sheet
	UiStyle.corner(buyButton, 26)
	local buttonGradient = UiStyle.gradient(buyButton, GREEN_TOP, GREEN_BOTTOM)
	UiStyle.stroke(buyButton, C.Edge, 3.5)
	local shine = UiStyle.frame(buyButton, UDim2.new(1, -24, 0.34, 0), UDim2.new(0, 12, 0.08, 0))
	shine.BackgroundTransparency = 0.75
	UiStyle.corner(shine, 14)
	local inside = UiStyle.frame(buyButton, UDim2.fromScale(1, 1))
	inside.BackgroundTransparency = 1
	local insideLayout = Instance.new("UIListLayout")
	insideLayout.FillDirection = Enum.FillDirection.Horizontal
	insideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	insideLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	insideLayout.Padding = UDim.new(0, 14)
	insideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	insideLayout.Parent = inside
	local sellLabel = UiStyle.text(inside, "SELL", 54, C.Cream, C.Edge)
	sellLabel.AutomaticSize = Enum.AutomaticSize.X
	sellLabel.Size = UDim2.fromOffset(0, 80)
	sellLabel.LayoutOrder = 0
	local buttonCoin = image(inside, Assets.HudCoin, 84, UDim2.new())
	buttonCoin.LayoutOrder = 1
	local buttonPrice = UiStyle.text(inside, "", 66, C.Cream, C.Edge)
	buttonPrice.AutomaticSize = Enum.AutomaticSize.X
	buttonPrice.Size = UDim2.fromOffset(0, 80)
	buttonPrice.LayoutOrder = 2
	hoverable(buyButton)
	buyButton.Activated:Connect(function()
		if not buyButton:GetAttribute("Enabled") then
			UiSound.play("Denied")
			return
		end
		if buyButton:GetAttribute("Mode") == "Sell" and pickedSlot then
			sell(pickedSlot)
		elseif pickedItem then
			buy(pickedItem)
		end
	end)
	detail = {
		name = name,
		icon = big,
		lines = lines,
		pathTitle = pathTitle,
		path = path,
		reason = reason,
		button = buyButton,
		buttonGradient = buttonGradient,
		buttonLabel = sellLabel,
		buttonCoin = buttonCoin,
		buttonPrice = buttonPrice,
	}

	-- The bag, with the undo button.
	local _, belt = panel(board, Vector2.new(1307, 197), Vector2.new(28, 853), DARK_TOP, DARK_BOTTOM, 18, 8)
	local bagLabel = UiStyle.text(belt, "INVENTORY", 40, C.Cream, C.Edge)
	bagLabel.Size = UDim2.fromOffset(250, 60)
	bagLabel.Position = UDim2.fromOffset(18, 18)
	local undoOuter, _, _ = panel(belt, Vector2.new(220, 70), Vector2.new(34, 92), CARD_TOP, CARD_BOTTOM, 14, 5)
	local undoLabel = UiStyle.text(undoOuter, "UNDO", 34, C.Ink)
	undoLabel.Size = UDim2.fromScale(1, 1)
	undoLabel.ZIndex = 3
	local undoButton = clickable(undoOuter)
	hoverable(undoButton)
	undoButton.Activated:Connect(function()
		UiSound.play("Undo")
		send("Undo")
	end)
	for i = 1, Config.Shop.Slots do
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.Size = UDim2.fromOffset(150, 150)
		button.Position = UDim2.fromOffset(300 + (i - 1) * 164, 16)
		button.Parent = belt
		UiStyle.corner(button, 14)
		local gradient = UiStyle.gradient(button, DARK_TOP, DARK_BOTTOM)
		local edge = UiStyle.stroke(button, C.GoldDark, 3)
		local number = UiStyle.text(button, tostring(i), 28, C.Cream, C.Edge)
		number.Size = UDim2.fromOffset(30, 30)
		number.Position = UDim2.fromOffset(8, 4)
		number.ZIndex = 3
		local art = image(button, "", 112, UDim2.fromScale(0.5, 0.52), Vector2.one / 2)
		local badge = UiStyle.frame(button, UDim2.fromOffset(40, 36), UDim2.new(1, -6, 1, -6), Vector2.one)
		badge.BackgroundColor3 = Color3.fromRGB(44, 30, 20)
		badge.ZIndex = 3
		UiStyle.corner(badge, 8)
		local count = UiStyle.text(badge, "", 26, C.Cream)
		count.Size = UDim2.fromScale(1, 1)
		count.ZIndex = 4
		button.MouseEnter:Connect(function()
			if Items.bag(player)[i] then
				UiSound.play("Hover")
			end
		end)
		button.Activated:Connect(function()
			if Items.bag(player)[i] then
				UiSound.play("Pick")
				pickedSlot = i
				paint()
			end
		end)
		button.MouseButton2Click:Connect(function()
			if Items.bag(player)[i] then
				pickedSlot = i
				sell(i)
			end
		end)
		slots[i] = { button = button, gradient = gradient, stroke = edge, icon = art, badge = badge, count = count }
	end
end

function Shop.isOpen(): boolean
	return isOpen
end

local function showPrompts()
	local team = player.Character and player.Character:GetAttribute("Team") or "Blue"
	for anchor, prompt in prompts do
		prompt.Enabled = not isOpen and anchor:GetAttribute("Team") == team
	end
end

-- Opens the armory, where the hero may shop (at his team's stall, or dead).
function Shop.open()
	if isOpen or player:GetAttribute("AtShop") ~= true then
		return
	end
	isOpen = true
	gui.Enabled = true
	gui.DisplayOrder = 18
	UiSound.play("ShopOpen")
	refit()
	HeroCamera.setEnabled(false)
	showCategory(category)
	showPrompts()
end

function Shop.close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	UiSound.play("ShopClose")
	HeroCamera.setEnabled(true)
	showPrompts()
end

-- The prompt at a stall (Workspace.Armories, ShopService) that opens the armory; only the hero's own team's show.
local function addPrompt(anchor: Instance)
	if not anchor:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Armory"
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = PROMPT_HOLD
	prompt.MaxActivationDistance = Config.Shop.Reach
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(Shop.open)
	prompts[anchor] = prompt
	showPrompts()
end

function Shop.start()
	build()
	-- Loaded now, so the board and every item's icon show at once the first time the shop opens or an item is bought.
	local images: { any } = { gui }
	for _, item in Config.Items do
		table.insert(images, item.Icon)
	end
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, images)
	-- Roblox only readies an image for drawing once it is on screen, and lets it go again while the shop is closed: each
	-- icon stays drawn as a near-clear pixel in the corner so it shows at once.
	local held = UiStyle.screen("ShopIcons", player:WaitForChild("PlayerGui"), -10)
	for _, item in Config.Items do
		local pixel = Instance.new("ImageLabel")
		pixel.BackgroundTransparency = 1
		pixel.Image = item.Icon
		pixel.ImageTransparency = 0.99
		pixel.Size = UDim2.fromOffset(1, 1)
		pixel.Parent = held
	end
	task.spawn(function()
		shopEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Shop") :: RemoteEvent
	end)
	task.spawn(function()
		local armories = Workspace:WaitForChild("Armories")
		armories.ChildAdded:Connect(addPrompt)
		for _, anchor in armories:GetChildren() do
			addPrompt(anchor)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		character:GetAttributeChangedSignal("Team"):Connect(showPrompts)
		showPrompts()
	end)
	player.AttributeChanged:Connect(function(name)
		if name == "AtShop" and player:GetAttribute("AtShop") ~= true then
			Shop.close()
		elseif isOpen and (name == "Coins" or name == "AtShop" or name:match("^Item") or name:match("^Count")) then
			paint()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.B then
			return
		end
		if isOpen then
			Shop.close()
		else
			Shop.open()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not isOpen then
			return
		end
		local fightAt = Workspace:GetAttribute("FightAt")
		local left = if fightAt then fightAt - Workspace:GetServerTimeNow() else 0
		countdown.Visible = left > 0
		if left > 0 then
			countdownText.Text = string.format("FIGHT IN  %d", math.ceil(left))
		end
	end)
end

return Shop
