-- The season pass (design 13, Shared.Pass): on the left the season and when it ends, the player's pass level with its
-- XP, and the premium track's button (locked until Robux come); in the middle seven levels at a time, each with its
-- free reward (claimed, ready to claim, or still to reach) over its premium one (locked), with arrows to page through
-- the thirty; on the right the last level's exclusive hero, or his silhouette until he is built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local PassPage = {}

local C = UiStyle.Colors
local SHOWN = 7
local PURPLE = Widgets.Kinds.Purple
local REACHED = Color3.fromRGB(124, 214, 64)
-- The blocks' middle under the screen's: the middle of the room between the tab bar and the bottom.
local MIDDLE = Widgets.MenuBarBottom / 2

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- What a reward is in words, for the notice after claiming it.
local function describe(reward: Pass.Reward): string
	local r = reward :: any
	if r.Coins then
		return "+" .. UiStyle.thousands(r.Coins) .. " coins"
	elseif r.Boost then
		return "Double XP for " .. math.round(r.Boost / 60) .. " minutes"
	elseif r.Emote then
		return "New emote: " .. Config.Emotes.List[r.Emote].Name
	end
	return tostring(r.Hero)
end

-- The season's card on the left.
local function seasonCard(page: Frame): (data: Profile.Data) -> ()
	local _, inner =
		UiStyle.panel(page, UDim2.fromOffset(410, 740), UDim2.new(0, 40, 0.5, MIDDLE), Vector2.new(0, 0.5), 14, 5)
	local title = Widgets.label(inner, Pass.name((Pass.current(now()))), 50, C.Ink)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.Position = UDim2.fromOffset(0, 22)
	local ends = Widgets.label(inner, "", 28, C.Ink)
	ends.Size = UDim2.new(1, 0, 0, 32)
	ends.Position = UDim2.fromOffset(0, 80)
	local rule = UiStyle.frame(inner, UDim2.new(1, -80, 0, 2), UDim2.fromOffset(40, 124))
	rule.BackgroundColor3 = C.GoldDark
	rule.BackgroundTransparency = 0.4

	-- The level on a shield of gold round dark brown.
	local shield = UiStyle.frame(inner, UDim2.fromOffset(230, 260), UDim2.new(0.5, 0, 0, 150), Vector2.new(0.5, 0))
	UiStyle.corner(shield, UDim.new(0.22, 0))
	UiStyle.gradient(shield, Color3.fromRGB(255, 214, 104), Color3.fromRGB(176, 108, 30))
	UiStyle.stroke(shield, C.Edge, 3)
	local face = UiStyle.frame(shield, UDim2.new(1, -28, 1, -28), UDim2.fromOffset(14, 14))
	UiStyle.corner(face, UDim.new(0.2, 0))
	UiStyle.gradient(face, Color3.fromRGB(92, 56, 28), Color3.fromRGB(40, 22, 10))
	local word = Widgets.label(face, "LEVEL", 38, C.Cream, nil, C.Edge)
	word.Size = UDim2.new(1, 0, 0, 44)
	word.Position = UDim2.fromOffset(0, 30)
	local number = Widgets.label(face, "1", 112, C.Xp, nil, C.Edge)
	number.Size = UDim2.new(1, 0, 0, 120)
	number.Position = UDim2.fromOffset(0, 78)

	local bar = UiStyle.bar(inner, UDim2.new(1, -70, 0, 44), UDim2.fromOffset(35, 440), C.Xp, C.XpDark)
	local xp = Widgets.label(bar.frame, "", 26, C.Cream, nil, C.Edge)
	xp.ZIndex = 3

	-- The premium track opens later, for Robux.
	local premium, premiumText = Widgets.button(
		inner,
		"PREMIUM\nCOMING SOON",
		"Purple",
		UDim2.new(1, -60, 0, 150),
		UDim2.new(0.5, 0, 1, -30),
		Vector2.new(0.5, 1),
		38
	)
	premiumText.LineHeight = 1.1
	Widgets.enable(premium, false, "Purple")
	Widgets.paint(premium, "Purple")
	premium.Active = false
	Widgets.lock(premium, 40, UDim2.new(1, -14, 0, 12), Vector2.new(1, 0))

	Widgets.every(ends, 30, function()
		local which, _, endsAt = Pass.current(now())
		title.Text = Pass.name(which)
		ends.Text = if endsAt then "ENDS IN " .. Pass.left(endsAt - now()) else "UNTIL THE LAUNCH"
	end)

	return function(data: Profile.Data)
		local level, into, need = Pass.level(data.Pass.Xp)
		number.Text = tostring(level)
		bar:set(if need > 0 then into / need else 1)
		xp.Text = if need > 0 then into .. " / " .. need .. " XP" else "MAX LEVEL"
	end
