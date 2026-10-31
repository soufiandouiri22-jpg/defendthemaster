-- A player's profile (owner, 2026-10-31, after League of Legends' cards that turn round on a click): his rank (badge,
-- tier, LP or place on the ladder, wins and losses, the season's peak), his account level, his mastery of the hero he
-- plays and his career (games, wins, win rate, MVPs). Two ways: a card turns round to show it on its back
-- (PlayerCard.flippable: the cards while a match loads and the end screen's star cards), or it opens large over the
-- screen (PlayerCard.open: the end screen's scoreboard rows, too small to turn), with his hero's portrait across the top
-- and his Roblox avatar over its foot. What he carries as attributes (ProfileService) comes from him while he is in the
-- server; after he left only what the screen knew.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local UiStyle = require(script.Parent.UiStyle)
local Widgets = require(script.Parent.Widgets)

local PlayerCard = {}

local C = UiStyle.Colors
local W = Widgets.Colors
-- The large card in reference pixels: its size, the portrait's band across its top and the avatar's round over its
-- foot, the badge and the crest.
local CARD_W, CARD_H = 640, 600
local BANNER = 220
local AVATAR = 124
local BADGE, CREST = 96, 96
-- A card's back: its badge and crest, the avatar's round on top of a card at least BACK_AVATAR_FROM high (the end
-- screen's star cards; the smaller loading cards are full without it and show it on their front), and the turn's
-- halves in seconds (narrowing to its edge, opening again).
local BACK_BADGE, BACK_CREST, BACK_CREST_TALL = 76, 52, 60
local BACK_AVATAR, BACK_AVATAR_FROM = 104, 520
local CLOSE, OPEN = 0.13, 0.16
-- How far under the top of its line a capital of the font (FredokaOne) starts, as a part of the text size: its ascent
-- of 974 and descent of 236 fill the line, its capitals stand 733 high.
local CAP_TOP = (974 - 733) / 1210
-- How far the career boxes' stroke (Widgets.dark's) reaches out of them.
local BOX_EDGE = 2.5

export type Info = {
	userId: number,
	name: string,
	hero: string?,
	mastery: number?,
	shown: number?,
	division: number?,
}

type Reader = (name: string) -> any

-- What the player of `userId` carries while he is in the server.
local function reader(userId: number): Reader
	local other = Players:GetPlayerByUserId(userId)
	return function(name: string): any
		return if other then other:GetAttribute(name) else nil
	end
end

type Standing = {
	tier: number?,
	rank: string,
	colour: Color3,
	standing: string,
	record: string?,
	peak: string?,
}

-- His rank in words: the tier and his LP (a Sunborn or Master his place on the ladder), his record and the season's
-- peak; unranked, how far his placements are or when Ranked opens for him.
local function standing(info: Info, get: Reader): Standing
	local tier = info.shown or get("RankShown")
	if not tier then
		local played = get("RankPlacements") or 0
		local note = if played > 0
			then `PLACEMENTS {played}/{Config.Ranked.Placements}`
			elseif (get("AccountLevel") or 0) < Config.Ranked.Level then `RANKED AT LEVEL {Config.Ranked.Level}`
			else "NO PLACEMENTS YET"
		return { tier = nil, rank = "UNRANKED", colour = C.CreamDark, standing = note }
	end
	local position, lp = get("RankPosition"), get("RankLp")
	local wins, losses = get("RankWins") or 0, get("RankLosses") or 0
	local peak = get("RankPeak")
	return {
		tier = tier,
		rank = string.upper(Ranks.label(tier, info.division or get("RankDivision"))),
		colour = (Widgets.tierColours(tier)),
		standing = if tier > Ranks.LEGEND and position then `#{position} ON THE LADDER` elseif lp then `{lp} LP` else "",
		record = if wins + losses > 0
			then `{wins}W  {losses}L  {math.floor(wins / (wins + losses) * 100 + 0.5)}%`
			else nil,
		peak = if peak then "PEAK  " .. string.upper(Ranks.name(peak)) else nil,
	}
end

-- His career: games, wins, win rate and MVPs, "-" for what is not known.
local function career(get: Reader): { { string } }
	local games, won, mvps = get("CareerGames"), get("CareerWins"), get("CareerMvps")
	return {
		{ if games then tostring(games) else "-", "GAMES" },
		{ if won then tostring(won) else "-", "WINS" },
		{ if games and games > 0 then `{math.floor((won or 0) / games * 100 + 0.5)}%` else "-", "WIN RATE" },
		{ if mvps then tostring(mvps) else "-", "MVPS" },
	}
end

-- A rank badge, or for an unranked player the first one faded.
local function badge(parent: Instance, tier: number?, size: number, position: UDim2?): ImageLabel
	local image = Widgets.badge(parent, tier or 1, size, position)
	if not tier then
		image.ImageTransparency = 0.6
		image.ImageColor3 = Color3.fromRGB(120, 110, 100)
	end
	return image
end

-- `stroke` in the colours of `tier`, light across its middle.
function PlayerCard.shine(stroke: UIStroke, tier: number): UIGradient
	local light, dark = Widgets.tierColours(tier)
	stroke.Color = Color3.new(1, 1, 1)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, dark),
		ColorSequenceKeypoint.new(0.5, light:Lerp(Color3.new(1, 1, 1), 0.35)),
		ColorSequenceKeypoint.new(1, dark),
	})
	shine.Rotation = 35
	shine.Parent = stroke
	return shine
