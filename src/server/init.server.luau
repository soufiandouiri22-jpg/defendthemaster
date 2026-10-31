-- Server entry point of Defend The Master. The lobby (Shared.Places) builds the menu's hall and runs the menu, the
-- party and the queue; a match builds the colosseum, waits for its players (MatchSetup), gives everyone his hero
-- (DraftService: the one chosen in the lobby, or a draft when Config.Draft.Enabled) and plays the match to its end
-- (MatchEnd).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)
local Ladder = require(script.Ladder)
local MenuService = require(script.MenuService)
local ProfileService = require(script.ProfileService)
local ShowcaseService = require(script.ShowcaseService)

ProfileService.start()
Ladder.start()
MenuService.start()
task.spawn(ShowcaseService.start)

if Places.isLobby() then
	local LobbyBuilder = require(script.Lobby.LobbyBuilder)
	local PartyService = require(script.Lobby.PartyService)
	local QueueService = require(script.Lobby.QueueService)
	-- The menu has no characters: the hall is only seen through the menu's camera.
	game:GetService("Players").CharacterAutoLoads = false
	LobbyBuilder.build()
	Workspace:SetAttribute("Role", "Lobby")
	PartyService.start()
	QueueService.start()
	print("[DefendTheMaster] lobby started")
	return
end

Workspace:SetAttribute("Role", "Match")
local BotService = require(script.BotService)
local ColosseumBuilder = require(script.ColosseumBuilder)
local CombatService = require(script.CombatService)
local CrownService = require(script.CrownService)
local DraftService = require(script.DraftService)
local Economy = require(script.Economy)
local HeroService = require(script.HeroService)
local MasterService = require(script.MasterService)
local MatchEnd = require(script.MatchEnd)
local MatchService = require(script.MatchService)
local MatchSetup = require(script.MatchSetup)
local MinionModel = require(script.MinionModel)
local MinionService = require(script.MinionService)
local PadService = require(script.PadService)
local ProgressService = require(script.ProgressService)
local ScoreService = require(script.ScoreService)
local ShopService = require(script.ShopService)
local TestGround = require(script.TestGround)

local testing = TestGround.on()
local layout = if testing then ColosseumBuilder.buildTestGround() else ColosseumBuilder.build()
MatchSetup.start()
DraftService.start()
Economy.start()
MatchService.start(layout, testing)
ProgressService.start()
ScoreService.start()
HeroService.start(layout)
MinionModel.publish()
MinionService.start(layout)
CombatService.start()
MasterService.start(layout, if testing then TestGround.MASTERS else nil)
PadService.start(layout)
ShopService.start(layout)
CrownService.start(layout)
MatchEnd.start()
print(if testing then "[DefendTheMaster] server started on the test ground" else "[DefendTheMaster] server started")

-- The test ground starts at once with the player's own hero; a match first gives everyone his.
if testing then
	HeroService.release()
	TestGround.minions(MinionService.spawnAt)
	return
end
task.spawn(function()
	if Config.Draft.Enabled then
		MatchSetup.awaitPlayers()
		DraftService.run(MatchSetup.slots())
	else
		-- Everyone's card shows from the moment his client has everything in (VersusView), with the lineup as soon as
		-- everyone is in, until all are ready and then for a while before the buy phase's clock runs.
		MatchSetup.awaitArrivals()
		DraftService.assign(MatchSetup.slots())
		MatchSetup.awaitPlayers()
		Workspace:SetAttribute("VersusUntil", Workspace:GetServerTimeNow() + Config.Match.Versus)
		task.wait(Config.Match.Versus)
	end
	BotService.start(layout, DraftService.botHeroes())
	HeroService.release()
	MatchService.begin()
end)
