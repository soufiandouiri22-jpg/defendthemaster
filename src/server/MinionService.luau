-- The team minions (Config.Minions). Every wave leaves a team's two doorways, some down the doorway's own side and some
-- through the middle (Config.Minions.Middle), and marches along a path worked out once at the start to the other team's
-- dais, turning on the enemies that come close: everything tagged "Combatant"
-- (heroes, and the Masters with the "Master" attribute) with another "Team" attribute, and the other team's minions
-- (owner, 2026-11-25; before, the two teams' waves passed by one another). They go first for an enemy hero who just
-- attacked them, or one of their heroes or their Master nearby (MinionService.heroAttacked), then for any enemy hero
-- near, then an enemy minion, then the enemy Master; the nearest of those, and they turn from what they fight as soon
-- as something they want more comes near. A minion that has
-- come to the end of its path with nobody in reach hunts: it walks to the nearest enemy hero or Master left anywhere in
-- the arena, and with none left stands on its own spot there. A vanished hero ("Hidden", a kit of Kind "Vanish") is
-- not there for them: they let go of him and pick another. Only the last hit by a player earns the bounty.
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
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Actors = require(script.Parent.Actors)
local Damage = require(script.Parent.Damage)
local Economy = require(script.Parent.Economy)
local MatchService = require(script.Parent.MatchService)
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
-- A minion walks straight on while nothing of the map stands in the line to where it goes, else along a path, found
-- again every REPATH seconds or once where it goes moved MOVED studs (as the Masters do). One that gains less than
-- STUCK_STEP studs in STUCK_TIME seconds of walking takes a path for ROUND seconds even where the line looks clear.
local REPATH, MOVED = 1, 4
local STUCK_TIME, STUCK_STEP, ROUND = 1, 1, 3
-- At the end of its path each minion stands on its own spot within this many studs, so a wave does not stack up.
local END_SPREAD = 6
-- The seconds between a wave's minions leaving one after another.
local WAVE_GAP = 0.9
type Stats = {
	Health: number,
	Damage: number,
	Interval: number,
	Range: number,
	Speed: number,
	Bounty: number,
	SpitSpeed: number?,
	Magic: boolean?,
}

-- A minion's way round what stands between it and `goal`, found at `at`; while a new one is found, the old one.
type Detour = {
	goal: Vector3,
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
	-- The lane it belongs to, for its most alive (Config.Minions.MaxWaves).
	lane: Lane,
	waypoint: number,
	-- Its own spot round the end of its path, and whether it got there (from then on it hunts).
	spot: Vector3,
	arrived: boolean,
	detour: Detour?,
	-- When it last walked, where it stood at `checkAt` while walking, and until when it takes a path anyway.
	walkedAt: number,
	checkFrom: Vector3,
	checkAt: number,
	roundUntil: number,
	target: Target?,
	-- Where it left its path for the current chase, and until when it ignores enemies after giving one up.
	chaseFrom: Vector3?,
	calmUntil: number,
	-- The enemy heroes who attacked it, one of its heroes or its Master, and until when each comes first.
	callers: { [Model]: number },
	nextAttack: number,
	-- The player or bot (Actors) who hit it last.
	lastHitBy: Instance?,
	dead: boolean,
	-- Thrown away by a blow (MinionService.knock) and how high it is above the ground meanwhile.
	knock: { started: number, from: Vector3, to: Vector3, height: number, length: number }?,
	lift: number,
}

-- An enemy: a tagged Combatant of the other team (a Model with a Humanoid, or with a "Health" attribute), or the root
-- of one of the other team's minions.
type Target = PVInstance

local minions: { Minion } = {}
local byRoot: { [BasePart]: Minion } = {}
local folder: Folder
local attackEvent: RemoteEvent
local obstacles = RaycastParams.new()
obstacles.FilterType = Enum.RaycastFilterType.Include
-- A doorway's way to the enemy dais, and the minions of a wave that take it, in marching order. Both teams' minions
-- on one stretch of the arena share its `index`, the root's "Lane" attribute: 1 down the +X side, 2 through the
-- middle on the +X side, 3 through the middle on the -X side, 4 down the -X side (BotService's lanes).
type Lane = { path: { Vector3 }, wave: { string }, index: number }
-- Each doorway's two lanes, down its own side and through the middle, by the door's CFrame.
local lanes: { [CFrame]: { Lane } } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function positionOf(t: Target): Vector3
	return flat(t:GetPivot().Position)
end

local function radiusOf(t: Target): number
	if t:IsA("BasePart") then
		return SETTINGS.Radius
	end
	return t:GetAttribute("Radius") or 1.5
end

local function alive(t: Target): boolean
	if not t.Parent or t:GetAttribute("Dead") then
		return false
	end
	local humanoid = t:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health > 0
	end
	return (t:GetAttribute("Health") or 0) > 0
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

local function hurtMinion(m: Minion, amount: number, player: Instance?)
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

-- `amount` of a minion's damage on `model`, physical or `magic` (on a hero, his Armor or Resist takes it down).
local function hurt(model: Target, amount: number, magic: boolean)
	local other = if model:IsA("BasePart") then byRoot[model] else nil
	if other then
		hurtMinion(other, amount, nil)
		return
	end
	if model:GetAttribute("Master") then
		amount *= SETTINGS.VsMaster
	elseif model:GetAttribute("Hero") then
		amount = Damage.mitigated(model, amount, magic, nil)
		ProgressService.hurtByMinion(model)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(amount)
	else
		model:SetAttribute("Health", math.max(0, (model:GetAttribute("Health") or 0) - amount))
	end
end

-- How much `m` wants `t`, most first: 1 a hero who attacked it, one of its heroes or its Master, 2 any other enemy
-- hero, 3 an enemy minion, 4 the enemy Master.
local function rankOf(m: Minion, t: Target, now: number): number
	local expires = m.callers[t :: Model]
	if expires and now < expires then
		return 1
	end
	if t:IsA("BasePart") then
		return 3
	end
	return if t:GetAttribute("Master") then 4 else 2
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
local function chooseTarget(m: Minion, combatants: { Target }, now: number): (Target?, number)
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

-- Moves `m` up to `distance` towards `goal`, turning aside when the way ahead is blocked, or straight on when
-- `squeeze` (to get out of what it got stuck in). Whether it moved.
local function walk(m: Minion, goal: Vector3, distance: number, squeeze: boolean?): boolean
	local offset = flat(goal - m.position)
	if offset.Magnitude < 0.05 then
		return true
	end
	local step = math.min(distance, offset.Magnitude)
	local direction = offset.Unit
	for _, turn in DETOURS do
		local d = CFrame.Angles(0, math.rad(turn), 0):VectorToWorldSpace(direction)
		if not blocked(m.position, d, step) then
			m.position += d * step
			m.facing = d
			return true
		end
	end
	if squeeze then
		m.position += direction * step
		m.facing = direction
		return true
	end
	return false
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

-- Moves `m` up to `distance` towards `goal`: straight on, or along a path round what stands in the way.
local function go(m: Minion, goal: Vector3, distance: number, now: number)
	if distance <= 0 then
		return
	end
	if now - m.walkedAt > TICK * 1.5 then
		m.checkFrom, m.checkAt = m.position, now
	elseif now - m.checkAt >= STUCK_TIME then
		if (m.position - m.checkFrom).Magnitude < STUCK_STEP then
			m.roundUntil = now + ROUND
		end
		m.checkFrom, m.checkAt = m.position, now
	end
	m.walkedAt = now

	local line = flat(goal - m.position)
	if now >= m.roundUntil and (line.Magnitude < 0.5 or not blocked(m.position, line.Unit, line.Magnitude - 0.5)) then
		m.detour = nil
		walk(m, goal, distance)
		return
	end
	local d = m.detour
	if not d or (not d.finding and (now - d.at >= REPATH or (goal - d.goal).Magnitude > MOVED)) then
		local fresh: Detour = {
			goal = goal,
			path = if d then d.path else {},
			waypoint = if d then d.waypoint else 1,
			at = now,
			finding = true,
		}
		m.detour = fresh
		local from = m.position
		task.spawn(function()
			local path = findPath(from, goal, true)
			fresh.path = path
			fresh.waypoint = math.min(2, #path)
			fresh.finding = false
		end)
		d = fresh
	end
	local route = d :: Detour
	local point = route.path[route.waypoint]
	while point and (point - m.position).Magnitude < 2.5 and route.waypoint < #route.path do
		route.waypoint += 1
		point = route.path[route.waypoint]
	end
	-- Blocked every way even along a path, it stands in the map (pushed there by others or a hero's charge).
	walk(m, point or goal, distance, now < m.roundUntil)
end

-- The enemy hero or Master nearest to `m` anywhere in the arena; nil when none is left.
local function quarryOf(m: Minion, combatants: { Target }): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for _, model in combatants do
		if model:IsA("Model") and model:GetAttribute("Team") ~= m.team and alive(model) then
			local distance = (positionOf(model) - m.position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- Walks `m` towards the nearest enemy left, round everything in the way; with none left, back to its own spot.
local function hunt(m: Minion, combatants: { Target }, step: number, now: number)
	local quarry = quarryOf(m, combatants)
	go(m, if quarry then positionOf(quarry) else m.spot, step, now)
end

local function attack(m: Minion, t: Target, gap: number, now: number)
	m.nextAttack = now + m.stats.Interval
	if m.kind == "Spitter" then
		local travel = math.max(0.1, gap / (m.stats.SpitSpeed or 40))
		attackEvent:FireAllClients(m.root, t, travel)
		task.delay(travel, function()
			if alive(t) then
				hurt(t, m.stats.Damage, m.stats.Magic == true)
			end
		end)
	else
		attackEvent:FireAllClients(m.root, t, BITE_HIT)
		task.delay(BITE_HIT, function()
			if not m.dead and alive(t) then
				hurt(t, m.stats.Damage, m.stats.Magic == true)
			end
		end)
	end
end

local function think(m: Minion, combatants: { Target }, now: number)
	local target = m.target
	if target and (not alive(target) or target:GetAttribute("Hidden")) then
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

	-- In Studio the Workspace attribute "TestMinionsStill" keeps every minion where it stands (it still turns and
	-- attacks), for tests that measure from them (Tools/Tests/reach_test.luau).
	local still = RunService:IsStudio() and Workspace:GetAttribute("TestMinionsStill") == true
	local step = if still then 0 else m.stats.Speed * TICK
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
			go(m, positionOf(target), step, now)
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
		go(m, goal, step, now)
	end
end

local function place(m: Minion)
	local centre = m.position + Vector3.new(0, SETTINGS.Height / 2 + m.lift, 0)
	m.root.CFrame = CFrame.lookAt(centre, centre + m.facing)
end

-- A knocked minion flies over the ground, fast and slowing, in its arc; down, it takes up its way again. Whether it
-- is flying still.
local function fly(m: Minion, now: number): boolean
	local k = m.knock
	if not k then
		return false
	end
	local s = math.clamp((now - k.started) / k.length, 0, 1)
	m.position = k.from:Lerp(k.to, 1 - (1 - s) ^ 2)
	m.lift = k.height * 4 * s * (1 - s)
	if s >= 1 then
		m.knock, m.lift = nil, 0
		if not m.arrived and not m.target then
			m.waypoint = rejoin(m)
		end
	end
	return true
end

-- A minion held against a charging hero (HeroKit.heldAt) goes along before him, facing him. Whether it is held.
local function held(m: Minion): boolean
	local at, look = HeroKit.heldAt(m.root, m.position.Y)
	if not at or not look then
		return false
	end
	m.knock, m.lift = nil, 0
	m.position, m.facing = at, -look
	return true
end

local function tick(now: number)
	local combatants: { Target } = {}
	for _, tagged in CollectionService:GetTagged("Combatant") do
		if tagged:IsA("Model") and not tagged:GetAttribute("Hidden") then
			table.insert(combatants, tagged)
		end
	end
	for _, m in minions do
		if not m.dead then
			table.insert(combatants, m.root)
		end
	end
	for _, m in table.clone(minions) do
		if not m.dead and not held(m) and not fly(m, now) then
			think(m, combatants, now)
		end
	end
	spread()
	for _, m in minions do
		place(m)
	end
end

-- How many minions of `lane` are still alive.
local function count(lane: Lane): number
	local n = 0
	for _, m in minions do
		if m.lane == lane then
			n += 1
		end
	end
	return n
end

-- A `team` minion of `kind` at `door` (where it stands and the way it faces) on `lane`; nil when the lane has its most
-- alive already.
local function spawn(team: string, kind: string, door: CFrame, lane: Lane): BasePart?
	if count(lane) >= SETTINGS.MaxWaves * #lane.wave then
		return nil
	end
	local path = lane.path
	local stats: Stats = SETTINGS.Kinds[kind]
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
	root:SetAttribute("Lane", lane.index)
	local m: Minion = {
		team = team,
		kind = kind,
		stats = stats,
		root = root,
		position = flat(door.Position),
		facing = door.LookVector,
		health = stats.Health,
		path = path,
		lane = lane,
		waypoint = 1,
		spot = spot,
		arrived = false,
		detour = nil,
		walkedAt = -math.huge,
		checkFrom = flat(door.Position),
		checkAt = 0,
		roundUntil = 0,
		target = nil,
		chaseFrom = nil,
		calmUntil = 0,
		callers = {},
		nextAttack = 0,
		lastHitBy = nil,
		dead = false,
		lift = 0,
	}
	place(m)
	CollectionService:AddTag(root, "Minion")
	root.Parent = folder
	byRoot[root] = m
	table.insert(minions, m)
	return root
end

-- One wave from every doorway, the minions leaving one after another: first those down its own side, then those
-- through the middle.
type Leaving = { team: string, kind: string, door: CFrame, lane: Lane }

local function wave(doors: { [string]: { CFrame } })
	-- Per moment, every doorway's minion leaving then.
	local steps: { { Leaving } } = {}
	for team, list in doors do
		for _, door in list do
			local i = 0
			for _, lane in lanes[door] or {} do
				for _, kind in lane.wave do
					i += 1
					steps[i] = steps[i] or {}
					table.insert(steps[i], { team = team, kind = kind, door = door, lane = lane })
				end
			end
		end
	end
	for _, step in steps do
		for _, leaving in step do
			spawn(leaving.team, leaving.kind, leaving.door, leaving.lane)
		end
		task.wait(WAVE_GAP)
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
function MinionService.damage(root: BasePart, amount: number, player: Instance?)
	local m = byRoot[root]
	if not m then
		return
	end
	hurtMinion(m, amount, player)
	local attacker = player and Actors.character(player)
	if attacker and not m.dead and attacker:GetAttribute("Team") ~= m.team then
		call(m, attacker, os.clock())
	end
end

-- Throws the minion whose root is `root` to `to` (over the ground), in an arc `height` studs high, in `length` seconds
-- (a kit's Knockback, CombatService).
function MinionService.knock(root: BasePart, to: Vector3, height: number, length: number)
	local m = byRoot[root]
	if not m or m.dead then
		return
	end
	local throw = flat(to - m.position)
	if throw.Magnitude > 0.05 then
		local origin = m.position + Vector3.new(0, SETTINGS.Height / 2, 0)
		local hit = Workspace:Spherecast(origin, SETTINGS.Radius * 0.9, throw, obstacles)
		if hit then
			throw = throw.Unit * math.max(0, hit.Distance - 0.2)
		end
	end
	m.knock = {
		started = os.clock(),
		from = m.position,
		to = m.position + throw,
		height = height,
		length = length,
	}
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

-- A `team` minion of `kind` at `at`, whose path ends where it stands (Studio's tests and test ground); its root.
function MinionService.spawnAt(team: string, kind: string, at: Vector3): BasePart?
	local door = CFrame.new(at)
	return spawn(team, kind, door, { path = { flat(at) }, wave = SETTINGS.Wave, index = 0 })
end

-- The path through `points`, one after another.
local function through(points: { Vector3 }): { Vector3 }
	local path = {}
	for i = 1, #points - 1 do
		local piece = findPath(points[i], points[i + 1])
		if i < #points - 1 then
			table.remove(piece)
		end
		table.move(piece, 1, #piece, #path + 1, path)
	end
	return path
end

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

	-- In Studio, tests reach the minions through ServerStorage.Dev: DamageMinion (root, amount, player), HeroAttacked
	-- (attacker, victim) and SpawnMinion (team, kind, position), a minion whose path ends where it stands.
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
		local spawnMinion = Instance.new("BindableFunction")
		spawnMinion.Name = "SpawnMinion"
		spawnMinion.OnInvoke = MinionService.spawnAt
		spawnMinion.Parent = dev
	end

	local blocking = {}
	for _, name in { "ArenaWall", "Centre", "Cover", "BlueBase", "RedBase" } do
		local f = layout.map:FindFirstChild(name)
		if f then
			table.insert(blocking, f)
		end
	end
	obstacles.FilterDescendantsInstances = blocking
	-- Each doorway's side minions march down the lane on its side of the arena, past the gate between the cover arc
	-- and the pillar, where they meet the other team's wave; its middle minions turn in before their own dais, pass the
	-- plateau on the doorway's side and meet the other team's there. Both go on to the enemy dais' front on that side.
	for team, list in layout.minionDoors do
		local enemy = if team == "Blue" then "Red" else "Blue"
		local own = flat(layout.daisFront[team])
		local front = layout.daisFront[enemy]
		for _, door in list do
			local side = if door.Position.X >= 0 then 1 else -1
			local goal = front - front.Unit * 6 + Vector3.new(side * 10, 0, 0)
			local inside = own - own.Unit * SETTINGS.Middle.Ahead + Vector3.new(side * SETTINGS.Middle.Apart, 0, 0)
			lanes[door] = {
				{
					path = through({ door.Position, Vector3.new(side * SETTINGS.LaneRadius, 0, 0), goal }),
					wave = SETTINGS.Wave,
					index = if side > 0 then 1 else 4,
				},
				{
					path = through({ door.Position, inside, Vector3.new(side * SETTINGS.Middle.Around, 0, 0), goal }),
					wave = SETTINGS.Middle.Wave,
					index = if side > 0 then 2 else 3,
				},
			}
			print(
				string.format(
					"[MinionService] %s doorway at %s: side path of %d points, middle path of %d",
					team,
					tostring(door.Position),
					#lanes[door][1].path,
					#lanes[door][2].path
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
		MatchService.awaitFight()
		task.wait(SETTINGS.FirstWave)
		while true do
			task.spawn(wave, layout.minionDoors)
			task.wait(SETTINGS.WaveInterval)
		end
	end)
end

return MinionService
