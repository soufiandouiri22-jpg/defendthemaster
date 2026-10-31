-- The end of a match (design 16, server MatchEnd). When a Master falls ("Winner" on Workspace) the camera turns to him
-- and goes slowly round him for Config.MatchEnd.Hold seconds; then the VICTORY or DEFEAT title (the results' own
-- heading, larger) springs up in the middle with its sting, and after TITLE seconds it gives way to the results, headed
-- by the same heading: the scoreboard of both teams in the middle (every hero's name, rank, KDA, damage and
-- grade, the MVP marked, the player's own row in gold) with the player's rewards in a band under it (his LP in
-- Ranked, his hero's mastery, the coins, the pass XP and the account XP; every player's mastery crest beside his
-- name), the match's MVP in a gold card on its left and the losing
-- team's best player in a card of his team's colour on its right, so everyone sees who stood out. PLAY AGAIN goes back to the lobby
-- and into the queue with his party, BACK TO MENU only back; until the server sends everyone back a clock counts
-- down. Clicking a player opens his profile (PlayerCard): a star card turns round to it, a row opens it large. The rest
-- of the HUD hides meanwhile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local HeroCamera = require(script.Parent.HeroCamera)
local Music = require(script.Parent.Music)
local PlayerCard = require(script.Parent.PlayerCard)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)
local Widgets = require(script.Parent.Widgets)

