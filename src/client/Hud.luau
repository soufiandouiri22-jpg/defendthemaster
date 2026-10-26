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

local function hex(colour: Color3): string
	return "#" .. colour:ToHex()
end

-- The top: the Masters' bars under their crowns, the score and the clock.
local function buildTop(gui: Frame): () -> ()
	local bars = {}
	for i, team in Config.TeamOrder do
		local left = i == 1
		local colour, dark = C[team], C[team .. "Dark"]
		local bar = UiStyle.bar(
			gui,
			UDim2.fromOffset(470, 44),
			if left then UDim2.fromOffset(84, 30) else UDim2.new(1, -84, 0, 30),
			colour:Lerp(Color3.new(1, 1, 1), 0.2),
			colour:Lerp(dark, 0.35),
			if left then Vector2.zero else Vector2.new(1, 0),
			not left
		)
		bar.frame.Name = team .. "Master"
		local crown = Instance.new("ImageLabel")
		crown.Name = team .. "Crown"
		crown.BackgroundTransparency = 1
		crown.Image = Assets.HudCrown
		crown.ImageColor3 = colour
		crown.Size = UDim2.fromOffset(100, 85)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = if left then UDim2.fromOffset(78, 50) else UDim2.new(1, -78, 0, 50)
		crown.ZIndex = 3
		crown.Parent = gui
		bars[team] = bar
	end

	local _, box = UiStyle.panel(gui, UDim2.fromOffset(480, 72), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), 16, 5)
	box.Parent.ZIndex = 2
	local score = UiStyle.text(box, "", 44, C.Ink)
	score.RichText = true
	score.Size = UDim2.fromScale(1, 1)
	score.ZIndex = 3

	local tab = UiStyle.frame(gui, UDim2.fromOffset(130, 44), UDim2.new(0.5, 0, 0, 76), Vector2.new(0.5, 0))
	tab.ZIndex = 3
	UiStyle.corner(tab, 10)
	UiStyle.gradient(tab, Color3.fromRGB(88, 60, 38), Color3.fromRGB(48, 32, 20))
	UiStyle.stroke(tab, C.CreamDark, 3)
	local clock = UiStyle.text(tab, "0:00", 32, C.Cream)
	clock.Size = UDim2.fromScale(1, 1)
	clock.ZIndex = 4

	local blue, red = Config.TeamOrder[1], Config.TeamOrder[2]
	return function()
		for team, bar in bars do
			local max = Workspace:GetAttribute("MasterMax" .. team) or Config.Master.Health
			bar:set((Workspace:GetAttribute("Master" .. team) or max) / max)
		end
		score.Text = string.format(
			'<font color="%s">%s %d</font> - VS - <font color="%s">%d %s</font>',
			hex(C[blue]:Lerp(Color3.new(0, 0, 0), 0.15)),
			string.upper(Config.Teams[blue].Name),
			Workspace:GetAttribute("Score" .. blue) or 0,
			hex(C[red]:Lerp(Color3.new(0, 0, 0), 0.1)),
			Workspace:GetAttribute("Score" .. red) or 0,
			string.upper(Config.Teams[red].Name)
		)
		local start = Workspace:GetAttribute("MatchStart")
		clock.Text = UiStyle.clock(if start then Workspace:GetServerTimeNow() - start else 0)
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
	local _, inner = UiStyle.panel(gui, UDim2.fromOffset(560, 178), UDim2.new(0, 24, 1, -22), Vector2.new(0, 1), 18, 6)
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
	-- centred: an empty ScreenGui on the topbar's safe insets measures them.
	local top = UiStyle.frame(gui, UDim2.new(1, 0, 0, 140), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	top.Name = "Top"
	top.BackgroundTransparency = 1
	local insets = Instance.new("ScreenGui")
	insets.Name = "HudTopInsets"
	insets.ResetOnSpawn = false
	insets.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	insets.Parent = playerGui
	local scale = gui:FindFirstChildOfClass("UIScale") :: UIScale
	local function fit()
		local screen = (Workspace.CurrentCamera :: Camera).ViewportSize.X
		local left = insets.AbsolutePosition.X
		local right = screen - left - insets.AbsoluteSize.X
		top.Size = UDim2.new(1, -2 * math.max(left, right, 0) / scale.Scale, 0, 140)
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
