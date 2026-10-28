-- The ladder (design 15, server Ladder through MenuService's Ladder): Global (the season's top 100) or Friends, the best
-- three on a podium of gold, silver and bronze, the others in a list under a header (#, player, tier, LP), and along the
-- foot the player's own place, rank, LP and wins. Every score is shown as its tier (Shared.Ranks), a Legend in the top as
-- Sunborn or Master by his place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local LeaderboardPage = {}

local C = UiStyle.Colors
local W = Widgets.Colors
-- How long a tab's list is kept before it is asked for again.
local KEEP = 30
local ROW = 74
local PODIUM = {
	{ colours = { Color3.fromRGB(232, 178, 70), Color3.fromRGB(168, 110, 30) }, height = 250 },
	{ colours = { Color3.fromRGB(196, 196, 204), Color3.fromRGB(122, 124, 136) }, height = 200 },
	{ colours = { Color3.fromRGB(196, 120, 70), Color3.fromRGB(126, 66, 34) }, height = 160 },
}

type Entry = { userId: number, name: string, score: number, position: number? }

-- The tier, division and LP an entry shows.
local function standing(entry: Entry, global: boolean): (number, number, number)
	local tier, division, lp = Ranks.fromScore(entry.score)
	if global then
		tier = Ranks.shown({ Tier = tier } :: any, entry.position)
	end
	return tier, division, lp
end

local function tierText(tier: number, division: number): string
	return string.upper(Ranks.label(tier, if Ranks.divided(tier) then division else nil))
end

-- A Roblox player's whole avatar, standing.
local function figure(parent: Instance, userId: number, size: UDim2, position: UDim2, anchor: Vector2): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = size
	image.Position = position
	image.AnchorPoint = anchor
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = parent
	if userId > 0 then
		task.spawn(function()
			local ok, content = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				userId,
				Enum.ThumbnailType.AvatarThumbnail,
				Enum.ThumbnailSize.Size420x420
			)
			if ok then
				image.Image = content
			end
		end)
	end
	return image
end

