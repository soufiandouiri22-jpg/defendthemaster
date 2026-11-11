-- Client entry point of Defend The Master. The server says what this place is (the Workspace attribute "Role"): in the
-- lobby the menu runs (Lobby.Menu), in a match the arena's views and the HUD, with the draft before the fight and the
-- end screen after it, from where Play Again goes to the next match; in a new player's first matches the tips show
-- over them (Tips). The loading screen (ReplicatedFirst.Loading) stays up until the place's world, pictures, music
-- and, in a match, the draft are there, and goes along on every teleport from here. The mouse is the game's gold gauntlet everywhere (Pointer).
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))

local Music = require(script.Music)
local Pictures = require(script.Pictures)
local Pointer = require(script.Pointer)
local Preferences = require(script.Preferences)
local ProfileClient = require(script.ProfileClient)

task.spawn(ProfileClient.start)
Preferences.start()
Loading.forTeleport()
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
Pointer.start(playerGui)

-- What the loading screen waits for: the world, everything on the screen, and every picture a page or the HUD can show.
local function everything(): { Instance | string }
	local list: { Instance | string } = { Workspace, playerGui }
	for _, id in Pictures.all() do
		table.insert(list, id)
	end
	return list
end

while not Workspace:GetAttribute("Role") do
	Workspace:GetAttributeChangedSignal("Role"):Wait()
end

if Workspace:GetAttribute("Role") == "Lobby" then
	local Menu = require(script.Lobby.Menu)
	local Showcase = require(script.Lobby.Showcase)
	local VersusView = require(script.VersusView)
	Music.start()
	Menu.start()
	task.spawn(VersusView.travel)
	task.spawn(function()
		local started = os.clock()
		while not Showcase.model() and os.clock() - started < 10 do
			task.wait(0.1)
		end
		Loading.preload(everything(), 12)
		Loading.ready()
	end)
	print("[DefendTheMaster] lobby client started")
	return
end

local AbilityBar = require(script.AbilityBar)
local BoostView = require(script.BoostView)
local BuyPhase = require(script.BuyPhase)
local ClothingWatch = require(script.ClothingWatch)
local DamageView = require(script.DamageView)
local Config = require(ReplicatedStorage.Shared.Config)
local Draft = require(script.Draft)
local EmoteControls = require(script.EmoteControls)
local HazardView = require(script.HazardView)
local HeroAnimator = require(script.HeroAnimator)
local HeroBars = require(script.HeroBars)
local HeroCamera = require(script.HeroCamera)
local HeroControls = require(script.HeroControls)
local HeroSounds = require(script.HeroSounds)
local HitFeedback = require(script.HitFeedback)
local Hud = require(script.Hud)
local ItemBar = require(script.ItemBar)
local JumpPadView = require(script.JumpPadView)
local KillFeed = require(script.KillFeed)
local LightningEffects = require(script.LightningEffects)
local MasterView = require(script.MasterView)
local MatchEndView = require(script.MatchEndView)
local MinionView = require(script.MinionView)
local PadView = require(script.PadView)
local PortalView = require(script.PortalView)
local RespawnTimer = require(script.RespawnTimer)
local RuneGateView = require(script.RuneGateView)
local Scoreboard = require(script.Scoreboard)
local Shop = require(script.Shop)
local Showroom = require(script.Showroom)
local Side = require(script.Side)
local Tips = require(script.Tips)
local Vanish = require(script.Vanish)
local VersusView = require(script.VersusView)

-- The views take their colours from the player's team (Side), so they wait for it.
Side.start()
Music.start()
HeroSounds.start()
MinionView.start()
task.spawn(MasterView.start)
HitFeedback.start()
LightningEffects.start()
HeroAnimator.start()
ClothingWatch.start(HeroAnimator.playing)
HeroCamera.start()
Hud.start()
HeroBars.start()
Vanish.start()
RespawnTimer.start()
Shop.start()
Scoreboard.start()
task.spawn(BoostView.start)
DamageView.start()
task.spawn(KillFeed.start)
task.spawn(BuyPhase.start)
task.spawn(PadView.start)
task.spawn(PortalView.start)
task.spawn(HazardView.start)
task.spawn(RuneGateView.start)
task.spawn(JumpPadView.start)
AbilityBar.start()
ItemBar.start()
HeroControls.start()
task.spawn(EmoteControls.start)
Showroom.start()
task.spawn(Tips.start)
-- The loading screen stays until the draft is up, or without a draft until both teams' cards have been shown
-- (VersusView), except on Studio's test ground, which has neither.
local draftShown = Loading.hold()
if RunService:IsStudio() and Workspace:GetAttribute("TestGround") == true then
	draftShown()
end
if Config.Draft.Enabled then
	task.spawn(Draft.start, draftShown)
else
	task.spawn(VersusView.start, draftShown, Loading.waitReady)
end
task.spawn(MatchEndView.start)
-- Play Again queues from the end screen: the next match's cards come over it and go along to that match.
task.spawn(VersusView.travel)
task.spawn(function()
	-- How far this client's loading screen is, for everyone's cards, until it has everything in.
	local report = ReplicatedStorage:WaitForChild("Net"):WaitForChild("LoadProgress", 10) :: RemoteEvent?
	while report do
		local share, done = Loading.progress()
		if done then
			break
		end
		report:FireServer(share)
		task.wait(0.3)
	end
end)
task.spawn(function()
	-- The server starts the draft once every player's client has everything in.
	Loading.waitReady()
	local net = ReplicatedStorage:WaitForChild("Net")
	local ready = net:WaitForChild("ClientReady", 10) :: RemoteEvent?
	if ready then
		ready:FireServer()
	end
end)
task.spawn(function()
	Loading.preload(everything(), 12)
	Loading.ready()
	-- Studio's test ground holds its minions back until the loading screen is gone (server TestGround).
	local loaded = ReplicatedStorage:WaitForChild("Net"):FindFirstChild("TestGroundLoaded")
	if loaded then
		Loading.waitGone()
		loaded:FireServer()
	end
end)
print("[DefendTheMaster] client started")
