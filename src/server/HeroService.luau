-- The players' heroes (Config.Heroes). The server loads each player's character with their hero's look instead of
-- their own avatar, sets it on one of the team's spawn pads, and brings it back there Config.RespawnTime seconds after
-- it dies. Until the draft and the teams exist, every player plays Config.DefaultHero on the Blue team.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HeroService = {}

local BODY_COLOURS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

-- The avatar of the hero `name`.
function HeroService.description(name: string): HumanoidDescription
	local look = Config.Heroes[name].Look
	local description = Instance.new("HumanoidDescription")
	description.Shirt = look.Shirt
	description.Pants = look.Pants
	description.HairAccessory = look.HairAccessory or ""
	description.FaceAccessory = look.FaceAccessory or ""
	for _, part in BODY_COLOURS do
		(description :: any)[part] = look.Skin
	end
	return description
end

export type Layout = {
	spawnPads: { [string]: { CFrame } },
}

function HeroService.start(layout: Layout)
	Players.CharacterAutoLoads = false
	local pads = layout.spawnPads.Blue
	local nextPad = 0

	local function spawn(player: Player)
		if not player.Parent then
			return
		end
		local hero = player:GetAttribute("Hero") or Config.DefaultHero
		player:LoadCharacterWithHumanoidDescription(HeroService.description(hero))
		local character = player.Character
		if not character then
			return
		end
		character:SetAttribute("Hero", hero)
		local head = character:FindFirstChild("Head")
		if Config.Heroes[hero].Look.HideHead and head and head:IsA("BasePart") then
			head.Transparency = 1
		end
		nextPad = nextPad % #pads + 1
		character:PivotTo(pads[nextPad])
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				task.wait(Config.RespawnTime)
				if player.Character == character then
					spawn(player)
				end
			end)
		end
	end

	Players.PlayerAdded:Connect(spawn)
	for _, player in Players:GetPlayers() do
		task.spawn(spawn, player)
	end
end

return HeroService
