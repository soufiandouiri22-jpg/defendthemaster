-- The players' heroes (Config.Heroes). The server loads each player's character with their hero's look instead of
-- their own avatar, in the proportions of the hero's animation pack and with the pack's weapons, sets it on one of the
-- team's spawn pads, and brings it back there after it dies (Config.Respawn, ProgressService.heroDied). Heroes carry the "Team"
-- attribute and the "Combatant" tag, so minions and other heroes can fight them. Until the draft and the teams exist,
-- every player plays Config.DefaultHero on the Blue team. Bots (BotService) get their heroes from here too.

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

local pads: { [string]: { CFrame } } = {}
local nextPad: { [string]: number } = {}

-- The next of `team`'s spawn pads, in turn.
function HeroService.pad(team: string): CFrame
	local list = pads[team]
	nextPad[team] = (nextPad[team] or 0) % #list + 1
	return list[nextPad[team]]
end

-- Makes `character` the hero `hero` of `team` at `level`: its attributes, head, weapons, health and speed. It becomes
-- a "Combatant" once it is in the world (HeroService.enlist).
function HeroService.prepare(character: Model, hero: string, team: string, level: number): Humanoid?
	character:SetAttribute("Hero", hero)
	character:SetAttribute("Team", team)
	character:SetAttribute("Level", level)
	local head = character:FindFirstChild("Head")
	if Config.Heroes[hero].Look.HideHead and head and head:IsA("BasePart") then
		head.Transparency = 1
	end
	arm(character, hero)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = Leveling.maxHealth(Config.Heroes[hero].Health, level)
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = Config.Combat.WalkSpeed
		-- A hero falls down whole when he dies, as StarterPlayer has it for players; a bot's model would fall apart.
		humanoid.BreakJointsOnDeath = false
		-- The HUD draws every hero's bar in its team's colour instead (HeroBars).
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return humanoid
end

local spawned: RemoteEvent? = nil

-- Puts the hero into the fight, and tells the clients he (re)appeared (Net.HeroSpawned) for the pad's burst of light.
function HeroService.enlist(character: Model)
	CollectionService:AddTag(character, "Combatant")
	if spawned then
		spawned:FireAllClients(character)
	end
end

function HeroService.discharge(character: Model)
	CollectionService:RemoveTag(character, "Combatant")
end

function HeroService.start(layout: Layout)
	Players.CharacterAutoLoads = false
	pads = layout.spawnPads
	local net = ReplicatedStorage:FindFirstChild("Net") or Instance.new("Folder")
	net.Name = "Net"
	net.Parent = ReplicatedStorage
	local event = Instance.new("RemoteEvent")
	event.Name = "HeroSpawned"
	event.Parent = net
	spawned = event

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
		local humanoid = HeroService.prepare(character, hero, "Blue", Leveling.level(player))
		character:PivotTo(HeroService.pad("Blue"))
		if humanoid then
			HeroService.enlist(character)
			humanoid.Died:Connect(function()
				HeroService.discharge(character)
				task.wait(ProgressService.heroDied(character, player, character:GetPivot().Position))
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
