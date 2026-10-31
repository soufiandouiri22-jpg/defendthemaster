-- The lobby's menu (designs 10 to 15 and 17) over the hall (Lobby.Showcase): the tab bar at the top (Play, Heroes,
-- Shop, Pass, Ranked) with a back arrow on the left and the coins and the settings on the right, and under it the
-- page of the chosen tab; the ladder (Leaderboard) opens from the Ranked page, the settings over everything. Away
-- from Play a dark veil lies over the hall. Notices (what the server answered) slide in under the tab bar. A player
-- without a hero starts on the welcome screen (Lobby.Welcome); becoming a hero there or on the heroes page plays his
-- transformation on the podium (Showcase.transform) with the menu out of the way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)
local Showcase = require(script.Parent.Showcase)

local Menu = {}

local C = UiStyle.Colors
local TABS = { "Play", "Heroes", "Shop", "Pass", "Ranked" }
-- The pages by name, each a module in this folder with `build(frame, menu)` that may return a function run whenever
-- the page opens.
local PAGES = {
	Play = "PlayPage",
	Heroes = "HeroesPage",
	Shop = "ShopPage",
	Pass = "PassPage",
	Ranked = "RankedPage",
	Leaderboard = "LeaderboardPage",
}
-- The tab each page belongs to.
local TAB_OF = { Leaderboard = "Ranked" }

export type Api = {
	go: (page: string) -> (),
	notice: (text: string, bad: boolean?) -> (),
	settings: () -> (),
	data: () -> Profile.Data?,
	ask: (action: string, ...any) -> ProfileClient.Answer,
	gui: ScreenGui,
	-- Shows or hides the menu itself (the tab bar, the pages, the vignette), for the welcome screen and a
	-- transformation.
	chrome: (visible: boolean) -> (),
	-- Opens the welcome screen (Lobby.Welcome).
	welcome: () -> (),
	-- Makes `hero` the player's hero and, when the server agrees, runs `before` (yielding), goes to the Play page and
	-- plays the transformation on the podium; true when he became him.
	become: (hero: string, before: (() -> ())?) -> boolean,
}

