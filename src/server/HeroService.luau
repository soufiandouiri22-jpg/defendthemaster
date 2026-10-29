-- The players' heroes (Config.Heroes). The server loads each player's character with their hero's look instead of
-- their own avatar, in the proportions of the hero's animation pack and with the pack's weapons, sets it on one of the
-- team's spawn pads, and brings it back there after it dies (Config.Respawn, ProgressService.heroDied). Heroes carry the "Team"
-- attribute and the "Combatant" tag, so minions and other heroes can fight them. A player plays the hero he drafted
-- (his "Hero" attribute, DraftService) on his team (his "Team" attribute, MatchSetup); the heroes come into the arena
-- once the draft is over (HeroService.release). Bots (BotService) get their heroes from here too; their look is
-- HeroLook's.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Motion = require(ReplicatedStorage.Shared.Motion)
local Actors = require(script.Parent.Actors)
local HeroLook = require(script.Parent.HeroLook)
local ProgressService = require(script.Parent.ProgressService)
local TestGround = require(script.Parent.TestGround)

local HeroService = {}

HeroService.description = HeroLook.description

-- Holds the root part of the dead hero `character` still, upright on the ground below where he died, with his body
-- joints on, so that his pack's fall (HeroAnimator) lays him down there, as the Masters fall.
local function lay(character: Model, humanoid: Humanoid)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	Motion.holdJoints(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- His own body too: he may have left the fight already (HeroService.discharge).
	local ignore = HeroKit.leapIgnore()
	table.insert(ignore, character)
	params.FilterDescendantsInstances = ignore
	local at = root.Position
	local below = Workspace:Raycast(at, Vector3.new(0, -60, 0), params)
	if below then
		at = Vector3.new(at.X, below.Position.Y + humanoid.HipHeight + root.Size.Y / 2, at.Z)
	end
	local facing = HeroKit.direction(Vector3.zero, root.CFrame.LookVector, -Vector3.zAxis)
	root.Anchored = true
	root.CFrame = CFrame.lookAt(at, at + facing)
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

-- Makes `character` the hero `hero` of `team` for `actor` (a player or bot): its attributes, head, weapons, health
-- and speed, with his level and items; "AttackSpeed" is his items' speed-up of the M1 combo, for every client. It
-- becomes a "Combatant" once it is in the world (HeroService.enlist).
function HeroService.prepare(character: Model, hero: string, team: string, actor: Instance): Humanoid?
	character:SetAttribute("Team", team)
	character:SetAttribute("Level", Leveling.level(actor :: any))
	character:SetAttribute("AttackSpeed", Items.attackSpeed(actor))
	HeroLook.dress(character, hero)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = Leveling.heroHealth(actor :: any, hero)
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = Items.walkSpeed(actor)
		-- A hero falls down whole when he dies, as StarterPlayer has it for players; a bot's model would fall apart.
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			lay(character, humanoid)
		end)
		-- The HUD draws every hero's bar in its team's colour instead (HeroBars).
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return humanoid
end

local spawned: RemoteEvent? = nil
local released = false
local spawnAll: () -> () = function() end
-- The players and bots whose hero has been in the arena before.
local appeared: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Puts the hero into the fight, and tells the clients he (re)appeared (Net.HeroSpawned) for the pad's burst of light,
-- and whether he came back after dying (the burst's sound is for that only, not for the start of the match).
function HeroService.enlist(character: Model)
	CollectionService:AddTag(character, "Combatant")
	local actor = Actors.owner(character)
	local again = actor ~= nil and appeared[actor] == true
	if actor then
		appeared[actor] = true
	end
	if spawned then
		spawned:FireAllClients(character, again)
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
		if not player.Parent or not released then
			return
		end
		local hero = player:GetAttribute("Hero") or TestGround.hero() or Config.DefaultHero
		if not Config.Heroes[hero] then
			hero = Config.DefaultHero
		end
		local team = player:GetAttribute("Team") or "Blue"
		player:LoadCharacterWithHumanoidDescription(HeroService.description(hero))
		local character = player.Character
		if not character then
			return
		end
		local humanoid = HeroService.prepare(character, hero, team, player)
		character:PivotTo(HeroService.pad(team))
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
	spawnAll = function()
		for _, player in Players:GetPlayers() do
			if not player.Character then
				task.spawn(spawn, player)
			end
		end
	end
end

-- Brings every player's hero into the arena, and from now on every player who comes in.
function HeroService.release()
	released = true
	spawnAll()
end

return HeroService
