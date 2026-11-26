-- The beast (Config.Beast): once in a match, `At` seconds into the fight, it comes out of the ground at a spot chosen
-- only then, on the line between the two halves and clear of everything built there. The server keeps it as the model
-- Workspace.Beast, one invisible anchored part `Radius` studs round its coil's middle, whose attributes the clients
-- show it by (BeastView): "Hole" (where the ground opens), "Land" (where its pivot lands), "Burst" (the server time
-- the ground bursts, `Rumble` seconds after it came), "Centre" (its coil's middle on the ground), "Look" (the flat way
-- its head faces), "Moving" (while it slithers), "Bite" (the server time its last bite began), "Health" and "MaxHealth", and "Phase" ("Rumble"
-- until the burst, "Flying" until it lands, "Out" while it roars, "Fight", then "Dead" from the server time "DiedAt").
-- Its landing throws every hero and minion within `Slam` studs `Throw` studs away from it. Landed, it carries the
-- "Combatant" tag, the "Beast" attribute and the team "Neutral", so every hero's attacks strike it (CombatService),
-- and fights there as League's Rift Herald; the minions leave it be (MinionService).
-- Slain, it leaves its key (Config.Beast.Key), whose state is on Workspace for the clients (KeyView): "SerpentKey"
-- ("Dropped" or "Carried"), "SerpentKeySpot" (where it floats while dropped), "SerpentKeyFor" (the only team that may
-- take it while dropped, none for anyone), "SerpentKeyTeam" (its carrier's team) and "SerpentKeyEnds" (the server time
-- it is gone, once taken); its carrier's player or bot and his hero have the attribute "SerpentKey". The carrier lets
-- the beast loose (Net.SerpentRelease, BeastService.release): it comes out beside him for his team ("Team", and
-- "Released"), with its own "Rumble" and "Flight", charges the enemy Master and headbutts him ("Ram", the server time
-- the headbutt began).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Actors = require(script.Parent.Actors)
local CombatService = require(script.Parent.CombatService)
local Damage = require(script.Parent.Damage)
local Remote = require(script.Parent.Remote)
local ProgressService = require(script.Parent.ProgressService)
local TestGround = require(script.Parent.TestGround)

local BeastService = {}

local SETTINGS = Config.Beast
local BITE = SETTINGS.Bite
-- How far round the hole and the landing nothing built may stand, and how often a spot is tried.
local CLEAR_HOLE, CLEAR_LAND, TRIES = SETTINGS.Hole + 4, 16, 60
-- How high and how long the landing throws.
local THROW_HEIGHT, THROW_TIME = 6, 0.55
-- The hit box's height.
local HEIGHT = 20
-- It bites only once it faces its target within this angle (radians).
local FACING = math.rad(35)
-- It sends a new "Look" once it turned this far (radians) from the last one sent, and a new "Centre" once it moved this
-- many studs.
local LOOK_STEP, CENTRE_STEP = math.rad(1.5), 0.6
-- It slithers only while it faces where it goes within this angle (radians), and circles towards the point this far
-- (radians) ahead of it round its circle.
local CRAWL_ANGLE, ROAM_AHEAD = math.rad(70), 0.6
local MIDDLE = SETTINGS.Middle
-- What of the map stands higher than this above the floor stops it; on its circle it turns back at most this often
-- (seconds).
local STANDS, TURN_BACK = 3, 1.5
-- The ways (radians off its look) it tries, hunting, when something stands right before it.
local SWERVES = { math.rad(45), math.rad(-45), math.rad(85), math.rad(-85) }
-- A hero's root stands this high over his feet.
local ROOT_HEIGHT = 3

type Beast = {
	model: Model,
	body: BasePart,
	centre: Vector3,
	map: Instance,
	-- The middle of the circle it slithers round while no one fights it, and when it last turned back on it.
	home: Vector3,
	turnedAt: number,
	hunting: boolean,
	sentCentre: Vector3,
	moving: boolean,
	-- Till when its bite holds it still.
	biting: number,
	-- Its coil's middle from its pivot, in its pivot's frame (BeastView places its model by the same).
	offset: Vector3,
	front: number,
	look: Vector3,
	sent: Vector3,
	struck: { [Model]: number },
	lastStriker: Model?,
	calmSince: number,
	nextBite: number,
	-- Let loose by a key's carrier: for his team, at the enemy Master; and whether its headbutt came.
	released: boolean,
	master: Model?,
	rammed: boolean,
}