local MatchEndView = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local PURPLE = Widgets.Kinds.Purple
local GRADE_COLOURS = {
	S = { Color3.fromRGB(255, 214, 90), Color3.fromRGB(200, 120, 20) },
	A = { Color3.fromRGB(150, 220, 110), Color3.fromRGB(52, 136, 32) },
	B = { Color3.fromRGB(120, 180, 250), Color3.fromRGB(30, 78, 186) },
	C = { Color3.fromRGB(220, 180, 140), Color3.fromRGB(140, 96, 60) },
	D = { Color3.fromRGB(190, 180, 170), Color3.fromRGB(110, 100, 92) },
}
local TEAM_FILL = { Blue = { C.Blue, C.BlueDark }, Red = { C.Red, C.RedDark } }
-- How long the title stands alone in the middle before the results come, and how much larger than the results'
-- heading it stands there.
local TITLE = 3.6
local TITLE_SCALE = 1.6
local ORBIT = 0.35
local SWING = math.rad(40)
local ROW = 46
-- The results' layout, in reference pixels: the scoreboard in the middle from TOP down with the rewards band under
-- it, a star card on each side of it, the buttons at the bottom.
local TOP = 292
local BOARD_W = 830
local BAND_H = 100
local CARD_W = 380
local CARD_GAP = 24
local BUTTON_W = 560
-- A star card's mastery crest: its width and how far above the card's foot it ends. The avatar round on the other
-- side, a little larger than its barrel, has its YOU tag over its foot, the two raised together until the tag stands
-- clear of the plate under it.
local CREST, CREST_BOTTOM = 104, 168
local AVATAR = 84
local AVATAR_BOTTOM = CREST_BOTTOM + CREST - AVATAR + 11
local TAG_W, TAG_H = 84, 30
local TAG_MIDDLE = AVATAR_BOTTOM - 7
-- The results (from HEAD_TOP, where the heading's plate and lettering begin, down to the rewards band) and the buttons
-- with the clock under them (NEXT_H high) stand with as much room above the results as between them and the buttons
-- and under the buttons: so the whole stands in the middle of the screen, and the buttons in the middle of the room
-- under the results, on every screen.
local HEAD_TOP = 82
local NEXT_H = 122

local player = Players.LocalPlayer

local function masterOf(team: string): Model?
	for _, model in Workspace:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("Master") and model:GetAttribute("Team") == team then
			return model
		end
	end
	return nil
end

-- The camera goes slowly round the fallen Master (or his throne without him).
local function watch(loser: string)
	local master = masterOf(loser)
	local centre = if master
		then master:GetPivot().Position
		else Workspace:GetAttribute("Throne" .. loser) :: Vector3? or Vector3.zero
	local camera = Workspace.CurrentCamera
	local blue = Workspace:GetAttribute("ThroneBlue") :: Vector3?
	local red = Workspace:GetAttribute("ThroneRed") :: Vector3?
	local arena = if blue and red then (blue + red) / 2 else centre - camera.CFrame.LookVector * 30
	local toward = arena - centre
	local base = math.atan2(toward.Z, toward.X)
	local target = centre + Vector3.new(0, 4, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if master then
		table.insert(ignore, master)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local clock = 0
	RunService:BindToRenderStep("MatchEndCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
		clock += dt
		camera.CameraType = Enum.CameraType.Scriptable
		local angle = base + math.sin(clock * ORBIT) * SWING
		local from = centre + Vector3.new(math.cos(angle) * 26, 14, math.sin(angle) * 26)
		local hit = Workspace:Raycast(target, from - target, params)
		if hit then
			from = hit.Position + (target - from).Unit * 1.5
		end
		camera.CFrame = CFrame.lookAt(from, target)
	end)
end

local function hideHud(own: ScreenGui)
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= own then
			gui.Enabled = false
		end
	end
end

-- A bar filled to `share`, with `text` on it.
local function bar(parent: Instance, size: UDim2, position: UDim2, share: number, colours: { Color3 }, text: string)
	local b = UiStyle.bar(parent, size, position, colours[1], colours[2])
	b:set(share)
	local label = Widgets.label(b.frame, text, 19, C.Cream, nil, C.Edge)
	label.ZIndex = 3
end

-- "LEVEL 4", or "LEVEL 3  >  4" after a level-up.
local function levelText(before: number?, level: number): string
	if before and before < level then
		return "LEVEL " .. before .. "  >  " .. level
	end
	return "LEVEL " .. level
end

-- Under a hero's name: a player's rank, a bot's hero.
local function subline(row: any): string
	if row.userId > 0 and row.shown then
		return string.upper(Ranks.label(row.shown, row.division))
	end
	return string.upper(row.hero)
end

-- A grade's seal (Assets.GradeSeals by its letter) with its + or - on a round of the letter's colours at its corner.
local function gradeShield(parent: Instance, grade: string, size: number, position: UDim2, anchor: Vector2?): ImageLabel
	local letter = string.sub(grade, 1, 1)
	local seal = Instance.new("ImageLabel")
	seal.Name = "Grade"
	seal.BackgroundTransparency = 1
	seal.Size = UDim2.fromOffset(size, size)
	seal.Position = position
	seal.AnchorPoint = anchor or Vector2.zero
	seal.ScaleType = Enum.ScaleType.Fit
	seal.Image = Assets.GradeSeals[letter] or Assets.GradeSeals.D
	seal.Parent = parent
	local sign = string.sub(grade, 2, 2)
	if sign ~= "" then
		local colours = GRADE_COLOURS[letter] or GRADE_COLOURS.D
		local round = UiStyle.frame(
			seal,
			UDim2.fromOffset(size * 0.4, size * 0.4),
			UDim2.fromScale(0.96, 0.2),
			Vector2.new(0.5, 0.5)
		)
		UiStyle.corner(round, UDim.new(0.5, 0))
		UiStyle.gradient(round, colours[1], colours[2])
		UiStyle.stroke(round, C.Edge, math.max(1.5, size / 40))
		round.ZIndex = seal.ZIndex + 1
		local label = Widgets.label(round, sign, math.floor(size * 0.36), C.Cream, nil, C.Edge)
		label.ZIndex = round.ZIndex + 1
	end
	return seal
end

local function medal(parent: Instance, size: number, position: UDim2, anchor: Vector2?): Frame
	local m = UiStyle.frame(parent, UDim2.fromOffset(size, size), position, anchor)
	UiStyle.corner(m, UDim.new(0.5, 0))
	UiStyle.gradient(m, Color3.fromRGB(255, 220, 110), Color3.fromRGB(206, 130, 30))
	UiStyle.stroke(m, C.Edge, math.max(2, size / 36))
	Widgets.label(m, "MVP", math.floor(size * 0.34), C.Cream, nil, C.Edge)
	return m
end

-- The heading in the menus' own style: VICTORY in gold or DEFEAT in grey, in the round lettering with its thick dark
-- edge, standing over a dark plate framed in gold or red; one 700 by 130 frame round the lettering, placed at
-- `position` by its middle.
local function heading(parent: Instance, won: boolean, position: UDim2): Frame
	local holder = UiStyle.frame(parent, UDim2.fromOffset(700, 130), position, Vector2.new(0.5, 0.5))
	holder.BackgroundTransparency = 1
	holder.Name = "HeadingBlock"
	local plate = Widgets.dark(holder, UDim2.fromOffset(560, 76), UDim2.new(0.5, 0, 0.5, 10), Vector2.new(0.5, 0.5), 16)
	plate.Name = "Heading"
	UiStyle.stroke(plate, if won then C.Gold else C.Red, 4)
	local word = UiStyle.text(holder, if won then "VICTORY" else "DEFEAT", 120, Color3.new(1, 1, 1), C.Edge)
	word.Name = "HeadingText"
	word.Size = UDim2.fromScale(1, 1)
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.5)
	local edge = word:FindFirstChildOfClass("UIStroke") :: UIStroke
	edge.Thickness = 9
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Color = if won
		then ColorSequence.new(Color3.fromRGB(255, 242, 170), Color3.fromRGB(240, 166, 36))
		else ColorSequence.new(Color3.fromRGB(236, 236, 242), Color3.fromRGB(146, 146, 162))
	fill.Parent = word
	return holder
end

-- The title in the middle of the screen: the heading, larger, growing in once and then standing still; returns it.
local function title(gui: ScreenGui, won: boolean): CanvasGroup
	local image = Instance.new("CanvasGroup")
	image.Name = "Title"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(760, 170)
	image.ZIndex = 20
	image.GroupTransparency = 1
	image.Parent = gui
	heading(image, won, UDim2.fromScale(0.5, 0.5))
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6 * TITLE_SCALE
	scale.Parent = image
	Widgets.tween(image, 0.3, { GroupTransparency = 0 })
	Widgets.tween(scale, 0.35, { Scale = TITLE_SCALE })
	return image
end

-- What the profile (PlayerCard) of the player on `row` starts from.
local function info(row: any): PlayerCard.Info
	return {
		userId = row.userId,
		name = row.name,
		hero = row.hero,
		mastery = row.mastery,
		shown = row.shown,
		division = row.division,
	}
end

-- Makes `target` open the profile card (PlayerCard) of the player on `row` when clicked, lighting up under the mouse;
-- a bot has none.
local function opens(target: GuiObject, row: any, radius: number)
	if row.userId <= 0 then
		return
	end
	local light = UiStyle.frame(target, UDim2.fromScale(1, 1))
	light.Name = "Hover"
	light.BackgroundColor3 = Color3.new(1, 1, 1)
	light.BackgroundTransparency = 1
	UiStyle.corner(light, radius)
	local button = Instance.new("TextButton")
	button.Name = "Profile"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 10
	button.Parent = target
	Widgets.feel(button)
	button.MouseEnter:Connect(function()
		Widgets.tween(light, 0.12, { BackgroundTransparency = 0.85 })
	end)
	button.MouseLeave:Connect(function()
		Widgets.tween(light, 0.12, { BackgroundTransparency = 1 })
	end)
	button.Activated:Connect(function()
		PlayerCard.open(target, info(row))
	end)
end

-- Both teams' heroes; returns how high the panel is.
local function scoreboard(parent: Instance, result: any): number
	local outer, inner =
		UiStyle.panel(parent, UDim2.fromOffset(BOARD_W, 500), UDim2.new(0.5, 0, 0, TOP), Vector2.new(0.5, 0), 14, 5)
	local columns = {
		{ "K / D / A", 420, 140 },
		{ "DAMAGE", 570, 120 },
		{ "GRADE", 690, 70 },
	}
	for _, column in columns do
		local text = Widgets.label(inner, column[1], 20, W.Muted)
		text.Size = UDim2.fromOffset(column[3], 30)
		text.Position = UDim2.fromOffset(column[2], 8)
	end
	local playerHead = Widgets.label(inner, "PLAYER", 20, W.Muted, "Left")
	playerHead.Size = UDim2.fromOffset(200, 30)
	playerHead.Position = UDim2.fromOffset(74, 8)

	local y = 40
	local current: string? = nil
	for _, row in result.players or {} do
		if row.team ~= current then
			current = row.team
			local fill = TEAM_FILL[row.team] or TEAM_FILL.Blue
			local strip = UiStyle.frame(inner, UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, y))
			UiStyle.corner(strip, 8)
			UiStyle.gradient(strip, fill[1], fill[2])
			local won = row.team == result.winner
			local label = Widgets.label(
				strip,
				string.upper(row.team) .. " TEAM  -  " .. (if won then "VICTORY" else "DEFEAT"),
				22,
				C.Cream,
				"Left",
				C.Edge
			)
			label.Size = UDim2.new(1, -20, 1, 0)
			label.Position = UDim2.fromOffset(14, 0)
			y += 40
		end
		local mine = row.userId == player.UserId and row.userId > 0
		local line = UiStyle.frame(inner, UDim2.new(1, -20, 0, ROW - 4), UDim2.fromOffset(10, y))
		line.Name = if mine then "Mine" else "Row"
		UiStyle.corner(line, 8)
		if mine then
			UiStyle.gradient(line, Color3.fromRGB(255, 226, 140), Color3.fromRGB(236, 182, 76))
			UiStyle.stroke(line, C.GoldDark, 3)
		else
			UiStyle.gradient(line, W.Parchment, W.Stripe)
		end
		local face =
			Widgets.portrait(line, row.hero, UDim2.fromOffset(ROW - 10, ROW - 10), UDim2.fromOffset(4, 3), true)
		UiStyle.corner(face, 6)
		local faceEdge = UiStyle.stroke(face, (TEAM_FILL[row.team] or TEAM_FILL.Blue)[2], 2)
		faceEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local x = ROW + 6
		if row.shown then
			Widgets.badge(line, row.shown, 36, UDim2.new(0, x, 0.5, 0), Vector2.new(0, 0.5))
			x += 40
		end
		if (row.mastery or 0) > 0 then
			Widgets.crest(line, row.mastery, 40, UDim2.new(0, x, 0.5, 0), Vector2.new(0, 0.5))
			x += 42
		end
		local name = Widgets.label(line, row.name, 22, C.Ink, "Left")
		name.Size = UDim2.fromOffset(392 - x, 24)
		name.Position = UDim2.fromOffset(x, 1)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local subText = Widgets.label(line, subline(row), 15, W.Muted, "Left")
		subText.Size = UDim2.fromOffset(392 - x, 16)
		subText.Position = UDim2.fromOffset(x, 24)
		local kda = Widgets.label(line, string.format("%d / %d / %d", row.kills, row.deaths, row.assists), 26, C.Ink)
		kda.Size = UDim2.fromOffset(140, ROW - 4)
		kda.Position = UDim2.fromOffset(410, 0)
		local damage = Widgets.label(line, UiStyle.thousands(row.damage), 24, C.Ink)
		damage.Size = UDim2.fromOffset(120, ROW - 4)
		damage.Position = UDim2.fromOffset(560, 0)
		gradeShield(line, row.grade, 34, UDim2.new(0, 715, 0.5, 0), Vector2.new(0.5, 0.5))
		if row.mvp then
			medal(line, 38, UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
		end
		opens(line, row, 8)
		y += ROW
	end
	local high = y + 34
	outer.Size = UDim2.fromOffset(BOARD_W, high)
	return high
end

-- The best hero of a team in a tall card: the match's MVP (gold) or the losing team's best (in its colour).
local function starCard(parent: Instance, row: any, side: number, high: number, mvp: boolean)
	local size = UDim2.fromOffset(CARD_W, high)
	local position = UDim2.new(0.5, side * (BOARD_W / 2 + CARD_GAP), 0, TOP)
	local anchor = Vector2.new(if side < 0 then 1 else 0, 0)
	local holder = UiStyle.frame(parent, size, position, anchor)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	UiStyle.corner(holder, 16)
	local picture = Widgets.portrait(holder, row.hero, UDim2.fromScale(1, 1))
	UiStyle.corner(picture, 16)

	local fill = TEAM_FILL[row.team] or TEAM_FILL.Blue
	local card = UiStyle.frame(parent, size, position, anchor)
	card.Name = if mvp then "MatchMvp" else "BestLoser"
	card.BackgroundTransparency = 1
	UiStyle.corner(card, 16)
	UiStyle.stroke(card, if mvp then C.Gold else fill[1], 5)

	local ribbon = UiStyle.frame(card, UDim2.new(1, -48, 0, 56), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	UiStyle.corner(ribbon, 12)
	if mvp then
		UiStyle.gradient(ribbon, Color3.fromRGB(255, 220, 110), Color3.fromRGB(206, 130, 30))
	else
		UiStyle.gradient(ribbon, fill[1], fill[2])
	end
	UiStyle.stroke(ribbon, C.Edge, 3)
	Widgets.label(ribbon, if mvp then "MATCH MVP" else "BEST OF " .. string.upper(row.team), 30, C.Cream, nil, C.Edge)

	local plate = Widgets.dark(card, UDim2.new(1, -28, 0, 150), UDim2.new(0.5, 0, 1, -14), Vector2.new(0.5, 1), 12)
	UiStyle.stroke(plate, if mvp then C.GoldDark else fill[2], 3)
	local name = Widgets.label(plate, row.name, 32, C.Cream, "Left", C.Edge)
	name.Size = UDim2.new(1, -130, 0, 36)
	name.Position = UDim2.fromOffset(16, 10)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = Widgets.label(plate, subline(row), 18, C.Gold, "Left")
	sub.Size = UDim2.new(1, -130, 0, 22)
	sub.Position = UDim2.fromOffset(16, 46)
	local kda = Widgets.label(
		plate,
		string.format("%d / %d / %d", row.kills, row.deaths, row.assists),
		34,
		C.Cream,
		"Left",
		C.Edge
	)
	kda.Size = UDim2.new(1, -130, 0, 38)
	kda.Position = UDim2.fromOffset(16, 72)
	local damage = Widgets.label(plate, UiStyle.thousands(row.damage) .. " DAMAGE", 20, C.Cream, "Left")
	damage.Size = UDim2.new(1, -130, 0, 24)
	damage.Position = UDim2.fromOffset(16, 112)
	gradeShield(plate, row.grade, 92, UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5))
	if (row.mastery or 0) > 0 then
		Widgets.crest(card, row.mastery, CREST, UDim2.new(1, -18, 1, -CREST_BOTTOM), Vector2.new(1, 1))
	end

	-- A player's own avatar (a bot has none) in a round over the portrait's corner, his YOU tag on its rim.
	if row.userId > 0 then
		local round = UiStyle.frame(
			card,
			UDim2.fromOffset(AVATAR, AVATAR),
			UDim2.new(0, 18 + CREST / 2, 1, -AVATAR_BOTTOM),
			Vector2.new(0.5, 1)
		)
		round.Name = "Avatar"
		UiStyle.corner(round, UDim.new(0.5, 0))
		UiStyle.gradient(round, fill[1], fill[2])
		UiStyle.stroke(round, if mvp then C.Gold else fill[1], 4)
		local head = Instance.new("ImageLabel")
		head.BackgroundTransparency = 1
		head.Size = UDim2.fromScale(1, 1)
		head.Image = "rbxthumb://type=AvatarHeadShot&id=" .. row.userId .. "&w=150&h=150"
		head.Parent = round
		UiStyle.corner(head, UDim.new(0.5, 0))
	end
	if row.userId == player.UserId and row.userId > 0 then
		local you = UiStyle.frame(
			card,
			UDim2.fromOffset(TAG_W, TAG_H),
			UDim2.new(0, 18 + CREST / 2, 1, -TAG_MIDDLE),
			Vector2.new(0.5, 0.5)
		)
		you.ZIndex = 3
		UiStyle.corner(you, 9)
		UiStyle.gradient(you, Color3.fromRGB(255, 226, 140), Color3.fromRGB(236, 182, 76))
		UiStyle.stroke(you, C.Edge, 3)
		Widgets.label(you, "YOU", 22, C.Cream, nil, C.Edge).ZIndex = you.ZIndex + 1
	end
	if row.userId > 0 then
		PlayerCard.flippable({ holder, card }, card, info(row), 16)
	end
end

-- The player's rewards in one band under the scoreboard: his LP (or none in Quick Play), the coins, the pass XP and
-- the account XP.
local function rewardsBand(parent: Instance, rewards: any, y: number)
	local band =
		Widgets.dark(parent, UDim2.fromOffset(BOARD_W, BAND_H), UDim2.new(0.5, 0, 0, y), Vector2.new(0.5, 0), 14)
	band.Name = "Rewards"
	UiStyle.stroke(band, C.Gold, 4)
	local tab = UiStyle.frame(band, UDim2.fromOffset(220, 32), UDim2.fromOffset(24, -16))
	UiStyle.corner(tab, 8)
	UiStyle.gradient(tab, Color3.fromRGB(255, 220, 110), Color3.fromRGB(206, 130, 30))
	UiStyle.stroke(tab, C.Edge, 2)
	Widgets.label(tab, "YOUR REWARDS", 20, C.Cream, nil, C.Edge)
	if rewards.boosted then
		local boost = UiStyle.frame(band, UDim2.fromOffset(200, 32), UDim2.new(1, -24, 0, -16), Vector2.new(1, 0))
		UiStyle.corner(boost, 8)
		UiStyle.gradient(boost, PURPLE[1], PURPLE[2])
		UiStyle.stroke(boost, C.Edge, 2)
		Widgets.label(boost, "2X XP BOOST", 20, C.Cream, nil, C.Edge)
	end

	local tiles = { 170, 170, 120, 155, 155 }
	local cells: { Frame } = {}
	local x = 10
	for i, w in tiles do
		local cell = UiStyle.frame(band, UDim2.fromOffset(w, BAND_H - 24), UDim2.fromOffset(x, 14))
		cell.BackgroundTransparency = 1
		cells[i] = cell
		if i > 1 then
			local line = UiStyle.frame(band, UDim2.fromOffset(2, BAND_H - 40), UDim2.fromOffset(x - 6, 20))
			line.BackgroundColor3 = C.GoldDark
			line.BackgroundTransparency = 0.3
		end
		x += w + 10
	end

	-- The rank.
	local rankCell = cells[1]
	if rewards.ranked and rewards.placing then
		local placing =
			Widgets.label(rankCell, if rewards.placed then "PLACED!" else "PLACEMENTS", 26, C.Cream, nil, C.Edge)
		placing.Size = UDim2.new(1, 0, 0, 30)
		placing.Position = UDim2.fromOffset(0, 6)
		local note = Widgets.label(
			rankCell,
			if rewards.placed and rewards.rank
				then string.upper(Ranks.label(rewards.rank.tier, rewards.rank.division))
				else (rewards.placements or 0) .. " / " .. Config.Ranked.Placements,
			20,
			C.Gold
		)
		note.Size = UDim2.new(1, 0, 0, 24)
		note.Position = UDim2.fromOffset(0, 38)
	elseif rewards.ranked and rewards.rank then
		local rank = rewards.rank
		local tier = player:GetAttribute("RankShown") or rank.tier
		Widgets.badge(rankCell, tier, 58, UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5))
		local delta = rewards.lp or 0
		local change = Widgets.label(
			rankCell,
			(if delta >= 0 then "+" else "") .. delta .. " LP",
			30,
			if delta >= 0 then W.Good else W.Bad,
			"Left",
			C.Edge
		)
		change.Size = UDim2.new(1, -64, 0, 34)
		change.Position = UDim2.fromOffset(64, 4)
		local label = if rewards.promoted
			then "PROMOTED!"
			elseif rewards.demoted then "DEMOTED"
			else string.upper(Ranks.label(tier, rank.division)) .. "  " .. rank.lp .. " LP"
		local rankText = Widgets.label(rankCell, label, 15, C.Gold, "Left")
		rankText.Size = UDim2.new(1, -64, 0, 20)
		rankText.Position = UDim2.fromOffset(64, 40)
		rankText.TextTruncate = Enum.TextTruncate.AtEnd
	else
		local mode = Widgets.label(rankCell, "QUICK PLAY", 26, C.Cream, nil, C.Edge)
		mode.Size = UDim2.new(1, 0, 0, 30)
		mode.Position = UDim2.fromOffset(0, 6)
		local note = Widgets.label(rankCell, "NO LP", 18, C.Gold)
		note.Size = UDim2.new(1, 0, 0, 22)
		note.Position = UDim2.fromOffset(0, 38)
	end

	-- The hero's mastery: his crest, the points, and a new level or a Mark of Mastery when the match brought one;
	-- the bar fills with points, or with marks once the points of the next level are there.
	local mastery = rewards.mastery
	if mastery and mastery.view then
		local view = mastery.view
		local cell = cells[2]
		Widgets.crest(cell, math.max(1, view.level), 72, UDim2.new(0, -4, 0.5, 0), Vector2.new(0, 0.5))
		local up = view.level > (mastery.levelBefore or 0) and (mastery.levelBefore or 0) > 0
		local head = if up then "MASTERY " .. view.level .. "!" else "+" .. UiStyle.thousands(mastery.points or 0)
		local text = Widgets.label(cell, head, 22, if up then C.Gold else C.Cream, "Left", C.Edge)
		text.Size = UDim2.new(1, -70, 0, 28)
		text.Position = UDim2.fromOffset(70, 2)
		local marks = mastery.marks or 0
		local sub = Widgets.label(
			cell,
			if marks > 0
				then "+" .. marks .. (if marks > 1 then " MARKS" else " MARK")
				else string.upper(mastery.hero or ""),
			14,
			C.Gold,
			"Left"
		)
		sub.Size = UDim2.new(1, -70, 0, 15)
		sub.Position = UDim2.fromOffset(70, 28)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		local points = view.into < view.need
		bar(
			cell,
			UDim2.new(1, -70, 0, 24),
			UDim2.fromOffset(70, 46),
			if points then view.into / view.need elseif view.marksNeed > 0 then view.marks / view.marksNeed else 1,
			{ Color3.fromRGB(255, 214, 90), Color3.fromRGB(200, 120, 20) },
			if points
				then UiStyle.thousands(view.into) .. " / " .. UiStyle.thousands(view.need)
				else "MARKS " .. view.marks .. " / " .. view.marksNeed
		)
	end

	-- The coins.
	local coin = Instance.new("ImageLabel")
	coin.BackgroundTransparency = 1
	coin.Image = Assets.HudCoin
	coin.Size = UDim2.fromOffset(44, 44)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 2, 0.5, 0)
	coin.Parent = cells[3]
	local coins = Widgets.label(cells[3], "+" .. UiStyle.thousands(rewards.coins or 0), 30, C.Cream, "Left", C.Edge)
	coins.Size = UDim2.new(1, -50, 1, 0)
	coins.Position = UDim2.fromOffset(50, 0)

	-- The pass and the account.
	local pass = rewards.pass or { level = 1, into = 0, need = 0 }
	local account = rewards.account or { level = 1, into = 0, need = 0 }
	local tracks = {
		{ cells[4], "PASS XP +" .. (rewards.passXp or 0), pass, rewards.passBefore, PURPLE },
		{
			cells[5],
			"ACCOUNT +" .. (rewards.accountXp or 0),
			account,
			rewards.accountBefore,
			{ Color3.fromRGB(92, 150, 246), Color3.fromRGB(30, 78, 186) },
		},
	}
	for _, track in tracks do
		local cell, text, progress = track[1], track[2], track[3]
		local head = Widgets.label(cell, text, 18, C.Cream, "Left", C.Edge)
		head.Size = UDim2.new(1, 0, 0, 26)
		head.Position = UDim2.fromOffset(4, 4)
		bar(
			cell,
			UDim2.new(1, -8, 0, 28),
			UDim2.fromOffset(4, 36),
			if progress.need > 0 then progress.into / progress.need else 1,
			track[5],
			levelText(track[4], progress.level)
		)
	end
