-- The heroes' shop (design 12, Shared.HeroShop): on the left the Featured hero large, with how long until the next and
-- his price, and on the right the Daily heroes, with how long until they change. Heroes are bought for coins only
-- (Robux and the coin packs come later); the daily ones the player already owns are left out. Without heroes for sale
-- the places say that new heroes are coming.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroShop = require(ReplicatedStorage.Shared.HeroShop)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)
local HeroesPage = require(script.Parent.HeroesPage)

local ShopPage = {}

local C = UiStyle.Colors

local function now(): number
	return math.floor(Workspace:GetServerTimeNow())
end

-- A small dark pill with a clock's lettering (the time left).
local function timer(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local pill = Widgets.dark(parent, size, position, anchor, size.Y.Offset // 2)
	local text = Widgets.label(pill, "", math.floor(size.Y.Offset * 0.5), C.Cream)
	return text
end

-- An empty place: a dark silhouette with a question mark and `text` under it.
local function empty(parent: Instance, text: string, big: boolean)
	local holder = UiStyle.frame(parent, UDim2.fromScale(1, 1))
	UiStyle.corner(holder, 10)
	UiStyle.gradient(holder, Color3.fromRGB(70, 58, 50), Color3.fromRGB(30, 24, 22))
	local mark = Widgets.label(holder, "?", if big then 260 else 110, Color3.fromRGB(116, 100, 88))
	mark.Size = UDim2.fromScale(1, 0.75)
	local note = Widgets.label(holder, text, if big then 40 else 26, C.Cream, nil, C.Edge)
	note.Size = UDim2.new(1, -20, 0.25, 0)
	note.Position = UDim2.new(0, 10, 0.72, 0)
	note.TextWrapped = true
end

function ShopPage.build(page: Frame, api: any)
	local middle = Widgets.middle(page, 820)
	-- Featured.
	local _, featuredInner, featuredBody =
		Widgets.panel(middle, UDim2.fromOffset(700, 820), UDim2.fromOffset(40, 0), nil, "", 38)
	local featuredTitle = featuredInner:FindFirstChild("Title", true) :: TextLabel
	featuredTitle.Text = "FEATURED"
	featuredTitle.TextXAlignment = Enum.TextXAlignment.Left
	featuredTitle.Position = UDim2.fromOffset(28, 0)
	local featuredClock = timer(featuredInner, UDim2.fromOffset(270, 44), UDim2.new(1, -22, 0, 4), Vector2.new(1, 0))
	local featuredHolder = UiStyle.frame(featuredBody, UDim2.new(1, -28, 1, -14), UDim2.fromOffset(14, 0))
	featuredHolder.BackgroundTransparency = 1

	-- Daily.
	local _, dailyInner, dailyBody =
		Widgets.panel(middle, UDim2.new(1, -820, 0, 820), UDim2.new(1, -40, 0, 0), Vector2.new(1, 0), "", 38)
	local dailyTitle = dailyInner:FindFirstChild("Title", true) :: TextLabel
	dailyTitle.Text = "DAILY"
	dailyTitle.TextXAlignment = Enum.TextXAlignment.Left
	dailyTitle.Position = UDim2.fromOffset(28, 0)
	local dailyClock = timer(dailyInner, UDim2.fromOffset(360, 44), UDim2.new(1, -22, 0, 4), Vector2.new(1, 0))
	local dailyGrid = UiStyle.frame(dailyBody, UDim2.new(1, -28, 1, -14), UDim2.fromOffset(14, 0))
	dailyGrid.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -9, 0.5, -9)
	grid.CellPadding = UDim2.fromOffset(18, 18)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = dailyGrid

	local offer = HeroShop.offer(now())

	local function buyButton(
		parent: Instance,
		hero: string,
		data: Profile.Data,
		size: UDim2,
		position: UDim2,
		anchor: Vector2,
		textSize: number
	)
		if Profile.owns(data, hero) then
			local b, text = Widgets.button(parent, "✓ OWNED", "Green", size, position, anchor, textSize)
			Widgets.enable(b, false, "Green")
			Widgets.paint(b, "Green")
			return b, text
		end
		local b, text = Widgets.button(parent, "", "Gold", size, position, anchor, textSize)
		text.Text = ""
		local row = Widgets.price(b, Config.Heroes[hero].Price or 0, textSize, C.Cream)
		row.ZIndex = 3
		for _, d in row:GetDescendants() do
			if d:IsA("TextLabel") then
				d.ZIndex = 3
				local edge = Instance.new("UIStroke")
				edge.Color = C.Edge
				edge.Thickness = math.max(2, textSize / 12)
				edge.Parent = d
			end
		end
		b.Activated:Connect(function()
			HeroesPage.buy(api, hero)
		end)
		return b, text
	end

	local function showFeatured(data: Profile.Data)
		for _, child in featuredHolder:GetChildren() do
			child:Destroy()
		end
		local hero = offer.featured
		if not hero then
			empty(featuredHolder, "NEW HEROES ARRIVE SOON", true)
			return
		end
		local settings = Config.Heroes[hero]
		local picture = Widgets.portrait(featuredHolder, hero, UDim2.fromScale(1, 1))
		UiStyle.corner(picture, 10)
		UiStyle.stroke(picture, C.Edge, 3)
		local name = Widgets.label(picture, hero, 84, C.Cream, nil, C.Edge)
		name.Size = UDim2.new(1, 0, 0, 90)
		name.Position = UDim2.new(0, 0, 1, -270)
		local role = Widgets.label(picture, string.upper(settings.Role or ""), 36, C.Cream, nil, C.Edge)
		role.Size = UDim2.new(1, 0, 0, 40)
		role.Position = UDim2.new(0, 0, 1, -184)
		buyButton(picture, hero, data, UDim2.new(1, -60, 0, 100), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1), 48)
	end

	local function dailyCard(hero: string?, order: number, data: Profile.Data)
		local card = UiStyle.frame(dailyGrid, UDim2.new())
		card.LayoutOrder = order
		card.BackgroundTransparency = 1
		if not hero then
			empty(card, "COMING SOON", false)
			return
		end
		local settings = Config.Heroes[hero]
		local back = UiStyle.frame(card, UDim2.fromScale(1, 1))
		UiStyle.corner(back, 10)
		UiStyle.gradient(back, C.Cream, C.CreamDark)
		UiStyle.stroke(back, C.GoldDark, 2.5)
		local picture = Widgets.portrait(back, hero, UDim2.new(0.5, -8, 1, -16), UDim2.fromOffset(8, 8), true)
		UiStyle.corner(picture, 8)
		local name = Widgets.label(back, hero, 44, C.Ink)
		name.Size = UDim2.new(0.5, -10, 0, 50)
		name.Position = UDim2.new(0.5, 4, 0, 40)
		local role = Widgets.label(
			back,
			string.upper(settings.Role or ""),
			26,
			Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.4)
		)
		role.Size = UDim2.new(0.5, -10, 0, 30)
		role.Position = UDim2.new(0.5, 4, 0, 92)
		buyButton(back, hero, data, UDim2.new(0.5, -26, 0, 74), UDim2.new(0.75, -2, 1, -18), Vector2.new(0.5, 1), 38)
	end

	local function render()
		local data = ProfileClient.get()
		if not data then
			return
		end
		offer = HeroShop.offer(now())
		showFeatured(data)
		for _, child in dailyGrid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local daily = {}
		for _, hero in offer.daily do
			if not Profile.owns(data, hero) then
				table.insert(daily, hero)
			end
		end
		for i = 1, Config.HeroShop.Daily do
			dailyCard(daily[i], i, data)
		end
	end

	Widgets.every(featuredClock, 1, function()
		local t = now()
		featuredClock.Text = "NEW IN " .. Widgets.left(offer.featuredEnds - t)
		dailyClock.Text = "REFRESHES IN " .. Widgets.left(offer.dailyEnds - t)
		if t >= offer.dailyEnds then
			render()
		end
	end)
	ProfileClient.watch(render)
	return render
end

return ShopPage
