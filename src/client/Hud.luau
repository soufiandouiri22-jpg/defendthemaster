-- The HUD of design 05 round the ability bar (AbilityBar): at the top each team's Master's health under its crown,
-- blue left and red right, jolting at every blow he takes, and between them the score (enemy heroes killed) over the match's clock (MatchService),
-- at the bottom left the hero's portrait with his level (a chime as it rises), his kills / deaths / assists
-- (ProgressService), health and XP (Shared.Leveling), with the boost over it: which comes next and when, and what it
-- does and how long it lasts; at the bottom right the round minimap with every hero, minion, throne and the boost
-- waiting to be taken on it, over the coin counter.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)
local Vanish = require(script.Parent.Vanish)

local Hud = {}

local C = UiStyle.Colors
local player = Players.LocalPlayer

-- The minimap (Assets.HudMinimap) shows the arena and its stands: this many studs from the centre to its rim.
local MAP_REACH = Config.Arena.Radius + 36
local MAP_SIZE = 270
local MAP_RING = 9
-- The bottom left's panel, drawn at UiStyle.BottomScale, this far in from the screen's corner.
local PANEL_WIDTH, PANEL_HEIGHT, PANEL_IN, PANEL_UP = 560, 178, 24, 22

-- The top, measured off design 05: each Master's bar under its team's crown at the ends, the score board in the middle
-- with the clock on the dark tab under it (Assets.HudScoreboard, drawn by Tools/ui_textures.py with BOARD_* its size).
local BOARD_WIDTH, BOARD_HEIGHT, TAB_HEIGHT, BOARD_PAD = 672, 88, 48, 4
local BOARD_TOP = 20
local BAR_HEIGHT, BAR_MIDDLE, BAR_GAP = 52, 97, 34
local CROWN_X, CROWN_Y = 62, 88
-- A Master's crown (Art/UI/hud_crown_*.png drawn at 100 x 94) is solid to CROWN_EDGE from its middle, but its points
-- rise over the bar's top: the bar starts under the last point, BAR_UNDER from the crown's middle, so none of it shows
-- between them. Its health runs from the crown's edge on (CROWN_COVER of the track, which lies 6 inside the rim), so
-- the bar is empty only as he dies; the fill tucks its rounded end FILL_TUCK under the crown.
local CROWN_EDGE, BAR_UNDER, FILL_TUCK = 42, 22, 9
local CROWN_COVER = CROWN_EDGE - BAR_UNDER - 6
local SCORE_GAP = 92
local TOP_BAR_MIN = 420

local TOP_COLOURS = {
	Blue = {
		fill = Color3.fromRGB(14, 144, 250),
		shine = Color3.fromRGB(110, 192, 248),
		ink = Color3.fromRGB(22, 138, 238),
		edge = Color3.fromRGB(10, 40, 96),
		crown = Assets.HudCrownBlue,
	},
	Red = {
		fill = Color3.fromRGB(234, 42, 36),
		shine = Color3.fromRGB(248, 116, 104),
		ink = Color3.fromRGB(232, 42, 34),
		edge = Color3.fromRGB(92, 12, 8),
		crown = Assets.HudCrownRed,
	},
}

-- Every blow on a Master shows on his bar (owner, 2026-10-30): it jolts and tilts, shaking out over SHAKE_TIME seconds
-- (up to SHAKE studs of the HUD and SHAKE_TURN degrees), swells by PUNCH (his crown by twice that) and settles back,
-- its fill flashes white, and what he lost stays in LOST_COLOUR for LOST_HOLD seconds before it drains in LOST_DRAIN.
-- A blow of HEAVY of his health or more strikes it fully, a light one at least LIGHT as hard.
local SHAKE, SHAKE_TURN, SHAKE_TIME, PUNCH = 14, 3, 0.4, 0.09
local LOST_COLOUR = Color3.fromRGB(255, 238, 176)
local LOST_HOLD, LOST_DRAIN = 0.3, 0.45
local HEAVY, LIGHT = 0.02, 0.55

type MasterBar = {
	rim: Frame,
	fill: Frame,
	lost: Frame,
	flash: Frame,
	punch: UIScale,
	crownPunch: UIScale,
	home: UDim2,
	lostShare: NumberValue,
	struckAt: number,
	strength: number,
}