function Menu.start()
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false)
	task.spawn(Showcase.start)

	local player = Players.LocalPlayer
	local gui = UiStyle.screen("Menu", player:WaitForChild("PlayerGui"), 10)

	local veil = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	veil.BackgroundColor3 = Color3.fromRGB(16, 10, 6)
	veil.BackgroundTransparency = 1
	veil.ZIndex = 0
	local vignette = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.ZIndex = 0
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.22, 1),
		NumberSequenceKeypoint.new(0.78, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	fade.Parent = vignette

	local pages = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	pages.BackgroundTransparency = 1
	pages.Name = "Pages"

	local top = UiStyle.frame(gui, UDim2.new(1, 0, 0, 110))
	top.BackgroundTransparency = 1
	top.Name = "Top"
	top.ZIndex = 5

	local frames: { [string]: Frame } = {}
	local opened: { [string]: (() -> ())? } = {}
	local current = ""
	local api: Api

	local setTab: (name: string) -> ()
	-- Left of the tab bar: the top left corner is Roblox's own buttons.
	local back = Widgets.iconButton(top, Assets.MenuBack, 64, UDim2.new(0.5, -396, 0, 22), Vector2.new(1, 0))
	back.Name = "Back"
	back.Visible = false

	local noticeFrame = UiStyle.frame(gui, UDim2.fromOffset(640, 56), UDim2.new(0.5, 0, 0, -70), Vector2.new(0.5, 0))
	noticeFrame.ZIndex = 50
	UiStyle.corner(noticeFrame, 12)
	UiStyle.gradient(noticeFrame, Widgets.Colors.Brown, Widgets.Colors.BrownDark)
	local noticeStroke = UiStyle.stroke(noticeFrame, C.Gold, 2.5)
	local noticeText = Widgets.label(noticeFrame, "", 26, C.Cream)
	noticeText.ZIndex = 51
	local noticeAt = 0

	local function go(name: string)
		local module = PAGES[name] and script.Parent:FindFirstChild(PAGES[name])
		if not module or name == current then
			return
		end
		if current ~= "" then
			UiSound.play("Tab", 0.7)
		end
		current = name
		for page, frame in frames do
			frame.Visible = page == name
		end
		if not frames[name] then
			local frame = UiStyle.frame(pages, UDim2.fromScale(1, 1))
			frame.BackgroundTransparency = 1
			frame.Name = name
			frames[name] = frame
			opened[name] = (require(module :: ModuleScript) :: any).build(frame, api)
		end
		local onOpen = opened[name]
		if onOpen then
			task.spawn(onOpen)
		end
		setTab(TAB_OF[name] or name)
		back.Visible = name ~= "Play"
		TweenService:Create(veil, TweenInfo.new(0.25), { BackgroundTransparency = if name == "Play" then 1 else 0.35 })
			:Play()
	end

	local settingsPage: any = nil
	local becoming = false
	api =
		{
			go = go,
			notice = function(text: string, bad: boolean?)
				noticeText.Text = text
				noticeStroke.Color = if bad then Widgets.Colors.Bad else C.Gold
				UiSound.play(if bad then "Denied" else "Pick", 0.7)
				noticeAt = os.clock()
				local at = noticeAt
				TweenService:Create(
					noticeFrame,
					TweenInfo.new(0.25, Enum.EasingStyle.Back),
					{ Position = UDim2.new(0.5, 0, 0, 108) }
				):Play()
				task.delay(3, function()
					if noticeAt == at then
						TweenService:Create(noticeFrame, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -70) })
							:Play()
					end
				end)
			end,
			settings = function()
				if not settingsPage then
					settingsPage = require(script.Parent.SettingsPage)
				end
				settingsPage.open(gui, api)
			end,
			data = ProfileClient.get,
			ask = function(action: string, ...: any): ProfileClient.Answer
				local answer = ProfileClient.ask(action, ...)
				if not answer.ok and answer.error then
					api.notice(answer.error, true)
				end
				return answer
			end,
			gui = gui,
			chrome = function(visible: boolean)
				top.Visible = visible
				pages.Visible = visible
				vignette.Visible = visible
			end,
			welcome = function()
				require(script.Parent.Welcome).open(api)
			end,
			become = function(hero: string, before: (() -> ())?): boolean
				if becoming then
					return false
				end
				becoming = true
				Showcase.hold(true)
				local answer = api.ask("Favourite", hero)
				if not answer.ok then
					Showcase.hold(false)
					becoming = false
					return false
				end
				if before then
					before()
				end
				go("Play")
				api.chrome(false)
				Showcase.view(0.5, nil, 0.6)
				task.wait(0.45)
				Showcase.transform(hero)
				Showcase.hold(false)
				api.chrome(true)
				becoming = false
				return true
			end,
		}

	local _, select =
		Widgets.tabs(top, TABS, UDim2.fromOffset(760, 64), UDim2.new(0.5, 0, 0, 22), Vector2.new(0.5, 0), go)
	setTab = select
	back.Activated:Connect(function()
		go(if current == "Leaderboard" then "Ranked" else "Play")
	end)

	local gear = Widgets.iconButton(top, Assets.MenuGear, 64, UDim2.new(1, -28, 0, 22), Vector2.new(1, 0))
	gear.Name = "Gear"
	gear.Activated:Connect(api.settings)
	local _, showCoins = Widgets.coins(top, UDim2.fromOffset(210, 64), UDim2.new(1, -106, 0, 22), Vector2.new(1, 0))
	ProfileClient.watch(function(data)
		showCoins(data.Coins)
	end)

	go("Play")

	-- A player without a hero yet starts on the welcome screen.
	ProfileClient.watch(function(data)
		if (data.Favourite or "") == "" and not becoming then
			task.spawn(api.welcome)
		end
	end)
end

return Menu
