-- The players of both teams on their cards while a match loads (owner, 2026-10-31, after League of Legends' loading
-- screen), over the loading screen once this client has everything in, the server has given everyone his hero
-- (Net.Draft "Done") and the pictures on the cards have loaded: Blue's four along the top, Red's along the bottom, a
-- tip between them, over the arena. Each card is the hero he plays, large ("MASTER OF" over his name from the mastery
-- of the hero's title on), with the player's own Roblox avatar in a round on its plate carrying his account level, his
-- name, his rank's badge with its name and his LP, and his mastery crest; a ranked player's card is edged in his
-- tier's colours (and with LOADING_BAR it shows how far his loading screen is: the "Loaded" attribute,
-- Net.LoadProgress). A player's card turns round on a click to his profile on its back (PlayerCard); the screen keeps
-- its own time (with HOLD_TURNED a turned card held it). With EARLY it came before the server's lineup, a card showing
-- the hero the player would play ("Showcase") and a place nobody had come for yet waiting empty until the bots filled
-- theirs. The server gives the lineup as soon as everyone is in the server, so the screen comes while the others are
-- still loading; it stays until they all have everything in and then the server's "VersusUntil" (Config.Match.Versus
-- seconds more), and goes with the loading screen under it. Only in a match without a draft (Config.Draft.Enabled off); a client coming in later skips it.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lineup = require(ReplicatedStorage.Shared.Lineup)
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local HeroCamera = require(script.Parent.HeroCamera)
local PlayerCard = require(script.Parent.PlayerCard)
local UiStyle = require(script.Parent.UiStyle)
local Widgets = require(script.Parent.Widgets)

local VersusView = {}