type Hero = { actor: Instance, character: Model, root: BasePart, humanoid: Humanoid, team: string }

-- Who lets a beast loose: his team, where he stands and the Master it goes for.
type Release = { team: string, from: Vector3, master: Model }

local rng = Random.new()
local hitEvent: RemoteEvent
local current: Beast? = nil
-- Whether it came this match already (or, on the test ground, TestBeast was changed to bring it).
local came = false
local KEY, RELEASE = SETTINGS.Key, SETTINGS.Release
local keyCarrier: Hero? = nil
local arena: Instance

-- Whether nothing of the map but its floor stands within `radius` studs of `at`.
local function clear(map: Instance, at: Vector3, radius: number): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local floor = map:FindFirstChild("Floor")
	local centre = map:FindFirstChild("Centre")
	for _, part in Workspace:GetPartBoundsInRadius(at + Vector3.new(0, 4, 0), radius, params) do
		local paving = centre and part.Parent == centre and part:IsA("Part")
		if not (floor and part:IsDescendantOf(floor)) and not paving then
			return false
		end
	end
	return true
end

-- A hole and its landing in the arena: on the line between the halves (Z = 0), either side of the middle.
local function arenaSpot(map: Instance): (Vector3, Vector3)
	local hole, land = Vector3.new(SETTINGS.From, 0, 0), Vector3.new(SETTINGS.From - SETTINGS.Leap, 0, 0)
	for _ = 1, TRIES do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = Vector3.new(
			side * rng:NextNumber(SETTINGS.From, SETTINGS.To),
			0,
			rng:NextNumber(-SETTINGS.Off, SETTINGS.Off)
		)
		local landAt = at + HeroKit.flat(-at).Unit * SETTINGS.Leap
		if clear(map, at, CLEAR_HOLE) and clear(map, landAt, CLEAR_LAND) then
			return at, landAt
		end
		hole, land = at, landAt
	end
	return hole, land
end

-- Its landing at `at` throws every hero and minion near, but those of `team` (whose carrier let it loose).
local function slam(at: Vector3, team: string?)
	local targets: { Instance } = {}
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Hero") and model:GetAttribute("Team") ~= team then
			table.insert(targets, model)
		end
	end
	local minions = Workspace:FindFirstChild("Minions")
	for _, root in if minions then minions:GetChildren() else {} do
		if root:IsA("BasePart") and not root:GetAttribute("Dead") and root:GetAttribute("Team") ~= team then
			table.insert(targets, root)
		end
	end
	for _, target in targets do
		local position = if target:IsA("BasePart") then target.Position else (target :: Model):GetPivot().Position
		local away = HeroKit.flat(position - at)
		if away.Magnitude <= SETTINGS.Slam then
			local way = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
			local reach = SETTINGS.Throw * (1 - 0.5 * away.Magnitude / SETTINGS.Slam)
			CombatService.carry(
				target,
				HeroKit.dashEnd(position, way, reach, HeroKit.leapIgnore()),
				THROW_HEIGHT,
				THROW_TIME
			)
		end
	end
end

-- The way its pivot faces when its head faces `look`.
local function facing(b: Beast, look: Vector3): CFrame
	return CFrame.lookAt(Vector3.zero, -look * b.front)
end

-- Where its head's pivot stands (on the flat) when it faces `look` round its coil's middle.
local function headAt(b: Beast, look: Vector3): Vector3
	return b.centre - facing(b, look):VectorToWorldSpace(b.offset)
end

