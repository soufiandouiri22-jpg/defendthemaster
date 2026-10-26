-- The team minions (Config.Minions). Every wave leaves a team's two doorways and marches along a path worked out once
-- at the start to the other team's dais, turning on the enemies that come close: the other team's minions and
-- everything tagged "Combatant" (heroes, and the Masters with the "Master" attribute) with another "Team" attribute.
-- They go first for an enemy hero who just attacked them, or one of their heroes or their Master nearby
-- (MinionService.heroAttacked),
-- and otherwise for the nearest enemy, minion, hero or Master. A minion that has come to the end of its path with
-- nobody in reach hunts: it walks to the nearest enemy left anywhere in the arena, and with none left stands on its own
-- spot there. Only the last hit by a player earns the bounty.
--
-- The server moves one invisible root part per minion, ten times a second, in Workspace.Minions, with the attributes
-- Team, Kind, Health, MaxHealth and Dead; each client shows the rock minion on it (MinionView). Attacks are sent to the
-- clients through ReplicatedStorage.Net.MinionAttack (root, target, travel time) so they can bite and spit on time.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(script.Parent.Economy)
local ProgressService = require(script.Parent.ProgressService)

local MinionService = {}

local SETTINGS = Config.Minions
local TICK = 0.1
-- When a bite lands after it starts (the client's lunge is at its furthest then).
local BITE_HIT = 0.25
-- How long a dead minion's root stays for the client's death.
local CORPSE_TIME = 1.5
-- The turns tried, in degrees, when the way ahead is blocked.
local DETOURS = { 0, 25, -25, 50, -50, 80, -80 }
-- A hunting minion works out its way to its quarry again this often, in seconds.
local HUNT_REFRESH = 2
-- At the end of its path each minion stands on its own spot within this many studs, so a wave does not stack up.
local END_SPREAD = 6

type Stats = {
	Health: number,
	Damage: number,
	Interval: number,
	Range: number,
	Speed: number,
	Bounty: number,
	SpitSpeed: number?,
}

-- The way a minion that has come to the end of its path walks to the nearest enemy left anywhere in the arena.
type Hunt = {
	quarry: Target,
	path: { Vector3 },
	waypoint: number,
	at: number,
	finding: boolean,
}

type Minion = {
	team: string,
	kind: string,
	stats: Stats,
	root: BasePart,
	position: Vector3,
	facing: Vector3,
	health: number,
	path: { Vector3 },
	waypoint: number,
	-- Its own spot round the end of its path, and whether it got there (from then on it hunts).
	spot: Vector3,
	arrived: boolean,
	hunt: Hunt?,
	target: Target?,
	-- Where it left its path for the current chase, and until when it ignores enemies after giving one up.
	chaseFrom: Vector3?,
	calmUntil: number,
	-- The enemy heroes who attacked it, one of its heroes or its Master, and until when each comes first.
	callers: { [Model]: number },
	nextAttack: number,
	lastHitBy: Player?,
	dead: boolean,
}

-- An enemy: another minion, or a tagged Combatant (a Model with a Humanoid, or with a "Health" attribute).
type Target = Minion | Model

local minions: { Minion } = {}
local byRoot: { [BasePart]: Minion } = {}
local folder: Folder
local attackEvent: RemoteEvent
local obstacles = RaycastParams.new()
obstacles.FilterType = Enum.RaycastFilterType.Include
-- Each doorway's path, by the door's CFrame.
local paths: { [CFrame]: { Vector3 } } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function isMinion(t: Target): boolean
	return typeof(t) == "table"
end

local function positionOf(t: Target): Vector3
	if isMinion(t) then
		return (t :: Minion).position
	end
	return flat((t :: Model):GetPivot().Position)
end

local function radiusOf(t: Target): number
	if isMinion(t) then
		return SETTINGS.Radius
	end
	return (t :: Model):GetAttribute("Radius") or 1.5
end

local function alive(t: Target): boolean
	if isMinion(t) then
		return not (t :: Minion).dead
	end
	local model = t :: Model
	if not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health > 0
	end
	return (model:GetAttribute("Health") or 0) > 0
end

local function kill(m: Minion)
	m.dead = true
	m.root:SetAttribute("Health", 0)
	m.root:SetAttribute("Dead", true)
	local killer = m.lastHitBy
	if killer and killer.Parent then
		Economy.give(killer, m.stats.Bounty, "last hit on a " .. m.team .. " " .. m.kind)
	end
	ProgressService.minionDied(m.team, m.kind, m.root.Position, if killer and killer.Parent then killer else nil)
	local index = table.find(minions, m)
	if index then
		table.remove(minions, index)
	end
	byRoot[m.root] = nil
	local root = m.root
	task.delay(CORPSE_TIME, function()
		root:Destroy()
	end)
end

local function hurtMinion(m: Minion, amount: number, player: Player?)
	if m.dead then
		return
	end
	m.health -= amount
	m.lastHitBy = player
	m.root:SetAttribute("Health", math.max(0, math.round(m.health)))
	if m.health <= 0 then
		kill(m)
	end
end

local function hurt(t: Target, amount: number)
	if isMinion(t) then
		hurtMinion(t :: Minion, amount, nil)
		return
	end
	local model = t :: Model
	if model:GetAttribute("Master") then
		amount *= SETTINGS.VsMaster
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(amount)
	else
		model:SetAttribute("Health", math.max(0, (model:GetAttribute("Health") or 0) - amount))
	end
end

-- How much `m` wants `t`: 1 a hero who attacked it, one of its heroes or its Master, 2 every other enemy.
local function rankOf(m: Minion, t: Target, now: number): number
	local expires = m.callers[t :: Model]
	if expires and now < expires then
		return 1
	end
	return 2
end

-- `m` turns on the hero `attacker` for CallTime seconds.
local function call(m: Minion, attacker: Model, now: number)
	for caller, expires in m.callers do
		if expires <= now then
			m.callers[caller] = nil
		end
	end
	m.callers[attacker] = now + SETTINGS.CallTime
	m.calmUntil = 0
end

-- The enemy `m` wants most within its reach, the nearest of that rank, and its rank; nil when there is none. A hero
-- it was called on may be as far as it would chase.
local function chooseTarget(m: Minion, combatants: { Model }, now: number): (Target?, number)
	local best: Target? = nil
	local bestRank, bestGap = math.huge, math.huge
	local function consider(t: Target)
		local rank = rankOf(m, t, now)
		if rank > bestRank then
			return
		end
		local reach = if rank == 1 then SETTINGS.Leash else SETTINGS.Acquire
		local gap = (positionOf(t) - m.position).Magnitude - radiusOf(t) - SETTINGS.Radius
		if gap < reach and (rank < bestRank or gap < bestGap) and alive(t) then
			best, bestRank, bestGap = t, rank, gap
		end
	end
	for _, other in minions do
		if other.team ~= m.team and not other.dead then
			consider(other)
		end
	end
	for _, model in combatants do
		if model:GetAttribute("Team") ~= m.team then
			consider(model)
		end
	end
	return best, bestRank
end

local function blocked(from: Vector3, direction: Vector3, distance: number): boolean
	local origin = from + Vector3.new(0, SETTINGS.Height / 2, 0)
	return Workspace:Spherecast(origin, SETTINGS.Radius * 0.9, direction * (distance + 0.5), obstacles) ~= nil
end

-- Moves `m` up to `distance` towards `goal`, turning aside when the way ahead is blocked.
local function walk(m: Minion, goal: Vector3, distance: number)
	local offset = flat(goal - m.position)
	if offset.Magnitude < 0.05 then
		return
	end
	local step = math.min(distance, offset.Magnitude)
	local direction = offset.Unit
	for _, turn in DETOURS do
		local d = CFrame.Angles(0, math.rad(turn), 0):VectorToWorldSpace(direction)
		if not blocked(m.position, d, step) then
			m.position += d * step
			m.facing = d
			return
		end
	end
end

-- Pushes minions apart so a wave does not stand in one spot and no two minions stand in each other.
local function spread()
	local gap = SETTINGS.Radius * 1.9
	for i, a in minions do
		for j = i + 1, #minions do
			local b = minions[j]
			local offset = flat(b.position - a.position)
			local distance = offset.Magnitude
			if distance < gap and distance > 0.01 then
				local push = offset.Unit * (gap - distance) * 0.25
				a.position -= push
				b.position += push
			end
		end
	end
end

-- The index of the waypoint ahead that `m` is closest to, to pick its path up again after a chase.
local function rejoin(m: Minion): number
	local best, bestDistance = m.waypoint, math.huge
	for i = m.waypoint, #m.path do
		local distance = (m.path[i] - m.position).Magnitude
		if distance < bestDistance then
			best, bestDistance = i, distance
		end
	end
	return best
end

local findPath: (from: Vector3, to: Vector3, quiet: boolean?) -> { Vector3 }

-- The enemy nearest to `m` anywhere in the arena (minion, hero or Master); nil when none is left.
local function quarryOf(m: Minion, combatants: { Model }): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for _, other in minions do
		if other.team ~= m.team and not other.dead then
			local distance = (other.position - m.position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	for _, model in combatants do
		if model:GetAttribute("Team") ~= m.team and alive(model) then
			local distance = (positionOf(model) - m.position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- Walks `m` towards the nearest enemy left, round everything in the way; with none left, back to its own spot.
local function hunt(m: Minion, combatants: { Model }, step: number, now: number)
	local quarry = quarryOf(m, combatants)
	if not quarry then
		m.hunt = nil
		walk(m, m.spot, step)
		return
	end
	local h = m.hunt
	if not h or (not h.finding and (h.quarry ~= quarry or now - h.at >= HUNT_REFRESH)) then
		local fresh: Hunt = {
			quarry = quarry,
			path = if h and h.quarry == quarry then h.path else {},
			waypoint = if h and h.quarry == quarry then h.waypoint else 1,
			at = now,
			finding = true,
		}
		m.hunt = fresh
		local from, to = m.position, positionOf(quarry)
		task.spawn(function()
			local path = findPath(from, to, true)
			fresh.path = path
			fresh.waypoint = math.min(2, #path)
			fresh.finding = false
		end)
		h = fresh
	end
	local route = h :: Hunt
	local goal = route.path[route.waypoint]
	if goal and (goal - m.position).Magnitude < 2.5 then
		route.waypoint += 1
		goal = route.path[route.waypoint]
	end
	walk(m, goal or positionOf(quarry), step)
end

local function attack(m: Minion, t: Target, gap: number, now: number)
	m.nextAttack = now + m.stats.Interval
	local targetInstance: Instance = if isMinion(t) then (t :: Minion).root else t :: Model
	if m.kind == "Spitter" then
		local travel = math.max(0.1, gap / (m.stats.SpitSpeed or 40))
		attackEvent:FireAllClients(m.root, targetInstance, travel)
		task.delay(travel, function()
			if alive(t) then
				hurt(t, m.stats.Damage)
			end
		end)
	else
		attackEvent:FireAllClients(m.root, targetInstance, BITE_HIT)
		task.delay(BITE_HIT, function()
			if not m.dead and alive(t) then
				hurt(t, m.stats.Damage)
			end
		end)
	end
end

local function think(m: Minion, combatants: { Model }, now: number)
	local target = m.target
	if target and not alive(target) then
		target = nil
	end
	if target and m.chaseFrom and (m.position - m.chaseFrom).Magnitude > SETTINGS.Leash then
		target = nil
		m.calmUntil = now + 2
	end
	if now >= m.calmUntil then
		local best, rank = chooseTarget(m, combatants, now)
		-- Of the heroes it was called on, it always goes for the nearest.
		local current = if target then rankOf(m, target, now) else math.huge
		if best and (rank < current or (rank == 1 and current == 1)) then
			target = best
			if not m.chaseFrom then
				m.chaseFrom = m.position
			end
		end
	end
	if m.target and not target then
		m.chaseFrom = nil
		if not m.arrived then
			m.waypoint = rejoin(m)
		end
	end
	m.target = target

	local step = m.stats.Speed * TICK
	if target then
		local offset = positionOf(target) - m.position
		local gap = offset.Magnitude - radiusOf(target) - SETTINGS.Radius
		if gap <= m.stats.Range then
			if offset.Magnitude > 0.01 then
				m.facing = flat(offset).Unit
			end
			if now >= m.nextAttack then
				attack(m, target, math.max(0, gap), now)
			end
		else
			walk(m, positionOf(target), step)
		end
		return
	end
	if m.arrived then
		hunt(m, combatants, step, now)
		return
	end
	local goal = m.path[m.waypoint]
	if goal then
		if (goal - m.position).Magnitude < 2.5 and m.waypoint < #m.path then
			m.waypoint += 1
			goal = m.path[m.waypoint]
		end
		if m.waypoint >= #m.path then
			goal = m.spot
			if (goal - m.position).Magnitude < 2.5 then
				m.arrived = true
			end
		end
		walk(m, goal, step)
	end
end

local function place(m: Minion)
	local centre = m.position + Vector3.new(0, SETTINGS.Height / 2, 0)
	m.root.CFrame = CFrame.lookAt(centre, centre + m.facing)
end

local function tick(now: number)
	local combatants = {}
	for _, tagged in CollectionService:GetTagged("Combatant") do
		if tagged:IsA("Model") then
			table.insert(combatants, tagged)
		end
	end
	for _, m in table.clone(minions) do
		if not m.dead then
			think(m, combatants, now)
		end
	end
	spread()
	for _, m in minions do
		place(m)
	end
end

local function count(team: string): number
	local n = 0
	for _, m in minions do
		if m.team == team then
			n += 1
		end
	end
	return n
end

local function spawn(team: string, kind: string, door: CFrame)
	if count(team) >= SETTINGS.MaxPerTeam then
		return
	end
	local stats: Stats = SETTINGS.Kinds[kind]
	local path = paths[door]
	local angle = math.random() * 2 * math.pi
	local spot = path[#path] + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.sqrt(math.random()) * END_SPREAD
	local root = Instance.new("Part")
	root.Name = "Minion"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.CastShadow = false
	root.Transparency = 1
	root.Size = Vector3.new(SETTINGS.Radius * 2, SETTINGS.Height, SETTINGS.Radius * 2)
	root:SetAttribute("Team", team)
	root:SetAttribute("Kind", kind)
	root:SetAttribute("Health", stats.Health)
	root:SetAttribute("MaxHealth", stats.Health)
	root:SetAttribute("Dead", false)
	local m: Minion = {
		team = team,
		kind = kind,
		stats = stats,
		root = root,
		position = flat(door.Position),
		facing = door.LookVector,
		health = stats.Health,
		path = path,
		waypoint = 1,
		spot = spot,
		arrived = false,
		hunt = nil,
		target = nil,
		chaseFrom = nil,
		calmUntil = 0,
		callers = {},
		nextAttack = 0,
		lastHitBy = nil,
		dead = false,
	}
	place(m)
	CollectionService:AddTag(root, "Minion")
	root.Parent = folder
	byRoot[root] = m
	table.insert(minions, m)
end

-- One wave from every doorway, the minions leaving one after another.
local function wave(doors: { [string]: { CFrame } })
	for _, kind in SETTINGS.Wave do
		for team, list in doors do
			for _, door in list do
				spawn(team, kind, door)
			end
		end
		task.wait(0.9)
	end
end

-- The path from `from` to `to` round everything in the way, flat on the sand; a straight line if none is found (with
-- a warning unless `quiet`).
function findPath(from: Vector3, to: Vector3, quiet: boolean?): { Vector3 }
	local path = PathfindingService:CreatePath({
		AgentRadius = SETTINGS.Radius + 0.7,
		AgentHeight = SETTINGS.Height,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 8,
	})
	local ok, problem = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local points = {}
		for _, waypoint in path:GetWaypoints() do
			table.insert(points, flat(waypoint.Position))
		end
		return points
	end
	if not quiet then
		warn("[MinionService] no path from", from, "to", to, problem or path.Status)
	end
	return { flat(from), flat(to) }
end

-- Damage to the minion whose root is `root`, from `player` (the bounty goes to the player who lands the last hit); the
-- minion turns on the player's hero.
function MinionService.damage(root: BasePart, amount: number, player: Player?)
	local m = byRoot[root]
	if not m then
		return
	end
	hurtMinion(m, amount, player)
	local attacker = player and player.Character
	if attacker and not m.dead and attacker:GetAttribute("Team") ~= m.team then
		call(m, attacker, os.clock())
	end
end

-- Tells the minions that the hero `attacker` hit `victim` (a hero or a Master): `victim`'s minions near it turn on
-- `attacker`.
function MinionService.heroAttacked(attacker: Model, victim: Model)
	local team = victim:GetAttribute("Team")
	if attacker:GetAttribute("Team") == team then
		return
	end
	local now = os.clock()
	local at = positionOf(victim)
	local reach = SETTINGS.CallForHelp + radiusOf(victim)
	for _, m in minions do
		if m.team == team and not m.dead and (m.position - at).Magnitude <= reach then
			call(m, attacker, now)
		end
	end
end

export type Layout = {
	minionDoors: { [string]: { CFrame } },
	daisFront: { [string]: Vector3 },
	map: Folder,
}

function MinionService.start(layout: Layout)
	local net = ReplicatedStorage:FindFirstChild("Net") or Instance.new("Folder")
	net.Name = "Net"
	net.Parent = ReplicatedStorage
	attackEvent = Instance.new("RemoteEvent")
	attackEvent.Name = "MinionAttack"
	attackEvent.Parent = net

	folder = Instance.new("Folder")
	folder.Name = "Minions"
	folder.Parent = Workspace

	-- In Studio, tests reach the minions through ServerStorage.Dev: DamageMinion (root, amount, player) and
	-- HeroAttacked (attacker, victim).
	if RunService:IsStudio() then
		local dev = ServerStorage:FindFirstChild("Dev") or Instance.new("Folder")
		dev.Name = "Dev"
		dev.Parent = ServerStorage
		for name, hook in { DamageMinion = MinionService.damage, HeroAttacked = MinionService.heroAttacked } do
			local bindable = Instance.new("BindableFunction")
			bindable.Name = name
			bindable.OnInvoke = hook
			bindable.Parent = dev
		end
	end

	local blocking = {}
	for _, name in { "ArenaWall", "Centre", "Cover", "BlueBase", "RedBase" } do
		local f = layout.map:FindFirstChild(name)
		if f then
			table.insert(blocking, f)
		end
	end
	obstacles.FilterDescendantsInstances = blocking

	-- Each doorway's minions march down the lane on their side of the arena, past the gate between the cover arc and
	-- the pillar, where they meet the other team's wave, and on to the enemy dais' front.
	for team, list in layout.minionDoors do
		local enemy = if team == "Blue" then "Red" else "Blue"
		local front = layout.daisFront[enemy]
		for _, door in list do
			local side = if door.Position.X >= 0 then 1 else -1
			local lane = Vector3.new(side * SETTINGS.LaneRadius, 0, 0)
			local goal = front - front.Unit * 6 + Vector3.new(side * 10, 0, 0)
			local path = findPath(door.Position, lane)
			table.remove(path)
			local rest = findPath(lane, goal)
			table.move(rest, 1, #rest, #path + 1, path)
			paths[door] = path
			print(
				string.format(
					"[MinionService] %s doorway at %s: path of %d points",
					team,
					tostring(door.Position),
					#paths[door]
				)
			)
		end
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= TICK then
			elapsed = math.min(elapsed - TICK, TICK)
			tick(os.clock())
		end
	end)

	task.spawn(function()
		task.wait(SETTINGS.FirstWave)
		while true do
			task.spawn(wave, layout.minionDoors)
			task.wait(SETTINGS.WaveInterval)
		end
	end)
end

return MinionService
