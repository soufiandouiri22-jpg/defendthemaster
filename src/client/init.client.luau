-- Client entry point of Defend The Master. The server says what this place is (the Workspace attribute "Role"): in the
-- lobby the menu runs (Lobby.Menu), in a match the arena's views and the HUD, with the draft before the fight and the
-- end screen after it. The loading screen (ReplicatedFirst.Loading) stays up until the place's world and pictures are
-- loaded, and goes along on every teleport from here.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))

local Music = require(script.Music)
local Pictures = require(script.Pictures)
local Preferences = require(script.Preferences)
local ProfileClient = require(script.ProfileClient)

task.spawn(ProfileClient.start)
Preferences.start()
Loading.forTeleport()
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

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
	Music.start()
	Menu.start()
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
local BuyPhase = require(script.BuyPhase)
local CrownView = require(script.CrownView)
local DamageView = require(script.DamageView)
local Draft = require(script.Draft)
local HeroAnimator = require(script.HeroAnimator)
local HeroBars = require(script.HeroBars)
local HeroCamera = require(script.HeroCamera)
local HeroControls = require(script.HeroControls)
local HeroSounds = require(script.HeroSounds)
local HitFeedback = require(script.HitFeedback)
local Hud = require(script.Hud)
local ItemBar = require(script.ItemBar)
local KillFeed = require(script.KillFeed)
local MasterView = require(script.MasterView)
local MatchEndView = require(script.MatchEndView)
local MinionView = require(script.MinionView)
local PadView = require(script.PadView)
local RespawnTimer = require(script.RespawnTimer)
local Scoreboard = require(script.Scoreboard)
local Shop = require(script.Shop)

Music.start()
HeroSounds.start()
MinionView.start()
task.spawn(MasterView.start)
HitFeedback.start()
HeroAnimator.start()
HeroCamera.start()
Hud.start()
HeroBars.start()
RespawnTimer.start()
Shop.start()
Scoreboard.start()
task.spawn(CrownView.start)
DamageView.start()
task.spawn(KillFeed.start)
task.spawn(BuyPhase.start)
task.spawn(PadView.start)
AbilityBar.start()
ItemBar.start()
HeroControls.start()
task.spawn(Draft.start)
task.spawn(MatchEndView.start)
task.spawn(function()
	Loading.preload(everything(), 12)
	Loading.ready()
end)
print("[DefendTheMaster] client started")
