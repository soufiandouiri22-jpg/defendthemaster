-- The ranked page (design 14, Shared.Ranks): on the left the player's rank (its badge, name and LP in the division,
-- his wins, losses and win rate, and when the season ends), in the middle every tier's badge with its divisions or how
-- it is reached, the player's own framed in gold, on the right the coins the season pays for the best tier reached, and
-- under it all the way to the ladder (LeaderboardPage).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local RankedPage = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local SETTINGS = Config.Ranked

-- The tier `data`'s player shows: Sunborn or Master by his place on the ladder (the server's RankShown).
local function shownTier(data: Profile.Data): number
	return Players.LocalPlayer:GetAttribute("RankShown") or data.Rank.Tier
end

local function yourRank(page: Frame): (data: Profile.Data) -> ()
	local _, _, body = Widgets.panel(page, UDim2.fromOffset(440, 690), UDim2.fromOffset(40, 0), nil, "YOUR RANK", 34)
	local badge = Widgets.badge(body, 1, 250, UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0))
	local name = Widgets.label(body, "", 46, C.Ink)
	name.Size = UDim2.new(1, 0, 0, 52)
	name.Position = UDim2.fromOffset(0, 262)
	local bar = UiStyle.bar(body, UDim2.new(1, -60, 0, 40), UDim2.fromOffset(30, 324), C.Blue, C.BlueDark)
	local lp = Widgets.label(bar.frame, "", 26, C.Cream, nil, C.Edge)
	lp.ZIndex = 3

	local stats = UiStyle.frame(body, UDim2.new(1, -40, 0, 110), UDim2.fromOffset(20, 384))
	stats.BackgroundTransparency = 1
	local values = {}
	for i, heading in { "WINS", "LOSSES", "WIN RATE" } do
		local cell = UiStyle.frame(stats, UDim2.fromScale(1 / 3, 1), UDim2.fromScale((i - 1) / 3, 0))
		cell.BackgroundTransparency = 1
		local h = Widgets.label(cell, heading, 24, W.Muted)
		h.Size = UDim2.new(1, 0, 0, 30)
		h.Position = UDim2.fromOffset(0, 8)
		local v = Widgets.label(cell, "0", 50, C.Ink)
		v.Size = UDim2.new(1, 0, 0, 56)
		v.Position = UDim2.fromOffset(0, 42)
		values[i] = v
		if i > 1 then
			local rule = UiStyle.frame(cell, UDim2.new(0, 2, 1, -20), UDim2.fromOffset(0, 10))
			rule.BackgroundColor3 = C.GoldDark
			rule.BackgroundTransparency = 0.5
		end
	end
	local rule = UiStyle.frame(body, UDim2.new(1, -60, 0, 2), UDim2.fromOffset(30, 504))
	rule.BackgroundColor3 = C.GoldDark
	rule.BackgroundTransparency = 0.4
	local ends = Widgets.label(body, "", 26, C.Ink)
	ends.Size = UDim2.new(1, -20, 0, 60)
	ends.Position = UDim2.fromOffset(10, 514)
	ends.TextWrapped = true

	return function(data: Profile.Data)
		local tier = shownTier(data)
		badge:SetAttribute("Tier", tier)
		local divided = Ranks.divided(tier)
		name.Text = string.upper(Ranks.label(tier, if divided then data.Rank.Division else nil))
		if not Ranks.placed(data.Rank) then
			badge:SetAttribute("Tier", 1)
			name.Text = "UNRANKED"
			bar:set(data.Rank.Placements / SETTINGS.Placements)
			lp.Text = "PLACEMENTS " .. data.Rank.Placements .. " / " .. SETTINGS.Placements
		elseif divided then
			bar:set(data.Rank.Lp / SETTINGS.DivisionLp)
			lp.Text = data.Rank.Lp .. " / " .. SETTINGS.DivisionLp .. " LP"
		else
			bar:set(1)
			lp.Text = UiStyle.thousands(data.Rank.Lp) .. " LP"
		end
		local wins, losses = data.Rank.Wins, data.Rank.Losses
		values[1].Text = tostring(wins)
		values[2].Text = tostring(losses)
		values[3].Text = if wins + losses > 0 then math.round(100 * wins / (wins + losses)) .. "%" else "-"
		local open, why = Ranks.unlocked(data)
		if not open then
			ends.Text = string.upper(why :: string)
			ends.TextColor3 = W.Bad
		else
			local days = math.max(0, math.ceil((Pass.endsAt() - Workspace:GetServerTimeNow()) / 86400))
			ends.Text = "SEASON "
				.. Config.Season.Number
				.. " ENDS IN "
				.. days
				.. (if days == 1 then " DAY" else " DAYS")
			ends.TextColor3 = C.Ink
		end
	end
end