end

-- The portrait's band round the hero's face: the whole width of the picture, as high as the band's shape asks.
local function banner(parent: Frame, hero: string?)
	local image = Widgets.portrait(parent, hero or "", UDim2.new(1, 0, 0, BANNER))
	image.Name = "Banner"
	UiStyle.corner(image, 16)
	local settings = hero and Config.Heroes[hero]
	local portrait = settings and settings.Portrait
	if portrait and portrait.Face then
		local _, y, side = table.unpack(portrait.Face)
		local high = 1024 * BANNER / CARD_W
		local middle = y + side * 0.45
		image.ImageRectOffset = Vector2.new(0, math.clamp(middle - high / 2, 0, 1024 - high))
		image.ImageRectSize = Vector2.new(1024, high)
	end
	local fade = UiStyle.frame(parent, UDim2.new(1, 0, 0, BANNER))
	fade.BackgroundColor3 = W.BrownDark
	UiStyle.corner(fade, 16)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = fade
end

-- A heading over one half of the large card.
local function heading(parent: Instance, value: string, x: number, y: number)
	local label = Widgets.label(parent, value, 18, W.Muted, "Left")
	label.Size = UDim2.fromOffset(280, 22)
	label.Position = UDim2.fromOffset(x, y)
end

-- A line of text beside a badge or a crest on the large card, as wide as its half of the card leaves it.
local function line(parent: Instance, value: string, size: number, colour: Color3, x: number, y: number): TextLabel
	local label = Widgets.label(parent, value, size, colour, "Left", C.Edge)
	local ends = if x < CARD_W / 2 then CARD_W / 2 - 10 else CARD_W - 20
	label.Size = UDim2.fromOffset(ends - x, size + 4)
	label.Position = UDim2.fromOffset(x, y)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

