-- The match's state for the HUD (design 05), as the server's attributes on Workspace: "FightAt" (the server time the
-- buy phase of Config.Match ends), "MatchStart" (set when it does), "Score" .. team (the enemy heroes the team killed), and "Master" .. team and "MasterMax" .. team
-- (its Master's health), and "Throne" .. team (where its Master sits, for the minimap). Until the Masters stand in the
-- arena their health stays full. The buy phase begins after the draft (MatchService.begin); "Phase" says where the
-- match is ("Draft", "Buy", "Fight", "Ended"). When a Master falls the match is over: "Winner" is the other team and
-- nobody can attack any more (MatchEnd).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TestGround = require(script.Parent.TestGround)

local MatchService = {}

-- The other team than `team`.
function MatchService.enemyOf(team: string): string
	return if team == Config.TeamOrder[1] then Config.TeamOrder[2] else Config.TeamOrder[1]
end

local finished: { (winner: string) -> () } = {}

-- Whether the buy phase is over and the match not yet, so heroes may attack.
function MatchService.fighting(): boolean
	local at = Workspace:GetAttribute("FightAt")
	return at ~= nil and Workspace:GetServerTimeNow() >= at and Workspace:GetAttribute("Winner") == nil
end

-- Runs `callback` with the winning team when a Master falls.
function MatchService.onFinished(callback: (winner: string) -> ())
	table.insert(finished, callback)
end

-- On the test ground a Master may fall without ending anything.
local function finish(winner: string)
	if Workspace:GetAttribute("Winner") ~= nil or TestGround.on() then
		return
	end
	Workspace:SetAttribute("Winner", winner)
	Workspace:SetAttribute("MatchEnd", Workspace:GetServerTimeNow())
	Workspace:SetAttribute("Phase", "Ended")
	for _, callback in finished do
		task.spawn(callback, winner)
	end
end

-- Waits until the buy phase is over.
function MatchService.awaitFight()
	while not MatchService.fighting() do
		task.wait(0.1)
	end
end

local function buyPhase()
	local deadline = os.clock() + 5
	while os.clock() < deadline do
		local waiting = false
		for _, player in Players:GetPlayers() do
			waiting = waiting or player.Character == nil
		end
		if not waiting then
			break
		end
		task.wait(0.2)
	end
	local fightAt = Workspace:GetServerTimeNow() + Config.Match.BuyTime
	Workspace:SetAttribute("FightAt", fightAt)
	Workspace:SetAttribute("Phase", "Buy")
	task.wait(Config.Match.BuyTime)
	Workspace:SetAttribute("MatchStart", fightAt)
	Workspace:SetAttribute("Phase", "Fight")
end

-- Starts the buy phase, once the draft is over and the heroes stand on their pads.
function MatchService.begin()
	task.spawn(buyPhase)
end

-- `team` killed an enemy hero.
function MatchService.scored(team: string)
	Workspace:SetAttribute("Score" .. team, (Workspace:GetAttribute("Score" .. team) or 0) + 1)
end

local function watchMaster(instance: Instance)
	if not instance:IsA("Model") or not instance:GetAttribute("Master") then
		return
	end
	local model = instance :: Model
	local team = model:GetAttribute("Team")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local function update()
		local health = if humanoid then humanoid.Health else model:GetAttribute("Health")
		local max = if humanoid then humanoid.MaxHealth else model:GetAttribute("MaxHealth")
		Workspace:SetAttribute("Master" .. team, math.max(0, math.round(health or 0)))
		Workspace:SetAttribute("MasterMax" .. team, max or Config.Master.Health)
		if (health or 0) <= 0 and Workspace:GetAttribute("MatchStart") ~= nil then
			finish(MatchService.enemyOf(team))
		end
	end
	if humanoid then
		humanoid.HealthChanged:Connect(update)
	else
		model:GetAttributeChangedSignal("Health"):Connect(update)
	end
	update()
end

export type Layout = {
	thrones: { [string]: CFrame },
}

-- With `immediate` (the test ground) there is no draft or buy phase: the fight is on at once.
function MatchService.start(layout: Layout, immediate: boolean?)
	if immediate then
		local now = Workspace:GetServerTimeNow()
		Workspace:SetAttribute("FightAt", now)
		Workspace:SetAttribute("MatchStart", now)
		Workspace:SetAttribute("Phase", "Fight")
	end
	for _, team in Config.TeamOrder do
		Workspace:SetAttribute("Throne" .. team, layout.thrones[team].Position)
		Workspace:SetAttribute("Score" .. team, 0)
		Workspace:SetAttribute("Master" .. team, Config.Master.Health)
		Workspace:SetAttribute("MasterMax" .. team, Config.Master.Health)
	end
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(watchMaster)
	for _, instance in CollectionService:GetTagged("Combatant") do
		watchMaster(instance)
	end
end

return MatchService