local function tiers(page: Frame): (data: Profile.Data) -> ()
	local area = UiStyle.frame(page, UDim2.new(1, -1040, 0, 640), UDim2.new(0.5, -10, 0, 25), Vector2.new(0.5, 0))
	area.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.2, -10, 0.5, -10)
	grid.CellPadding = UDim2.fromOffset(12, 20)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = area
	local frames = {}
	for tier, settings in SETTINGS.Tiers do
		local cell = UiStyle.frame(area, UDim2.new())
		cell.LayoutOrder = tier
		cell.BackgroundTransparency = 1
		local glow = UiStyle.frame(cell, UDim2.fromScale(1, 1))
		glow.BackgroundColor3 = Color3.fromRGB(60, 36, 16)
		glow.BackgroundTransparency = 0.35
		UiStyle.corner(glow, 14)
		UiStyle.stroke(glow, C.Xp, 4)
		glow.Visible = false
		glow.Name = "Glow"
		Widgets.badge(cell, tier, 196, UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
		local name = Widgets.label(cell, tier .. " " .. string.upper(settings.Name), 28, C.Cream, nil, C.Edge)
		name.Size = UDim2.new(1, 0, 0, 32)
		name.Position = UDim2.new(0, 0, 1, -72)
		local span = Widgets.label(cell, Ranks.span(tier), 22, C.CreamDark, nil, C.Edge)
		span.Size = UDim2.new(1, 0, 0, 26)
		span.Position = UDim2.new(0, 0, 1, -38)
		frames[tier] = glow
	end
	return function(data: Profile.Data)
		local own = shownTier(data)
		for tier, glow in frames do
			glow.Visible = tier == own
		end
	end
end

local function seasonRewards(page: Frame): (data: Profile.Data) -> ()
	local _, _, body = Widgets.panel(
		page,
		UDim2.fromOffset(440, 690),
		UDim2.new(1, -40, 0, 0),
		Vector2.new(1, 0),
		"SEASON REWARDS",
		34
	)
	local list = UiStyle.frame(body, UDim2.new(1, -28, 1, -20), UDim2.fromOffset(14, 6))
	list.BackgroundTransparency = 1
	Widgets.list(list, "Vertical", 14)
	local rows = {}
	for i, reward in SETTINGS.SeasonRewards do
		local row = UiStyle.frame(list, UDim2.new(1, 0, 0, 150))
		row.LayoutOrder = i
		UiStyle.corner(row, 10)
		UiStyle.gradient(row, Color3.fromRGB(250, 236, 200), Color3.fromRGB(226, 204, 158))
		local edge = UiStyle.stroke(row, C.GoldDark, 2)
		Widgets.badge(row, reward.Tier, 96, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
		local name = Widgets.label(row, string.upper(Ranks.name(reward.Tier)), 34, C.Ink, "Left")
		name.Size = UDim2.new(1, -130, 0, 44)
		name.Position = UDim2.fromOffset(120, 26)
		local coins = UiStyle.frame(row, UDim2.new(1, -130, 0, 44), UDim2.fromOffset(120, 80))
		coins.BackgroundTransparency = 1
		local price = Widgets.price(coins, reward.Coins, 34)
		local layout = price:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		rows[i] = { edge = edge, tier = reward.Tier }
	end
	local note = Widgets.label(list, "THE BEST TIER YOU REACH THIS SEASON PAYS OUT AT ITS END.", 22, W.Muted)
	note.Size = UDim2.new(1, 0, 0, 60)
	note.TextWrapped = true
	note.LayoutOrder = 100
	return function(data: Profile.Data)
		local best = 0
		for i, row in rows do
			if data.Rank.Peak >= row.tier then
				best = i
			end
		end
		for i, row in rows do
			row.edge.Color = if i == best then C.Xp else C.GoldDark
			row.edge.Thickness = if i == best then 4 else 2
		end
	end
end

function RankedPage.build(page: Frame, api: any)
	-- The three blocks with the ladder's button 30 under them, together in the middle of the room under the tab bar.
	local middle = Widgets.middle(page, 820)
	local showRank = yourRank(middle)
	local showTiers = tiers(middle)
	local showRewards = seasonRewards(middle)
	local ladder = Widgets.button(
		middle,
		"VIEW LEADERBOARD",
		"Gold",
		UDim2.fromOffset(560, 100),
		UDim2.fromScale(0.5, 1),
		Vector2.new(0.5, 1),
		44
	)
	local trophy = Instance.new("ImageLabel")
	trophy.BackgroundTransparency = 1
	trophy.Image = Assets.MenuTrophy
	trophy.ScaleType = Enum.ScaleType.Fit
	trophy.Size = UDim2.fromOffset(64, 64)
	trophy.Position = UDim2.new(0, 30, 0.5, 0)
	trophy.AnchorPoint = Vector2.new(0, 0.5)
	trophy.ZIndex = 3
	trophy.Parent = ladder
	local ladderText = ladder:FindFirstChild("Label") :: TextLabel
	ladderText.Position = UDim2.fromOffset(40, 0)
	ladderText.Size = UDim2.new(1, -40, 1, 0)
	ladder.Activated:Connect(function()
		api.go("Leaderboard")
	end)
	local function render()
		local data = ProfileClient.get()
		if data then
			showRank(data)
			showTiers(data)
			showRewards(data)
		end
	end
	ProfileClient.watch(render)
	Players.LocalPlayer:GetAttributeChangedSignal("RankShown"):Connect(render)
	return render
end

return RankedPage