local function living(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 and not model:GetAttribute("Hidden") then humanoid else nil
end

-- The heroes standing within `reach` studs of `at` (flat, to their edge).
local function heroesNear(at: Vector3, reach: number): { Model }
	local found = {}
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Hero") and living(model) then
			local radius = model:GetAttribute("Radius") or 1.5
			if HeroKit.flat(model:GetPivot().Position - at).Magnitude <= reach + radius then
				table.insert(found, model)
			end
		end
	end
	return found
end

-- Whether it still goes for a hero who struck it: while he struck it within `Grudge` seconds or stays within `Aggro`.
local function holds(b: Beast, model: Model, now: number): boolean
	if not model.Parent or not living(model) then
		return false
	end
	return now - (b.struck[model] or -math.huge) <= SETTINGS.Grudge
		or HeroKit.flat(model:GetPivot().Position - b.centre).Magnitude <= SETTINGS.Aggro
end

-- The hero it goes for: the one who struck it last while it holds on to him, else the nearest other it holds on to.
local function choose(b: Beast, now: number): Model?
	local last = b.lastStriker
	if last and holds(b, last, now) then
		return last
	end
	local best, bestGap = nil, math.huge
	for model in b.struck do
		if holds(b, model, now) then
			local gap = HeroKit.flat(model:GetPivot().Position - b.centre).Magnitude
			if gap < bestGap then
				best, bestGap = model, gap
			end
		elseif not model.Parent then
			b.struck[model] = nil
		end
	end
	return best
end

-- The point it slithers to on its circle round `home` while no one fights it.
local function roamGoal(b: Beast): Vector3
	local from = HeroKit.flat(b.centre - b.home)
	local at = if from.Magnitude > 0.1 then math.atan2(from.Z, from.X) else 0
	local radius = SETTINGS.Roam.Radius
	return b.home + Vector3.new(math.cos(at + ROAM_AHEAD) * radius, 0, math.sin(at + ROAM_AHEAD) * radius)
end

-- A circle's middle moved so that all of the circle lies within the middle.
local function keepIn(home: Vector3): Vector3
	local radius = SETTINGS.Roam.Radius
	local x, z = math.max(MIDDLE.X - radius, 0), math.max(MIDDLE.Z - radius, 0)
	return Vector3.new(math.clamp(home.X, -x, x), 0, math.clamp(home.Z, -z, z))
end

-- A circle with it on its edge, turning the way it faces.
local function circleHere(b: Beast)
	b.home = keepIn(b.centre + Vector3.new(-b.look.Z, 0, b.look.X) * SETTINGS.Roam.Radius)
end

-- Whether its coil may lie at `at`, going `way`: with nothing of the map standing up from the floor before it, and
-- while it `roams` not further out of the middle than it is (a hunt may lead it anywhere).
local function free(b: Beast, at: Vector3, way: Vector3, roams: boolean): boolean
	local outX, outZ = math.abs(at.X) > MIDDLE.X, math.abs(at.Z) > MIDDLE.Z
	if
		roams and ((outX and math.abs(at.X) > math.abs(b.centre.X)) or (outZ and math.abs(at.Z) > math.abs(b.centre.Z)))
	then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { b.map }
	local floor = b.map:FindFirstChild("Floor")
	local ahead = at + way * (SETTINGS.Radius * 0.5) + Vector3.new(0, STANDS + 4, 0)
	for _, part in Workspace:GetPartBoundsInRadius(ahead, SETTINGS.Radius * 0.6, params) do
		local top = part.Position.Y + part.Size.Y / 2
		if part.CanCollide and top > STANDS and not (floor and part:IsDescendantOf(floor)) then
			return false
		end
	end
	return true
end

local function bite(b: Beast)
	local spot = headAt(b, b.look) + b.look * BITE.Ahead
	for _, model in heroesNear(spot, BITE.Radius) do
		local humanoid = living(model)
		if humanoid then
			local amount = math.round(Damage.mitigated(model, BITE.Damage, false, nil))
			hitEvent:FireAllClients(model, amount, model:GetPivot().Position, nil)
			ProgressService.hurtByWarden(model, b.model, "Beast")
			humanoid:TakeDamage(amount)
		end
	end
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

-- The floor under `at`, from the map.
local function floorUnder(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arena }
	local hit = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else Vector3.new(at.X, 0, at.Z)
end

-- The key falls at `at`, for `team` alone to take, or (nil) for anyone.
local function dropKey(at: Vector3, team: string?)
	Workspace:SetAttribute("SerpentKey", "Dropped")
	Workspace:SetAttribute("SerpentKeySpot", floorUnder(at) + Vector3.new(0, KEY.Float, 0))
	Workspace:SetAttribute("SerpentKeyFor", team)
	Workspace:SetAttribute("SerpentKeyTeam", nil)
end

local function letKeyGo()
	local hero = keyCarrier
	if hero then
		hero.actor:SetAttribute("SerpentKey", nil)
		if hero.character.Parent then
			hero.character:SetAttribute("SerpentKey", nil)
		end
	end
	keyCarrier = nil
	Workspace:SetAttribute("SerpentKeyTeam", nil)
end

local function clearKey()
	letKeyGo()
	for _, name in { "SerpentKey", "SerpentKeySpot", "SerpentKeyFor", "SerpentKeyEnds" } do
		Workspace:SetAttribute(name, nil)
	end
end

local function takeKey(hero: Hero)
	keyCarrier = hero
	hero.actor:SetAttribute("SerpentKey", true)
	hero.character:SetAttribute("SerpentKey", true)
	if not Workspace:GetAttribute("SerpentKeyEnds") then
		Workspace:SetAttribute("SerpentKeyEnds", Workspace:GetServerTimeNow() + KEY.Lasts)
	end
	Workspace:SetAttribute("SerpentKey", "Carried")
	Workspace:SetAttribute("SerpentKeySpot", nil)
	Workspace:SetAttribute("SerpentKeyFor", nil)
	Workspace:SetAttribute("SerpentKeyTeam", hero.team)
end

-- The key's life: gone when its time is up, falling where its carrier fell, taken by the nearest hero allowed who
-- touches it (within `Reach`, his feet near the floor under it).
local function keyStep()
	local state = Workspace:GetAttribute("SerpentKey")
	if not state then
		return
	end
	local ends = Workspace:GetAttribute("SerpentKeyEnds")
	if ends and Workspace:GetServerTimeNow() >= ends then
		clearKey()
		return
	end
	if state == "Carried" then
		local hero = keyCarrier
		if not hero then
			clearKey()
			return
		end
		local alive = hero.character.Parent ~= nil
			and Actors.character(hero.actor) == hero.character
			and hero.humanoid.Health > 0
		if not alive then
			local at = hero.root.Position
			letKeyGo()
			dropKey(at, nil)
		end
	elseif state == "Dropped" then
		local spot = Workspace:GetAttribute("SerpentKeySpot")
		if typeof(spot) ~= "Vector3" then
			return
		end
		local only = Workspace:GetAttribute("SerpentKeyFor")
		local floor = spot.Y - KEY.Float
		local nearest: Hero? = nil
		local best = KEY.Reach
		for _, hero in heroes() do
			local distance = HeroKit.flat(hero.root.Position - spot).Magnitude
			if
				(only == nil or hero.team == only)
				and distance <= best
				and math.abs(hero.root.Position.Y - ROOT_HEIGHT - floor) < 4
			then
				nearest, best = hero, distance
			end
		end
		if nearest then
			takeKey(nearest)
		end
	end
end

local function die(b: Beast)
	local model = b.model
	CollectionService:RemoveTag(model, "Combatant")
	model:SetAttribute("Health", 0)
	model:SetAttribute("DiedAt", Workspace:GetServerTimeNow())
	model:SetAttribute("Phase", "Dead")
	local killer = b.lastStriker
	local team = if killer then killer:GetAttribute("Team") else nil
	if team then
		model:SetAttribute("KillerTeam", team)
	end
	if not b.released then
		clearKey()
		dropKey(b.centre, team)
	end
	task.delay(SETTINGS.Dying, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Its blow on the Master: `amount` off his health, the damage shown as every hit's.
local function strike(b: Beast, amount: number)
	local master = b.master
	local humanoid = master and master:FindFirstChildOfClass("Humanoid")
	if not master or not humanoid or humanoid.Health <= 0 or not b.model.Parent then
		return
	end
	if b.model:GetAttribute("Phase") ~= "Fight" then
		return
	end
	hitEvent:FireAllClients(master, amount, master:GetPivot().Position, nil)
	humanoid:TakeDamage(amount)
end

-- Let loose: straight at the enemy Master through everything, the headbutt once its head reaches him, then its
-- bites; from the headbutt on it wanes.
local function charge(b: Beast, dt: number, now: number)
	local model, master = b.model, b.master
	if b.rammed then
		local health = (model:GetAttribute("Health") or 0) - RELEASE.Health * RELEASE.Decay * dt
		model:SetAttribute("Health", math.max(0, health))
	end
	local humanoid = master and master:FindFirstChildOfClass("Humanoid")
	if not master or not master.Parent or not humanoid or humanoid.Health <= 0 then
		return
	end
	local goal = master:GetPivot().Position
	local want = HeroKit.flat(goal - b.centre)
	if want.Magnitude < 0.1 then
		return
	end
	want = want.Unit
	local angle = math.atan2(b.look:Cross(want).Y, b.look:Dot(want))
	local turn = math.clamp(angle, -RELEASE.Turn * dt, RELEASE.Turn * dt)
	b.look = CFrame.Angles(0, turn, 0):VectorToWorldSpace(b.look)
	if math.acos(math.clamp(b.look:Dot(b.sent), -1, 1)) >= LOOK_STEP then
		b.sent = b.look
		model:SetAttribute("Look", b.look)
	end
	local reach = RELEASE.Reach + (master:GetAttribute("Radius") or 3)
	local gap = HeroKit.flat(goal - headAt(b, b.look)).Magnitude - reach
	local moving = false
	if gap > 0 and now >= b.biting and math.abs(angle) <= CRAWL_ANGLE then
		b.centre += b.look * math.min(RELEASE.Speed * dt, gap)
		moving = true
		b.body.CFrame = CFrame.lookAt(b.centre, b.centre + b.look) + Vector3.new(0, HEIGHT / 2, 0)
		if (b.centre - b.sentCentre).Magnitude >= CENTRE_STEP then
			b.sentCentre = b.centre
			model:SetAttribute("Centre", b.centre)
		end
	end
	if moving ~= b.moving then
		b.moving = moving
		model:SetAttribute("Centre", b.centre)
		b.sentCentre = b.centre
		model:SetAttribute("Moving", moving)
	end
	if gap <= 0 and now >= b.nextBite and math.abs(angle) <= FACING then
		local ram = not b.rammed
		b.rammed = true
		b.nextBite = now + RELEASE.Every
		b.biting = now + BITE.Length
		model:SetAttribute("Look", b.look)
		b.sent = b.look
		local at = Workspace:GetServerTimeNow()
		if ram then
			model:SetAttribute("Ram", at)
		end
		model:SetAttribute("Bite", at)
		local blow = if ram then math.round(RELEASE.Ram * humanoid.MaxHealth) else RELEASE.Hit
		task.delay(BITE.Hit, strike, b, blow)
	end
end

local function step(b: Beast, dt: number)
	local model = b.model
	if not model.Parent then
		current = nil
		return
	end
	local health = model:GetAttribute("Health") or 0
	if health <= 0 then
		current = nil
		die(b)
		return
	end
	if model:GetAttribute("Phase") ~= "Fight" then
		return
	end
	local now = os.clock()
	if b.released then
		charge(b, dt, now)
		return
	end
	local target = choose(b, now)
	if target then
		b.calmSince = now
	elseif b.hunting then
		circleHere(b)
	end
	b.hunting = target ~= nil
	local goal = if target then target:GetPivot().Position else roamGoal(b)
	local want = HeroKit.flat(goal - b.centre)
	local moving = false
	if want.Magnitude > 0.1 then
		want = want.Unit
		local angle = math.atan2(b.look:Cross(want).Y, b.look:Dot(want))
		-- Right behind it, one way round, or it would waver between the two.
		if math.abs(angle) > math.pi - 0.05 then
			angle = math.pi
		end
		local turn = math.clamp(angle, -SETTINGS.Turn * dt, SETTINGS.Turn * dt)
		b.look = CFrame.Angles(0, turn, 0):VectorToWorldSpace(b.look)
		if math.acos(math.clamp(b.look:Dot(b.sent), -1, 1)) >= LOOK_STEP then
			b.sent = b.look
			model:SetAttribute("Look", b.look)
		end
		-- It slithers after its target till its bite reaches him, and round its circle when it has none; not while
		-- it bites.
		local gap = if target
			then HeroKit.flat(goal - headAt(b, b.look)).Magnitude - (BITE.Ahead + BITE.Radius * 0.5)
			else math.huge
		local speed = if target then SETTINGS.Speed else SETTINGS.Roam.Speed
		if gap > 0 and now >= b.biting and math.abs(angle) <= CRAWL_ANGLE then
			local length = math.min(speed * dt, gap)
			local way = b.look
			-- Hunting, it slides round what stands in its way.
			if target and not free(b, b.centre + way * length, way, false) then
				for _, swerve in SWERVES do
					local side = CFrame.Angles(0, swerve, 0):VectorToWorldSpace(b.look)
					if free(b, b.centre + side * length, side, false) then
						way = side
						break
					end
				end
			end
			local next = b.centre + way * length
			if free(b, next, way, target == nil) then
				b.centre = next
				moving = true
				b.body.CFrame = CFrame.lookAt(b.centre, b.centre + b.look) + Vector3.new(0, HEIGHT / 2, 0)
				if (b.centre - b.sentCentre).Magnitude >= CENTRE_STEP then
					b.sentCentre = b.centre
					model:SetAttribute("Centre", b.centre)
				end
			elseif not target and now - b.turnedAt >= TURN_BACK then
				-- The circle the other way round, away from what stopped it.
				b.turnedAt = now
				b.home = keepIn(b.centre * 2 - b.home)
			end
		end
	end
	if moving ~= b.moving then
		b.moving = moving
		model:SetAttribute("Centre", b.centre)
		b.sentCentre = b.centre
		model:SetAttribute("Moving", moving)
	end
	if not target then
		local most = model:GetAttribute("MaxHealth") or SETTINGS.Health
		if now - b.calmSince >= SETTINGS.Calm and health < most then
			model:SetAttribute("Health", math.min(most, health + most * SETTINGS.Heal * dt))
		end
		return
	end

	if want.Magnitude > 0 then
		local angle = math.atan2(b.look:Cross(want).Y, b.look:Dot(want))
		local head = headAt(b, b.look)
		local gap = HeroKit.flat(goal - head).Magnitude
		if now >= b.nextBite and math.abs(angle) <= FACING and gap <= BITE.Ahead + BITE.Radius then
			b.nextBite = now + BITE.Every
			b.biting = now + BITE.Length
			model:SetAttribute("Look", b.look)
			b.sent = b.look
			model:SetAttribute("Bite", Workspace:GetServerTimeNow())
			task.delay(BITE.Hit, function()
				if model.Parent and model:GetAttribute("Phase") == "Fight" then
					bite(b)
				end
			end)
		end
	end
end

-- Its coil's middle from its pivot in its pivot's frame, flat, at its Scale (ReplicatedStorage.Beast's bounds).
local function coilOffset(): (Vector3, number)
	local template = ReplicatedStorage:FindFirstChild("Beast")
	if not template or not template:IsA("Model") then
		return Vector3.zero, 1
	end
	local box = template:GetBoundingBox()
	local offset = template:GetPivot():PointToObjectSpace(box.Position) * SETTINGS.Scale
	local front = template:GetAttribute("Front")
	return Vector3.new(offset.X, 0, offset.Z), if front == -1 then -1 else 1
end

-- There is only ever one: a new one takes the old one's place (on the test ground, TestBeast). Let loose by `release`,
-- it comes out beside its carrier, a little towards the Master it goes for.
local function come(map: Instance, release: Release?)
	came = true
	local old = Workspace:FindFirstChild("Beast")
	if old then
		old:Destroy()
	end
	current = nil
	local hole, land
	local rumble, flight, wake = SETTINGS.Rumble, SETTINGS.Flight, SETTINGS.Wake
	if release then
		local way = HeroKit.flat(release.master:GetPivot().Position - release.from).Unit
		hole = floorUnder(release.from + Vector3.new(-way.Z, 0, way.X) * (SETTINGS.Hole + 4))
		hole = Vector3.new(hole.X, 0, hole.Z)
		land = hole + way * RELEASE.Leap
		rumble, flight, wake = RELEASE.Rumble, RELEASE.Flight, RELEASE.Wake
	else
		hole, land = arenaSpot(map)
	end
	local way = HeroKit.flat(land - hole).Unit
	local offset, front = coilOffset()
	local b: Beast = {
		model = Instance.new("Model"),
		body = Instance.new("Part"),
		centre = land,
		map = map,
		home = land,
		turnedAt = 0,
		hunting = false,
		sentCentre = land,
		moving = false,
		biting = 0,
		offset = offset,
		front = front,
		look = way,
		sent = way,
		struck = {},
		lastStriker = nil,
		calmSince = 0,
		nextBite = 0,
		released = release ~= nil,
		master = if release then release.master else nil,
		rammed = false,
	}
	b.centre = land + facing(b, way):VectorToWorldSpace(offset)
	b.sentCentre = b.centre
	circleHere(b)

	local model, body = b.model, b.body
	model.Name = "Beast"
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Transparency = 1
	body.Size = Vector3.new(SETTINGS.Radius * 2, HEIGHT, SETTINGS.Radius * 2)
	body.CFrame = CFrame.lookAt(b.centre, b.centre + way) + Vector3.new(0, HEIGHT / 2, 0)
	body.Parent = model
	model.PrimaryPart = body
	local health = if release then RELEASE.Health else SETTINGS.Health
	model:SetAttribute("Beast", true)
	model:SetAttribute("Team", if release then release.team else "Neutral")
	model:SetAttribute("Released", if release then true else nil)
	model:SetAttribute("Radius", SETTINGS.Radius)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("Hole", hole)
	model:SetAttribute("Land", land)
	model:SetAttribute("Centre", b.centre)
	model:SetAttribute("Look", way)
	model:SetAttribute("Rumble", rumble)
	model:SetAttribute("Flight", flight)
	model:SetAttribute("Burst", Workspace:GetServerTimeNow() + rumble)
	model:SetAttribute("Phase", "Rumble")
	model.Parent = Workspace
	task.wait(rumble)
	if not model.Parent then
		return
	end
	model:SetAttribute("Phase", "Flying")
	task.wait(flight)
	if not model.Parent then
		return
	end
	model:SetAttribute("Phase", "Out")
	CollectionService:AddTag(model, "Combatant")
	current = b
	slam(land, if release then release.team else nil)
	task.wait(wake)
	if model.Parent and model:GetAttribute("Phase") == "Out" then
		b.calmSince = os.clock()
		model:SetAttribute("Phase", "Fight")
	end
end

local function enemyMaster(team: string): Model?
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Master") and model:GetAttribute("Team") ~= team then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return model
			end
		end
	end
	return nil
end

-- The key's carrier `actor` (a player or bot) lets the beast loose at the enemy Master: not while another beast is
-- about. Whether it came.
function BeastService.release(actor: Instance): boolean
	local hero = keyCarrier
	if not hero or hero.actor ~= actor or hero.humanoid.Health <= 0 or Workspace:GetAttribute("Winner") ~= nil then
		return false
	end
	local old = Workspace:FindFirstChild("Beast")
	if old and old:GetAttribute("Phase") ~= "Dead" then
		return false
	end
	local master = enemyMaster(hero.team)
	if not master then
		return false
	end
	local from = hero.root.Position
	clearKey()
	task.spawn(come, arena, { team = hero.team, from = from, master = master })
	return true
end

-- The fight's start, then `At` seconds, then the beast; on the test ground TestBeast's seconds after the first hero
-- stands there.
local function schedule(map: Instance, testing: boolean)
	local wait = if testing then Workspace:GetAttribute("TestBeast") else SETTINGS.At
	if type(wait) ~= "number" then
		return
	end
	while Workspace:GetAttribute("MatchStart") == nil do
		task.wait(0.5)
	end
	local at = Workspace:GetAttribute("MatchStart") + wait
	local function heroOut(): boolean
		for _, model in CollectionService:GetTagged("Combatant") do
			if model:GetAttribute("Hero") and model:FindFirstChild("HumanoidRootPart") then
				return true
			end
		end
		return false
	end
	if testing then
		while not heroOut() do
			task.wait(0.25)
		end
		at = Workspace:GetServerTimeNow() + wait
	end
	while Workspace:GetServerTimeNow() < at do
		task.wait(0.25)
	end
	if Workspace:GetAttribute("Winner") == nil and not came then
		come(map)
	end
end

export type Layout = {
	map: Folder,
}

function BeastService.start(layout: Layout)
	arena = layout.map
	hitEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("HeroHit") :: RemoteEvent
	Remote.event("SerpentRelease", 2, function(player)
		BeastService.release(player)
	end)
	task.spawn(function()
		while true do
			keyStep()
			task.wait(0.1)
		end
	end)
	CombatService.beastStruck = function(character: Model)
		local b = current
		if b then
			b.struck[character] = os.clock()
			b.lastStriker = character
			b.calmSince = os.clock()
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		if current then
			step(current, dt)
		end
	end)

	local testing = TestGround.on()
	task.spawn(schedule, layout.map, testing)
	-- On the test ground every new TestBeast brings it again that many seconds later, to be watched once more.
	if testing then
		Workspace:GetAttributeChangedSignal("TestBeast"):Connect(function()
			came = true
			local old = Workspace:FindFirstChild("Beast")
			if old then
				old:Destroy()
			end
			current = nil
			local wait = Workspace:GetAttribute("TestBeast")
			if type(wait) == "number" then
				task.delay(wait, come, layout.map)
			end
		end)
	end
end

return BeastService
