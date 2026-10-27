-- The HUD of design 05 round the ability bar (AbilityBar): at the top each team's Master's health under its crown,
-- blue left and red right, and between them the score (enemy heroes killed) over the match's clock (MatchService);
-- at the bottom left the hero's portrait with his level, health and XP (Shared.Leveling); at the bottom right the
-- round minimap with every hero, minion and throne on it, over the coin counter.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local UiStyle = require(script.Parent.UiStyle)

local Hud = {}

local C = UiStyle.Colors
local player = Players.LocalPlayer

-- The minimap (Assets.HudMinimap) shows the arena and its stands: this many studs from the centre to its rim.
local MAP_REACH = Config.Arena.Radius + 36
local MAP_SIZE = 270
local MAP_RING = 9

-- The top, measured off design 05: each Master's bar under its team's crown at the ends, the score board in the middle
-- with the clock on the dark tab under it (Assets.HudScoreboard, drawn by Tools/ui_textures.py with BOARD_* its size).
local BOARD_WIDTH, BOARD_HEIGHT, TAB_HEIGHT, BOARD_PAD = 672, 88, 48, 4
local BOARD_TOP = 20
local BAR_HEIGHT, BAR_MIDDLE, BAR_GAP = 52, 97, 34
local CROWN_X, CROWN_Y = 62, 88
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

-- A Master's bar as in design 05: a light gold rim, a black line inside it, a dark grey track and a glossy fill.
local function masterBar(parent: Frame, team: string, left: boolean): Frame
	local colours = TOP_COLOURS[team]
	local rim = UiStyle.frame(
		parent,
		UDim2.new(0.5, -(BOARD_WIDTH / 2 + BAR_GAP + CROWN_X), 0, BAR_HEIGHT),
		if left then UDim2.fromOffset(CROWN_X, BAR_MIDDLE) else UDim2.new(1, -CROWN_X, 0, BAR_MIDDLE),
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
	local fill = UiStyle.frame(track, UDim2.fromScale(1, 1))
	fill.Name = "Fill"
	if not left then
		fill.AnchorPoint = Vector2.new(1, 0)
		fill.Position = UDim2.fromScale(1, 0)
	end
	UiStyle.corner(fill, 9)
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
	crown.Position = if left then UDim2.fromOffset(CROWN_X, CROWN_Y) else UDim2.new(1, -CROWN_X, 0, CROWN_Y)
	crown.ZIndex = 3
	crown.Parent = parent
	return fill
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
	local fills = {}
	for i, team in Config.TeamOrder do
		fills[team] = masterBar(gui, team, i == 1)
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
		for team, fill in fills do
			local max = Workspace:GetAttribute("MasterMax" .. team) or Config.Master.Health
			local share = math.clamp((Workspace:GetAttribute("Master" .. team) or max) / max, 0, 1)
			fill.Size = UDim2.fromScale(share, 1)
			fill.Visible = share > 0
		end
		blueScore.Text =
			string.format("%s %d", string.upper(Config.Teams[blue].Name), Workspace:GetAttribute("Score" .. blue) or 0)
		redScore.Text =
			string.format("%d %s", Workspace:GetAttribute("Score" .. red) or 0, string.upper(Config.Teams[red].Name))
		local start = Workspace:GetAttribute("MatchStart")
		clock.Text = UiStyle.clock(if start then math.max(0, Workspace:GetServerTimeNow() - start) else 0)
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

-- The bottom left: portrait, level, health and XP.
local function buildPlayer(gui: ScreenGui): () -> ()
	local outer, inner =
		UiStyle.panel(gui, UDim2.fromOffset(560, 178), UDim2.new(0, 24, 1, -22), Vector2.new(0, 1), 18, 6)
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
	local health = UiStyle.bar(inner, UDim2.fromOffset(360, 40), UDim2.fromOffset(170, 62), C.Health, C.HealthDark)
	local xpLabel = UiStyle.text(inner, "XP", 32, C.Xp, C.Edge)
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.Size = UDim2.fromOffset(50, 34)
	xpLabel.Position = UDim2.fromOffset(170, 114)
	local xp = UiStyle.bar(inner, UDim2.fromOffset(312, 26), UDim2.fromOffset(218, 118), C.Xp, C.XpDark)

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

	return function()
		local lv = Leveling.level(player)
		level.Text = "LV " .. lv
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		health:set(if humanoid and humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0)
		local step = Leveling.step(lv)
		xp:set(if step then (player:GetAttribute("Xp") or 0) / step else 1)
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
			if model:IsA("Model") and model:GetAttribute("Hero") and team and model ~= own then
				dot(16, C[team], C.Edge, 4).Position = at(model:GetPivot().Position)
			end
		end
		local root = own and own:FindFirstChild("HumanoidRootPart") :: BasePart?
		if own and root then
			dot(20, C[own:GetAttribute("Team") or "Blue"], Color3.new(1, 1, 1), 5).Position = at(root.Position)
		end
		for _, d in pool do
			if not d.used then
				d.frame.Visible = false
			end
		end
		coins.Text = UiStyle.thousands(player:GetAttribute("Coins") or 0)
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
	local updates = { buildTop(top), buildPlayer(gui), buildMap(gui) }
	RunService.RenderStepped:Connect(function()
		for _, update in updates do
			update()
		end
	end)
end

return Hud