function LeaderboardPage.build(page: Frame, api: any)
	local tab = "Global"
	local cache: { [string]: { at: number, answer: any } } = {}

	-- The Global and Friends tabs, the podium and the list, and the player's own place under them: one block in the
	-- middle of the room under the tab bar.
	local middle = Widgets.middle(page, 918)

	-- The podium of the best three.
	local _, podiumInner = UiStyle.panel(middle, UDim2.fromOffset(760, 640), UDim2.fromOffset(50, 138), nil, 14, 5)
	local podium = UiStyle.frame(podiumInner, UDim2.new(1, -40, 1, -70), UDim2.fromOffset(20, 60))
	podium.BackgroundTransparency = 1
	Widgets.ribbon(middle, "TOP 100", UDim2.fromOffset(300, 64), UDim2.fromOffset(430, 104), Vector2.new(0.5, 0))

	-- The list of the others.
	local _, listInner =
		UiStyle.panel(middle, UDim2.new(1, -910, 0, 640), UDim2.new(1, -50, 0, 138), Vector2.new(1, 0), 14, 5)
	local header = Widgets.dark(listInner, UDim2.new(1, -24, 0, 50), UDim2.fromOffset(12, 12), nil, 8)
	local COLUMNS = {
		{ "#", 0, 70 },
		{ "PLAYER", 150, 0.42 },
		{ "TIER", 0.56, 0.28 },
		{ "LP", 0.86, 0.12 },
	}
	for i, spec in COLUMNS do
		local text = Widgets.label(header, spec[1], 26, C.Cream, if i == 2 then "Left" else nil)
		local x, w = spec[2], spec[3]
		text.Position = if x >= 1 then UDim2.fromOffset(x, 0) else UDim2.fromScale(x, 0)
		text.Size = if w >= 1 then UDim2.new(0, w, 1, 0) else UDim2.fromScale(w, 1)
	end
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, -24, 1, -80)
	list.Position = UDim2.fromOffset(12, 70)
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = C.GoldDark
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = listInner

	-- The player's own place along the foot.
	local you = UiStyle.frame(middle, UDim2.fromOffset(1090, 110), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1))
	UiStyle.corner(you, 12)
	UiStyle.gradient(you, Color3.fromRGB(46, 84, 170), Color3.fromRGB(18, 36, 90))
	UiStyle.stroke(you, C.Gold, 3)
	local youBadge = Widgets.badge(you, 1, 92, UDim2.new(0, 20, 0.5, 0), Vector2.new(0, 0.5))
	local youCells = {}
	local CELLS = { { 0.12, 0.2 }, { 0.32, 0.3 }, { 0.62, 0.2 }, { 0.82, 0.18 } }
	for i, cell in CELLS do
		local f = UiStyle.frame(you, UDim2.fromScale(cell[2], 1), UDim2.fromScale(cell[1], 0))
		f.BackgroundTransparency = 1
		if i > 1 then
			local rule = UiStyle.frame(f, UDim2.new(0, 2, 1, -30), UDim2.fromOffset(0, 15))
			rule.BackgroundColor3 = Color3.fromRGB(120, 150, 220)
			rule.BackgroundTransparency = 0.4
		end
		local top = Widgets.label(f, "", 40, C.Cream, nil, C.Edge)
		top.Size = UDim2.fromScale(1, 0.55)
		top.Position = UDim2.fromScale(0, 0.08)
		local bottom = Widgets.label(f, "", 22, Color3.fromRGB(200, 214, 250))
		bottom.Size = UDim2.fromScale(1, 0.3)
		bottom.Position = UDim2.fromScale(0, 0.6)
		youCells[i] = { top = top, bottom = bottom }
	end

	local function row(entry: Entry, index: number, global: boolean)
		local tier, division, lp = standing(entry, global)
		local r = UiStyle.frame(list, UDim2.new(1, -10, 0, ROW), UDim2.fromOffset(0, (index - 1) * (ROW + 6)))
		UiStyle.corner(r, 8)
		local mine = entry.userId == Players.LocalPlayer.UserId
		if mine then
			UiStyle.gradient(r, Color3.fromRGB(255, 232, 160), Color3.fromRGB(240, 204, 120))
			UiStyle.stroke(r, C.GoldDark, 2)
		else
			UiStyle.gradient(
				r,
				if index % 2 == 0 then C.Cream else W.Parchment,
				if index % 2 == 0 then C.CreamDark else W.Stripe
			)
		end
		local position = Widgets.label(r, tostring(entry.position or index), 32, C.Ink)
		position.Size = UDim2.new(0, 70, 1, 0)
		Widgets.avatar(r, entry.userId, ROW - 16, UDim2.new(0, 80, 0.5, 0), Vector2.new(0, 0.5))
		local name = Widgets.label(r, entry.name, 30, C.Ink, "Left")
		name.Size = UDim2.new(0.42, -10, 1, 0)
		name.Position = UDim2.fromOffset(150, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		Widgets.badge(r, tier, ROW - 14, UDim2.fromScale(0.56, 0.5), Vector2.new(0, 0.5))
		local tierLabel = Widgets.label(r, tierText(tier, division), 24, C.Ink, "Left")
		tierLabel.Size = UDim2.new(0.28, -(ROW - 4), 1, 0)
		tierLabel.Position = UDim2.new(0.56, ROW - 4, 0, 0)
		local lpText = Widgets.label(r, UiStyle.thousands(lp), 30, C.Ink)
		lpText.Size = UDim2.fromScale(0.12, 1)
		lpText.Position = UDim2.fromScale(0.86, 0)
	end

	local function place(entry: Entry?, slot: number, global: boolean)
		local count = #PODIUM
		local spec = PODIUM[slot]
		local column = UiStyle.frame(podium, UDim2.new(1 / count, -16, 1, 0), UDim2.new((slot - 1) / count, 8, 0, 0))
		column.BackgroundTransparency = 1
		local block = UiStyle.frame(column, UDim2.new(1, 0, 0, spec.height), UDim2.fromScale(0, 1), Vector2.new(0, 1))
		UiStyle.corner(block, 8)
		UiStyle.gradient(block, spec.colours[1], spec.colours[2])
		UiStyle.stroke(block, C.Edge, 3)
		local disc = UiStyle.frame(block, UDim2.fromOffset(62, 62), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
		UiStyle.corner(disc, 31)
		UiStyle.gradient(disc, spec.colours[1]:Lerp(Color3.new(1, 1, 1), 0.3), spec.colours[2])
		UiStyle.stroke(disc, C.Edge, 2.5)
		Widgets.label(disc, tostring(slot), 40, C.Cream, nil, C.Edge)
		if not entry then
			local none = Widgets.label(block, "-", 40, C.Cream, nil, C.Edge)
			none.Size = UDim2.new(1, 0, 0, 50)
			none.Position = UDim2.fromOffset(0, 84)
			return
		end
		local tier, _, lp = standing(entry, global)
		-- The thumbnail leaves room under the feet, so it stands a little into the block.
		figure(
			column,
			entry.userId,
			UDim2.new(1, 40, 0, 320),
			UDim2.new(0.5, 0, 1, -spec.height + 34),
			Vector2.new(0.5, 1)
		)
		local name = Widgets.label(block, entry.name, 24, C.Cream, nil, C.Edge)
		name.Size = UDim2.new(1, -8, 0, 30)
		name.Position = UDim2.fromOffset(4, 80)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		Widgets.badge(
			block,
			tier,
			if spec.height >= 200 then 64 else 40,
			UDim2.new(0.5, 0, 0, 110),
			Vector2.new(0.5, 0)
		)
		local points = Widgets.label(block, UiStyle.thousands(lp) .. " LP", 24, C.Cream, nil, C.Edge)
		points.Size = UDim2.new(1, 0, 0, 30)
		points.Position = UDim2.new(0, 0, 1, -38)
	end

	local function showYou(answer: any, data: Profile.Data?)
		local player = Players.LocalPlayer
		local rank = data and data.Rank
		local tier = player:GetAttribute("RankShown") or (rank and rank.Tier) or 1
		youBadge:SetAttribute("Tier", tier)
		local mine = answer and answer.you
		local position = mine and mine.position
		if tab == "Friends" and answer and answer.entries then
			position = nil
			for i, entry in answer.entries do
				if entry.userId == player.UserId then
					position = i
				end
			end
		end
		youCells[1].top.Text = if position then "#" .. UiStyle.thousands(position) elseif mine then "100+" else "-"
		youCells[1].bottom.Text = if mine or position then "PLACE" else "UNRANKED"
		youCells[2].top.Text = player.DisplayName
		youCells[2].top.TextTruncate = Enum.TextTruncate.AtEnd
		youCells[2].bottom.Text = if rank then tierText(tier, rank.Division) else ""
		youCells[3].top.Text = if rank then UiStyle.thousands(rank.Lp) .. " LP" else "0 LP"
		youCells[3].bottom.Text = "LP"
		youCells[4].top.Text = if rank then tostring(rank.Wins) else "0"
		youCells[4].bottom.Text = "WINS"
	end

	local function show(answer: any)
		for _, child in podium:GetChildren() do
			child:Destroy()
		end
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local entries: { Entry } = answer and answer.entries or {}
		local global = tab == "Global"
		for slot = 1, 3 do
			place(entries[slot], slot, global)
		end
		for i = 4, #entries do
			row(entries[i], i - 3, global)
		end
		if #entries <= 3 then
			local note = Widgets.label(
				list,
				if #entries == 0
					then (if global
						then "NO RANKED PLAYERS YET THIS SEASON."
						else "NONE OF YOUR FRIENDS PLAY RANKED YET.")
					else "NO MORE PLAYERS YET.",
				28,
				W.Muted
			)
			note.Size = UDim2.new(1, 0, 0, 120)
		end
		showYou(answer, ProfileClient.get())
	end

	local function load()
		local kept = cache[tab]
		if kept and os.clock() - kept.at < KEEP then
			show(kept.answer)
			return
		end
		local asked = tab
		local answer = api.ask("Ladder", tab)
		if answer.ok then
			cache[asked] = { at = os.clock(), answer = answer }
		end
		if tab == asked then
			show(if answer.ok then answer else nil)
		end
	end

	local markTab: (name: string) -> ()
	_, markTab = Widgets.tabs(
		middle,
		{ "Global", "Friends" },
		UDim2.fromOffset(460, 60),
		UDim2.fromScale(0.5, 0),
		Vector2.new(0.5, 0),
		function(name: string)
			if name ~= tab then
				tab = name
				markTab(tab)
				task.spawn(load)
			end
		end
	)
	markTab(tab)
	ProfileClient.watch(function(data)
		local kept = cache[tab]
		showYou(kept and kept.answer, data)
	end)
	return function()
		load()
	end
end

return LeaderboardPage
