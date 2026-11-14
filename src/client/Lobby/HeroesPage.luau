-- The heroes' page (design 11): every hero of Config.Heroes as a card in a grid (his portrait, name and class, and
-- owned, his price, or the season pass he comes from), filtered by class, with places for heroes still to come; and
-- on the right the chosen hero large, with his line, his five abilities and what can be done with him: become him (the
-- menu's `become`: back to Play, where the podium's hero turns into him), buy him for coins, or find him in the pass. A hero's mastery (Shared.Mastery) shows as his
-- crest on his card, and for the chosen hero with the points to the next level, the Marks of Mastery it asks, the
-- season's next milestone and, from level Config.Mastery.Title, his title.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroShop = require(ReplicatedStorage.Shared.HeroShop)
local Mastery = require(ReplicatedStorage.Shared.Mastery)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local HeroesPage = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local COLUMNS = 5
-- The grid always shows at least this many places, the rest as heroes to come.
local PLACES = 10
local CARD_HEIGHT = 330
local KEYS = { "M1", "M2", "E", "R", "Dash" }
local LABELS = { Dash = "Shift" }
-- The mouse's buttons show as the mouse with that button lit.
local MOUSE = { M1 = Assets.MouseLeft, M2 = Assets.MouseRight }
local PURPLE = Widgets.Kinds.Purple

local function heroNames(): { string }
	local list = {}
	for name in Config.Heroes do
		table.insert(list, name)
	end
	-- Owned starters first, then by price, then by name.
	table.sort(list, function(a, b)
		local sa, sb = Config.Heroes[a], Config.Heroes[b]
		local ka = if sa.Starter then 0 elseif sa.Exclusive then 2 else 1
		local kb = if sb.Starter then 0 elseif sb.Exclusive then 2 else 1
		if ka ~= kb then
			return ka < kb
		end
		if (sa.Price or 0) ~= (sb.Price or 0) then
			return (sa.Price or 0) < (sb.Price or 0)
		end
		return a < b
	end)
	return list
end

-- The strip along a card's foot: owned, the price, or the pass.
local function cardFoot(card: Frame, hero: string, data: Profile.Data)
	local settings = Config.Heroes[hero]
	local foot = UiStyle.frame(card, UDim2.new(1, -12, 0, 46), UDim2.new(0, 6, 1, -6), Vector2.new(0, 1))
	UiStyle.corner(foot, 6)
	if Profile.owns(data, hero) then
		UiStyle.gradient(foot, Color3.fromRGB(226, 240, 196), Color3.fromRGB(196, 222, 160))
		local text = Widgets.label(foot, "✓ OWNED", 26, W.Good)
		text.Name = "Owned"
	elseif settings.Exclusive then
		UiStyle.gradient(foot, PURPLE[1], PURPLE[2])
		Widgets.label(foot, Pass.name((Pass.current(Workspace:GetServerTimeNow()))), 22, C.Cream, nil, C.Edge)
	elseif settings.Price then
		UiStyle.gradient(foot, C.Cream, C.CreamDark)
		UiStyle.stroke(foot, C.GoldDark, 1.5)
		Widgets.price(foot, settings.Price, 26)
	else
		UiStyle.gradient(foot, C.Cream, C.CreamDark)
		Widgets.label(foot, "SOON", 24, W.Muted)
	end
end

