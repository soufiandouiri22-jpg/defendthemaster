-- The scoreboard while Tab is held, as League of Legends has it in the HUD's look (UiStyle): a parchment panel with at
-- the top each team's crown and score round the match's clock, then the blue and the red team, a row per hero
-- (the server's ScoreService, ReplicatedStorage.Scores): his portrait in his team's ring with his level, greyed with
-- the seconds until he is back while he is dead; his name (the hero's for a bot); the six slots of his bag; and his
-- kills, deaths and assists. The player's own row is gold. It stands in for Roblox's player list, which Tab opened.
-- It rustles like paper as it opens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local Scoreboard = {}

local C = UiStyle.Colors
local player = Players.LocalPlayer

-- The board is laid out at these sizes and drawn at SCALE of them.
local SCALE = 0.8
local WIDTH = 860
local PAD = 16
local HEADER = 84
local STRIP = 36
local ROW, ROW_GAP = 64, 6
local TEAM_GAP = 14
local PORTRAIT = 54
local NAME_X, NAME_WIDTH = 84, 240
local SLOT, SLOT_GAP = 44, 6
local ITEMS_X = NAME_X + NAME_WIDTH + 10
local KDA_WIDTH = 170
local SLOT_TOP, SLOT_BOTTOM = Color3.fromRGB(250, 238, 206), Color3.fromRGB(222, 196, 146)
local EMPTY_TOP, EMPTY_BOTTOM = Color3.fromRGB(150, 118, 80), Color3.fromRGB(118, 90, 60)
local ROW_TOP, ROW_BOTTOM = Color3.fromRGB(255, 249, 232), Color3.fromRGB(240, 224, 186)
local OWN_TOP, OWN_BOTTOM = Color3.fromRGB(255, 234, 160), Color3.fromRGB(240, 196, 98)
local SLASH = string.format('<font color="#%s"> / </font>', C.GoldDark:ToHex())

type Slot = { frame: Frame, gradient: UIGradient, icon: ImageLabel, badge: Frame, count: TextLabel }
type Row = {
	frame: Frame,
	gradient: UIGradient,
	edge: UIStroke,
	ring: Frame,
	face: ImageLabel,
	level: TextLabel,
	wait: TextLabel,
	name: TextLabel,
	hero: TextLabel,
	slots: { Slot },
	kda: TextLabel,
}

local function slot(parent: Instance, index: number): Slot
	local frame = UiStyle.frame(
		parent,
		UDim2.fromOffset(SLOT, SLOT),
		UDim2.new(0, ITEMS_X + (index - 1) * (SLOT + SLOT_GAP), 0.5, 0),
		Vector2.new(0, 0.5)
	)
	UiStyle.corner(frame, 7)
	local gradient = UiStyle.gradient(frame, EMPTY_TOP, EMPTY_BOTTOM)
	UiStyle.stroke(frame, C.GoldDark, 2)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.new(1, -6, 1, -6)
	icon.Position = UDim2.fromOffset(3, 3)
	icon.ZIndex = 2
	icon.Parent = frame
	local badge = UiStyle.frame(frame, UDim2.fromOffset(18, 16), UDim2.new(1, -2, 1, -2), Vector2.one)
	badge.BackgroundColor3 = Color3.fromRGB(44, 30, 20)
	badge.ZIndex = 3
	UiStyle.corner(badge, 5)
	local count = UiStyle.text(badge, "", 13, C.Cream)
	count.Size = UDim2.fromScale(1, 1)
	count.ZIndex = 4
	return { frame = frame, gradient = gradient, icon = icon, badge = badge, count = count }
end

local function row(parent: Instance): Row
	local frame = UiStyle.frame(parent, UDim2.new(1, 0, 0, ROW))
	UiStyle.corner(frame, 12)
	local gradient = UiStyle.gradient(frame, ROW_TOP, ROW_BOTTOM)
	local edge = UiStyle.stroke(frame, C.GoldDark, 1.5)

	local ring = UiStyle.frame(
		frame,
		UDim2.fromOffset(PORTRAIT, PORTRAIT),
		UDim2.new(0, 10 + PORTRAIT / 2, 0.5, 0),
		Vector2.new(0.5, 0.5)
	)
	UiStyle.corner(ring, UDim.new(0.5, 0))
	UiStyle.stroke(ring, C.Edge, 2)
	local back = UiStyle.frame(ring, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4))
	back.BackgroundColor3 = Color3.fromRGB(226, 186, 128)
	back.ClipsDescendants = true
	UiStyle.corner(back, UDim.new(0.5, 0))
	local face = Instance.new("ImageLabel")
	face.BackgroundTransparency = 1
	face.Size = UDim2.fromScale(1, 1)
	face.ScaleType = Enum.ScaleType.Crop
	face.Parent = back
	UiStyle.corner(face, UDim.new(0.5, 0))
	local wait = UiStyle.text(ring, "", 24, Color3.new(1, 1, 1), C.Edge)
	wait.Size = UDim2.fromScale(1, 1)
	wait.ZIndex = 3
	local badge = UiStyle.frame(ring, UDim2.fromOffset(26, 26), UDim2.new(1, 4, 1, 4), Vector2.one)
	badge.BackgroundColor3 = Color3.fromRGB(46, 32, 22)
	badge.ZIndex = 4
	UiStyle.corner(badge, UDim.new(0.5, 0))
	UiStyle.stroke(badge, C.Gold, 2)
	local level = UiStyle.text(badge, "1", 16, C.Cream)
	level.Size = UDim2.fromScale(1, 1)
	level.ZIndex = 5

	local name = UiStyle.text(frame, "", 26, C.Ink)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Size = UDim2.fromOffset(NAME_WIDTH, 30)
	name.Position = UDim2.fromOffset(NAME_X, 6)
	local hero = UiStyle.text(frame, "", 18, C.GoldDark)
	hero.TextXAlignment = Enum.TextXAlignment.Left
	hero.Size = UDim2.fromOffset(NAME_WIDTH, 22)
	hero.Position = UDim2.fromOffset(NAME_X, 36)

	local slots = {}
	for i = 1, Config.Shop.Slots do
		slots[i] = slot(frame, i)
	end

	local kda = UiStyle.text(frame, "", 30, C.Ink)
	kda.RichText = true
	kda.TextXAlignment = Enum.TextXAlignment.Right
	kda.AnchorPoint = Vector2.new(1, 0.5)
	kda.Size = UDim2.fromOffset(KDA_WIDTH, ROW)
	kda.Position = UDim2.new(1, -18, 0.5, 0)

	return {
		frame = frame,
		gradient = gradient,
		edge = edge,
		ring = ring,
		face = face,
		level = level,
		wait = wait,
		name = name,
		hero = hero,
		slots = slots,
		kda = kda,
	}
end

local function show(r: Row, entry: Instance, team: string)
	local own = entry:GetAttribute("Player") == player.UserId
	r.gradient.Color = if own then ColorSequence.new(OWN_TOP, OWN_BOTTOM) else ColorSequence.new(ROW_TOP, ROW_BOTTOM)
	r.edge.Color = if own then C.Edge else C.GoldDark
	r.edge.Thickness = if own then 3 else 1.5
	r.ring.BackgroundColor3 = C[team]

	local hero = entry:GetAttribute("Hero")
	local portrait = hero and Config.Heroes[hero] and Config.Heroes[hero].Portrait
	r.face.Visible = portrait ~= nil
	if portrait then
		local x, y, size = table.unpack(portrait.Face)
		r.face.Image = portrait.Image
		r.face.ImageRectOffset = Vector2.new(x, y)
		r.face.ImageRectSize = Vector2.new(size, size)
	end
	local back = entry:GetAttribute("RespawnAt")
	local left = if typeof(back) == "number" then math.ceil(back - Workspace:GetServerTimeNow()) else 0
	r.face.ImageColor3 = if left > 0 then Color3.fromRGB(96, 90, 88) else Color3.new(1, 1, 1)
	r.wait.Text = if left > 0 then tostring(left) else ""
	r.level.Text = tostring(entry:GetAttribute("Level") or 1)

	local name = entry:GetAttribute("Name")
	local bot = name == nil or name == ""
	r.name.Text = if bot then hero or "" else name
	r.hero.Text = if bot then "Bot" else hero or ""

	local bag = Items.bag(entry :: any)
	for i, s in r.slots do
		local held = bag[i]
		local item = held and Config.Items[held.id]
		s.icon.Image = if item then item.Icon else ""
		s.gradient.Color = if item
			then ColorSequence.new(SLOT_TOP, SLOT_BOTTOM)
			else ColorSequence.new(EMPTY_TOP, EMPTY_BOTTOM)
		s.badge.Visible = held ~= nil and item ~= nil and (held.count > 1 or item.Potion == true)
		s.count.Text = if held then tostring(held.count) else ""
	end

	r.kda.Text = table.concat({
		tostring(entry:GetAttribute("Kills") or 0),
		tostring(entry:GetAttribute("Deaths") or 0),
		tostring(entry:GetAttribute("Assists") or 0),
	}, SLASH)
end

function Scoreboard.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	local gui = UiStyle.screen("Scoreboard", player:WaitForChild("PlayerGui"), 5)
	gui.Enabled = false
	local outer, inner =
		UiStyle.panel(gui, UDim2.fromOffset(WIDTH, 200), UDim2.fromScale(0.5, 0.5), Vector2.one / 2, 20, 6)
	outer.Name = "Board"
	UiStyle.shrink(outer, SCALE)

	-- The top: each team's crown and score at its end, the clock between them.
	local scores: { [string]: TextLabel } = {}
	for i, team in Config.TeamOrder do
		local left = i == 1
		local crown = Instance.new("ImageLabel")
		crown.BackgroundTransparency = 1
		crown.Image = if left then Assets.HudCrownBlue else Assets.HudCrownRed
		crown.Size = UDim2.fromOffset(70, 66)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = if left
			then UDim2.fromOffset(PAD + 35, PAD + HEADER / 2)
			else UDim2.new(1, -PAD - 35, 0, PAD + HEADER / 2)
		crown.Parent = inner
		local score = UiStyle.text(inner, "", 46, C[team], C[team .. "Dark"])
		score.TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		score.AnchorPoint = Vector2.new(if left then 0 else 1, 0.5)
		score.Size = UDim2.fromOffset(260, 56)
		score.Position = if left
			then UDim2.fromOffset(PAD + 80, PAD + HEADER / 2)
			else UDim2.new(1, -PAD - 80, 0, PAD + HEADER / 2)
		scores[team] = score
	end
	local tab = UiStyle.frame(inner, UDim2.fromOffset(150, 52), UDim2.new(0.5, 0, 0, PAD + HEADER / 2), Vector2.one / 2)
	tab.BackgroundColor3 = Color3.fromRGB(46, 32, 22)
	UiStyle.corner(tab, UDim.new(0.5, 0))
	UiStyle.stroke(tab, C.Gold, 3)
	local clock = UiStyle.text(tab, "0:00", 34, Color3.new(1, 1, 1), Color3.fromRGB(30, 16, 6))
	clock.Size = UDim2.fromScale(1, 1)

	-- Each team: a strip in its colour with the columns' names, then its rows.
	local sections: { [string]: { holder: Frame, rows: { Row } } } = {}
	for _, team in Config.TeamOrder do
		local holder = UiStyle.frame(inner, UDim2.new(1, -2 * PAD, 0, 0))
		holder.BackgroundTransparency = 1
		local strip = UiStyle.frame(holder, UDim2.new(1, 0, 0, STRIP))
		UiStyle.corner(strip, 10)
		UiStyle.gradient(strip, C[team], C[team .. "Dark"])
		UiStyle.stroke(strip, C.Edge, 2)
		local title = UiStyle.text(strip, string.upper(Config.Teams[team].Name) .. " TEAM", 24, C.Cream, C.Edge)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Size = UDim2.new(0, 260, 1, 0)
		title.Position = UDim2.fromOffset(14, 0)
		local items = UiStyle.text(strip, "ITEMS", 20, C.Cream, C.Edge)
		items.Size = UDim2.new(0, Config.Shop.Slots * (SLOT + SLOT_GAP) - SLOT_GAP, 1, 0)
		items.Position = UDim2.fromOffset(ITEMS_X, 0)
		local kda = UiStyle.text(strip, "K / D / A", 20, C.Cream, C.Edge)
		kda.TextXAlignment = Enum.TextXAlignment.Right
		kda.AnchorPoint = Vector2.new(1, 0)
		kda.Size = UDim2.new(0, KDA_WIDTH, 1, 0)
		kda.Position = UDim2.new(1, -18, 0, 0)
		sections[team] = { holder = holder, rows = {} }
	end

	local function update()
		local start = Workspace:GetAttribute("MatchStart")
		clock.Text = UiStyle.clock(if start then math.max(0, Workspace:GetServerTimeNow() - start) else 0)
		for team, score in scores do
			score.Text = tostring(Workspace:GetAttribute("Score" .. team) or 0)
		end

		local byTeam: { [string]: { Instance } } = {}
		for _, team in Config.TeamOrder do
			byTeam[team] = {}
		end
		local folder = ReplicatedStorage:FindFirstChild("Scores")
		for _, entry in if folder then folder:GetChildren() else {} do
			local list = byTeam[entry:GetAttribute("Team")]
			if list then
				table.insert(list, entry)
			end
		end

		local y = PAD + HEADER
		for _, team in Config.TeamOrder do
			local section = sections[team]
			local list = byTeam[team]
			table.sort(list, function(a, b)
				return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
			end)
			for i, entry in list do
				local r = section.rows[i]
				if not r then
					r = row(section.holder)
					r.frame.Position = UDim2.fromOffset(0, STRIP + ROW_GAP + (i - 1) * (ROW + ROW_GAP))
					section.rows[i] = r
				end
				r.frame.Visible = true
				show(r, entry, team)
			end
			for i = #list + 1, #section.rows do
				section.rows[i].frame.Visible = false
			end
			local height = STRIP + #list * (ROW + ROW_GAP)
			section.holder.Position = UDim2.fromOffset(PAD, y)
			section.holder.Size = UDim2.new(1, -2 * PAD, 0, height)
			y += height + TEAM_GAP
		end
		outer.Size = UDim2.fromOffset(WIDTH, y - TEAM_GAP + PAD + 12)
	end

	local function open(shown: boolean)
		if gui.Enabled == shown then
			return
		end
		if shown then
			update()
			UiSound.play("Scoreboard")
		end
		gui.Enabled = shown
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Tab and not processed then
			open(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			open(false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		open(false)
	end)
	RunService.RenderStepped:Connect(function()
		if gui.Enabled then
			update()
		end
	end)
end

return Scoreboard