local C = UiStyle.Colors
local TEAM_FILL = { Blue = { C.Blue, C.BlueDark }, Red = { C.Red, C.RedDark } }
local READY = Color3.fromRGB(120, 220, 100)
-- The cards in reference pixels: their size, the room between them, the rows' middles from the screen's middle (so a
-- taller screen keeps them centred) and the plate at their foot with the avatar's round on its top edge.
local CARD_W, CARD_H, CARD_GAP, CARD_CORNER = 300, 404, 30, 14
local ROW_Y = { Blue = -244, Red = 244 }
local TIP_Y = 0
-- Each card's loading bar with LOADING N% and READY on its plate; off since the owner found it out of place
-- (2026-10-31), the plate then only as high as the name and the rank need.
local LOADING_BAR = false
local PLATE_H = if LOADING_BAR then 140 else 116
local AVATAR, CREST = 78, 70
-- How fast the glint goes round the edge of a Legend's card and up, in degrees a second.
local GLINT = 120
-- What a card draws on its frame beside its inside (the inside's own pieces go with it), cleared before it draws again.
local DRAWN = { Crest = true, Avatar = true, Back = true, Hover = true, Turn = true }
-- With HOLD_TURNED a card turned round keeps the screen up for its player, up to TURNED_UNTIL seconds before the
-- fight; off since the owner wants the screen to last its own time (2026-10-31).
local HOLD_TURNED = false
local TURNED_UNTIL = 3
-- The arena behind the cards, as League shows its map: the colosseum of the loading screen before
-- (Art/UI/loading_plate.png), darkened to DIM so the cards stand out.
local ARENA = "rbxassetid://127668674329359"
local DIM = 0.42
-- The cards come in one after another, this far apart in seconds; the screen fades in and out in FADE seconds.
local STAGGER, FADE = 0.06, 0.4
-- The longest it waits for the server's lineup before it lets the loading screen go anyway.
local LONGEST = 60
-- The screen comes in complete (owner, 2026-10-31): built out of sight under the loading screen, it waits for the
-- server's lineup and then for every picture on its cards (the avatars come from Roblox only now), at most PICTURES
-- seconds. With EARLY it came at once with the lineup as it stood (each player's hero to be, the places
-- nobody had come for yet WAITING...) and filled in when the server's came.
local EARLY = false
local PICTURES = 3
-- The screen comes right after this client's loading screen, as League's does, and stays until every player is in
-- (the server's "VersusUntil" comes then); waiting longer than WAITING_AFTER seconds, the tip's line says for how many.
local WAITING_AFTER = 1

local TIPS = {
	"An ability you can raise glows on your bar: spend your points before you forget them.",
	"The Sun Crown makes its carrier and his team hit harder. Take it, and do not drop it.",
	"Standing on your own pad heals you once you are out of the fight for a moment.",
	"Your Master is the match: if he falls, it is over. Do not leave him alone too long.",
	"Shop in the buy phase: nobody can attack before the fight begins.",
	"Kills in a row are worth more. Stay alive to keep your streak.",
}

type Entry = {
	team: string,
	index: number,
	userId: number,
	name: string,
	hero: string?,
	shown: number?,
	division: number?,
	lp: number?,
	placements: number?,
	position: number?,
	level: number?,
	mastery: number,
	player: Player?,
	empty: boolean,
}

type Card = {
	frame: Frame,
	inner: Frame,
	entry: Entry?,
	key: string,
	bar: Frame?,
	status: TextLabel?,
	glint: UIGradient?,
	turned: boolean?,
	-- In the lobby (VersusView.travel) the cards do not turn: the backs need what the match's server publishes.
	still: boolean?,
}

local player = Players.LocalPlayer

-- What `other` carries of his rank and level (ProfileService), on `entry`.
local function standing(entry: Entry, other: Player?): Entry
	if other then
		entry.shown = entry.shown or other:GetAttribute("RankShown")
		entry.division = entry.division or other:GetAttribute("RankDivision")
		entry.lp = other:GetAttribute("RankLp")
		entry.placements = other:GetAttribute("RankPlacements")
		entry.position = other:GetAttribute("RankPosition")
		entry.level = entry.level or other:GetAttribute("AccountLevel")
	end
	return entry
end

-- The places as they stand before the server's lineup: each team's players who are here (the "Team" attribute) with
-- the hero they will play, the rest empty.
local function provisional(): { Entry }
	local list = {}
	for _, team in Config.TeamOrder do
		local here = {}
		for _, other in Players:GetPlayers() do
			if other:GetAttribute("Team") == team then
				table.insert(here, other)
			end
		end
		table.sort(here, function(a, b)
			return a.UserId < b.UserId
		end)
		for index = 1, Config.HeroesPerTeam do
			local other = here[index]
			table.insert(
				list,
				standing({
					team = team,
					index = index,
					userId = if other then other.UserId else 0,
					name = if other then other.DisplayName else "",
					hero = if other then other:GetAttribute("Showcase") else nil,
					mastery = if other then other:GetAttribute("ShowcaseMastery") or 0 else 0,
					player = other,
					empty = other == nil,
				}, other)
			)
		end
	end
	return list
end

-- The places from the server's lineup (Net.Draft's picks).
local function final(state: any): { Entry }
	local list = {}
	for _, pick in state.picks or {} do
		local index = tonumber(string.match(pick.key or "", "%d+$")) or 1
		local other = if pick.userId > 0 then Players:GetPlayerByUserId(pick.userId) else nil
		table.insert(
			list,
			standing({
				team = pick.team,
				index = index,
				userId = pick.userId,
				name = pick.name,
				hero = pick.hero,
				shown = pick.shown,
				division = pick.division,
				level = pick.level,
				mastery = if pick.mastery and pick.hero then pick.mastery[pick.hero] or 0 else 0,
				player = other,
				empty = false,
			}, other)
		)
	end
	return list
end

-- The places from the lobby's lineup of a found match (Net.Queue "Lineup", Shared.Lineup): each team's players in
-- their order, then its bots with the heroes the match's server will give them.
local function travelling(lineup: any): { Entry }
	local list = {}
	for _, team in Config.TeamOrder do
		local ids = (lineup.teams or {})[team] or {}
		local taken = {}
		local count = math.min(#ids, Config.HeroesPerTeam)
		for index = 1, count do
			local id = ids[index]
			local card = (lineup.cards or {})[tostring(id)] or {}
			local hero = card.hero or Config.DefaultHero
			table.insert(taken, hero)
			table.insert(list, {
				team = team,
				index = index,
				userId = id,
				name = card.name or "",
				hero = hero,
				shown = card.shown,
				division = card.division,
				lp = card.lp,
				placements = card.placements,
				position = card.position,
				level = card.level,
				mastery = card.mastery or 0,
				player = Players:GetPlayerByUserId(id),
				empty = false,
			})
		end
		for offset, hero in Lineup.botHeroes(taken, Config.HeroesPerTeam - count) do
			table.insert(list, {
				team = team,
				index = count + offset,
				userId = 0,
				name = "Bot",
				hero = hero,
				mastery = 0,
				empty = false,
			})
		end
	end
	return list
end

-- The line under a player's name, in the middle of `plate` at `y`: his rank's badge, its name in the tier's colour
-- and his LP (a Sunborn or Master his place on the ladder); while he plays his placements how far he is, before
-- them UNRANKED; a bot's BOT.
local function rankLine(plate: Frame, entry: Entry, y: number)
	local line = UiStyle.frame(plate, UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, y))
	line.BackgroundTransparency = 1
	Widgets.list(line, "Horizontal", 6, "Center")
	local function text(value: string, colour: Color3, order: number)
		local label = Widgets.label(line, value, 19, colour, nil, C.Edge)
		label.Size = UDim2.fromScale(0, 1)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = order
	end
	if entry.userId <= 0 then
		text("BOT", C.CreamDark, 1)
		return
	end
	local tier = entry.shown
	if not tier then
		local played = entry.placements or 0
		text(if played > 0 then `PLACEMENTS {played}/{Config.Ranked.Placements}` else "UNRANKED", C.CreamDark, 1)
		return
	end
	local badge = Widgets.badge(line, tier, 32)
	badge.LayoutOrder = 1
	text(string.upper(Ranks.label(tier, entry.division)), (Widgets.tierColours(tier)), 2)
	if tier > Ranks.LEGEND and entry.position then
		text(`#{entry.position}`, C.Gold, 3)
	elseif entry.lp then
		text(`{entry.lp} LP`, C.Cream, 3)
	end
end

-- The card's edge: a ranked player's in his tier's colours, glinting round from Legend up; else his team's, or gold
-- on the player's own card.
local function edge(card: Card, entry: Entry, mine: boolean)
	local stroke = card.frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	local old = stroke:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	card.glint = nil
	local tier = if entry.empty then nil else entry.shown
	if not tier then
		stroke.Color = if mine then C.Gold else (TEAM_FILL[entry.team] or TEAM_FILL.Blue)[1]
		return
	end
	local shine = PlayerCard.shine(stroke, tier)
	if tier >= Ranks.LEGEND then
		card.glint = shine
	end
end

-- The player's account level in a small round at the foot of his avatar's round.
local function levelRound(round: Frame, level: number)
	local dot = UiStyle.frame(round, UDim2.fromOffset(34, 26), UDim2.fromScale(0.86, 0.86), Vector2.new(0.5, 0.5))
	dot.Name = "Level"
	dot.ZIndex = 5
	UiStyle.corner(dot, UDim.new(0.5, 0))
	UiStyle.gradient(dot, Color3.fromRGB(74, 52, 34), Color3.fromRGB(38, 26, 18))
	UiStyle.stroke(dot, C.Gold, 2)
	local number = Widgets.label(dot, tostring(level), 16, C.Cream, nil, C.Edge)
	number.ZIndex = 6
end

-- Draws `entry` on `card`, from nothing.
local function draw(card: Card, entry: Entry)
	for _, child in card.inner:GetChildren() do
		child:Destroy()
	end
	for _, child in card.frame:GetChildren() do
		if DRAWN[child.Name] then
			child:Destroy()
		end
	end
	card.inner.Visible = true
	local wasTurned = card.turned
	card.turned = false
	card.entry = entry
	card.bar, card.status = nil, nil
	local fill = TEAM_FILL[entry.team] or TEAM_FILL.Blue
	local mine = entry.userId == player.UserId and entry.userId > 0
	edge(card, entry, mine)

	if entry.empty or not entry.hero then
		local back = UiStyle.frame(card.inner, UDim2.fromScale(1, 1))
		UiStyle.corner(back, CARD_CORNER)
		UiStyle.gradient(back, fill[2]:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(14, 12, 18))
		local mark = Widgets.label(card.inner, "?", 120, fill[1]:Lerp(Color3.new(1, 1, 1), 0.2), nil, C.Edge)
		mark.Size = UDim2.new(1, 0, 1, -PLATE_H)
		mark.TextTransparency = 0.5
	else
		-- Each layer rounds its own corners: ClipsDescendants only cuts square ones.
		local portrait = Widgets.portrait(card.inner, entry.hero, UDim2.fromScale(1, 1))
		UiStyle.corner(portrait, CARD_CORNER)
		local dim = UiStyle.frame(card.inner, UDim2.fromScale(1, 1))
		UiStyle.corner(dim, CARD_CORNER)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		local fall = Instance.new("UIGradient")
		fall.Rotation = 90
		fall.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		fall.Parent = dim
		-- From the mastery that earns the hero's title on, "MASTER OF" over his name, both in gold.
		local titled = entry.mastery >= Config.Mastery.Title
		local heroName =
			Widgets.label(card.inner, string.upper(entry.hero), 32, if titled then C.Gold else C.Cream, nil, C.Edge)
		heroName.Size = UDim2.new(1, -20, 0, 38)
		heroName.Position = UDim2.new(0, 10, 1, -PLATE_H - AVATAR / 2 - 46)
		if titled then
			local title = Widgets.label(card.inner, "MASTER OF", 18, C.Gold, nil, C.Edge)
			title.Size = UDim2.new(1, -20, 0, 20)
			title.Position = UDim2.new(0, 10, 1, -PLATE_H - AVATAR / 2 - 64)
		end
	end

	local plate =
		Widgets.dark(card.inner, UDim2.new(1, -16, 0, PLATE_H), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1), 12)
	UiStyle.stroke(plate, if mine then C.GoldDark else fill[2], 3)
	if entry.empty then
		Widgets.label(plate, "WAITING...", 24, C.CreamDark, nil, C.Edge)
		return
	end

	-- The avatar's round on the plate's top edge, over the card's frame so the card does not cut it; a bot's shows BOT.
	local round = UiStyle.frame(
		card.frame,
		UDim2.fromOffset(AVATAR, AVATAR),
		UDim2.new(0.5, 0, 1, -8 - PLATE_H),
		Vector2.new(0.5, 0.5)
	)
	round.Name = "Avatar"
	round.ZIndex = 3
	UiStyle.corner(round, UDim.new(0.5, 0))
	UiStyle.gradient(round, fill[1], fill[2])
	UiStyle.stroke(round, if mine then C.Gold else C.Edge, 3)
	if entry.userId > 0 then
		local head = Instance.new("ImageLabel")
		head.BackgroundTransparency = 1
		head.Size = UDim2.fromScale(1, 1)
		head.Image = "rbxthumb://type=AvatarHeadShot&id=" .. entry.userId .. "&w=150&h=150"
		head.ZIndex = 4
		head.Parent = round
		UiStyle.corner(head, UDim.new(0.5, 0))
	else
		local bot = Widgets.label(round, "BOT", 22, C.Cream, nil, C.Edge)
		bot.ZIndex = 4
	end
	if entry.userId > 0 and entry.level then
		levelRound(round, entry.level)
	end

	local name = Widgets.label(plate, entry.name, 26, if mine then C.Gold else C.Cream, nil, C.Edge)
	name.Size = UDim2.new(1, -20, 0, 30)
	name.Position = UDim2.fromOffset(10, AVATAR / 2 + 4)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	rankLine(plate, entry, AVATAR / 2 + 36)

	if entry.mastery > 0 then
		local crest = Widgets.crest(card.frame, entry.mastery, CREST, UDim2.new(0.5, 0, 0, -14), Vector2.new(0.5, 0))
		crest.ZIndex = 3
		for _, child in crest:GetDescendants() do
			if child:IsA("GuiObject") then
				child.ZIndex = 4
			end
		end
	end
	-- A player's card turns round on a click to his profile on its back (a bot's has none); drawn again, it stays turned.
	if entry.userId > 0 and not card.still then
		local turn = PlayerCard.flippable(
			{ card.frame },
			card.frame,
			{
				userId = entry.userId,
				name = entry.name,
				hero = entry.hero,
				mastery = entry.mastery,
				shown = entry.shown,
				division = entry.division,
			},
			CARD_CORNER,
			function(back)
				card.turned = back
			end
		)
		if wasTurned then
			turn()
		end
	end
	if not LOADING_BAR then
		return
	end

	-- How far his loading screen is: a thin bar along the plate's foot with its share, READY once he is in.
	local track = UiStyle.frame(plate, UDim2.new(1, -36, 0, 6), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1))
	track.BackgroundColor3 = Color3.new(0, 0, 0)
	track.BackgroundTransparency = 0.5
	UiStyle.corner(track, UDim.new(0.5, 0))
	local bar = UiStyle.frame(track, UDim2.fromScale(0, 1))
	bar.BackgroundColor3 = C.Cream
	UiStyle.corner(bar, UDim.new(0.5, 0))
	local status = Widgets.label(plate, "", 15, C.CreamDark)
	status.Size = UDim2.new(1, -20, 0, 16)
	status.Position = UDim2.new(0, 10, 1, -36)
	card.bar, card.status = bar, status