-- Asks whether to buy `hero` for his price and, when yes, buys him (MenuService's BuyHero).
function HeroesPage.buy(api: any, hero: string)
	local price = Config.Heroes[hero].Price or 0
	local data = api.data()
	if data and data.Coins < price then
		api.notice("Not enough coins: " .. hero .. " costs " .. UiStyle.thousands(price) .. ".", true)
		return
	end
	Widgets.confirm(
		api.gui,
		"BUY HERO",
		"Buy " .. hero .. " for " .. UiStyle.thousands(price) .. " coins?",
		"BUY",
		"Gold",
		function()
			local answer = api.ask("BuyHero", hero)
			if answer.ok then
				UiSound.play("Buy", 0.9)
				api.notice(hero .. " joins your heroes!")
			end
		end
	)
end

function HeroesPage.build(page: Frame, api: any)
	local selected = Config.DefaultHero
	local filter = "All"

	-- The grid's panel on the left, the chosen hero's on the right, both with their middles in the middle of the room
	-- under the tab bar.
	local middle = Widgets.middle(page, 922)
	local _, inner = UiStyle.panel(middle, UDim2.new(1, -660, 0, 820), UDim2.fromOffset(40, 51), nil, 14, 5)
	local _, side = UiStyle.panel(middle, UDim2.fromOffset(560, 922), UDim2.new(1, -40, 0, 0), Vector2.new(1, 0), 14, 5)

	local count = Widgets.label(inner, "MY HEROES", 36, C.Ink, "Left")
	count.Size = UDim2.fromOffset(330, 60)
	count.Position = UDim2.fromOffset(28, 14)

	local filters = UiStyle.frame(inner, UDim2.new(1, -380, 0, 56), UDim2.new(1, -20, 0, 16), Vector2.new(1, 0))
	filters.BackgroundTransparency = 1
	local filterLayout = Widgets.list(filters, "Horizontal", 8)
	filterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local filterButtons: { [string]: TextButton } = {}
	local names = { "All" }
	for _, class in Config.Classes do
		table.insert(names, class)
	end

	local grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.new(1, -36, 1, -98)
	grid.Position = UDim2.fromOffset(18, 86)
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = C.GoldDark
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = inner
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / COLUMNS, -14, 0, CARD_HEIGHT)
	layout.CellPadding = UDim2.fromOffset(14, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 6)
	gridPadding.PaddingLeft = UDim.new(0, 6)
	gridPadding.PaddingRight = UDim.new(0, 6)
	gridPadding.Parent = grid

	-- The chosen hero.
	local picture = UiStyle.frame(side, UDim2.new(1, -28, 0, 320), UDim2.fromOffset(14, 14))
	picture.BackgroundTransparency = 1
	picture.ClipsDescendants = true
	UiStyle.corner(picture, 10)
	local pictureEdge = UiStyle.frame(side, UDim2.new(1, -28, 0, 320), UDim2.fromOffset(14, 14))
	pictureEdge.BackgroundTransparency = 1
	UiStyle.corner(pictureEdge, 10)
	UiStyle.stroke(pictureEdge, C.Edge, 3)
	local heroName = Widgets.label(side, "", 58, C.Ink)
	heroName.Size = UDim2.new(1, 0, 0, 66)
	heroName.Position = UDim2.fromOffset(0, 342)
	local heroRole = Widgets.label(side, "", 32, C.Ink)
	heroRole.Size = UDim2.new(1, 0, 0, 38)
	heroRole.Position = UDim2.fromOffset(0, 404)
	local rule = UiStyle.frame(side, UDim2.new(1, -80, 0, 2), UDim2.fromOffset(40, 452))
	rule.BackgroundColor3 = C.GoldDark
	rule.BackgroundTransparency = 0.4
	local line = Widgets.label(side, "", 28, C.Ink)
	line.Size = UDim2.new(1, -70, 0, 80)
	line.Position = UDim2.fromOffset(35, 460)
	line.TextWrapped = true
	local abilities = UiStyle.frame(side, UDim2.new(1, -60, 0, 130), UDim2.fromOffset(30, 548))
	abilities.BackgroundTransparency = 1
	local abilityLayout = Widgets.list(abilities, "Horizontal", 12)
	abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local masteryBox = Widgets.dark(side, UDim2.new(1, -60, 0, 98), UDim2.fromOffset(30, 692), nil, 12)
	masteryBox.Name = "Mastery"
	UiStyle.stroke(masteryBox, C.GoldDark, 3)
	local action, actionText = Widgets.button(
		side,
		"SET AS FAVOURITE",
		"Blue",
		UDim2.new(1, -60, 0, 80),
		UDim2.new(0.5, 0, 1, -18),
		Vector2.new(0.5, 1),
		38
	)
	local actionKind = "Blue"
	local onAction: (() -> ())? = nil

	local render: () -> ()

	-- The chosen hero's mastery: his crest and level, the bar to the next level (its points, then its marks), and the
	-- season's next milestone or his title.
	local function showMastery(data: Profile.Data)
		for _, child in masteryBox:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local view = Mastery.view(data.Mastery and data.Mastery[selected])
		local crest =
			Widgets.crest(masteryBox, math.max(1, view.level), 96, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
		if view.level == 0 then
			crest.ImageTransparency = 0.55
			local number = crest:FindFirstChild("Level") :: TextLabel
			number.Visible = false
		end
		local head = Widgets.label(
			masteryBox,
			if view.level == 0 then "MASTERY  -  NOT PLAYED" else "MASTERY " .. view.level,
			26,
			C.Cream,
			"Left",
			C.Edge
		)
		head.Size = UDim2.new(1, -120, 0, 30)
		head.Position = UDim2.fromOffset(110, 6)
		local points = view.into < view.need
		local b = UiStyle.bar(
			masteryBox,
			UDim2.new(1, -124, 0, 26),
			UDim2.fromOffset(110, 38),
			Color3.fromRGB(255, 214, 90),
			Color3.fromRGB(200, 120, 20)
		)
		b:set(if points then view.into / view.need elseif view.marksNeed > 0 then view.marks / view.marksNeed else 1)
		local barText = Widgets.label(
			b.frame,
			if points
				then UiStyle.thousands(view.into) .. " / " .. UiStyle.thousands(view.need) .. " POINTS"
				else "MARKS OF MASTERY " .. view.marks .. " / " .. view.marksNeed,
			18,
			C.Cream,
			nil,
			C.Edge
		)
		barText.ZIndex = 3
		local note = if view.title
			then "MASTER OF " .. string.upper(selected)
			else "NEXT MARK: A GAME AT " .. view.goal .. " OR BETTER" .. (if view.goalGames > 1
				then "  (" .. view.progress .. " / " .. view.goalGames .. ")"
				else "")
		local noteText = Widgets.label(masteryBox, note, 17, C.Gold, "Left")
		noteText.Size = UDim2.new(1, -120, 0, 22)
		noteText.Position = UDim2.fromOffset(110, 68)
		noteText.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local function showHero(data: Profile.Data)
		local settings = Config.Heroes[selected]
		for _, child in picture:GetChildren() do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end
		Widgets.portrait(picture, selected, UDim2.fromScale(1, 1))
		heroName.Text = string.upper(selected)
		heroRole.Text = string.upper(settings.Role or "")
		heroRole.TextColor3 = Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.35)
		line.Text = settings.Description or ""
		showMastery(data)
		for _, child in abilities:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, key in KEYS do
			local slot = UiStyle.frame(abilities, UDim2.fromOffset(86, 130))
			slot.BackgroundTransparency = 1
			slot.LayoutOrder = i
			local box = UiStyle.frame(slot, UDim2.fromOffset(84, 84), UDim2.fromOffset(1, 6))
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
				mouse.Position = UDim2.fromOffset(0, 100)
				mouse.Parent = slot
			else
				local keyText = Widgets.label(slot, LABELS[key] or key, 26, C.Ink)
				keyText.Size = UDim2.new(1, 0, 0, 30)
				keyText.Position = UDim2.fromOffset(0, 94)
			end
		end

		local owned = Profile.owns(data, selected)
		if owned and data.Favourite == selected then
			actionText.Text = "YOUR HERO"
			actionKind = "Gold"
			Widgets.enable(action, false, actionKind)
			onAction = nil
		elseif owned then
			actionText.Text = "BECOME " .. string.upper(selected)
			actionKind = "Blue"
			Widgets.enable(action, true, actionKind)
			onAction = function()
				Widgets.enable(action, false, actionKind)
				if not api.become(selected) then
					render()
				end
			end
		elseif HeroShop.forSale(selected) then
			actionText.Text = "BUY  " .. UiStyle.thousands(settings.Price)
			actionKind = "Gold"
			Widgets.enable(action, true, actionKind)
			onAction = function()
				HeroesPage.buy(api, selected)
			end
		elseif settings.Exclusive then
			actionText.Text = Pass.name((Pass.current(Workspace:GetServerTimeNow())))
			actionKind = "Purple"
			Widgets.enable(action, true, actionKind)
			onAction = function()
				api.go("Pass")
			end
		else
			actionText.Text = "COMING SOON"
			actionKind = "Grey"
			Widgets.enable(action, false, actionKind)
			onAction = nil
		end
	end

	local function card(hero: string, order: number, data: Profile.Data)
		local settings = Config.Heroes[hero]
		local owned = Profile.owns(data, hero)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Text = ""
		b.LayoutOrder = order
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = grid
		UiStyle.corner(b, 10)
		UiStyle.gradient(b, C.Cream, C.CreamDark)
		local chosen = hero == selected
		UiStyle.stroke(b, if chosen then C.Xp elseif owned then C.Gold else C.GoldDark, if chosen then 5 else 3)
		local holder = UiStyle.frame(b, UDim2.new(1, -12, 0, 196), UDim2.fromOffset(6, 6))
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = true
		UiStyle.corner(holder, 7)
		local portrait = Widgets.portrait(holder, hero, UDim2.fromScale(1, 1), nil, true)
		UiStyle.corner(portrait, 7)
		if not owned then
			Widgets.lock(holder, 34, UDim2.new(1, -8, 1, -8), Vector2.new(1, 1))
		end
		local level = Mastery.view(data.Mastery and data.Mastery[hero]).level
		if level > 0 then
			Widgets.crest(holder, level, 70, UDim2.new(1, -2, 0, 2), Vector2.new(1, 0))
		end
		if data.Favourite == hero then
			local star = Widgets.label(holder, "★", 34, C.Xp, nil, C.Edge)
			star.Size = UDim2.fromOffset(40, 40)
			star.Position = UDim2.fromOffset(4, 2)
		end
		if settings.Exclusive then
			local ribbon = Widgets.dark(b, UDim2.new(1, -30, 0, 30), UDim2.new(0.5, 0, 0, -10), Vector2.new(0.5, 0), 6)
			local fill = ribbon:FindFirstChildOfClass("UIGradient") :: UIGradient
			fill.Color = ColorSequence.new(PURPLE[1], PURPLE[2])
			Widgets.label(ribbon, "PASS EXCLUSIVE", 18, C.Cream)
		end
		local name = Widgets.label(b, hero, 30, C.Ink)
		name.Size = UDim2.new(1, -8, 0, 34)
		name.Position = UDim2.fromOffset(4, 206)
		name.TextScaled = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local role =
			Widgets.label(b, string.upper(settings.Role or ""), 22, Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.4))
		role.Size = UDim2.new(1, 0, 0, 26)
		role.Position = UDim2.fromOffset(0, 240)
		cardFoot(b, hero, data)
		Widgets.feel(b)
		b.Activated:Connect(function()
			if selected ~= hero then
				selected = hero
				render()
			end
		end)
	end

	-- A place for a hero still to come: a dark silhouette.
	local function soon(order: number)
		local f = UiStyle.frame(grid, UDim2.new())
		f.LayoutOrder = order
		UiStyle.corner(f, 10)
		UiStyle.gradient(f, Color3.fromRGB(214, 196, 160), Color3.fromRGB(186, 166, 128))
		UiStyle.stroke(f, W.Locked, 2.5)
		local holder = UiStyle.frame(f, UDim2.new(1, -12, 0, 196), UDim2.fromOffset(6, 6))
		UiStyle.corner(holder, 7)
		UiStyle.gradient(holder, Color3.fromRGB(70, 60, 54), Color3.fromRGB(34, 28, 26))
		local mark = Widgets.label(holder, "?", 110, Color3.fromRGB(120, 106, 96))
		mark.Name = "Mark"
		local name = Widgets.label(f, "???", 30, W.Muted)
		name.Size = UDim2.new(1, 0, 0, 34)
		name.Position = UDim2.fromOffset(0, 206)
		local foot = UiStyle.frame(f, UDim2.new(1, -12, 0, 46), UDim2.new(0, 6, 1, -6), Vector2.new(0, 1))
		UiStyle.corner(foot, 6)
		foot.BackgroundColor3 = Color3.fromRGB(198, 180, 144)
		Widgets.label(foot, "COMING SOON", 22, W.Muted)
	end

	render = function()
		local data = ProfileClient.get()
		if not data then
			return
		end
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local all = heroNames()
		local owned = 0
		for _, hero in all do
			if Profile.owns(data, hero) then
				owned += 1
			end
		end
		count.Text = "MY HEROES " .. owned .. " / " .. #all
		local shown = 0
		for i, hero in all do
			if filter == "All" or Config.Heroes[hero].Role == filter then
				shown += 1
				card(hero, i, data)
			end
		end
		local places = math.max(PLACES, math.ceil(shown / COLUMNS) * COLUMNS)
		if filter == "All" then
			for i = shown + 1, places do
				soon(1000 + i)
			end
		elseif shown == 0 then
			for i = 1, COLUMNS do
				soon(1000 + i)
			end
		end
		if not Config.Heroes[selected] then
			selected = Config.DefaultHero
		end
		showHero(data)
	end

	for i, name in names do
		local b = Widgets.button(filters, string.upper(name), "Cream", UDim2.new(1 / #names, -8, 0, 52), nil, nil, 24)
		b.LayoutOrder = i
		filterButtons[name] = b
		b.Activated:Connect(function()
			filter = name
			for other, button in filterButtons do
				Widgets.paint(button, if other == filter then "Gold" else "Cream")
			end
			render()
		end)
	end
	Widgets.paint(filterButtons.All, "Gold")

	action.Activated:Connect(function()
		if action.Active and onAction then
			onAction()
		end
	end)
	local first = true
	ProfileClient.watch(function(data)
		if first then
			first = false
			selected = Profile.showcase(data)
		end
		render()
	end)
	return render
end

return HeroesPage