end

-- Where the heading stands in the results: its middle HEADING_Y under the top of their board.
local HEADING_Y = 110

local function results(gui: ScreenGui, titleImage: CanvasGroup, event: RemoteEvent, result: any)
	local body = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	body.BackgroundTransparency = 1
	body.Name = "Results"
	local canvas = Instance.new("CanvasGroup")
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.GroupTransparency = 1
	canvas.Parent = body
	local board = UiStyle.frame(canvas, UDim2.fromScale(1, 1))
	board.BackgroundTransparency = 1
	board.Name = "Board"
	local landing = heading(board, player:GetAttribute("Team") == result.winner, UDim2.new(0.5, 0, 0, HEADING_Y))
	landing.Visible = false

	-- The score and the time.
	local score = UiStyle.frame(board, UDim2.fromOffset(700, 46), UDim2.new(0.5, 0, 0, 204), Vector2.new(0.5, 0))
	score.BackgroundTransparency = 1
	local scoreLayout = Widgets.list(score, "Horizontal", 14, "Center")
	scoreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local parts = {
		{ "BLUE " .. (result.score and result.score.Blue or 0), C.Blue:Lerp(Color3.new(1, 1, 1), 0.2) },
		{ "-", C.Cream },
		{ (result.score and result.score.Red or 0) .. " RED", C.Red:Lerp(Color3.new(1, 1, 1), 0.2) },
	}
	for i, part in parts do
		local t = UiStyle.text(score, part[1], 44, part[2], C.Edge)
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, 46)
		t.LayoutOrder = i
	end
	local played = Widgets.label(board, UiStyle.clock(result.duration or 0), 28, C.Cream, nil, C.Edge)
	played.Size = UDim2.new(1, 0, 0, 32)
	played.Position = UDim2.fromOffset(0, 248)

	-- The scoreboard with the rewards under it, and a star card on each side: the match's MVP on the left, the
	-- losing team's best on the right.
	local high = scoreboard(board, result)
	rewardsBand(board, result.rewards or {}, TOP + high + 18)
	local cardHigh = high + 18 + BAND_H
	local best: any, loser: any = nil, nil
	for _, row in result.players or {} do
		if row.team == result.winner then
			if not best or (row.mvp and not best.mvp) then
				best = row
			end
		elseif not loser then
			loser = row
		end
	end
	if best then
		starCard(board, best, -1, cardHigh, best.mvp == true)
	end
	if loser then
		starCard(board, loser, 1, cardHigh, false)
	end
	local bottom = TOP + cardHigh
	local total = bottom - HEAD_TOP + NEXT_H
	board.Size = UDim2.new(1, 0, 0, bottom)
	board.Position = UDim2.new(0, 0, 1 / 3, -total / 3 - HEAD_TOP)

	-- The big title flies up into the heading's place while the rest fades in, and becomes the heading there.
	local rise = 0.45
	Widgets.tween(titleImage, rise, { Position = UDim2.new(0.5, 0, 1 / 3, HEADING_Y - HEAD_TOP - total / 3) })
	local shrink = titleImage:FindFirstChildOfClass("UIScale")
	if shrink then
		Widgets.tween(shrink, rise, { Scale = 1 })
	end
	task.delay(rise * 0.3, function()
		Widgets.tween(canvas, rise, { GroupTransparency = 0 })
	end)
	task.delay(rise * 1.3, function()
		landing.Visible = true
		titleImage:Destroy()
	end)

	-- What next.
	local after = UiStyle.frame(canvas, UDim2.new(1, 0, 0, NEXT_H), UDim2.new(0, 0, 2 / 3, total / 3 - NEXT_H))
	after.BackgroundTransparency = 1
	after.Name = "Next"
	-- PLAY AGAIN on the right in gold, as PLAY on the menu; BACK TO MENU beside it in blue.
	local again, againText = Widgets.button(
		after,
		"PLAY AGAIN",
		"Gold",
		UDim2.fromOffset(BUTTON_W, 90),
		UDim2.new(0.5, 12, 0, -8),
		Vector2.new(0, 0),
		48
	)
	again.Name = "PlayAgain"
	Widgets.shimmer(again)
	local menu, menuText = Widgets.button(
		after,
		"BACK TO MENU",
		"Blue",
		UDim2.fromOffset(BUTTON_W, 90),
		UDim2.new(0.5, -12, 0, -8),
		Vector2.new(1, 0),
		48
	)
	menu.Name = "BackToMenu"
	local clock = Widgets.label(after, "", 22, C.Cream, nil, C.Edge)
	clock.Size = UDim2.new(1, 0, 0, 28)
	clock.Position = UDim2.new(0, 0, 1, 4)
	clock.AnchorPoint = Vector2.new(0, 1)
	Widgets.every(clock, 0.5, function()
		local left = (result.returnAt or 0) - Workspace:GetServerTimeNow()
		clock.Text = if left > 0 then "BACK TO THE LOBBY IN " .. UiStyle.clock(left) else "GOING BACK..."
	end)

	local chosen = false
	local function choose(action: string, label: TextLabel)
		if chosen then
			return
		end
		chosen = true
		label.Text = "GOING BACK..."
		Widgets.enable(again, false, "Gold")
		Widgets.enable(menu, false, "Blue")
		event:FireServer(action)
		task.delay(12, function()
			-- Still here: the teleport failed, so the buttons work again.
			if gui.Parent then
				chosen = false
				againText.Text, menuText.Text = "PLAY AGAIN", "BACK TO MENU"
				Widgets.enable(again, true, "Gold")
				Widgets.enable(menu, true, "Blue")
			end
		end)
	end
	again.Activated:Connect(function()
		choose("PlayAgain", againText)
	end)
	menu.Activated:Connect(function()
		choose("Menu", menuText)
	end)
