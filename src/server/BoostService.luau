-- The boosts (Config.Boosts), the objective on the plateau in the middle, one at a time. Their state is on Workspace for
-- the clients (Shared.Boosts): "Boost", "BoostKind", "BoostAt", "BoostSpot", "BoostEnds" and "BoostTeam"; the
-- carrier's player or bot and his hero have the attribute "Boost". Damage gives the Sun Crown's extra damage and the
-- Moon Shield's lesser damage taken, Items.walkSpeed the Wind Gem's speed and Leveling.cooldown the Star
-- Hourglass's shorter cooldowns; the Life Heart heals here.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Actors = require(script.Parent.Actors)
local Damage = require(script.Parent.Damage)

local SETTINGS = Config.Boosts
local TICK = 0.1
-- A hero's root stands this high over his feet.
local ROOT_HEIGHT = 3

local BoostService = {}

type Hero = { actor: Instance, character: Model, root: BasePart, humanoid: Humanoid, team: string }

local top: Vector3
local map: Folder
local carrier: Hero? = nil
-- The boosts still to come in this round, and whether the first has been dealt.
local round: { string } = {}
local dealt = false
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function heroes(): { Hero }
	local all = {}
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local team = character and character:GetAttribute("Team")
		if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and team then
			table.insert(all, { actor = actor, character = character, root = root, humanoid = humanoid, team = team })
		end
	end
	return all
end

local function shuffled(): { string }
	local all = table.clone(SETTINGS.Order)
	for i = #all, 2, -1 do
		local j = random:NextInteger(1, i)
		all[i], all[j] = all[j], all[i]
	end
	return all
end

-- The next boost: the first is always SETTINGS.First, then every round deals all of them shuffled, never the one in
-- play now (Workspace's "BoostKind", also when it was set by hand to test one) again.
local function deal(): string
	local shown = Workspace:GetAttribute("BoostKind")
	if #round == 0 then
		round = shuffled()
		if not dealt then
			table.remove(round, table.find(round, SETTINGS.First) :: number)
			table.insert(round, 1, SETTINGS.First)
		end
	end
	if round[1] == shown and dealt then
		if #round == 1 then
			round = shuffled()
			table.remove(round, table.find(round, shown) :: number)
		else
			local j = random:NextInteger(2, #round)
			round[1], round[j] = round[j], round[1]
		end
	end
	dealt = true
	return table.remove(round, 1) :: string
end

-- Every hero walks at his speed with or without the Wind Gem, unless his own motion has him slowed or Vanish
-- speeds him up: CombatService and HeroControls give him his speed back afterwards.
local function refreshSpeed()
	for _, hero in heroes() do
		if hero.humanoid.WalkSpeed >= Config.Combat.WalkSpeed and not hero.character:GetAttribute("Hidden") then
			hero.humanoid.WalkSpeed = Items.walkSpeed(hero.actor)
		end
	end
end

-- The floor under `at`, from the map.
local function ground(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local hit = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else Vector3.new(at.X, 0, at.Z)
end

local function place(state: string, spot: Vector3?)
	Workspace:SetAttribute("Boost", state)
	Workspace:SetAttribute("BoostSpot", spot)
end

local function take(hero: Hero)
	carrier = hero
	hero.actor:SetAttribute("Boost", true)
	hero.character:SetAttribute("Boost", true)
	if not Workspace:GetAttribute("BoostEnds") then
		Workspace:SetAttribute("BoostEnds", now() + SETTINGS.Lasts)
		-- Each boost counts once for whoever takes it first (MatchEnd).
		hero.actor:SetAttribute("Boosts", (hero.actor:GetAttribute("Boosts") or 0) + 1)
	end
	Workspace:SetAttribute("BoostTeam", hero.team)
	place("Carried", nil)
	refreshSpeed()
end

local function letGo()
	if carrier then
		carrier.actor:SetAttribute("Boost", nil)
		if carrier.character.Parent then
			carrier.character:SetAttribute("Boost", nil)
		end
	end
	carrier = nil
	Workspace:SetAttribute("BoostTeam", nil)
end

local function fade(at: number)
	letGo()
	Workspace:SetAttribute("BoostEnds", nil)
	Workspace:SetAttribute("BoostAt", at)
	Workspace:SetAttribute("BoostKind", deal())
	place("Waiting", nil)
	refreshSpeed()
end

-- The hero nearest the boost at `spot` who touches it: within `Reach` of it, his feet near the floor under it.
local function toucher(spot: Vector3): Hero?
	local floor = spot.Y - SETTINGS.Float
	local nearest: Hero? = nil
	local best = SETTINGS.Reach
	for _, hero in heroes() do
		local distance = HeroKit.flat(hero.root.Position - spot).Magnitude
		if distance <= best and math.abs(hero.root.Position.Y - ROOT_HEIGHT - floor) < 3 then
			nearest, best = hero, distance
		end
	end
	return nearest
end

-- The Life Heart heals the carrier's team each tick, less while wounded (Damage.healing).
local function heal()
	local team = Workspace:GetAttribute("BoostTeam")
	for _, hero in heroes() do
		if hero.team == team then
			local share = Boosts.bonus(hero.actor, "Heal") * TICK * Damage.healing(hero.actor)
			if share > 0 then
				local humanoid = hero.humanoid
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * share)
			end
		end
	end
end

local function step()
	local state = Workspace:GetAttribute("Boost")
	local ends = Workspace:GetAttribute("BoostEnds")
	if ends and now() >= ends then
		fade(now() + SETTINGS.Gap)
		return
	end
	if state == "Waiting" then
		if now() >= (Workspace:GetAttribute("BoostAt") or math.huge) then
			place("Ready", top + Vector3.new(0, SETTINGS.Float, 0))
		end
	elseif state == "Carried" then
		local hero = carrier
		local alive = hero
			and hero.character.Parent ~= nil
			and Actors.character(hero.actor) == hero.character
			and hero.humanoid.Health > 0
		if hero and not alive then
			local fell = ground(hero.root.Position)
			letGo()
			place("Dropped", fell + Vector3.new(0, SETTINGS.Float, 0))
			refreshSpeed()
		else
			heal()
		end
	elseif state == "Ready" or state == "Dropped" then
		local spot = Workspace:GetAttribute("BoostSpot")
		local hero = if typeof(spot) == "Vector3" then toucher(spot) else nil
		if hero then
			take(hero)
		end
	end
end

export type Layout = { map: Folder }

function BoostService.start(layout: Layout)
	map = layout.map
	top = ground(Vector3.new(0, 30, 0))
	Workspace:SetAttribute("BoostKind", deal())
	place("Waiting", nil)
	task.spawn(function()
		while not Workspace:GetAttribute("MatchStart") do
			task.wait(0.2)
		end
		Workspace:SetAttribute("BoostAt", Workspace:GetAttribute("MatchStart") + SETTINGS.FirstAt)
		while true do
			step()
			task.wait(TICK)
		end
	end)
end

return BoostService
