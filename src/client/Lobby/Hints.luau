-- The lobby's one-time hints after the player's first match (Config.FirstMatch): one at a time on the Play page, a
-- parchment bubble with a bobbing gold arrow pointing at what it is about (the EMOTE button, with the G key that opens
-- the wheel in a match; the Pass tab; the Ranked tab); GOT IT marks it seen in the profile (MenuService's HintSeen,
-- data.SeenHints) and the next follows. Laid on the screen in its own pixels, over the menu but under its pop-ups.

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
local GAP = 14
-- Seconds on the Play page before the first hint, and between two.
local FIRST_WAIT, NEXT_WAIT = 1.5, 0.8
local KEY = 54

type Hint = {
	id: string,
	title: string,
	text: (data: Profile.Data) -> string,
	target: (menu: ScreenGui) -> GuiObject?,
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
		id = "Pass",
		title = "THE PASS",
		text = function()
			return "Every match you play fills the Pass. Open it to collect your rewards."
		end,
		target = function(menu)
			return find(menu, { "Top", "Tabs", "Row", "Pass" })
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
	},
}

-- The first hint not seen yet, for a player who has played a match.
local function nextHint(data: Profile.Data?, seen: { [string]: boolean }): Hint?
	if not data or Profile.newGames(data) == 0 then
		return nil
	end
	for _, hint in HINTS do
		if not data.SeenHints[hint.id] and not seen[hint.id] then
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
	bubble.Visible = false
	UiStyle.corner(bubble, 16)
	UiStyle.stroke(bubble, C.Gold, 3)
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

	local seen: { [string]: boolean } = {}
	local shown: Hint? = nil
	local readyAt = math.huge

	ok.Activated:Connect(function()
		local hint = shown
		if not hint then
			return
		end
		seen[hint.id] = true
		shown = nil
		bubble.Visible = false
		readyAt = os.clock() + NEXT_WAIT
		task.spawn(ProfileClient.ask, "HintSeen", hint.id)
	end)

	RunService.RenderStepped:Connect(function()
		local top = menu:FindFirstChild("Top") :: GuiObject?
		local play = find(menu, { "Pages", "Play" })
		-- Not under the loading screen, which waits for every picture shown under it.
		local onPlay = Loading.isGone() and menu.Enabled and top ~= nil and top.Visible and play ~= nil and play.Visible
		local hint = if onPlay then nextHint(ProfileClient.get(), seen) else nil
		local target = hint and hint.target(menu)
		if not hint or not target or not target.Visible or target.AbsoluteSize.X <= 0 then
			bubble.Visible = false
			readyAt = math.max(readyAt, os.clock() + FIRST_WAIT)
			if not hint then
				readyAt = math.huge
			end
			return
		end
		if readyAt == math.huge then
			readyAt = os.clock() + FIRST_WAIT
		end
		if os.clock() < readyAt then
			return
		end
		if shown ~= hint then
			shown = hint
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
		bubble.Visible = true

		local scale = math.max(gui.AbsoluteSize.Y / 1080, 0.6)
		size.Scale = scale
		local screen = gui.AbsoluteSize
		-- Absolute positions count from under Roblox's top bar; this screen starts above it.
		local corner = target.AbsolutePosition - gui.AbsolutePosition
		local centre = corner + target.AbsoluteSize / 2
		local below = centre.Y < screen.Y / 2
		local half = WIDTH * scale / 2
		local x = math.clamp(centre.X, half + 16, screen.X - half - 16)
		local bob = 8 * math.abs(math.sin(os.clock() * 4))
		if below then
			bubble.AnchorPoint = Vector2.new(0.5, 0)
			local y = corner.Y + target.AbsoluteSize.Y + (ARROW + GAP) * scale
			bubble.Position = UDim2.fromOffset(x, y)
			arrow.Rotation = 0
			arrow.Position = UDim2.fromOffset(WIDTH / 2 + (centre.X - x) / scale, -ARROW / 2 - 4 + bob)
		else
			bubble.AnchorPoint = Vector2.new(0.5, 1)
			local y = corner.Y - (ARROW + GAP) * scale
			bubble.Position = UDim2.fromOffset(x, y)
			arrow.Rotation = 180
			arrow.Position = UDim2.fromOffset(WIDTH / 2 + (centre.X - x) / scale, HEIGHT + ARROW / 2 + 4 - bob)
		end
	end)
end

return Hints
