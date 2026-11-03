-- Server entry point of Defend The Master. The lobby (Shared.Places) builds the menu's hall and runs the menu, the
-- party and the queue; a match builds the colosseum, waits for its players (MatchSetup), gives everyone his hero
-- (DraftService: the one chosen in the lobby, or a draft when Config.Draft.Enabled) and plays the match to its end
-- (MatchEnd), from where Play Again queues for the next one (QueueService, its parties MatchEnd's).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)
local Ladder = require(script.Ladder)
local MenuService = require(script.MenuService)
local ProfileService = require(script.ProfileService)
local QueueService = require(script.QueueService)
local ShowcaseService = require(script.ShowcaseService)
local TraceService = require(script.TraceService)

-- Nobody ever plays his own avatar: the menu has no characters (the hall is only seen through the menu's camera), and
-- in a match HeroService gives everyone his hero. Before anything can yield, or a player who comes in while the match
-- server is still starting up (MatchSetup reads its record) walks in as his avatar.
game:GetService("Players").CharacterAutoLoads = false
-- The log first, so it has everything from the start (Tools/trace.py).
TraceService.start()

ProfileService.start()
Ladder.start()
MenuService.start()
task.spawn(ShowcaseService.start)

if Places.isLobby() then
	local LobbyBuilder = require(script.Lobby.LobbyBuilder)
	local PartyService = require(script.Lobby.PartyService)
	LobbyBuilder.build()
	Workspace:SetAttribute("Role", "Lobby")
	PartyService.start()
	QueueService.start(PartyService)
	print("[DefendTheMaster] lobby started")
	return
end

Workspace:SetAttribute("Role", "Match")
local BoostService = require(script.BoostService)
local BotService = require(script.BotService)
local ColosseumBuilder = require(script.ColosseumBuilder)
local CombatService = require(script.CombatService)
local DraftService = require(script.DraftService)
local Economy = require(script.Economy)
local EmoteService = require(script.EmoteService)
local HazardService = require(script.HazardService)
local HeroService = require(script.HeroService)
local JumpPadService = require(script.JumpPadService)
local MasterService = require(script.MasterService)
local MatchEnd = require(script.MatchEnd)
local MatchService = require(script.MatchService)
local MatchSetup = require(script.MatchSetup)
local MinionModel = require(script.MinionModel)
local MinionService = require(script.MinionService)
local PadService = require(script.PadService)
local PortalService = require(script.PortalService)
local ProgressService = require(script.ProgressService)
local RuneGateService = require(script.RuneGateService)
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
-- Before the minions, whose paths go round the portals' stones.
PortalService.start(layout)
MinionService.start(layout)
CombatService.start()
EmoteService.start()
-- After CombatService, which makes Net.HeroHit.
HazardService.start(layout)
RuneGateService.start(layout)
JumpPadService.start()
MasterService.start(layout, if testing then TestGround.MASTERS else nil)
PadService.start(layout)
ShopService.start(layout)
BoostService.start(layout)
MatchEnd.start()
QueueService.start({ partyOf = MatchEnd.partyOf })
print(if testing then "[DefendTheMaster] server started on the test ground" else "[DefendTheMaster] server started")

-- The test ground starts at once with the player's own hero; a match first gives everyone his.
if testing then
	HeroService.release()
	TestGround.minions(MinionService.spawnAt)
	return
end
-- The longest the match waits for all its heroes (players' and bots') to stand in the arena, should one never come.
local HEROES_OUT = 10
task.spawn(function()
	if Config.Draft.Enabled then
		MatchSetup.awaitPlayers()
		DraftService.run(MatchSetup.slots())
	else
		-- Everyone's card shows from the moment his client has everything in (VersusView), with the lineup as soon as
		-- everyone is in, until all are ready and then for a while before the buy phase's clock runs. Under the cards
		-- the heroes come into the arena, standing still on their pads, and the match waits until every client has
		-- loaded what they bring too, so it begins with everything in (owner, 2026-11-03).
		MatchSetup.awaitArrivals()
		local slots = MatchSetup.slots()
		DraftService.assign(slots)
		MatchSetup.awaitPlayers()
		local shownUntil = Workspace:GetServerTimeNow() + Config.Match.Versus
		BotService.start(layout, DraftService.botHeroes())
		HeroService.release(true)
		local since = os.clock()
		while HeroService.count() < #slots and os.clock() - since < HEROES_OUT do
			task.wait(0.1)
		end
		Workspace:SetAttribute("HeroesOut", HeroService.count())
		MatchSetup.awaitHeroesLoaded()
		local untilAt = math.max(shownUntil, Workspace:GetServerTimeNow())
		Workspace:SetAttribute("VersusUntil", untilAt)
		task.wait(untilAt - Workspace:GetServerTimeNow())
		HeroService.go()
		MatchService.begin()
		return
	end
	BotService.start(layout, DraftService.botHeroes())
	HeroService.release()
	MatchService.begin()
end)