end

-- Gives `frame`'s fill (its UIGradient) the colours `top` to `bottom`.
local function recolour(frame: GuiObject, top: Color3, bottom: Color3)
	local fill = frame:FindFirstChildOfClass("UIGradient") :: UIGradient
	fill.Color = ColorSequence.new(top, bottom)
end

-- The last level's card on the right: the exclusive hero.
local function heroCard(page: Frame)
	local _, inner =
		UiStyle.panel(page, UDim2.fromOffset(260, 500), UDim2.new(1, -60, 0.5, MIDDLE), Vector2.new(1, 0.5), 14, 5)
	recolour(inner, PURPLE[1], PURPLE[2])
	local strip = Widgets.dark(inner, UDim2.new(1, -24, 0, 46), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), 8)
	Widgets.label(strip, "LEVEL " .. Config.Pass.Levels, 28, C.Cream)
	local picture = UiStyle.frame(inner, UDim2.new(1, -24, 0, 280), UDim2.fromOffset(12, 64))
	picture.BackgroundTransparency = 1
	picture.ClipsDescendants = true
	UiStyle.corner(picture, 8)
	local hero = Config.Pass.Hero
	local name, role
	if hero and Config.Heroes[hero] then
		Widgets.portrait(picture, hero, UDim2.fromScale(1, 1), nil, true)
		name, role = hero, string.upper(Config.Heroes[hero].Role or "")
	else
		local dark = UiStyle.frame(picture, UDim2.fromScale(1, 1))
		UiStyle.gradient(dark, Color3.fromRGB(46, 22, 72), Color3.fromRGB(14, 8, 22))
		Widgets.label(dark, "?", 180, Color3.fromRGB(120, 80, 170), nil, Color3.fromRGB(20, 10, 30))
		name, role = "???", "COMING SOON"
	end
	local nameText = Widgets.label(inner, name, 42, C.Cream, nil, C.Edge)
	nameText.Size = UDim2.new(1, 0, 0, 46)
	nameText.Position = UDim2.fromOffset(0, 270)
	nameText.ZIndex = 3
	local roleText = Widgets.label(inner, role, 26, C.Cream, nil, C.Edge)
	roleText.Size = UDim2.new(1, 0, 0, 30)
	roleText.Position = UDim2.fromOffset(0, 314)
	roleText.ZIndex = 3
	local ribbon = Widgets.dark(inner, UDim2.new(1, 10, 0, 48), UDim2.new(0.5, 0, 0, 360), Vector2.new(0.5, 0), 6)
	recolour(ribbon, Color3.fromRGB(255, 210, 100), Color3.fromRGB(196, 124, 34))
	Widgets.label(ribbon, "EXCLUSIVE HERO", 26, C.Ink)
	local never = Widgets.label(inner, "NEVER RETURNS", 24, C.Xp, nil, C.Edge)
	never.Size = UDim2.new(1, 0, 0, 30)
	never.Position = UDim2.fromOffset(0, 420)
end

