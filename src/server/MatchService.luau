-- The match's state for the HUD (design 05), as the server's attributes on Workspace: "MatchStart" (the server time
-- the match began), "Score" .. team (the enemy heroes the team killed), and "Master" .. team and "MasterMax" .. team
-- (its Master's health), and "Throne" .. team (where its Master sits, for the minimap). Until the Masters stand in the
-- arena their health stays full.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MatchService = {}

-- The other team than `team`.
function MatchService.enemyOf(team: string): string
	return if team == Config.TeamOrder[1] then Config.TeamOrder[2] else Config.TeamOrder[1]
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

function MatchService.start(layout: Layout)
	Workspace:SetAttribute("MatchStart", Workspace:GetServerTimeNow())
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
