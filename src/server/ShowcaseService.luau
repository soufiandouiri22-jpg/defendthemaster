-- The heroes for the menu: one model of every hero (HeroLook) in ReplicatedStorage.Showcase, standing still with its
-- root anchored. Each client puts its own showcase hero (Shared.Profile.showcase) on the hall's podium and plays his
-- showcase pose with his aura there (Lobby.Showcase); the heroes page, the shop and the leaderboard show copies in
-- their portraits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroLook = require(script.Parent.HeroLook)

local ShowcaseService = {}

local function build(hero: string): Model?
	local ok, model =
		pcall(Players.CreateHumanoidModelFromDescription, Players, HeroLook.description(hero), Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("[ShowcaseService] could not build", hero, model)
		return nil
	end
	model.Name = hero
	HeroLook.dress(model, hero)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
		model.PrimaryPart = root
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return model
end

function ShowcaseService.start()
	local folder = Instance.new("Folder")
	folder.Name = "Showcase"
	for hero in Config.Heroes do
		local model = build(hero)
		if model then
			model.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

return ShowcaseService
