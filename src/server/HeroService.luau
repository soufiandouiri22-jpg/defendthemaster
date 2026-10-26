-- The players' heroes (Config.Heroes). The server loads each player's character with their hero's look instead of
-- their own avatar, in the proportions of the hero's animation pack and with the pack's weapons, sets it on one of the
-- team's spawn pads, and brings it back there Config.RespawnTime seconds after it dies. Heroes carry the "Team"
-- attribute and the "Combatant" tag, so minions and other heroes can fight them. Until the draft and the teams exist,
-- every player plays Config.DefaultHero on the Blue team.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Motion = require(ReplicatedStorage.Shared.Motion)
local ProgressService = require(script.Parent.ProgressService)

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
	-- The proportions of the animation packs' rigs.
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	return description
end

-- Puts the hero's weapons from its animation pack's rig on `character`, bound to its root part as on the pack's rig.
local function arm(character: Model, hero: string)
	local settings = Config.Heroes[hero]
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not settings.Pack or not root then
		return
	end
	local components = ReplicatedStorage[settings.Pack].Rig.Components
	local shift = Motion.rootShift(character)
	local folder = Instance.new("Folder")
	folder.Name = "Weapons"
	for _, name in settings.Weapons or {} do
		local weapon = components[name]:Clone()
		for _, d in weapon:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				d.CastShadow = true
			elseif d:IsA("Weld") and d.Name == "ComponentBinding" then
				d.Part0 = root
				d.C0 = shift * d.C0
			end
		end
		weapon.Parent = folder
	end
	folder.Parent = character
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
		character:SetAttribute("Team", "Blue")
		local head = character:FindFirstChild("Head")
		if Config.Heroes[hero].Look.HideHead and head and head:IsA("BasePart") then
			head.Transparency = 1
		end
		arm(character, hero)
		nextPad = nextPad % #pads + 1
		character:PivotTo(pads[nextPad])
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = Leveling.maxHealth(Config.Heroes[hero].Health, Leveling.level(player))
			humanoid.Health = humanoid.MaxHealth
			humanoid.WalkSpeed = Config.Combat.WalkSpeed
			-- The HUD draws every hero's bar in its team's colour instead (HeroBars).
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			CollectionService:AddTag(character, "Combatant")
			humanoid.Died:Connect(function()
				CollectionService:RemoveTag(character, "Combatant")
				ProgressService.heroDied(character, player, character:GetPivot().Position)
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