-- The fill's size for `share` of his health.
local function fillSize(share: number): UDim2
	return UDim2.new(share, FILL_TUCK - share * CROWN_COVER, 1, 0)
end

-- A Master's bar as in design 05: a light gold rim, a black line inside it, a dark grey track and a glossy fill, with
-- its crown held on the rim's end so the two stay together on every screen.
local function masterBar(parent: Frame, team: string, left: boolean): MasterBar
	local colours = TOP_COLOURS[team]
	local rim = UiStyle.frame(
		parent,
		UDim2.new(0.5, -(BOARD_WIDTH / 2 + BAR_GAP + CROWN_X + BAR_UNDER), 0, BAR_HEIGHT),
		if left
			then UDim2.fromOffset(CROWN_X + BAR_UNDER, BAR_MIDDLE)
			else UDim2.new(1, -(CROWN_X + BAR_UNDER), 0, BAR_MIDDLE),
		if left then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
	)
	rim.Name = team .. "Master"
	UiStyle.corner(rim, 14)
	UiStyle.gradient(rim, Color3.fromRGB(254, 220, 162), Color3.fromRGB(198, 150, 90))
	UiStyle.stroke(rim, Color3.fromRGB(62, 38, 16), 1.5)
	local track = UiStyle.frame(rim, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6))
	track.BackgroundColor3 = Color3.fromRGB(51, 50, 48)
	UiStyle.corner(track, 9)
	UiStyle.stroke(track, Color3.fromRGB(14, 12, 10), 3)
	local lost = UiStyle.frame(track, UDim2.fromScale(1, 1))
	lost.Name = "Lost"
	lost.BackgroundColor3 = LOST_COLOUR
	local fill = UiStyle.frame(track, UDim2.fromScale(1, 1))
	fill.Name = "Fill"
	for _, bar in { lost, fill } do
		bar.Position = UDim2.fromOffset(CROWN_COVER - FILL_TUCK, 0)
		if not left then
			bar.AnchorPoint = Vector2.new(1, 0)
			bar.Position = UDim2.new(1, -(CROWN_COVER - FILL_TUCK), 0, 0)
		end
		UiStyle.corner(bar, 9)
	end
	local flash = UiStyle.frame(fill, UDim2.fromScale(1, 1))
	flash.Name = "Flash"
	flash.BackgroundTransparency = 1
	UiStyle.corner(flash, 9)
	local gloss = UiStyle.gradient(fill, colours.shine, colours.fill)
	gloss.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colours.shine),
		ColorSequenceKeypoint.new(0.16, colours.shine:Lerp(colours.fill, 0.5)),
		ColorSequenceKeypoint.new(0.26, colours.fill),
		ColorSequenceKeypoint.new(1, colours.fill:Lerp(Color3.new(0, 0, 0), 0.06)),
	})

	local crown = Instance.new("ImageLabel")
	crown.Name = team .. "Crown"
	crown.BackgroundTransparency = 1
	crown.Image = colours.crown
	crown.Size = UDim2.fromOffset(100, 94)
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Position = UDim2.new(if left then 0 else 1, if left then -BAR_UNDER else BAR_UNDER, 0.5, CROWN_Y - BAR_MIDDLE)
	crown.ZIndex = 3
	crown.Parent = rim
	local punch = Instance.new("UIScale")
	punch.Parent = rim
	local crownPunch = Instance.new("UIScale")
	crownPunch.Parent = crown
	local lostShare = Instance.new("NumberValue")
	lostShare.Value = 1
	return {
		rim = rim,
		fill = fill,
		lost = lost,
		flash = flash,
		punch = punch,
		crownPunch = crownPunch,
		home = rim.Position,
		lostShare = lostShare,
		struckAt = -math.huge,
		strength = 0,
	}
end