end

-- A card's glint going round its edge, its loading bar and status: the bots and whoever is ready are READY.
local function update(card: Card)
	if card.glint then
		card.glint.Rotation = (os.clock() * GLINT) % 360
	end
	local entry = card.entry
	if not entry or not card.bar or not card.status then
		return
	end
	local other = entry.player
	local ready = entry.userId <= 0 or (other and other:GetAttribute("ClientReady") == true)
	local share = if ready then 1 elseif other then other:GetAttribute("Loaded") or 0 else 0
	card.bar.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	card.bar.BackgroundColor3 = if ready then READY else C.Cream
	card.status.Text = if ready then "READY" else `LOADING {math.floor(share * 100 + 0.5)}%`
	card.status.TextColor3 = if ready then READY else C.CreamDark
end

-- A key for what a card shows, so it is only drawn again when that changes.
local function keyOf(entry: Entry): string
	return table.concat({
		entry.userId,
		entry.name,
		entry.hero or "",
		entry.shown or "",
		entry.division or "",
		entry.lp or "",
		entry.placements or "",
		entry.position or "",
		entry.level or "",
		entry.mastery,
		tostring(entry.empty),
	}, "|")
end

-- Builds the screen; returns its gui and its cards by team and place.
local function build(): (ScreenGui, { [string]: Card })
	local gui = UiStyle.screen("Versus", player:WaitForChild("PlayerGui"), 1001)
	local back = Instance.new("ImageLabel")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BorderSizePixel = 0
	back.BackgroundColor3 = Color3.fromRGB(8, 7, 10)
	back.Image = ARENA
	back.ScaleType = Enum.ScaleType.Crop
	back.Parent = gui
	local dim = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.fromRGB(8, 7, 10)
	dim.BackgroundTransparency = DIM
	for team, y in ROW_Y do
		local fill = TEAM_FILL[team]
		local glow = UiStyle.frame(gui, UDim2.new(1, 0, 0, CARD_H + 120), UDim2.new(0, 0, 0.5, y), Vector2.new(0, 0.5))
		glow.BackgroundColor3 = fill[1]
		local shape = Instance.new("UIGradient")
		shape.Rotation = 90
		shape.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		})
		shape.Parent = glow
	end

	local tip = Widgets.label(gui, TIPS[math.random(#TIPS)], 24, C.Cream, nil, C.Edge)
	tip.Name = "Tip"
	tip.Size = UDim2.new(1, -200, 0, 30)
	tip.Position = UDim2.new(0.5, 0, 0.5, TIP_Y)
	tip.AnchorPoint = Vector2.new(0.5, 0.5)

	local cards = {}
	local row = Config.HeroesPerTeam * CARD_W + (Config.HeroesPerTeam - 1) * CARD_GAP
	for _, team in Config.TeamOrder do
		for index = 1, Config.HeroesPerTeam do
			local x = -row / 2 + (index - 1) * (CARD_W + CARD_GAP) + CARD_W / 2
			local frame = UiStyle.frame(
				gui,
				UDim2.fromOffset(CARD_W, CARD_H),
				UDim2.new(0.5, x, 0.5, ROW_Y[team]),
				Vector2.new(0.5, 0.5)
			)
			frame.Name = team .. index
			frame.BackgroundTransparency = 1
			UiStyle.corner(frame, 14)
			UiStyle.stroke(frame, TEAM_FILL[team][1], 4)
			local inner = UiStyle.frame(frame, UDim2.fromScale(1, 1))
			inner.Name = "Inner"
			inner.BackgroundTransparency = 1
			inner.ClipsDescendants = true
			UiStyle.corner(inner, 14)
			cards[team .. index] = { frame = frame, inner = inner, entry = nil, key = "" }
		end
	end
	return gui, cards
end

-- Fades `gui` in (from nothing) or out over FADE seconds; the cards also rise into place one after another. With
-- `instant` it is there at once, in place of the same cards that came with the teleport.
local function show(gui: ScreenGui, cards: { [string]: Card }, instant: boolean?)
	local group = Instance.new("CanvasGroup")
	group.Name = "Fade"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = if instant then 0 else 1
	group.Parent = gui
	for _, child in gui:GetChildren() do
		if child ~= group and child:IsA("GuiObject") then
			child.Parent = group
		end
	end
	if instant then
		return
	end
	Widgets.tween(group, FADE, { GroupTransparency = 0 })
	local order = 0
	for _, team in Config.TeamOrder do
		for index = 1, Config.HeroesPerTeam do
			local card = cards[team .. index]
			local goal = card.frame.Position
			card.frame.Position = goal + UDim2.fromOffset(0, if team == Config.TeamOrder[1] then -40 else 40)
			task.delay(order * STAGGER, function()
				Widgets.tween(card.frame, 0.35, { Position = goal })
			end)
			order += 1
		end
	end
end

-- Puts `entries` on the cards, drawing again only those that changed.
local function place(cards: { [string]: Card }, entries: { Entry })
	for _, entry in entries do
		local card = cards[entry.team .. entry.index]
		if card then
			local key = keyOf(entry)
			if key ~= card.key then
				card.key = key
				draw(card, entry)
			else
				card.entry = entry
			end
		end
	end
end

-- Whether the player holds the screen: a card of it turned round, until TURNED_UNTIL seconds before the fight.
local function holding(cards: { [string]: Card }): boolean
	if not HOLD_TURNED then
		return false
	end
	local fightAt = Workspace:GetAttribute("FightAt")
	if typeof(fightAt) == "number" and Workspace:GetServerTimeNow() >= fightAt - TURNED_UNTIL then
		return false
	end
	for _, card in cards do
		if card.turned then
			return true
		end
	end
	return false
end

-- While the server waits for players still loading (no "VersusUntil" yet), what the tip's line says instead: how many
-- of the players on the cards are in.
local function waiting(cards: { [string]: Card }): string?
	if typeof(Workspace:GetAttribute("VersusUntil")) == "number" then
		return nil
	end
	local total, ready = 0, 0
	for _, card in cards do
		local entry = card.entry
		if entry and entry.userId > 0 then
			total += 1
			local other = entry.player or Players:GetPlayerByUserId(entry.userId)
			if other and other:GetAttribute("ClientReady") == true then
				ready += 1
			end
		end
	end
	return `WAITING FOR PLAYERS  {ready}/{total}`
end

-- Hides Roblox's chat while the screen is up: its window lies over the top left card and takes its clicks. Returns
-- what brings it back as it was.
local function hideChat(): () -> ()
	local parts: { Instance } = {}
	for _, class in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local part = TextChatService:FindFirstChildOfClass(class)
		if part and (part :: any).Enabled then
			(part :: any).Enabled = false
			table.insert(parts, part)
		end
	end
	return function()
		for _, part in parts do
			(part :: any).Enabled = true
		end
	end
end

-- Runs the screen in a match without a draft; `release` lets the loading screen go (it goes when the cards have been
-- shown, or at once on the test ground and for a client coming in after the start).
function VersusView.start(release: () -> (), waitReady: () -> ())
	if Workspace:GetAttribute("TestGround") == true then
		release()
		return
	end
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, { ARENA })
	local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Draft") :: RemoteEvent
	local state: any = nil
	event.OnClientEvent:Connect(function(s)
		state = s
	end)
	event:FireServer("Hello")
	-- The cards that came with the teleport (VersusView.travel) are up already; else the screen comes once this client
	-- has everything in under the black one.
	local arrived = Loading.arrived()
	if not arrived then
		waitReady()
	end
	local function over(): boolean
		local untilAt = Workspace:GetAttribute("VersusUntil")
		return typeof(untilAt) == "number" and Workspace:GetServerTimeNow() >= untilAt
	end
	local function lineup(): boolean
		return state ~= nil and state.phase == "Done"
	end
	local phase = Workspace:GetAttribute("Phase")
	if phase == "Buy" or phase == "Fight" or phase == "Ended" or over() then
		if arrived then
			arrived:Destroy()
		end
		release()
		return
	end

	-- The mouse stays free for the cards, also once the hero stands under the screen, and while it waits for them.
	HeroCamera.setEnabled(false)
	local gui, cards = build()
	local placedFinal = false
	local started = os.clock()
	if EARLY then
		place(cards, provisional())
	else
		gui.Enabled = false
		while not lineup() and os.clock() - started < LONGEST do
			task.wait(0.1)
		end
		placedFinal = lineup()
		place(cards, if placedFinal then final(state) else provisional())
		Loading.preload({ gui }, PICTURES)
		if over() then
			gui:Destroy()
			if arrived then
				arrived:Destroy()
			end
			release()
			HeroCamera.setEnabled(true)
			return
		end
		gui.Enabled = true
	end
	local tip = gui:FindFirstChild("Tip", true) :: TextLabel
	-- In place of the cards that came with the teleport: the same, now turning on a click, with their tip.
	local came = arrived and arrived:FindFirstChild("Tip", true) :: TextLabel?
	if came then
		tip.Text = came.Text
	end
	local saying = tip.Text
	show(gui, cards, arrived ~= nil)
	if arrived then
		arrived:Destroy()
	end
	Loading.unshield()
	local showChat = hideChat()
	local frame = RunService.RenderStepped:Connect(function()
		for _, card in cards do
			update(card)
		end
	end)
	local shownAt = os.clock()
	while os.clock() - started < LONGEST do
		if state and state.phase == "Done" then
			if not placedFinal then
				placedFinal = true
				place(cards, final(state))
			end
			if over() and not holding(cards) then
				break
			end
		elseif not placedFinal then
			place(cards, provisional())
		end
		local line = if os.clock() - shownAt >= WAITING_AFTER then waiting(cards) else nil
		tip.Text = line or saying
		tip.TextColor3 = if line then C.Gold else C.Cream
		task.wait(0.25)
	end
	release()
	HeroCamera.setEnabled(true)
	showChat()
	local group = gui:FindFirstChild("Fade") :: CanvasGroup?
	if group then
		Widgets.tween(group, 0.5, { GroupTransparency = 1 })
	end
	task.delay(0.6, function()
		frame:Disconnect()
		gui:Destroy()
	end)
end

-- In the lobby: once a match is found (Net.Queue "Lineup") its cards come over the menu, complete with their pictures
-- (at most PICTURES seconds), and go along as the teleport's screen, so the player sees them until the fight
-- (Loading.arrived, VersusView.start); then the lobby's server teleports him ("Prepared"). If the match falls through
-- (the queue's state is no longer Found), they go and the black screen goes along on teleports again.
function VersusView.travel()
	local queue = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Queue") :: RemoteEvent
	local current: ScreenGui? = nil
	local glinting: RBXScriptConnection? = nil
	local function drop()
		local gui = current
		current = nil
		if glinting then
			glinting:Disconnect()
			glinting = nil
		end
		if gui then
			local group = gui:FindFirstChild("Fade") :: CanvasGroup?
			if group then
				Widgets.tween(group, 0.3, { GroupTransparency = 1 })
			end
			task.delay(0.35, function()
				gui:Destroy()
			end)
			Loading.forTeleport()
		end
	end
	queue.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Lineup" and typeof(payload) == "table" and not current then
			local gui, cards = build()
			gui.Enabled = false
			current = gui
			for _, card in cards do
				card.still = true
			end
			place(cards, travelling(payload))
			Loading.preload({ gui }, PICTURES)
			if current ~= gui then
				return
			end
			gui.Enabled = true
			show(gui, cards)
			glinting = RunService.RenderStepped:Connect(function()
				for _, card in cards do
					update(card)
				end
			end)
			-- Sent along once the cards stand in place, as they then show in the match.
			task.wait(FADE + STAGGER * (2 * Config.HeroesPerTeam) + 0.35)
			if current ~= gui then
				return
			end
			TeleportService:SetTeleportGui(gui)
			queue:FireServer("Prepared")
		elseif kind == "State" and typeof(payload) == "table" then
			if payload.state ~= "Found" and payload.state ~= "Teleporting" then
				drop()
			end
		end
	end)
end

return VersusView
