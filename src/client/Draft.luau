-- The draft before the buy phase (design 07, server DraftService): over the arena, seen from a slowly turning camera,
-- the two teams down the sides (each place's hero, rank and name, the one picking aglow), who is picking and his time
-- at the top, the heroes in the middle (filtered by class; the player's own, the taken ones marked PICKED), the chosen
-- hero under them with LOCK IN. Anyone may look at heroes; on his turn the
-- player's choice is shown to everyone (Net.Draft "Hover") and LOCK IN takes it ("Lock"). The rest of the HUD hides
-- meanwhile. When the picks have been shown ("Ready") the draft goes and the camera is the hero's again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local ProfileClient = require(script.Parent.ProfileClient)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)
local Widgets = require(script.Parent.Widgets)

local Draft = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local COLUMNS = 5
local PLACES = 10
local CARD_HEIGHT = 214
local ROW_HEIGHT = 150
local CENTRE = 1024
-- The heights of the title with the clock and of the block of the teams, the heroes and LOCK IN, the room between
-- them, and the most of the screen's height they may fill together.
local HEADING_HEIGHT = 156
local BLOCK_HEIGHT = 788
local GAP = 64
local ROOM = 0.94
local TEAM_NAMES = { Blue = "BLUE TEAM", Red = "RED TEAM" }
local TEAM_FILL = { Blue = { C.Blue, C.BlueDark }, Red = { C.Red, C.RedDark } }
-- How quickly the camera goes round the arena (radians a second).
local ORBIT = 0.035

type PickState = {
	key: string,
	team: string,
	userId: number,
	name: string,
	hero: string?,
	hover: string?,
	locked: boolean,
	shown: number?,
	division: number?,
	mastery: { [string]: number }?,
}

type State = {
	phase: string,
	turn: number,
	endsAt: number,
	picks: { PickState },
	owned: { string },
}

local player = Players.LocalPlayer

local function heroNames(): { string }
	local list = {}
	for name in Config.Heroes do
		table.insert(list, name)
	end
	table.sort(list, function(a, b)
		local sa, sb = Config.Heroes[a], Config.Heroes[b]
		if (sa.Starter and 0 or 1) ~= (sb.Starter and 0 or 1) then
			return sa.Starter == true
		end
		return a < b
	end)
	return list
end

local function taken(state: State, hero: string): boolean
	for _, pick in state.picks do
		if pick.locked and pick.hero == hero then
			return true
		end
	end
	return false
end

-- As DraftService: his own, and not taken unless all of his own are.
local function allowed(state: State, hero: string): boolean
	if not table.find(state.owned, hero) then
		return false
	end
	if not taken(state, hero) then
		return true
	end
	for _, other in state.owned do
		if not taken(state, other) then
			return false
		end
	end
	return true
end

-- The camera goes slowly round the middle of the arena, between the two thrones.
local function orbit(): RBXScriptConnection
	local blue = Workspace:GetAttribute("ThroneBlue") :: Vector3? or Vector3.new(0, 0, -100)
	local red = Workspace:GetAttribute("ThroneRed") :: Vector3? or Vector3.new(0, 0, 100)
	local middle = (blue + red) / 2
	local radius = (red - blue).Magnitude * 0.42
	local angle = math.atan2((red - blue).Z, (red - blue).X) + math.pi / 2
	local camera = Workspace.CurrentCamera
	return RunService.RenderStepped:Connect(function(dt)
		angle += dt * ORBIT
		camera.CameraType = Enum.CameraType.Scriptable
		local from = middle + Vector3.new(math.cos(angle) * radius, 34, math.sin(angle) * radius)
		camera.CFrame = CFrame.lookAt(from, middle + Vector3.new(0, 6, 0))
	end)
end

-- Hides the other screens while the draft is up; returns what brings them back.
local function hideHud(own: ScreenGui): () -> ()
	local hidden = {}
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= own and gui.Enabled then
			gui.Enabled = false
			table.insert(hidden, gui)
		end
	end
	return function()
		for _, gui in hidden do
			gui.Enabled = true
		end
	end
end

local function build(event: RemoteEvent)
	local gui = UiStyle.screen("Draft", player:WaitForChild("PlayerGui"), 20)
	gui.Enabled = false

	local shade = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Rotation = 90
	shadeFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.3, 0.85),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 0.45),
	})
	shadeFade.Parent = shade

	-- Who is picking and his time, GAP above everything else in one block of BLOCK_HEIGHT: together in the middle of
	-- the screen, drawn smaller where they would fill more than ROOM of its height.
	local group = UiStyle.frame(
		gui,
		UDim2.new(1, 0, 0, HEADING_HEIGHT + GAP + BLOCK_HEIGHT),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	group.BackgroundTransparency = 1
	group.Name = "Group"
	local groupScale = Instance.new("UIScale")
	groupScale.Parent = group
	local function fit()
		local room = shade.AbsoluteSize.Y
		local tall = group.AbsoluteSize.Y / groupScale.Scale
		if room > 0 and tall > 0 then
			groupScale.Scale = math.min(1, room * ROOM / tall)
		end
	end
	shade:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)

	local title = Widgets.label(group, "", 54, C.Cream, nil, C.Edge)
	title.Size = UDim2.new(1, 0, 0, 64)
	local timer = Widgets.label(group, "", 92, C.Cream, nil, C.Edge)
	timer.Size = UDim2.new(1, 0, 0, 96)
	timer.Position = UDim2.fromOffset(0, 60)

	local middle = UiStyle.frame(group, UDim2.new(1, 0, 0, BLOCK_HEIGHT), UDim2.fromOffset(0, HEADING_HEIGHT + GAP))
	middle.BackgroundTransparency = 1
	middle.Name = "Middle"

	-- The teams, their middles level with the block's.
	local rows: { [string]: { Frame } } = {}
	for side, team in Config.TeamOrder do
		local left = side == 1
		local _, inner = UiStyle.panel(
			middle,
			UDim2.fromOffset(410, 720),
			if left then UDim2.fromOffset(24, 34) else UDim2.new(1, -24, 0, 34),
			if left then Vector2.zero else Vector2.new(1, 0),
			14,
			5
		)
		local heading = Widgets.label(inner, TEAM_NAMES[team], 46, TEAM_FILL[team][1], nil, C.Edge)
		heading.Size = UDim2.new(1, 0, 0, 64)
		heading.Position = UDim2.fromOffset(0, 6)
		rows[team] = {}
		for i = 1, Config.HeroesPerTeam do
			local row = UiStyle.frame(inner, UDim2.new(1, -24, 0, ROW_HEIGHT), UDim2.fromOffset(12, 76 + (i - 1) * 157))
			row.Name = team .. i
			UiStyle.corner(row, 10)
			UiStyle.gradient(row, W.Parchment, W.Stripe)
			table.insert(rows[team], row)
		end
	end

	-- The heroes.
	local _, grid =
		UiStyle.panel(middle, UDim2.fromOffset(CENTRE, 560), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), 14, 5)
	local filters = UiStyle.frame(grid, UDim2.new(1, -28, 0, 56), UDim2.fromOffset(14, 12))
	filters.BackgroundTransparency = 1
	Widgets.list(filters, "Horizontal", 8)
	local cards = UiStyle.frame(grid, UDim2.new(1, -28, 1, -88), UDim2.fromOffset(14, 80))
	cards.BackgroundTransparency = 1
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / COLUMNS, -12, 0, CARD_HEIGHT)
	layout.CellPadding = UDim2.fromOffset(12, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = cards

	-- The chosen hero, and LOCK IN.
	local _, detail =
		UiStyle.panel(middle, UDim2.fromOffset(CENTRE - 384, 210), UDim2.new(0.5, -CENTRE / 2, 0, 578), nil, 14, 5)
	local picture = UiStyle.frame(detail, UDim2.fromOffset(180, 180), UDim2.fromOffset(10, 10))
	picture.BackgroundTransparency = 1
	picture.ClipsDescendants = true
	UiStyle.corner(picture, 10)
	local pictureEdge = UiStyle.frame(detail, UDim2.fromOffset(180, 180), UDim2.fromOffset(10, 10))
	pictureEdge.BackgroundTransparency = 1
	UiStyle.corner(pictureEdge, 10)
	UiStyle.stroke(pictureEdge, C.Edge, 3)
	local heroName = Widgets.label(detail, "", 62, C.Cream, "Left", C.Edge)
	heroName.Size = UDim2.new(1, -220, 0, 70)
	heroName.Position = UDim2.fromOffset(208, 8)
	local heroRole = Widgets.label(detail, "", 32, C.Ink, "Left")
	heroRole.Size = UDim2.new(1, -220, 0, 38)
	heroRole.Position = UDim2.fromOffset(208, 76)
	local rule = UiStyle.frame(detail, UDim2.new(1, -230, 0, 2), UDim2.fromOffset(208, 118))
	rule.BackgroundColor3 = C.GoldDark
	rule.BackgroundTransparency = 0.4
	local line = Widgets.label(detail, "", 27, C.Ink, "Left")
	line.Size = UDim2.new(1, -230, 0, 66)
	line.Position = UDim2.fromOffset(208, 126)
	line.TextWrapped = true
	line.TextYAlignment = Enum.TextYAlignment.Top

	local lock, lockText = Widgets.button(
		middle,
		"LOCK IN",
		"Gold",
		UDim2.fromOffset(360, 170),
		UDim2.new(0.5, CENTRE / 2, 0, 598),
		Vector2.new(1, 0),
		72
	)
	lock.Name = "LockIn"
	Widgets.shimmer(lock)

	local state: State? = nil
	local selected = Config.DefaultHero
	local filter = "All"
	local wasMine = false
	local filterButtons: { [string]: TextButton } = {}

	local function current(): PickState?
		return state and state.picks[state.turn]
	end

	local function myTurn(): boolean
		local pick = current()
		return state ~= nil and state.phase == "Draft" and pick ~= nil and pick.userId == player.UserId
	end

	local function fillRow(row: Frame, pick: PickState?, picking: boolean)
		for _, child in row:GetChildren() do
			if not child:IsA("UICorner") and not child:IsA("UIGradient") then
				child:Destroy()
			end
		end
		local team = if pick then pick.team else "Blue"
		local holder = UiStyle.frame(row, UDim2.fromOffset(ROW_HEIGHT - 16, ROW_HEIGHT - 16), UDim2.fromOffset(8, 8))
		holder.ClipsDescendants = true
		UiStyle.corner(holder, 8)
		local hero = pick and (pick.hero or pick.hover)
		if hero and Config.Heroes[hero] then
			local face = Widgets.portrait(holder, hero, UDim2.fromScale(1, 1), nil, true)
			UiStyle.corner(face, 8)
			if not pick.locked then
				face.ImageTransparency = 0.35
			end
		else
			UiStyle.gradient(holder, TEAM_FILL[team][1]:Lerp(Color3.new(0, 0, 0), 0.25), TEAM_FILL[team][2])
			local mark = Widgets.label(holder, "?", 80, TEAM_FILL[team][1]:Lerp(Color3.new(1, 1, 1), 0.35))
			mark.Name = "Mark"
		end
		local edge = UiStyle.frame(row, holder.Size, holder.Position)
		edge.BackgroundTransparency = 1
		UiStyle.corner(edge, 8)
		UiStyle.stroke(edge, TEAM_FILL[team][2], 3)
		if picking then
			local glow = UiStyle.stroke(row, Color3.fromRGB(140, 220, 255), 4)
			glow.Name = "Glow"
			if team == "Red" then
				glow.Color = Color3.fromRGB(255, 150, 120)
			end
			local ribbon =
				Widgets.dark(row, UDim2.fromOffset(ROW_HEIGHT - 6, 30), UDim2.fromOffset(3, ROW_HEIGHT - 34), nil, 6)
			local fill = ribbon:FindFirstChildOfClass("UIGradient") :: UIGradient
			fill.Color = ColorSequence.new(TEAM_FILL[team][1], TEAM_FILL[team][2])
			Widgets.label(ribbon, "PICKING...", 20, C.Cream, nil, C.Edge)
		elseif pick and pick.locked then
			local done = Widgets.label(row, "✓", 30, W.Good, nil, C.Edge)
			done.Size = UDim2.fromOffset(36, 36)
			done.Position = UDim2.new(1, -40, 0, 4)
		end
		local textLeft = ROW_HEIGHT + 4
		local human = pick ~= nil and pick.userId > 0
		if human and pick.shown then
			Widgets.badge(row, pick.shown, 58, UDim2.fromOffset(textLeft, 22))
			textLeft += 64
		end
		local mine = pick ~= nil and pick.userId == player.UserId
		local name =
			Widgets.label(row, if pick then pick.name else "", 28, if mine then TEAM_FILL[team][2] else C.Ink, "Left")
		name.Size = UDim2.new(1, -textLeft - 8, 0, 34)
		name.Position = UDim2.fromOffset(textLeft, 30)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local below = if not human
			then "BOT"
			elseif pick.shown then string.upper(Ranks.label(pick.shown, pick.division))
			else "UNRANKED"
		local rank = Widgets.label(row, below, 22, TEAM_FILL[team][2], "Left")
		rank.Size = UDim2.new(1, -textLeft - 8, 0, 28)
		rank.Position = UDim2.fromOffset(textLeft, 66)
		local level = hero and pick and pick.mastery and pick.mastery[hero]
		if level and level > 0 then
			Widgets.crest(row, level, 64, UDim2.new(1, -10, 1, -8), Vector2.new(1, 1))
		end
		if hero and pick and pick.locked then
			local heroText = Widgets.label(row, string.upper(hero), 20, W.Muted, "Left")
			heroText.Size = UDim2.new(1, -textLeft - 80, 0, 24)
			heroText.Position = UDim2.fromOffset(textLeft, 98)
		end
	end

	local function showDetail()
		local settings = Config.Heroes[selected]
		for _, child in picture:GetChildren() do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end
		Widgets.portrait(picture, selected, UDim2.fromScale(1, 1), nil, true)
		heroName.Text = selected
		local colour = Widgets.roleColour(settings.Role)
		heroName.TextColor3 = Color3.fromRGB(226, 66, 40)
		heroRole.Text = string.upper(settings.Role or "")
		heroRole.TextColor3 = colour:Lerp(C.Ink, 0.45)
		line.Text = settings.Description or ""
	end

	local function showLock()
		local s = state
		local pick = current()
		if not s or s.phase ~= "Draft" then
			lockText.Text = "READY"
			Widgets.enable(lock, false, "Green")
			Widgets.paint(lock, "Green")
		elseif myTurn() then
			lockText.Text = "LOCK IN"
			local ok = allowed(s, selected)
			Widgets.enable(lock, ok, if ok then "Gold" else "Grey")
		else
			local mine = false
			for _, other in s.picks do
				if other.userId == player.UserId and other.locked then
					mine = true
				end
			end
			lockText.Text = if mine then "LOCKED" elseif pick then "WAIT" else "LOCK IN"
			Widgets.enable(lock, false, if mine then "Green" else "Grey")
			if mine then
				Widgets.paint(lock, "Green")
			end
		end
		lockText.TextSize = if lockText.Text == "LOCK IN" then 72 else 60
	end

	local function card(hero: string, order: number, s: State)
		local settings = Config.Heroes[hero]
		local own = table.find(s.owned, hero) ~= nil
		local gone = taken(s, hero)
		local b = Instance.new("TextButton")
		b.Name = hero
		b.AutoButtonColor = false
		b.Text = ""
		b.LayoutOrder = order
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = cards
		UiStyle.corner(b, 10)
		UiStyle.gradient(b, C.Cream, C.CreamDark)
		local chosen = hero == selected
		UiStyle.stroke(b, if chosen then C.Xp elseif own then C.Gold else W.Locked, if chosen then 5 else 3)
		local holder = UiStyle.frame(b, UDim2.new(1, -10, 0, 140), UDim2.fromOffset(5, 5))
		holder.BackgroundTransparency = 1
		holder.ClipsDescendants = true
		UiStyle.corner(holder, 7)
		local face = Widgets.portrait(holder, hero, UDim2.fromScale(1, 1), nil, true)
		UiStyle.corner(face, 7)
		if gone and not allowed(s, hero) then
			face.ImageColor3 = Color3.fromRGB(150, 150, 150)
			local ribbon =
				Widgets.dark(holder, UDim2.new(1, 0, 0, 34), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 4)
			local fill = ribbon:FindFirstChildOfClass("UIGradient") :: UIGradient
			fill.Color = ColorSequence.new(Color3.fromRGB(214, 52, 40), Color3.fromRGB(130, 24, 18))
			Widgets.label(ribbon, "PICKED", 22, C.Cream, nil, C.Edge)
		elseif not own then
			Widgets.lock(holder, 32, UDim2.new(1, -6, 1, -6), Vector2.new(1, 1))
		end
		local name = Widgets.label(b, hero, 26, C.Ink)
		name.Size = UDim2.new(1, -8, 0, 30)
		name.Position = UDim2.fromOffset(4, 148)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local role =
			Widgets.label(b, string.upper(settings.Role or ""), 20, Widgets.roleColour(settings.Role):Lerp(C.Ink, 0.4))
		role.Size = UDim2.new(1, 0, 0, 24)
		role.Position = UDim2.fromOffset(0, 180)
		Widgets.feel(b)
		b.Activated:Connect(function()
			if selected == hero then
				return
			end
			selected = hero
			if myTurn() and own then
				event:FireServer("Hover", hero)
			end
			Draft.render()
		end)
	end

	local function soon(order: number)
		local f = UiStyle.frame(cards, UDim2.new())
		f.LayoutOrder = order
		UiStyle.corner(f, 10)
		UiStyle.gradient(f, Color3.fromRGB(214, 196, 160), Color3.fromRGB(186, 166, 128))
		UiStyle.stroke(f, W.Locked, 2.5)
		local holder = UiStyle.frame(f, UDim2.new(1, -10, 0, 140), UDim2.fromOffset(5, 5))
		UiStyle.corner(holder, 7)
		UiStyle.gradient(holder, Color3.fromRGB(70, 60, 54), Color3.fromRGB(34, 28, 26))
		local mark = Widgets.label(holder, "?", 90, Color3.fromRGB(120, 106, 96))
		mark.Name = "Mark"
		local name = Widgets.label(f, "COMING SOON", 20, W.Muted)
		name.Size = UDim2.new(1, 0, 0, 30)
		name.Position = UDim2.fromOffset(0, 160)
	end

	function Draft.render()
		local s = state
		if not s then
			return
		end
		local pick = current()
		-- Rows: each team's places in their order.
		for _, team in Config.TeamOrder do
			for i, row in rows[team] do
				local found: PickState? = nil
				for _, p in s.picks do
					if p.team == team and tonumber(string.match(p.key, "%d+")) == i then
						found = p
					end
				end
				fillRow(row, found, s.phase == "Draft" and found ~= nil and found == pick)
			end
		end
		-- The heroes.
		for _, child in cards:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local shown = 0
		for i, hero in heroNames() do
			if filter == "All" or Config.Heroes[hero].Role == filter then
				shown += 1
				card(hero, i, s)
			end
		end
		local places = if filter == "All" then PLACES elseif shown == 0 then COLUMNS else shown
		for i = shown + 1, places do
			soon(1000 + i)
		end
		showDetail()
		showLock()
	end

	local function updateTitle()
		local s = state
		if not s then
			return
		end
		local pick = current()
		local left = math.max(0, s.endsAt - Workspace:GetServerTimeNow())
		if s.phase == "Draft" and pick then
			if pick.userId == player.UserId then
				title.Text = "YOUR TURN: PICK YOUR HERO"
				title.TextColor3 = C.Xp
			else
				title.Text = string.upper(pick.name) .. " IS PICKING"
				title.TextColor3 = TEAM_FILL[pick.team][1]:Lerp(Color3.new(1, 1, 1), 0.35)
			end
			timer.Text = UiStyle.clock(math.ceil(left))
			timer.TextColor3 = if left <= 5 then Color3.fromRGB(255, 110, 90) else C.Cream
		else
			title.Text = "GET READY"
			title.TextColor3 = C.Xp
			timer.Text = UiStyle.clock(math.ceil(left))
			timer.TextColor3 = C.Cream
		end
	end
	Widgets.every(timer, 0.2, updateTitle)

	local names = { "All" }
	for _, class in Config.Classes do
		table.insert(names, class)
	end
	for i, name in names do
		local b = Widgets.button(filters, string.upper(name), "Cream", UDim2.new(1 / #names, -8, 0, 52), nil, nil, 24)
		b.Name = name
		b.LayoutOrder = i
		filterButtons[name] = b
		b.Activated:Connect(function()
			filter = name
			for other, button in filterButtons do
				Widgets.paint(button, if other == filter then "Gold" else "Cream")
			end
			Draft.render()
		end)
	end
	Widgets.paint(filterButtons.All, "Gold")

	lock.Activated:Connect(function()
		if lock.Active and myTurn() and state and allowed(state, selected) then
			event:FireServer("Lock", selected)
			UiSound.play("Buy", 0.9)
		end
	end)

	local camera: RBXScriptConnection? = nil
	local restore: (() -> ())? = nil

	local function open()
		if gui.Enabled then
			return
		end
		restore = hideHud(gui)
		gui.Enabled = true
		camera = orbit()
	end

	local function close()
		if not gui.Enabled then
			return
		end
		gui.Enabled = false
		if camera then
			camera:Disconnect()
			camera = nil
		end
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		if restore then
			restore()
			restore = nil
		end
	end

	-- The hero chosen first: the last one played if he may be, else the first of his own he may take.
	local function firstChoice(s: State): string
		local data = ProfileClient.get()
		local last = data and data.LastHero
		if last and allowed(s, last) then
			return last
		end
		for _, hero in heroNames() do
			if allowed(s, hero) then
				return hero
			end
		end
		return s.owned[1] or Config.DefaultHero
	end

	event.OnClientEvent:Connect(function(s: State)
		local first = state == nil
		state = s
		if s.phase == "Draft" or s.phase == "Ready" then
			open()
		elseif s.phase == "Done" then
			close()
			return
		else
			return
		end
		local mine = myTurn()
		if mine and not wasMine then
			selected = firstChoice(s)
			event:FireServer("Hover", selected)
			UiSound.play("Tab", 0.8)
		elseif first then
			selected = firstChoice(s)
		end
		wasMine = mine
		updateTitle()
		Draft.render()
	end)
	event:FireServer("Hello")
end

function Draft.render() end

function Draft.start()
	local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Draft") :: RemoteEvent
	build(event)
end

return Draft