-- `bar`'s Master lost `share` of his health (Hud's top): the blow that shows on it.
local function strike(bar: MasterBar, share: number, now: number)
	local strength = math.clamp(share / HEAVY, LIGHT, 1)
	local shaking = math.max(0, 1 - (now - bar.struckAt) / SHAKE_TIME) * bar.strength
	bar.struckAt, bar.strength = now, math.max(strength, shaking)
	bar.punch.Scale = 1 + PUNCH * strength
	TweenService:Create(bar.punch, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	bar.crownPunch.Scale = 1 + 2 * PUNCH * strength
	TweenService:Create(bar.crownPunch, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	bar.flash.BackgroundTransparency = 0.15
	TweenService:Create(bar.flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
end

-- Shows `bar` at `share` of his health: the fill at once, the lost part draining after it, the jolt of his last blow.
local function showMaster(bar: MasterBar, share: number, now: number)
	bar.fill.Size = fillSize(share)
	bar.fill.Visible = share > 0
	if share > bar.lostShare.Value then
		bar.lostShare.Value = share
	end
	bar.lost.Size = fillSize(bar.lostShare.Value)
	bar.lost.Visible = bar.lostShare.Value > share + 0.0001
	local left = math.max(0, 1 - (now - bar.struckAt) / SHAKE_TIME)
	if left <= 0 then
		bar.rim.Position = bar.home
		bar.rim.Rotation = 0
		return
	end
	local amount = bar.strength * left * left
	bar.rim.Position = bar.home
		+ UDim2.fromOffset((math.random() * 2 - 1) * SHAKE * amount, (math.random() * 2 - 1) * SHAKE * 0.6 * amount)
	bar.rim.Rotation = (math.random() * 2 - 1) * SHAKE_TURN * amount
end

local function scoreText(parent: Instance, team: string?, align: Enum.TextXAlignment, x: number): TextLabel
	local colours = team and TOP_COLOURS[team]
	local label = UiStyle.text(
		parent,
		"",
		58,
		if colours then colours.ink else Color3.fromRGB(50, 28, 12),
		colours and colours.edge
	)
	if colours then
		(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 3
	end
	label.TextXAlignment = align
	label.AnchorPoint = Vector2.new(if align == Enum.TextXAlignment.Right then 1 else 0, 0.5)
	label.Size = UDim2.fromOffset(if colours then 240 else 170, 66)
	label.Position = UDim2.new(0.5, x, 0, BOARD_PAD + BOARD_HEIGHT / 2)
	label.ZIndex = 3
	return label
end

local function buildTop(gui: Frame): () -> ()
	local bars: { [string]: MasterBar } = {}
	local drains: { [string]: Tween } = {}
	local function shareOf(team: string): number
		local max = Workspace:GetAttribute("MasterMax" .. team) or Config.Master.Health
		return math.clamp((Workspace:GetAttribute("Master" .. team) or max) / max, 0, 1)
	end
	for i, team in Config.TeamOrder do
		local bar = masterBar(gui, team, i == 1)
		bars[team] = bar
		local was = shareOf(team)
		Workspace:GetAttributeChangedSignal("Master" .. team):Connect(function()
			local share = shareOf(team)
			local lost = was - share
			was = share
			if lost <= 0 then
				return
			end
			strike(bar, lost, os.clock())
			if drains[team] then
				drains[team]:Cancel()
			end
			local info = TweenInfo.new(LOST_DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, LOST_HOLD)
			drains[team] = TweenService:Create(bar.lostShare, info, { Value = share })
			drains[team]:Play()
		end)
	end

	local board = Instance.new("ImageLabel")
	board.Name = "Score"
	board.BackgroundTransparency = 1
	board.Image = Assets.HudScoreboard
	board.Size = UDim2.fromOffset(BOARD_WIDTH + 2 * BOARD_PAD, BOARD_HEIGHT + TAB_HEIGHT + 2 * BOARD_PAD)
	board.AnchorPoint = Vector2.new(0.5, 0)
	board.Position = UDim2.new(0.5, 0, 0, BOARD_TOP - BOARD_PAD)
	board.ZIndex = 2
	board.Parent = gui
	local blue, red = Config.TeamOrder[1], Config.TeamOrder[2]
	local blueScore = scoreText(board, blue, Enum.TextXAlignment.Right, -SCORE_GAP)
	local versus = scoreText(board, nil, Enum.TextXAlignment.Center, -85)
	versus.Text = "- VS -"
	local redScore = scoreText(board, red, Enum.TextXAlignment.Left, SCORE_GAP)

	local clock = UiStyle.text(board, "0:00", 36, Color3.new(1, 1, 1), Color3.fromRGB(30, 16, 6))
	clock.AnchorPoint = Vector2.new(0.5, 0.5)
	clock.Size = UDim2.fromOffset(160, TAB_HEIGHT)
	clock.Position = UDim2.new(0.5, 0, 0, BOARD_PAD + BOARD_HEIGHT + TAB_HEIGHT / 2 - 3)
	clock.ZIndex = 3

	return function()
		local now = os.clock()
		for team, bar in bars do
			showMaster(bar, shareOf(team), now)
		end
		blueScore.Text =
			string.format("%s %d", string.upper(Config.Teams[blue].Name), Workspace:GetAttribute("Score" .. blue) or 0)
		redScore.Text =
			string.format("%d %s", Workspace:GetAttribute("Score" .. red) or 0, string.upper(Config.Teams[red].Name))
		local start = Workspace:GetAttribute("MatchStart")
		clock.Text = UiStyle.clock(if start then math.max(0, Workspace:GetServerTimeNow() - start) else 0)
	end
end

-- The boost (Shared.Boosts) for everyone, in a pill over the bottom left's panel (owner, 2026-11-02: out of the way of
-- the rest) edged in the boost's colour, with its picture (a dot in its colour until it has one): in the last `Warn`
-- seconds before the next one, when it comes and what it does ("WIND FEATHER IN 0:15 · SPEED UP"); while carried what
-- it does and the time until it fades, "ENEMY" before it in the enemy's colour when they have it; while dropped its
-- name and the time. While it floats in the middle the pill is gone: the boost shows itself, and on the minimap.
-- The time blinks for its last BOOST_BLINK seconds.
local BOOST_BLINK = 10
local function buildBoost(gui: ScreenGui): () -> ()
	local pill = UiStyle.frame(
		gui,
		UDim2.fromOffset(0, 40),
		UDim2.new(0, PANEL_IN, 1, -PANEL_UP - PANEL_HEIGHT * UiStyle.BottomScale - 10),
		Vector2.new(0, 1)
	)
	pill.Name = "BoostTimer"
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.fromRGB(46, 32, 22)
	pill.ZIndex = 3
	pill.Visible = false
	UiStyle.corner(pill, UDim.new(0.5, 0))
	local edge = UiStyle.stroke(pill, C.Gold, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = pill
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = pill
	local picture = Instance.new("ImageLabel")
	picture.BackgroundTransparency = 1
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Size = UDim2.fromOffset(48, 34)
	picture.ZIndex = 4
	picture.LayoutOrder = 1
	picture.Parent = pill
	local dot = UiStyle.frame(pill, UDim2.fromOffset(20, 20))
	dot.ZIndex = 4
	dot.LayoutOrder = 1
	UiStyle.corner(dot, UDim.new(0.5, 0))
	UiStyle.stroke(dot, Color3.fromRGB(30, 16, 6), 2)
	local label = UiStyle.text(pill, "", 24, Color3.new(1, 1, 1), Color3.fromRGB(30, 16, 6))
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 36)
	label.ZIndex = 4
	label.LayoutOrder = 2
	local labelEdge = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- The player's team, kept while he waits to respawn without a character.
	local team: string? = nil

	return function()
		team = player.Character and player.Character:GetAttribute("Team") or team
		local boost = Boosts.current()
		local state = Workspace:GetAttribute("Boost")
		local now = Workspace:GetServerTimeNow()
		local name = if boost then string.upper(boost.Name) else ""
		local text: string? = nil
		local left: number? = nil
		local enemy = false
		if boost and state == "Waiting" then
			local at = Workspace:GetAttribute("BoostAt")
			if typeof(at) == "number" and at - now <= Config.Boosts.Warn then
				text =
					string.format("%s IN %s · %s", name, UiStyle.clock(math.max(0, math.ceil(at - now))), boost.Short)
			end
		elseif boost and (state == "Carried" or state == "Dropped") then
			local ends = Workspace:GetAttribute("BoostEnds")
			if typeof(ends) == "number" then
				left = math.max(0, ends - now)
				local clock = UiStyle.clock(math.ceil(left :: number))
				if state == "Dropped" then
					text = string.format("%s DROPPED %s", name, clock)
				else
					enemy = Workspace:GetAttribute("BoostTeam") ~= team
					text = string.format("%s%s %s", if enemy then "ENEMY " else "", boost.Short, clock)
				end
			end
		end
		pill.Visible = text ~= nil
		if not boost or not text then
			return
		end
		label.Text = text
		picture.Image = boost.Image or ""
		picture.Visible = boost.Image ~= nil
		dot.Visible = boost.Image == nil
		dot.BackgroundColor3 = boost.Color
		local ending = left ~= nil and left <= BOOST_BLINK
		local dim = ending and os.clock() % 0.5 < 0.25
		local enemyColour = Config.Teams[if team == "Red" then "Blue" else "Red"].Color
		label.TextColor3 = if ending
			then Color3.fromRGB(255, 110, 90)
			elseif enemy then enemyColour:Lerp(Color3.new(1, 1, 1), 0.35)
			else Color3.new(1, 1, 1)
		label.TextTransparency = if dim then 0.6 else 0
		labelEdge.Transparency = if dim then 0.6 else 0
		picture.ImageTransparency = if dim then 0.6 else 0
		edge.Color = if ending then Color3.fromRGB(255, 110, 90) else boost.Color
	end
end

-- The hero's painted portrait (Config.Heroes[hero].Portrait), cut to his head and shoulders.
local function showPortrait(image: ImageLabel, character: Model)
	local hero = character:GetAttribute("Hero")
	local portrait = hero and Config.Heroes[hero] and Config.Heroes[hero].Portrait
	image.Visible = portrait ~= nil
	if portrait then
		local x, y, size = table.unpack(portrait.Face)
		image.Image = portrait.Image
		image.ImageRectOffset = Vector2.new(x, y)
		image.ImageRectSize = Vector2.new(size, size)
	end
end

-- The bottom left: portrait, level, kills / deaths / assists, health and XP.
local function buildPlayer(gui: ScreenGui): () -> ()
	local outer, inner = UiStyle.panel(
		gui,
		UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		UDim2.new(0, PANEL_IN, 1, -PANEL_UP),
		Vector2.new(0, 1),
		18,
		6
	)
	UiStyle.shrink(outer, UiStyle.BottomScale)
	local frame, back = UiStyle.panel(inner, UDim2.fromOffset(150, 150), UDim2.fromOffset(4, 8), nil, 14, 5)
	frame.Name = "Portrait"
	UiStyle.gradient(back, Color3.fromRGB(246, 214, 160), Color3.fromRGB(200, 150, 96))
	back.ClipsDescendants = true
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Crop
	image.Visible = false
	image.Parent = back
	UiStyle.corner(image, 9)

	local level = UiStyle.text(inner, "LV 1", 46, C.Ink)
	level.TextXAlignment = Enum.TextXAlignment.Left
	level.Size = UDim2.fromOffset(200, 50)
	level.Position = UDim2.fromOffset(172, 6)
	local health = UiStyle.bar(
		inner,
		UDim2.fromOffset(360, 40),
		UDim2.fromOffset(170, 62),
		C.Health,
		C.HealthDark,
		nil,
		nil,
		C.Trail
	)
	local xpLabel = UiStyle.text(inner, "XP", 32, C.Xp, C.Edge)
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.Size = UDim2.fromOffset(50, 34)
	xpLabel.Position = UDim2.fromOffset(170, 114)
	local xp = UiStyle.bar(inner, UDim2.fromOffset(312, 26), UDim2.fromOffset(218, 118), C.Xp, C.XpDark)

	local score = UiStyle.frame(inner, UDim2.fromOffset(250, 50), UDim2.new(1, -16, 0, 6), Vector2.new(1, 0))
	score.Name = "Kda"
	score.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = score
	local caption = UiStyle.text(score, "KDA", 22, C.GoldDark)
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.Size = UDim2.fromOffset(0, 30)
	caption.LayoutOrder = 1
	local kda = UiStyle.text(score, "0 / 0 / 0", 36, C.Ink)
	kda.RichText = true
	kda.AutomaticSize = Enum.AutomaticSize.X
	kda.Size = UDim2.fromOffset(0, 44)
	kda.LayoutOrder = 2
	local slash = string.format('<font color="#%s"> / </font>', C.GoldDark:ToHex())

	local function added(character: Model)
		showPortrait(image, character)
		character:GetAttributeChangedSignal("Hero"):Connect(function()
			showPortrait(image, character)
		end)
	end
	player.CharacterAdded:Connect(added)
	if player.Character then
		added(player.Character)
	end
	local reached = Leveling.level(player)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local lv = Leveling.level(player)
		if lv > reached then
			UiSound.play("LevelUp")
		end
		reached = lv
	end)

	return function()
		local lv = Leveling.level(player)
		level.Text = "LV " .. lv
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		health:set(if humanoid and humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0)
		local step = Leveling.step(lv)
		xp:set(if step then (player:GetAttribute("Xp") or 0) / step else 1)
		kda.Text = table.concat({
			tostring(player:GetAttribute("Kills") or 0),
			tostring(player:GetAttribute("Deaths") or 0),
			tostring(player:GetAttribute("Assists") or 0),
		}, slash)
	end
end

type Dot = { frame: Frame, used: boolean }

-- The bottom right: the minimap over the coins.
local function buildMap(gui: ScreenGui): () -> ()
	local ring = UiStyle.frame(gui, UDim2.fromOffset(MAP_SIZE, MAP_SIZE), UDim2.new(1, -30, 1, -96), Vector2.new(1, 1))
	ring.Name = "Minimap"
	UiStyle.corner(ring, UDim.new(0.5, 0))
	UiStyle.gradient(ring, C.Gold, C.GoldDark)
	UiStyle.stroke(ring, C.Edge, 3)
	local inside = MAP_SIZE - 2 * MAP_RING
	local map = UiStyle.frame(ring, UDim2.fromOffset(inside, inside), UDim2.fromOffset(MAP_RING, MAP_RING))
	map.BackgroundColor3 = Color3.fromRGB(150, 128, 100)
	UiStyle.corner(map, UDim.new(0.5, 0))
	UiStyle.stroke(map, C.Edge, 2)
	local k = inside / (2 * MAP_REACH)
	local picture = Instance.new("ImageLabel")
	picture.BackgroundTransparency = 1
	picture.Image = Assets.HudMinimap
	picture.Size = UDim2.fromScale(1, 1)
	picture.Parent = map
	UiStyle.corner(picture, UDim.new(0.5, 0))

	local function at(position: Vector3): UDim2
		return UDim2.fromOffset(inside / 2 + position.X * k, inside / 2 + position.Z * k)
	end

	for _, team in Config.TeamOrder do
		local throne = Workspace:GetAttribute("Throne" .. team)
		if typeof(throne) == "Vector3" then
			local crown = Instance.new("ImageLabel")
			crown.BackgroundTransparency = 1
			crown.Image = Assets.HudCrown
			crown.ImageColor3 = C[team]
			crown.Size = UDim2.fromOffset(30, 26)
			crown.AnchorPoint = Vector2.new(0.5, 0.5)
			crown.Position = at(throne)
			crown.ZIndex = 2
			crown.Parent = map
		end
	end

	-- The boost waiting to be taken, on the plateau or where its carrier fell.
	local boostIcon = Instance.new("ImageLabel")
	boostIcon.Name = "Boost"
	boostIcon.BackgroundTransparency = 1
	boostIcon.ScaleType = Enum.ScaleType.Fit
	boostIcon.Size = UDim2.fromOffset(36, 36)
	boostIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	boostIcon.ZIndex = 6
	boostIcon.Visible = false
	boostIcon.Parent = map

	local pool: { Dot } = {}
	local function dot(size: number, colour: Color3, edge: Color3, z: number): Frame
		local d: Dot? = nil
		for _, candidate in pool do
			if not candidate.used then
				d = candidate
				break
			end
		end
		if not d then
			local f = UiStyle.frame(map, UDim2.new(), nil, Vector2.new(0.5, 0.5))
			UiStyle.corner(f, UDim.new(0.5, 0))
			UiStyle.stroke(f, edge, 1.5)
			d = { frame = f, used = false }
			table.insert(pool, d :: Dot)
		end
		local found = d :: Dot
		found.used = true
		found.frame.Visible = true
		found.frame.Size = UDim2.fromOffset(size, size)
		found.frame.BackgroundColor3 = colour
		found.frame.ZIndex = z;
		(found.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = edge
		return found.frame
	end

	local pill =
		UiStyle.frame(gui, UDim2.fromOffset(220, 56), UDim2.new(1, -30 - MAP_SIZE / 2, 1, -26), Vector2.new(0.5, 1))
	pill.Name = "Coins"
	UiStyle.corner(pill, 28)
	UiStyle.gradient(pill, Color3.fromRGB(96, 66, 40), Color3.fromRGB(52, 34, 20))
	UiStyle.stroke(pill, C.Gold, 3)
	local coin = Instance.new("ImageLabel")
	coin.BackgroundTransparency = 1
	coin.Image = Assets.HudCoin
	coin.Size = UDim2.fromOffset(64, 64)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, -14, 0.5, 0)
	coin.Parent = pill
	local coins = UiStyle.text(pill, "0", 36, C.Cream, C.Edge)
	local shown = player:GetAttribute("Coins") or 0
	coins.Size = UDim2.new(1, -56, 1, 0)
	coins.Position = UDim2.fromOffset(48, 0)

	return function()
		for _, d in pool do
			d.used = false
		end
		local minions = Workspace:FindFirstChild("Minions")
		if minions then
			for _, root in minions:GetChildren() do
				local team = root:GetAttribute("Team")
				if root:IsA("BasePart") and team and not root:GetAttribute("Dead") then
					dot(8, C[team], C.Edge, 3).Position = at(root.Position)
				end
			end
		end
		local own = player.Character
		for _, model in CollectionService:GetTagged("Combatant") do
			local team = model:GetAttribute("Team")
			if
				model:IsA("Model")
				and model:GetAttribute("Hero")
				and team
				and model ~= own
				and not Vanish.unseen(model)
			then
				dot(16, C[team], C.Edge, 4).Position = at(model:GetPivot().Position)
			end
		end
		local root = own and own:FindFirstChild("HumanoidRootPart") :: BasePart?
		if own and root then
			dot(20, C[own:GetAttribute("Team") or "Blue"], Color3.new(1, 1, 1), 5).Position = at(root.Position)
		end
		local boost = Boosts.current()
		local state = Workspace:GetAttribute("Boost")
		local spot = Workspace:GetAttribute("BoostSpot")
		if boost and boost.Image and (state == "Ready" or state == "Dropped") and typeof(spot) == "Vector3" then
			boostIcon.Image = boost.Image
			boostIcon.Position = at(spot)
			boostIcon.Visible = true
		else
			boostIcon.Visible = false
		end
		for _, d in pool do
			if not d.used then
				d.frame.Visible = false
			end
		end
		-- Coins count up to what the player has, less what is still flying home from a kill (KillFeed's "Held");
		-- spending shows at once.
		local target = math.max(0, (player:GetAttribute("Coins") or 0) - (pill:GetAttribute("Held") or 0))
		shown = if target > shown then math.min(target, shown + math.max(1, (target - shown) * 0.15)) else target
		coins.Text = UiStyle.thousands(shown)
	end
end

function Hud.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = UiStyle.screen("Hud", playerGui)
	-- The top stands in the topbar's row, as far in from both ends as Roblox's buttons reach in from either, so it stays
	-- centred: an empty ScreenGui on the topbar's safe insets measures them. Roblox's buttons keep their size while the
	-- HUD scales with the screen, so where they leave too little room for bars of TOP_BAR_MIN the whole top shrinks.
	local top = UiStyle.frame(gui, UDim2.new(1, 0, 0, 170), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	top.Name = "Top"
	top.BackgroundTransparency = 1
	local shrink = Instance.new("UIScale")
	shrink.Parent = top
	local insets = Instance.new("ScreenGui")
	insets.Name = "HudTopInsets"
	insets.ResetOnSpawn = false
	insets.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	insets.Parent = playerGui
	local scale = gui:FindFirstChildOfClass("UIScale") :: UIScale
	local needed = 2 * (CROWN_X + TOP_BAR_MIN + BAR_GAP) + BOARD_WIDTH
	local function fit()
		local screen = (Workspace.CurrentCamera :: Camera).ViewportSize.X
		local left = insets.AbsolutePosition.X
		local right = screen - left - insets.AbsoluteSize.X
		local room = (screen - 2 * math.max(left, right, 0)) / scale.Scale
		shrink.Scale = math.min(1, room / needed)
		top.Size = UDim2.fromOffset(math.max(room, needed), 170)
	end
	insets:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)
	insets:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	scale:GetPropertyChangedSignal("Scale"):Connect(fit)
	fit()
	local updates = { buildTop(top), buildBoost(gui), buildPlayer(gui), buildMap(gui) }
	RunService.RenderStepped:Connect(function()
		for _, update in updates do
			update()
		end
	end)
end

return Hud
