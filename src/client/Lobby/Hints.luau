-- The lobby's one-time hints: one at a time on the Play page, a parchment bubble with a bobbing gold arrow pointing at
-- what it is about. Before the player's first match only the two he needs to start (the Heroes tab and PLAY), so he
-- is in a match at once; after it (Config.FirstMatch) the rest, when what he won there gives them meaning (the EMOTE
-- button, with the G key that opens the wheel in a match; the Shop, the Pass and the Ranked tabs; owner, 2026-11-16).
-- GOT IT marks it seen in the profile (MenuService's HintSeen, data.SeenHints) and the bubble glides on to the next,
-- after the last it shrinks away. Laid on the screen in its own pixels, over the menu but under its pop-ups.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local Prompts = require(script.Parent.Parent.Tips.Prompts)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local Hints = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local WIDTH, HEIGHT = 560, 196
local ARROW = 56
-- The arrow's picture leaves this much empty under its foot (Art/UI/tutorial_edge_arrow.png drawn ARROW high).
local FOOT = 7
-- The bubble's gold edge (drawn outside it), the room always kept between that edge and the arrow's foot, how far the
-- arrow bobs towards what it points at, and how close its tip then comes to it.
local EDGE, CLEAR, BOB, REACH = 3, 8, 6, 4
-- How far the bubble stays from what it points at, and the arrow's middle from the bubble at rest.
local AWAY = EDGE + CLEAR + ARROW - FOOT + BOB + REACH
local HOLD = EDGE + CLEAR - FOOT + ARROW / 2
-- Seconds on the Play page before the first hint.
local FIRST_WAIT = 1.5
-- Seconds the last hint takes to shrink away after GOT IT (the first shows at once at its full size; owner,
-- 2026-11-20); how fast the bubble glides on to the next hint (a rate: the share of the way left it closes each moment).
local LEAVE, GLIDE = 0.14, 10
-- Where the bubble waits while no hint shows. It is never made invisible: a frame shown again is drawn one frame
-- where it last stood before it moves (the top left corner, where it was made), so it only ever moves.
local OFF = UDim2.fromOffset(-10000, -10000)
local KEY = 54

type Hint = {
	id: string,
	-- Shown before his first match, not after it (all others only after it).
	first: boolean?,
	title: string,
	text: (data: Profile.Data) -> string,
	target: (menu: ScreenGui) -> GuiObject?,
	-- What is seen round the target, when that is not the target itself (a tab's bar): the arrow keeps away from it.
	outline: ((menu: ScreenGui) -> GuiObject?)?,
	-- A key shown at its foot, with what it does.
	key: { name: string, text: string }?,
}

local function find(menu: ScreenGui, path: { string }): GuiObject?
	local at: Instance? = menu
	for _, name in path do
		at = at and at:FindFirstChild(name)
	end
	return if at and at:IsA("GuiObject") then at else nil
end

local HINTS: { Hint } = {
	{
		id = "Heroes",
		first = true,
		title = "YOUR HEROES",
		text = function()
			return "Open HEROES to see every hero and their abilities, and choose who you play."
		end,
		target = function(menu)
			return find(menu, { "Top", "Tabs", "Row", "Heroes" })
		end,
		outline = function(menu)
			return find(menu, { "Top", "Tabs" })
		end,
	},
	{
		id = "Play",
		first = true,
		title = "READY TO FIGHT",
		text = function()
			return "Press PLAY to join a match. Defend your Master and bring down theirs!"
		end,
		target = function(menu)
			return find(menu, { "Pages", "Play", "PlayArea", "PlayButton" })
		end,
	},
	{
		id = "Emote",
		title = "YOUR EMOTES",
		text = function(data)
			local emote = Config.Emotes.List[Config.FirstMatch.Emote]
			local name = if emote and data.Emotes[Config.FirstMatch.Emote] then emote.Name else nil
			return (if name then "Your new emote " .. name .. " is here. " else "")
				.. "Press EMOTE to dance, and EDIT to fill your wheel."
		end,
		target = function(menu)
			return find(menu, { "Pages", "Play", "Emote" })
		end,
		key = { name = "G", text = "Hold in a match" },
	},
	{
		id = "ShopTab",
		title = "THE SHOP",
		text = function()
			return "Spend the coins you win in matches on new heroes: a featured one, and new ones every day."
		end,
		target = function(menu)
			return find(menu, { "Top", "Tabs", "Row", "Shop" })
		end,
		outline = function(menu)
			return find(menu, { "Top", "Tabs" })
		end,
	},
	{
		id = "Pass",
		title = "THE PASS",
		text = function()
			return "Every match you play fills the Pass. Open it to collect your rewards."
		end,
		target = function(menu)
			return find(menu, { "Top", "Tabs", "Row", "Pass" })
		end,
		outline = function(menu)
			return find(menu, { "Top", "Tabs" })
		end,
	},
	{
		id = "Ranked",
		title = "RANKED",
		text = function(data)
			local open, why = Ranks.unlocked(data)
			return if open then "Ranked is open: win matches to climb the ladder." else why or ""
		end,
		target = function(menu)
			return find(menu, { "Top", "Tabs", "Row", "Ranked" })
		end,
		outline = function(menu)
			return find(menu, { "Top", "Tabs" })
		end,
	},
}

-- The top and bottom of `object` on the screen counted from `origin`, its border (UIStroke) round it included.
local function rows(object: GuiObject, origin: Vector2): (number, number)
	local grow = 0
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Enabled and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
		grow = stroke.Thickness
		local at: Instance? = object
		while at do
			local scale = at:FindFirstChildOfClass("UIScale")
			if scale then
				grow *= scale.Scale
			end
			at = at.Parent
		end
	end
	local top = object.AbsolutePosition.Y - origin.Y - grow
	return top, top + object.AbsoluteSize.Y + 2 * grow
end

-- The first hint not seen yet of those for before his first match or of those for after it.
local function nextHint(data: Profile.Data?, seen: { [string]: boolean }): Hint?
	if not data then
		return nil
	end
	local first = Profile.newGames(data) == 0
	for _, hint in HINTS do
		if (hint.first == true) == first and not data.SeenHints[hint.id] and not seen[hint.id] then
			return hint
		end
	end
	return nil
end

-- Starts the hints over the lobby's menu `menu`.
function Hints.start(menu: ScreenGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyHints"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.DisplayOrder = menu.DisplayOrder + 2

	local bubble = UiStyle.frame(gui, UDim2.fromOffset(WIDTH, HEIGHT))
	bubble.Name = "Hint"
	bubble.BackgroundColor3 = W.Parchment
	bubble.Position = OFF
	UiStyle.corner(bubble, 16)
	UiStyle.stroke(bubble, C.Gold, EDGE)
	local size = Instance.new("UIScale")
	size.Parent = bubble
	local title = Widgets.label(bubble, "", 30, C.GoldDark, "Left")
	title.Size = UDim2.new(1, -48, 0, 40)
	title.Position = UDim2.fromOffset(24, 14)
	local body = Widgets.label(bubble, "", 24, C.Ink, "Left")
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Size = UDim2.new(1, -48, 0, 80)
	body.Position = UDim2.fromOffset(24, 56)
	local ok = Widgets.button(
		bubble,
		"GOT IT",
		"Green",
		UDim2.fromOffset(170, 56),
		UDim2.new(1, -18, 1, -14),
		Vector2.new(1, 1),
		26
	)
	local keyRow = UiStyle.frame(bubble, UDim2.fromOffset(WIDTH - 230, KEY))
	keyRow.Name = "Key"
	keyRow.BackgroundTransparency = 1
	keyRow.AnchorPoint = Vector2.new(0, 1)
	keyRow.Position = UDim2.new(0, 24, 1, -15)
	local arrow = Instance.new("ImageLabel")
	arrow.BackgroundTransparency = 1
	arrow.Image = Assets.TutorialEdgeArrow
	arrow.Size = UDim2.fromOffset(ARROW, ARROW)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Parent = bubble

	-- GOT IT's own press (Widgets.feel), left grown by the click that sent its hint away.
	local press = ok:FindFirstChildOfClass("UIScale")

	local seen: { [string]: boolean } = {}
	local shown: Hint? = nil
	local leftAt: number? = nil
	local readyAt = math.huge
	-- Where the bubble's top middle is on the screen while it shows, gliding to where its hint wants it.
	local at: Vector2? = nil

	ok.Activated:Connect(function()
		local hint = shown
		if not hint or leftAt then
			return
		end
		seen[hint.id] = true
		task.spawn(ProfileClient.ask, "HintSeen", hint.id)
		if nextHint(ProfileClient.get(), seen) then
			readyAt = 0
		else
			shown = nil
			leftAt = os.clock()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local scale = math.max(gui.AbsoluteSize.Y / 1080, 0.6)
		if leftAt then
			local t = (now - leftAt) / LEAVE
			if t < 1 then
				size.Scale = scale * (1 - t * t)
				return
			end
			leftAt = nil
			bubble.Position = OFF
			at = nil
		end
		local top = menu:FindFirstChild("Top") :: GuiObject?
		local play = find(menu, { "Pages", "Play" })
		-- Not under the loading screen, which waits for every picture shown under it.
		local onPlay = Loading.isGone() and menu.Enabled and top ~= nil and top.Visible and play ~= nil and play.Visible
		local hint = if onPlay then nextHint(ProfileClient.get(), seen) else nil
		local target = hint and hint.target(menu)
		if not hint or not target or not target.Visible or target.AbsoluteSize.X <= 0 then
			bubble.Position = OFF
			at = nil
			readyAt = math.max(readyAt, now + FIRST_WAIT)
			if not hint then
				readyAt = math.huge
			end
			return
		end
		if readyAt == math.huge then
			readyAt = now + FIRST_WAIT
		end
		if now < readyAt then
			return
		end
		if shown ~= hint then
			shown = hint
			if press then
				press.Scale = 1
			end
			local data = ProfileClient.get() :: Profile.Data
			title.Text = hint.title
			body.Text = hint.text(data)
			keyRow:ClearAllChildren()
			if hint.key then
				Prompts.row(keyRow, { hint.key.name }, KEY)
				local what = Widgets.label(keyRow, hint.key.text, 24, C.Ink, "Left")
				what.Size = UDim2.new(1, -(Prompts.width(hint.key.name, KEY) + 12), 1, 0)
				what.Position = UDim2.fromOffset(Prompts.width(hint.key.name, KEY) + 12, 0)
			end
			UiSound.play("Pick", 0.6)
		end
		size.Scale = scale
		local screen = gui.AbsoluteSize
		-- Absolute positions count from under Roblox's top bar; this screen starts above it.
		local centre = target.AbsolutePosition - gui.AbsolutePosition + target.AbsoluteSize / 2
		local upper, lower = rows(hint.outline and hint.outline(menu) or target, gui.AbsolutePosition)
		local below = centre.Y < screen.Y / 2
		local half = WIDTH * scale / 2
		local x = math.clamp(centre.X, half + 16, screen.X - half - 16)
		local goal = Vector2.new(x, if below then lower + AWAY * scale else upper - AWAY * scale - HEIGHT * scale)
		local spot = if at then at:Lerp(goal, 1 - math.exp(-GLIDE * dt)) else goal
		at = spot
		-- It shrinks away towards the side its arrow is on.
		local anchor = if below then 0 else 1
		bubble.AnchorPoint = Vector2.new(0.5, anchor)
		bubble.Position = UDim2.fromOffset(spot.X, spot.Y + anchor * HEIGHT * scale)
		-- The arrow shows once the bubble has come where it points from.
		arrow.ImageTransparency = math.clamp(((goal - spot).Magnitude - 2) / 12, 0, 1)
		local bob = BOB * math.abs(math.sin(now * 4))
		local reach = WIDTH / 2 + (centre.X - spot.X) / scale
		if below then
			arrow.Rotation = 0
			arrow.Position = UDim2.fromOffset(reach, -HOLD - bob)
		else
			arrow.Rotation = 180
			arrow.Position = UDim2.fromOffset(reach, HEIGHT + HOLD + bob)
		end
	end)
end

return Hints
