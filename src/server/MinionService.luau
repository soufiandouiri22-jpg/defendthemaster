-- The team minions (Config.Minions). Every wave leaves a team's two doorways and marches along a path worked out once
-- at the start to the other team's dais, turning on the enemies that come close: the other team's minions and
-- everything tagged "Combatant" (heroes, and the Masters with the "Master" attribute) with another "Team" attribute.
-- They pick in this order: an enemy hero who just attacked one of their heroes nearby (MinionService.heroAttacked), the
-- enemy minions, the enemy heroes, the enemy Master; the nearest first within each. Only the last hit by a player earns
-- the bounty.
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

type Stats = {
	Health: number,
	Damage: number,
	Interval: number,
	Range: number,
	Speed: number,
	Bounty: number,
	SpitSpeed: number?,
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
	target: Target?,
	-- Where it left its path for the current chase, and until when it ignores enemies after giving one up.
	chaseFrom: Vector3?,
	calmUntil: number,
	-- The enemy hero who attacked one of its heroes, and until when that hero comes first.
	called: Model?,
	calledUntil: number,
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

-- How much `m` wants `t`, 1 first: the hero it was called on, minions, heroes, the Master.
local function rankOf(m: Minion, t: Target, now: number): number
	if isMinion(t) then
		return 2
	end
	if t == m.called and now < m.calledUntil then
		return 1
	end
	if (t :: Model):GetAttribute("Master") then
		return 4
	end
	return 3
end

-- The enemy `m` wants most within its reach, the nearest of that rank, and its rank; nil when there is none. The hero
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
		if best and (not target or rank < rankOf(m, target, now)) then
			target = best
			if not m.chaseFrom then
				m.chaseFrom = m.position
			end
		end
	end
	if m.target and not target then
		m.chaseFrom = nil
		m.waypoint = rejoin(m)
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
	local goal = m.path[m.waypoint]
	if goal then
		if (goal - m.position).Magnitude < 2.5 and m.waypoint < #m.path then
			m.waypoint += 1
			goal = m.path[m.waypoint]
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
		path = paths[door],
		waypoint = 1,
		target = nil,
		chaseFrom = nil,
		calmUntil = 0,
		called = nil,
		calledUntil = 0,
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

-- The path from `from` to `to` round everything in the way, flat on the sand; a straight line if none is found.
local function findPath(from: Vector3, to: Vector3): { Vector3 }
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
	warn("[MinionService] no path from", from, "to", to, problem or path.Status)
	return { flat(from), flat(to) }
end

-- Damage to the minion whose root is `root`, from `player` (the bounty goes to the player who lands the last hit).
function MinionService.damage(root: BasePart, amount: number, player: Player?)
	local m = byRoot[root]
	if m then
		hurtMinion(m, amount, player)
	end
end

-- Tells the minions that the hero `attacker` hit the hero `victim`: `victim`'s minions near it turn on `attacker`.
function MinionService.heroAttacked(attacker: Model, victim: Model)
	local team = victim:GetAttribute("Team")
	if attacker:GetAttribute("Team") == team then
		return
	end
	local now = os.clock()
	local at = positionOf(victim)
	for _, m in minions do
		if m.team == team and not m.dead and (m.position - at).Magnitude <= SETTINGS.CallForHelp then
			m.called = attacker
			m.calledUntil = now + SETTINGS.CallTime
			m.calmUntil = 0
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