-- Lines of text ({ text, size, colour }) one under the other from `x`, together centred on the height `middle` (the
-- middle of the badge or crest they stand beside).
local function column(parent: Instance, x: number, middle: number, entries: { { any } })
	local gap = 6
	local total = gap * (#entries - 1)
	for _, entry in entries do
		total += entry[2] + 4
	end
	local y = middle - total / 2
	for _, entry in entries do
		line(parent, entry[1], entry[2], entry[3], x, y)
		y += entry[2] + 4 + gap
	end
end

-- The career's boxes along `parent` (its first `count` of them, else all four), `across` in a row (all of them
-- without it), each row `high` pixels high: each box a number over what it counts.
local function stats(
	parent: GuiObject,
	get: Reader,
	high: number,
	numberSize: number,
	labelSize: number,
	across: number?,
	count: number?
): Frame
	local entries = table.move(career(get), 1, count or 4, 1, {})
	local perRow = across or #entries
	local rows = math.ceil(#entries / perRow)
	local gap = 8
	local grid = UiStyle.frame(parent, UDim2.new(1, 0, 0, high * rows + gap * (rows - 1)))
	grid.BackgroundTransparency = 1
	Widgets.list(grid, "Vertical", gap, "Center")
	for r = 1, rows do
		local row = UiStyle.frame(grid, UDim2.new(1, 0, 0, high))
		row.BackgroundTransparency = 1
		row.LayoutOrder = r
		local layout = Widgets.list(row, "Horizontal", gap, "Center")
		layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
		for index = (r - 1) * perRow + 1, math.min(r * perRow, #entries) do
			local entry = entries[index]
			local box = Widgets.dark(row, UDim2.fromScale(0, 1), nil, nil, 8)
			box.LayoutOrder = index
			UiStyle.stroke(box, C.GoldDark, 2)
			local number = Widgets.label(box, entry[1], numberSize, C.Cream, nil, C.Edge)
			number.Size = UDim2.fromScale(1, 0.62)
			local what = Widgets.label(box, entry[2], labelSize, C.Gold)
			what.Size = UDim2.fromScale(1, 0.3)
			what.Position = UDim2.fromScale(0, 0.62)
		end
	end
	return grid
end

-- The player's Roblox avatar in a round `size` across, his account level `level` on its rim's foot.
local function avatar(parent: Instance, userId: number, size: number, level: number?): Frame
	local round = UiStyle.frame(parent, UDim2.fromOffset(size, size))
	round.Name = "Avatar"
	UiStyle.corner(round, UDim.new(0.5, 0))
	UiStyle.gradient(round, C.Blue, C.BlueDark)
	UiStyle.stroke(round, C.Gold, 4)
	local head = Instance.new("ImageLabel")
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 1)
	head.Image = "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=150&h=150"
	head.Parent = round
	UiStyle.corner(head, UDim.new(0.5, 0))
	if level then
		local dot = UiStyle.frame(round, UDim2.fromOffset(52, 32), UDim2.new(0.5, 0, 1, 2), Vector2.new(0.5, 0.5))
		UiStyle.corner(dot, UDim.new(0.5, 0))
		UiStyle.gradient(dot, Color3.fromRGB(74, 52, 34), Color3.fromRGB(38, 26, 18))
		UiStyle.stroke(dot, C.Gold, 2)
		Widgets.label(dot, tostring(level), 20, C.Cream, nil, C.Edge)
	end
	return round
end

-- Opens the large card of `info` over `gui`; clicking beside it or its X closes it.
function PlayerCard.open(gui: Instance, info: Info)
	local get = reader(info.userId)
	local holder = Widgets.popup(gui, "PlayerCard")
	local veil = Widgets.veil(holder, 0.4)
	local card =
		UiStyle.frame(holder, UDim2.fromOffset(CARD_W, CARD_H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	card.Name = "Card"
	UiStyle.corner(card, 16)
	card.BackgroundColor3 = W.BrownDark
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = card
	Widgets.tween(scale, 0.18, { Scale = 1 })

	local rank = standing(info, get)
	local edge = UiStyle.stroke(card, C.Gold, 5)
	if rank.tier then
		PlayerCard.shine(edge, rank.tier)
	end

	banner(card, info.hero)

	-- The avatar's round over the band's foot, his account level on its rim.
	avatar(card, info.userId, AVATAR, get("AccountLevel")).Position = UDim2.fromOffset(30, BANNER - AVATAR * 0.6)

	-- His name and under it his title: Master of the hero from that mastery on, else the hero he played.
	local mastery = info.mastery or 0
	local titled = info.hero ~= nil and mastery >= Config.Mastery.Title
	local nameX = 30 + AVATAR + 18
	local name = Widgets.label(card, info.name, 38, C.Cream, "Left", C.Edge)
	name.Size = UDim2.fromOffset(CARD_W - nameX - 20, 44)
	name.Position = UDim2.fromOffset(nameX, BANNER - 30)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local subtitle = if titled
		then "MASTER OF " .. string.upper(info.hero :: string)
		elseif info.hero then string.upper(info.hero)
		else ""
	local sub = Widgets.label(card, subtitle, 20, if titled then C.Gold else C.CreamDark, "Left", C.Edge)
	sub.Size = UDim2.fromOffset(CARD_W - nameX - 20, 24)
	sub.Position = UDim2.fromOffset(nameX, BANNER + 14)

	-- The rule under the avatar's level, clear of it.
	local divider = UiStyle.frame(card, UDim2.new(1, -60, 0, 2), UDim2.fromOffset(30, BANNER + 86))
	divider.BackgroundColor3 = C.GoldDark
	divider.BackgroundTransparency = 0.4
	local top = BANNER + 104
	local split = UiStyle.frame(card, UDim2.fromOffset(2, 166), UDim2.fromOffset(CARD_W / 2, top - 2))
	split.BackgroundColor3 = C.GoldDark
	split.BackgroundTransparency = 0.6

	-- His rank: the badge with its lines centred beside it.
	heading(card, "RANKED", 30, top)
	local picture = top + 32
	local middle = picture + BADGE / 2
	badge(card, rank.tier, BADGE, UDim2.fromOffset(30, picture))
	local ranked = {
		{ rank.rank, if rank.tier then 24 else 26, rank.colour },
		{ rank.standing, if rank.tier then 20 else 18, C.Cream },
	}
	if rank.record then
		table.insert(ranked, { rank.record, 18, C.CreamDark })
	end
	if rank.peak then
		table.insert(ranked, { rank.peak, 16, C.Gold })
	end
	column(card, 30 + BADGE + 14, middle, ranked)

	-- His mastery of the hero he played, the same way beside its crest.
	local right = CARD_W / 2 + 20
	heading(card, "HERO MASTERY", right, top)
	if info.hero and mastery > 0 then
		Widgets.crest(card, mastery, CREST, UDim2.fromOffset(right, picture))
		column(card, right + CREST + 14, middle, {
			{ string.upper(info.hero), 26, C.Cream },
			{ `LEVEL {mastery}`, 20, C.Gold },
			{
				if titled then "TITLE EARNED" else `TITLE AT LEVEL {Config.Mastery.Title}`,
				16,
				if titled then C.Gold else C.CreamDark,
			},
		})
	else
		column(card, right, middle, {
			{ if info.hero then string.upper(info.hero) else "-", 26, C.Cream },
			{ "NO MASTERY YET", 18, C.CreamDark },
		})
	end

	-- His career.
	local foot = stats(card, get, 70, 30, 15)
	foot.Size = UDim2.new(1, -60, 0, 70)
	foot.Position = UDim2.fromOffset(30, CARD_H - 96)

	local close =
		Widgets.button(card, "X", "Grey", UDim2.fromOffset(46, 46), UDim2.new(1, -12, 0, 12), Vector2.new(1, 0), 26)
	local function shut()
		holder:Destroy()
	end
	close.Activated:Connect(shut)
	veil.Activated:Connect(shut)
end

-- The back of a card filling `parent` (rounded by `radius`): his avatar on a tall card, his name and level, his rank,
-- his mastery of the hero and his career, one under the other in its middle; for a card of any size.
function PlayerCard.back(parent: GuiObject, info: Info, radius: number): Frame
	local get = reader(info.userId)
	local back = UiStyle.frame(parent, UDim2.fromScale(1, 1))
	back.Name = "Back"
	UiStyle.corner(back, radius)
	UiStyle.gradient(back, W.Brown, W.BrownDark)
	local tall = parent.Size.Y.Offset >= BACK_AVATAR_FROM
	local spacing = if tall then 5 else 3
	local nameSize = if tall then 30 else 26
	local layout = Widgets.list(back, "Vertical", spacing, "Center")
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	Widgets.padding(back, 14)
	-- What shows first starts out of its place (the avatar's stroke) or a little inside it (the name's capitals), and
	-- the boxes' stroke reaches BOX_EDGE pixels under them: the padding underneath evens that out, so what shows is
	-- centred.
	local inset = back:FindFirstChildOfClass("UIPadding")
	if inset then
		local first = if tall then -4 else 2 + nameSize * CAP_TOP
		inset.PaddingBottom = UDim.new(0, math.round(14 + first + BOX_EDGE))
	end
	local order = 0
	local function add(item: GuiObject)
		order += 1
		item.LayoutOrder = order
	end
	local function text(value: string, size: number, colour: Color3)
		local label = Widgets.label(back, value, size, colour, nil, C.Edge)
		label.Size = UDim2.new(1, 0, 0, size + 4)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		add(label)
	end
	local function rule()
		local holder = UiStyle.frame(back, UDim2.new(1, 0, 0, if tall then 18 else 14))
		holder.BackgroundTransparency = 1
		local stripe = UiStyle.frame(holder, UDim2.new(0.8, 0, 0, 2), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		stripe.BackgroundColor3 = C.GoldDark
		stripe.BackgroundTransparency = 0.4
		add(holder)
	end

	local level = get("AccountLevel")
	if tall then
		-- Room under the round for the level on its rim.
		local holder = UiStyle.frame(back, UDim2.new(1, 0, 0, BACK_AVATAR + 20))
		holder.BackgroundTransparency = 1
		local round = avatar(holder, info.userId, BACK_AVATAR, level)
		round.AnchorPoint = Vector2.new(0.5, 0)
		round.Position = UDim2.fromScale(0.5, 0)
		add(holder)
		text(info.name, nameSize, C.Cream)
	else
		text(info.name, nameSize, C.Cream)
		text(if level then `LEVEL {level}` else "", 17, C.Gold)
	end
	rule()

	local rank = standing(info, get)
	add((badge(back, rank.tier, BACK_BADGE)))
	text(rank.rank, 24, rank.colour)
	text(rank.standing, 18, C.Cream)
	if rank.record then
		text(rank.record, 16, C.CreamDark)
	end
	if rank.peak then
		text(rank.peak, 15, C.Gold)
	end
	rule()

	-- His mastery of the hero: the crest beside the hero's name and his level or title.
	-- The two lines as high as their text, beside the crest in its middle, or without a crest centred on the card.
	local mastery = info.mastery or 0
	local crestSize = if tall then BACK_CREST_TALL else BACK_CREST
	local heroSize, noteSize = if tall then 22 else 20, 15
	local wordsHigh = heroSize + 4 + noteSize + 4
	local crested = mastery > 0
	local row = UiStyle.frame(back, UDim2.new(1, 0, 0, if crested then crestSize else wordsHigh))
	row.BackgroundTransparency = 1
	Widgets.list(row, "Horizontal", 12, "Center").VerticalAlignment = Enum.VerticalAlignment.Center
	if crested then
		local crest = Widgets.crest(row, mastery, crestSize)
		crest.LayoutOrder = 1
	end
	local words =
		UiStyle.frame(row, if crested then UDim2.fromOffset(160, wordsHigh) else UDim2.new(1, 0, 0, wordsHigh))
	words.BackgroundTransparency = 1
	words.LayoutOrder = 2
	local align = if crested then "Left" else nil
	-- From the mastery of the hero's title on both lines in gold, as "MASTER OF" stands gold on the card's front.
	local titled = mastery >= Config.Mastery.Title
	local heroName = Widgets.label(
		words,
		string.upper(info.hero or "-"),
		heroSize,
		if titled then C.Gold else C.Cream,
		align,
		C.Edge
	)
	heroName.Size = UDim2.new(1, 0, 0, heroSize + 4)
	heroName.TextTruncate = Enum.TextTruncate.AtEnd
	local note = if crested then `MASTERY {mastery}` else "NO MASTERY YET"
	local masteryNote = Widgets.label(words, note, noteSize, if titled then C.Gold else C.CreamDark, align)
	masteryNote.Size = UDim2.new(1, 0, 0, noteSize + 4)
	masteryNote.Position = UDim2.fromOffset(0, heroSize + 4)
	add(row)
	rule()
	-- The boxes stand as far under their rule (their stroke reaching BOX_EDGE pixels out of them) as what shows first
	-- stands under the rule above the hero: his name's capitals, or the crest's picture beside them where it is higher.
	local shows = 2 + heroSize * CAP_TOP
	if crested then
		local tops = Assets.MasteryCrestTops
		shows = math.min((crestSize - wordsHigh) / 2 + shows, crestSize * tops[math.clamp(mastery, 1, #tops)])
	end
	local gap = UiStyle.frame(back, UDim2.new(1, 0, 0, math.max(0, math.round(shows + BOX_EDGE - spacing))))
	gap.BackgroundTransparency = 1
	add(gap)

	-- The career, a little narrower than the card: on a tall card two by two; on a small one its first three in a
	-- row (without the MVPs, so they are not crammed).
	local grid = if tall then stats(back, get, 46, 24, 12, 2) else stats(back, get, 48, 22, 12, nil, 3)
	grid.Size = UDim2.new(if tall then 0.86 else 0.9, 0, 0, grid.Size.Y.Offset)
	add(grid)
	return back
end

-- Makes `host` turn round on a click to show the back of `info`'s card, and back again, together with the other
-- `frames` that make up the card (all of one size and place): each narrows to its middle line, the front gives way to
-- the back, and it opens again. `onTurn` hears whether the back now shows. Lights up under the mouse. Returns what
-- turns it at once, without the movement (a card drawn again that was turned).
function PlayerCard.flippable(
	frames: { GuiObject },
	host: GuiObject,
	info: Info,
	radius: number,
	onTurn: ((back: boolean) -> ())?
): () -> ()
	local light = UiStyle.frame(host, UDim2.fromScale(1, 1))
	light.Name = "Hover"
	light.BackgroundColor3 = Color3.new(1, 1, 1)
	light.BackgroundTransparency = 1
	light.ZIndex = 19
	UiStyle.corner(light, radius)
	local button = Instance.new("TextButton")
	button.Name = "Turn"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 20
	button.Parent = host
	Widgets.feel(button)
	button.MouseEnter:Connect(function()
		Widgets.tween(light, 0.12, { BackgroundTransparency = 0.88 })
	end)
	button.MouseLeave:Connect(function()
		Widgets.tween(light, 0.12, { BackgroundTransparency = 1 })
	end)

	local turned, busy = false, false
	local back: Frame? = nil
	local hidden: { GuiObject } = {}
	local function squeeze(share: number, seconds: number, style: Enum.EasingDirection, shapes: { [GuiObject]: any })
		local last: Tween? = nil
		for frame, shape in shapes do
			local size, position = shape[1], shape[2]
			local wide = size.X.Offset
			local narrow = math.max(2, wide * share)
			last = TweenService:Create(frame, TweenInfo.new(seconds, Enum.EasingStyle.Sine, style), {
				Size = UDim2.new(size.X.Scale, narrow, size.Y.Scale, size.Y.Offset),
				Position = position + UDim2.fromOffset((0.5 - frame.AnchorPoint.X) * (wide - narrow), 0),
			})
			last:Play()
		end
		if last then
			last.Completed:Wait()
		end
	end
	local function swap()
		turned = not turned
		if turned then
			back = back or PlayerCard.back(host, info, radius)
			hidden = {}
			for _, frame in frames do
				for _, child in frame:GetChildren() do
					if
						child:IsA("GuiObject")
						and child ~= back
						and child ~= light
						and child ~= button
						and child.Visible
					then
						child.Visible = false
						table.insert(hidden, child)
					end
				end
			end
			if back then
				back.Visible = true
			end
		else
			for _, child in hidden do
				child.Visible = true
			end
			hidden = {}
			if back then
				back.Visible = false
			end
		end
		if onTurn then
			onTurn(turned)
		end
	end
	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local shapes = {}
		for _, frame in frames do
			shapes[frame] = { frame.Size, frame.Position, frame.ClipsDescendants }
			frame.ClipsDescendants = true
		end
		squeeze(0, CLOSE, Enum.EasingDirection.In, shapes)
		-- A fault in the back still opens the card again rather than leaving it a sliver.
		local ok, fault = pcall(swap)
		if not ok then
			warn("[PlayerCard] turn: " .. tostring(fault))
		end
		squeeze(1, OPEN, Enum.EasingDirection.Out, shapes)
		for frame, shape in shapes do
			frame.Size, frame.Position, frame.ClipsDescendants = shape[1], shape[2], shape[3]
		end
		busy = false
	end)
	return swap
end

return PlayerCard