function PassPage.build(page: Frame, api: any)
	local showSeason = seasonCard(page)
	heroCard(page)

	local track = UiStyle.frame(page, UDim2.new(1, -880, 0, 720), UDim2.new(0, 520, 0.5, MIDDLE), Vector2.new(0, 0.5))
	track.BackgroundTransparency = 1
	local layout = Widgets.list(track, "Horizontal", 14)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local first = 1
	local placed = false

	local arrows = {}
	for _, side in { -1, 1 } do
		local arrow = Widgets.iconButton(
			page,
			Assets.MenuBack,
			60,
			if side < 0 then UDim2.new(0, 496, 0.5, MIDDLE) else UDim2.new(1, -336, 0.5, MIDDLE),
			Vector2.new(if side < 0 then 1 else 0, 0.5)
		)
		local icon = arrow:FindFirstChild("Icon") :: ImageLabel
		icon.Rotation = if side < 0 then 0 else 180
		arrows[side] = arrow
	end

	local function column(level: number, data: Profile.Data, current: number)
		local reached = level <= current
		local claimed = data.Pass.Claimed[tostring(level)] == true
		local col = UiStyle.frame(track, UDim2.new(1 / SHOWN, -14, 1, 0))
		col.BackgroundTransparency = 1
		col.LayoutOrder = level

		-- The level's number on top, green once reached; the current level framed in gold.
		local head = Widgets.dark(col, UDim2.new(1, 0, 0, 74), nil, nil, 10)
		local number = Widgets.label(head, tostring(level), 44, if reached then REACHED else C.Cream, nil, C.Edge)
		number.Name = "Level"
		if level == current then
			local edge = head:FindFirstChildOfClass("UIStroke") :: UIStroke
			edge.Color = C.Xp
			edge.Thickness = 4
		end

		-- The free reward.
		local free = Widgets.dark(col, UDim2.new(1, 0, 0, 300), UDim2.fromOffset(0, 86), nil, 10)
		if level == current then
			local edge = free:FindFirstChildOfClass("UIStroke") :: UIStroke
			edge.Color = C.Xp
			edge.Thickness = 4
		end
		local label = UiStyle.frame(free, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 10))
		UiStyle.corner(label, 6)
		UiStyle.gradient(label, C.Cream, C.CreamDark)
		Widgets.label(label, "FREE", 26, C.Ink)
		local box = UiStyle.frame(free, UDim2.new(1, -16, 0, 200), UDim2.fromOffset(8, 58))
		box.BackgroundTransparency = 1
		local reward = Pass.free(level)
		if claimed then
			local check = Widgets.label(box, "✓", 120, REACHED, nil, C.Edge)
			check.Size = UDim2.fromScale(1, 0.7)
			local amount = (reward :: any).Coins
			local text =
				Widgets.label(box, if amount then UiStyle.thousands(amount) else "CLAIMED", 28, C.Cream, nil, C.Edge)
			text.Size = UDim2.fromScale(1, 0.24)
			text.Position = UDim2.fromScale(0, 0.68)
		else
			Widgets.reward(box)(reward)
		end
		if reached and not claimed then
			local claim = Widgets.button(
				free,
				"CLAIM",
				"Green",
				UDim2.new(1, -16, 0, 50),
				UDim2.new(0.5, 0, 1, -8),
				Vector2.new(0.5, 1),
				26
			)
			Widgets.shimmer(claim)
			claim.Activated:Connect(function()
				if not claim.Active then
					return
				end
				claim.Active = false
				local answer = api.ask("Claim", level, "Free")
				if answer.ok then
					UiSound.play("LevelUp", 0.6)
					api.notice(describe(reward))
				else
					claim.Active = true
				end
			end)
		end

		-- The premium reward, locked.
		local premium = UiStyle.frame(col, UDim2.new(1, 0, 0, 300), UDim2.fromOffset(0, 398))
		UiStyle.corner(premium, 10)
		UiStyle.gradient(premium, PURPLE[1]:Lerp(Color3.new(0, 0, 0), 0.25), PURPLE[2]:Lerp(Color3.new(0, 0, 0), 0.4))
		UiStyle.stroke(premium, PURPLE[3], 2.5)
		local plabel = UiStyle.frame(premium, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 10))
		UiStyle.corner(plabel, 6)
		UiStyle.gradient(plabel, PURPLE[1], PURPLE[2])
		Widgets.label(plabel, "PREMIUM", 22, C.Cream, nil, C.Edge)
		local pbox = UiStyle.frame(premium, UDim2.new(1, -16, 0, 220), UDim2.fromOffset(8, 62))
		pbox.BackgroundTransparency = 1
		local premiumReward = Pass.premium(level) :: any
		if premiumReward.Hero == nil and level == Config.Pass.Levels then
			Widgets.label(pbox, "?", 110, Color3.fromRGB(170, 130, 220), nil, C.Edge)
		else
			Widgets.reward(pbox)(premiumReward)
		end
		Widgets.lock(premium, 30, UDim2.new(1, -8, 0, 56), Vector2.new(1, 0))
	end

	local function render()
		local data = ProfileClient.get()
		if not data then
			return
		end
		showSeason(data)
		local current = (Pass.level(data.Pass.Xp))
		if not placed then
			placed = true
			-- Open where the first reward waits, else at the current level.
			local focus = current
			for l = 1, current do
				if not data.Pass.Claimed[tostring(l)] then
					focus = l
					break
				end
			end
			first = math.clamp(focus - 1, 1, Config.Pass.Levels - SHOWN + 1)
		end
		for _, child in track:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for level = first, math.min(Config.Pass.Levels, first + SHOWN - 1) do
			column(level, data, current)
		end
		arrows[-1].Visible = first > 1
		arrows[1].Visible = first + SHOWN - 1 < Config.Pass.Levels
	end

	for side, arrow in arrows do
		arrow.Activated:Connect(function()
			first = math.clamp(first + side * SHOWN, 1, Config.Pass.Levels - SHOWN + 1)
			UiSound.play("Tab", 0.6)
			render()
		end)
	end
	ProfileClient.watch(render)
	return render
end

return PassPage
