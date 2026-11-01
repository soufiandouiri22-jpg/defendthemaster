-- The menu's first page (design 10), round the hero on the podium: the player's card at the top left (his head, name,
-- account level with its XP, and his rank with its LP), his party under it (Lobby.Party: the leader with a crown and
-- three places to invite into), the season pass's card at the top right (its level and the last reward), and at the
-- bottom right the mode (Quick Play or Ranked, which opens as Ranks.unlocked says) over the PLAY button, which puts
-- the party in the queue (Net.Queue, server QueueService) and while it searches shows the time and cancels. Until the
-- player has chosen his hero it reads CHOOSE HERO and opens the welcome screen (Lobby.Welcome); while two of the party
-- play the same hero it reads SAME HERO and cannot be pressed, the line above it saying which.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Account = require(ReplicatedStorage.Shared.Account)
local Config = require(ReplicatedStorage.Shared.Config)
local Lineup = require(ReplicatedStorage.Shared.Lineup)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)
local Party = require(script.Parent.Party)

local PlayPage = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local MODE_NAMES = { QuickPlay = "QUICK PLAY", Ranked = "RANKED" }

local function profileCard(page: Frame)
	local player = Players.LocalPlayer
	local _, inner = UiStyle.panel(page, UDim2.fromOffset(520, 300), UDim2.fromOffset(40, 0))
	Widgets.avatar(inner, player.UserId, 150, UDim2.fromOffset(18, 18))
	local name = Widgets.label(inner, player.DisplayName, 42, C.Ink, "Left")
	name.Size = UDim2.fromOffset(320, 48)
	name.Position = UDim2.fromOffset(188, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local level = Widgets.label(inner, "LEVEL 1", 28, W.Muted, "Left")
	level.Size = UDim2.fromOffset(300, 32)
	level.Position = UDim2.fromOffset(188, 74)
	local xp = UiStyle.bar(inner, UDim2.fromOffset(300, 22), UDim2.fromOffset(188, 112), C.Xp, C.XpDark)
	local badge = Widgets.badge(inner, 1, 96, UDim2.fromOffset(28, 176))
	local rank = Widgets.label(inner, "RECRUIT IV", 32, C.Ink, "Left")
	rank.Size = UDim2.fromOffset(330, 38)
	rank.Position = UDim2.fromOffset(138, 184)
	local lp = Widgets.label(inner, "0 LP", 40, C.Ink, "Left")
	lp.Size = UDim2.fromOffset(330, 44)
	lp.Position = UDim2.fromOffset(138, 222)

	ProfileClient.watch(function(data)
		local lvl, into, need = Account.level(data.Xp)
		level.Text = "LEVEL " .. lvl
		xp:set(if need > 0 then into / need else 1)
		if not Ranks.placed(data.Rank) then
			badge:SetAttribute("Tier", 1)
			rank.Text = "UNRANKED"
			lp.Text = "PLACEMENTS " .. data.Rank.Placements .. "/" .. Config.Ranked.Placements
			lp.TextSize = 28
			return
		end
		lp.TextSize = 40
		local shown = player:GetAttribute("RankShown") or data.Rank.Tier
		badge:SetAttribute("Tier", shown)
		rank.Text = string.upper(Ranks.label(shown, if Ranks.divided(shown) then data.Rank.Division else nil))
		lp.Text = data.Rank.Lp .. " LP"
	end)
end

local function passCard(page: Frame, api: any)
	local outer, inner = Widgets.panel(
		page,
		UDim2.fromOffset(330, 290),
		UDim2.new(1, -36, 0, 214),
		Vector2.new(1, 0),
		"SEASON " .. Config.Season.Number .. " PASS",
		26
	)
	local level = Widgets.label(inner, "LEVEL 1", 26, C.Ink, "Left")
	level.Size = UDim2.fromOffset(140, 30)
	level.Position = UDim2.fromOffset(20, 104)
	local bar = UiStyle.bar(inner, UDim2.fromOffset(120, 20), UDim2.fromOffset(20, 144), C.Xp, C.XpDark)
	-- The free track's next reward waiting for him; once the season has its own hero, that hero.
	local box = UiStyle.frame(inner, UDim2.fromOffset(136, 170), UDim2.new(1, -16, 0, 60), Vector2.new(1, 0))
	UiStyle.corner(box, 8)
	UiStyle.gradient(box, Color3.fromRGB(96, 70, 44), Color3.fromRGB(52, 34, 20))
	UiStyle.stroke(box, C.GoldDark, 2.5)
	local show = Widgets.reward(box)
	local click = Instance.new("TextButton")
	click.Text = ""
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = 10
	click.Parent = outer
	Widgets.feel(click)
	click.Activated:Connect(function()
		api.go("Pass")
	end)
	ProfileClient.watch(function(data)
		local lvl, into, need = Pass.level(data.Pass.Xp)
		level.Text = "LEVEL " .. lvl
		bar:set(if need > 0 then into / need else 1)
		if Config.Pass.Hero then
			show({ Hero = Config.Pass.Hero })
			return
		end
		local waiting = math.min(Config.Pass.Levels, lvl + 1)
		for l = 1, lvl do
			if not data.Pass.Claimed[tostring(l)] then
				waiting = l
				break
			end
		end
		show(Pass.free(waiting))
	end)
end

local function playArea(page: Frame, api: any)
	local mode = "QuickPlay"
	local area = UiStyle.frame(page, UDim2.fromOffset(470, 260), UDim2.new(1, -40, 1, -48), Vector2.new(1, 1))
	area.Name = "PlayArea"
	area.BackgroundTransparency = 1

	local selector = Widgets.dark(area, UDim2.fromOffset(390, 70), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), 12)
	local modeText = Widgets.label(selector, MODE_NAMES[mode], 32, C.Cream)
	local status = Widgets.label(area, "", 26, C.Cream, nil, C.Edge)
	status.Size = UDim2.fromOffset(470, 30)
	status.Position = UDim2.fromOffset(0, -38)
	status.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 26
	fit.Parent = status
	local arrows = {}
	for _, side in { -1, 1 } do
		local arrow = Instance.new("TextButton")
		arrow.Text = if side < 0 then "<" else ">"
		arrow.Font = UiStyle.Font
		arrow.TextSize = 40
		arrow.TextColor3 = C.Cream
		arrow.BackgroundTransparency = 1
		arrow.Size = UDim2.fromOffset(56, 70)
		arrow.Position = if side < 0 then UDim2.fromOffset(4, 0) else UDim2.new(1, -60, 0, 0)
		arrow.Parent = selector
		Widgets.feel(arrow)
		table.insert(arrows, arrow)
	end

	local play, playText = Widgets.button(
		area,
		"PLAY",
		"Gold",
		UDim2.fromOffset(460, 150),
		UDim2.fromScale(0.5, 1),
		Vector2.new(0.5, 1),
		78
	)
	play.Name = "PlayButton"
	Widgets.shimmer(play)

	local queue = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Queue") :: RemoteEvent
	local state = { state = "Idle", mode = mode, since = 0 }

	-- Whether Ranked is open to the player, and else why not.
	local function rankedOpen(): (boolean, string?)
		local data = ProfileClient.get()
		if not data then
			return false, "Your data is still loading."
		end
		return Ranks.unlocked(data)
	end

	-- Whether the player still has to choose his hero (his favourite is empty): PLAY then opens the welcome screen.
	local function heroless(): boolean
		local data = ProfileClient.get()
		return data ~= nil and (data.Favourite or "") == ""
	end

	-- The hero two of the party play, which keeps it out of the queue (Lineup.clash).
	local function clash(): string?
		local heroes = {}
		for _, member in Party.state().members do
			local other = Players:GetPlayerByUserId(member.userId)
			local hero = other and other:GetAttribute("Showcase")
			if hero then
				table.insert(heroes, hero)
			end
		end
		return Lineup.clash(heroes)
	end

	local function refresh()
		local searching = state.state == "Searching" or state.state == "Found" or state.state == "Teleporting"
		local leader = Party.isLeader()
		modeText.Text = MODE_NAMES[if searching then state.mode else mode]
		for _, arrow in arrows do
			arrow.Visible = not searching and leader
		end
		if not searching and heroless() then
			playText.Text = "CHOOSE HERO"
			Widgets.enable(play, true, "Gold")
		elseif not searching and clash() then
			playText.Text = "SAME HERO"
			Widgets.enable(play, false, "Gold")
		elseif state.state == "Searching" then
			playText.Text = "CANCEL"
			Widgets.enable(play, leader, "Blue")
		elseif state.state == "Found" or state.state == "Teleporting" then
			playText.Text = "MATCH FOUND"
			Widgets.enable(play, false, "Green")
			Widgets.paint(play, "Green")
		elseif not leader then
			playText.Text = "READY"
			Widgets.enable(play, false, "Gold")
		else
			playText.Text = "PLAY"
			Widgets.enable(play, true, "Gold")
		end
		playText.TextSize = if playText.Text == "PLAY" then 78 else 54
	end

	for i, arrow in arrows do
		arrow.Activated:Connect(function()
			local modes = Config.Queue.Modes
			local index = table.find(modes, mode) or 1
			local nextMode = modes[(index - 1 + (if i == 1 then -1 else 1)) % #modes + 1]
			if nextMode == "Ranked" then
				local open, why = rankedOpen()
				if not open then
					api.notice(why :: string, true)
					return
				end
			end
			mode = nextMode
			UiSound.play("Tab", 0.6)
			refresh()
		end)
	end

	local pressed = 0
	play.Activated:Connect(function()
		-- A double click would start and stop the search at once.
		if not play.Active or os.clock() - pressed < 0.6 then
			return
		end
		pressed = os.clock()
		if state.state ~= "Searching" and heroless() then
			api.welcome()
		elseif state.state == "Searching" then
			queue:FireServer("Cancel")
		else
			queue:FireServer("Join", mode)
		end
	end)

	queue.OnClientEvent:Connect(function(kind: string, payload: any, bad: boolean?)
		if kind == "State" then
			state = payload
			refresh()
		elseif kind == "Notice" then
			api.notice(payload, bad ~= false)
		end
	end)
	queue:FireServer("Hello")
	Party.onChanged(refresh)
	local function watchHero(other: Player)
		other:GetAttributeChangedSignal("Showcase"):Connect(refresh)
	end
	Players.PlayerAdded:Connect(watchHero)
	for _, other in Players:GetPlayers() do
		watchHero(other)
	end
	ProfileClient.watch(function()
		if mode == "Ranked" and not (rankedOpen()) then
			mode = "QuickPlay"
		end
		refresh()
	end)

	Widgets.every(status, 0.25, function()
		if state.state == "Searching" then
			local waited = Workspace:GetServerTimeNow() - (state.since or 0)
			status.Text = "SEARCHING  " .. UiStyle.clock(waited)
		elseif state.state == "Found" or state.state == "Teleporting" then
			status.Text = "JOINING THE MATCH..."
		else
			local hero = clash()
			status.Text = if hero then string.upper(hero) .. " TWICE: PICK DIFFERENT HEROES" else ""
		end
	end)
	refresh()
end

function PlayPage.build(page: Frame, api: any)
	-- The player's card with his party 14 under it, the two in the middle of the room under the tab bar.
	local column = Widgets.middle(page, 904)
	profileCard(column)
	Party.build(column, api)
	passCard(page, api)
	playArea(page, api)
	return nil
end

return PlayPage