end

function MatchEndView.start()
	local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("MatchEnd") :: RemoteEvent
	local result: any = nil
	local gui: ScreenGui? = nil
	local titleImage: CanvasGroup? = nil
	local titled = false
	local shown = false
	local started = false

	local function showResults()
		if shown or not result or not titled or not gui or not titleImage then
			return
		end
		shown = true
		results(gui, titleImage, event, result)
	end

	local function onWinner()
		local winner = Workspace:GetAttribute("Winner")
		if typeof(winner) ~= "string" or started then
			return
		end
		started = true
		Music.stop(2.5)
		local loser = if winner == Config.TeamOrder[1] then Config.TeamOrder[2] else Config.TeamOrder[1]
		watch(loser)
		local endedAt = Workspace:GetAttribute("MatchEnd") or Workspace:GetServerTimeNow()
		local hold = math.max(0, endedAt + Config.MatchEnd.Hold - Workspace:GetServerTimeNow())
		task.delay(hold, function()
			local won = player:GetAttribute("Team") == winner
			local screen = UiStyle.screen("MatchEnd", player:WaitForChild("PlayerGui"), 30)
			hideHud(screen)
			HeroCamera.setEnabled(false)
			local shade = UiStyle.frame(screen, UDim2.fromScale(1, 1))
			shade.BackgroundColor3 = Color3.new(0, 0, 0)
			shade.BackgroundTransparency = 1
			Widgets.tween(shade, 0.6, { BackgroundTransparency = 0.5 })
			gui = screen
			titleImage = title(screen, won)
			UiSound.play(if won then "Victory" else "Defeat")
			task.delay(TITLE, function()
				titled = true
				showResults()
			end)
		end)
	end

	event.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Result" then
			result = payload
			showResults()
		elseif kind == "Notice" and gui then
			local note = gui:FindFirstChild("Notice") :: TextLabel?
			if not note then
				-- Just over the buttons once they are there.
				local buttons = gui:FindFirstChild("Next", true)
				local made = Widgets.label(buttons or gui, "", 24, C.Xp, nil, C.Edge)
				made.Name = "Notice"
				made.Size = UDim2.new(1, 0, 0, 28)
				made.Position = if buttons then UDim2.fromOffset(0, -6) else UDim2.new(0, 0, 1, -132)
				made.AnchorPoint = Vector2.new(0, 1)
				note = made
			end
			(note :: TextLabel).Text = payload
		end
	end)
	Workspace:GetAttributeChangedSignal("Winner"):Connect(onWinner)
	onWinner()
	event:FireServer("Hello")
end

return MatchEndView
