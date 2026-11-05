-- The bots (Config.Bots): AI heroes that fill both teams up to TeamSize, as many fewer on a team as it has players. A
-- bot is an Actor (a Configuration in ServerStorage.Bots) whose hero the server moves: it goes after an enemy hero no
-- one of its team fights yet, anywhere in the arena, and helps with one only when all are taken; with none alive it
-- fights the other enemies (Config.Bots). It fights with its own hero's whole kit through CombatService, as a player
-- would: a fighter up close goes in with it, an archer keeps his distance; with a person's reaction time, rests and
-- misses (Config.Bots), not perfectly. It levels up as players do and spends its points itself; while Buys is on it
-- buys its hero's build at the armory (ShopService: at its stall in the buy phase, and while dead) and drinks its
-- potions. It comes back on a
-- spawn pad after it dies. It plays the hero the draft picked for its place (BotService.start), and a bot that takes over
-- from a player who left plays his hero.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Actors = require(script.Parent.Actors)
local CombatService = require(script.Parent.CombatService)
local Economy = require(script.Parent.Economy)
local HeroService = require(script.Parent.HeroService)
local MatchService = require(script.Parent.MatchService)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local BotService = {}

local SETTINGS = Config.Bots
local TICK = 0.1
-- How often a bot works out its way round the walls again, and how far its goal may move before it does sooner.
local PATH_REFRESH, PATH_SLACK = 2, 6
-- A bot that gains less than STUCK_STEP studs in STUCK_TIME seconds walking takes a path for DETOUR seconds.
local STUCK_TIME, STUCK_STEP, DETOUR = 1, 1, 3
-- How far above or below it a bot counts an enemy as level with it.
local RISE = 3

-- A leap or dash under way: the server carries the bot from `from` to `to`, as a player's client carries him.
type Move = {
	started: number,
	from: Vector3,
	to: Vector3,
	takeoff: number,
	land: number,
	sharp: boolean,
	-- An Ascend's kit, which holds him in the air where he cast it instead (HeroKit.lift).
	lift: any?,
	-- Thrown away by a blow (CombatService's knock): how high the arc goes over the way.
	height: number?,
}

type Bot = {
	actor: Configuration,
	team: string,
	hero: string,
	-- The lane it plays: 1 east, -1 west.
	side: number,
	active: boolean,
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	path: { PathWaypoint },
	waypoint: number,
	pathGoal: Vector3?,
	pathAt: number,
	finding: boolean,
	move: Move?,
	-- Where it stood STUCK_TIME ago, and until when it takes a path even where the way looks clear.
	checkAt: number,
	checkFrom: Vector3,
	detourUntil: number,
	-- Until when it holds its next ability and its next swing, and the enemy hero it last turned on.
	calmUntil: number,
	swingAt: number,
	focus: Instance?,
	-- The enemy hero it goes after.
	prey: Instance?,
	-- Which way it steps around a target it already has in range, so it never stands still in a fight.
	circle: number,
	circleAt: number,
	-- What it fights this tick, and the one its attack under way keeps aiming at.
	aimFor: Instance?,
	aiming: Aiming?,
}

-- An attack under way that follows its target till it strikes or lets go (Bot.aiming): `speed` of what it shoots,
-- if anything, and `side`, how far to one side it misses (-1 to 1, of Miss), chosen once per attack.
type Aiming = {
	target: Instance,
	speed: number?,
	side: number,
}

type Target = {
	instance: Instance,
	position: Vector3,
	radius: number,
	velocity: Vector3,
	hero: boolean,
}

local bots: { Bot } = {}
local folder: Folder
local stalls: { [string]: { Vector3 } } = {}
local made = 0
-- Per team the heroes still to be played by its next bots.
local waiting: { [string]: { string } } = {}
local walls = RaycastParams.new()
walls.FilterType = Enum.RaycastFilterType.Exclude

-- A minion's root is moved by the server, not by physics, so its velocity is measured from where it was a moment ago.
local seen: { [BasePart]: { at: Vector3, time: number, velocity: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
local function track(root: BasePart): Vector3
	local now = os.clock()
	local last = seen[root]
	if not last then
		seen[root] = { at = root.Position, time = now, velocity = Vector3.zero }
		return Vector3.zero
	end
	local passed = now - last.time
	if passed >= 0.1 then
		last.velocity = if passed < 1 then (root.Position - last.at) / passed else Vector3.zero
		last.at, last.time = root.Position, now
	end
	return last.velocity
end

local function alive(b: Bot): boolean
	return b.character ~= nil and b.character.Parent ~= nil and b.humanoid ~= nil and b.humanoid.Health > 0
end

-- The enemies of `team` within `reach` studs of `from`: heroes, and the rest (minions, Masters).
local function enemiesNear(team: string, from: Vector3, reach: number): ({ Target }, { Target })
	local heroes, others = {}, {}
	for _, model in CollectionService:GetTagged("Combatant") do
		-- A vanished hero (CombatService's Vanish) is unseen.
		if not model:IsA("Model") or model:GetAttribute("Team") == team or model:GetAttribute("Hidden") then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local living = if humanoid then humanoid.Health > 0 else (model:GetAttribute("Health") or 0) > 0
		local position = model:GetPivot().Position
		if living and HeroKit.flat(position - from).Magnitude <= reach then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local target: Target = {
				instance = model,
				position = position,
				radius = model:GetAttribute("Radius") or 1.5,
				velocity = if root then root.AssemblyLinearVelocity else Vector3.zero,
				hero = model:GetAttribute("Hero") ~= nil,
			}
			table.insert(if target.hero then heroes else others, target)
		end
	end
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		for _, root in minions:GetChildren() do
			if
				root:IsA("BasePart")
				and root:GetAttribute("Team") ~= team
				and not root:GetAttribute("Dead")
				and HeroKit.flat(root.Position - from).Magnitude <= reach
			then
				table.insert(others, {
					instance = root,
					position = root.Position,
					radius = Config.Minions.Radius,
					velocity = track(root),
					hero = false,
				})
			end
		end
	end
	return heroes, others
end

local function nearest(list: { Target }, from: Vector3): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for _, t in list do
		local distance = HeroKit.flat(t.position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = t, distance
		end
	end
	return best
end

-- Whether nothing of the arena stands between `from` and `to`. The cast starts a little behind `from`, since it misses
-- what it starts in (a wall the hero leans on).
local function clear(from: Vector3, to: Vector3): boolean
	local offset = HeroKit.flat(to - from)
	if offset.Magnitude < 0.5 then
		return true
	end
	local back = offset.Unit * 1.5
	return Workspace:Spherecast(from - back, 1.2, offset + back, walls) == nil
end

-- Walks the bot towards `goal`: straight when nothing is in the way, else along a path round the walls.
local function walkTo(b: Bot, goal: Vector3, now: number)
	local root, humanoid = b.root :: BasePart, b.humanoid :: Humanoid
	local flatGoal = Vector3.new(goal.X, root.Position.Y, goal.Z)
	if HeroKit.flat(goal - root.Position).Magnitude < 1.5 then
		humanoid:Move(Vector3.zero)
		return
	end
	if now - b.checkAt >= STUCK_TIME then
		if (root.Position - b.checkFrom).Magnitude < STUCK_STEP then
			b.detourUntil = now + DETOUR
		end
		b.checkAt, b.checkFrom = now, root.Position
	end
	if now >= b.detourUntil and clear(root.Position, flatGoal) then
		b.path = {}
		humanoid:MoveTo(flatGoal)
		return
	end
	local stale = #b.path == 0
		or not b.pathGoal
		or (b.pathGoal - goal).Magnitude > PATH_SLACK
		or now - b.pathAt > PATH_REFRESH
	if stale and not b.finding then
		b.finding = true
		b.pathGoal = goal
		b.pathAt = now
		local from = root.Position
		task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				WaypointSpacing = 6,
			})
			local ok = pcall(function()
				path:ComputeAsync(from, goal)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				b.path = path:GetWaypoints()
				b.waypoint = math.min(2, #b.path)
			end
			b.finding = false
		end)
	end
	local waypoint = b.path[b.waypoint]
	if waypoint and HeroKit.flat(waypoint.Position - root.Position).Magnitude < 3 then
		b.waypoint += 1
		waypoint = b.path[b.waypoint]
	end
	if waypoint then
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
	else
		humanoid:MoveTo(flatGoal)
	end
end

-- Steps beside `target`, so a bot that already has its range never stands still in a fight.
local function circle(b: Bot, target: Target, now: number)
	local root = b.root :: BasePart
	if now - b.circleAt > 2.4 then
		b.circle = -b.circle
		b.circleAt = now
	end
	local offset = HeroKit.flat(target.position - root.Position)
	local out = if offset.Magnitude > 0.1 then offset.Unit else HeroKit.flat(root.CFrame.LookVector)
	if out.Magnitude < 0.1 then
		out = Vector3.zAxis
	end
	local side = Vector3.new(-out.Z, 0, out.X) * b.circle
	walkTo(b, root.Position + side * 10, now)
end

-- What turns a bot to its aim and holds an ascending one up: constraints, as the server's own CFrame set on the bot
-- reached the players in steps (owner, 2026-11-01: Rowan and Jestrel moved laggy, turned to every shot ten times a
-- second), a constraint's motion as smoothly as any physics.
local function constraint(root: BasePart, name: string, class: string): any
	local found = root:FindFirstChild(name)
	if found then
		return found
	end
	local at = Instance.new("Attachment")
	at.Name = name .. "At"
	at.Parent = root
	local align = Instance.new(class) :: any
	align.Name = name
	align.Mode = if class == "AlignPosition"
		then Enum.PositionAlignmentMode.OneAttachment
		else Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = at
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root
	return align
end

local function holder(root: BasePart): AlignPosition
	return constraint(root, "BotLift", "AlignPosition")
end

local function letGo(root: BasePart?)
	local align = root and root:FindFirstChild("BotLift") :: AlignPosition?
	if align then
		align.Enabled = false
	end
end

-- Turns the bot to `aim` and keeps it so (its humanoid no longer turning it the way it walks) till `unface`.
local function face(b: Bot, aim: Vector3)
	local root, humanoid = b.root :: BasePart, b.humanoid :: Humanoid
	local turn = constraint(root, "BotTurn", "AlignOrientation") :: AlignOrientation
	turn.CFrame = CFrame.lookAt(Vector3.zero, HeroKit.direction(root.Position, aim, root.CFrame.LookVector))
	turn.Enabled = true
	humanoid.AutoRotate = false
end

local function unface(b: Bot)
	local root, humanoid = b.root, b.humanoid
	local turn = root and root:FindFirstChild("BotTurn") :: AlignOrientation?
	if turn and turn.Enabled then
		turn.Enabled = false
	end
	if humanoid then
		humanoid.AutoRotate = true
	end
end

-- Uses `key` towards `aim`, facing it; for a leap or dash the server then carries the bot to where it lands.
local function use(b: Bot, key: string, aim: Vector3): boolean
	if not CombatService.ready(b.actor, key) then
		return false
	end
	local root = b.root :: BasePart
	face(b, aim)
	local ok, landing = CombatService.act(b.actor, key, aim)
	local kit = Config.Heroes[b.hero].Kit[key]
	if ok and b.aimFor then
		local shot = if kit.Kind == "Combo" then kit.Hits[1] else kit.Shot or kit
		b.aiming = { target = b.aimFor, speed = shot.ProjectileSpeed, side = math.random() * 2 - 1 }
	end
	if ok and (kit.Kind == "Ascend" or kit.Kind == "Rain") then
		b.move = { started = os.clock(), from = root.Position, to = root.Position, takeoff = 0, land = 0, lift = kit }
		b.path = {}
	elseif ok and landing then
		local dash = kit.Kind == "Dash"
		b.move = {
			started = os.clock(),
			from = root.Position,
			to = landing,
			takeoff = if dash then kit.Start else kit.Takeoff,
			land = if dash then kit.Move else kit.Land,
			sharp = dash,
		}
		b.path = {}
	end
	return ok
end

local function reaction(): number
	return SETTINGS.Reaction.Min + math.random() * (SETTINGS.Reaction.Max - SETTINGS.Reaction.Min)
end

-- An ability the bot could use now, once it has waited its reaction time since the last.
local function maybe(b: Bot, key: string, aim: Vector3, now: number): boolean
	if now < b.calmUntil or not use(b, key, aim) then
		return false
	end
	b.calmUntil = now + reaction()
	return true
end

-- Somewhere up to Stray studs from `at`, where a leap or dash aimed at it lands.
local function stray(at: Vector3): Vector3
	local angle = math.random() * 2 * math.pi
	return at + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (math.random() * SETTINGS.Stray)
end

-- How far `target` is from the bot, from edge to edge: round, and up or down past RISE studs, so a bot under an enemy on a
-- ledge goes up to him rather than swinging from below where its strikes do not reach (CombatService).
local function gapTo(root: BasePart, target: Target): number
	local rise = math.max(0, math.abs(target.position.Y - root.Position.Y) - RISE)
	local round = HeroKit.flat(target.position - root.Position).Magnitude
	return math.sqrt(round * round + rise * rise) - target.radius
end

-- `at` turned round `from` so it passes up to Miss studs beside it either way, near or far (`side` of Miss, else
-- anywhere in it): where a shot or a thrown dagger flies.
local function miss(from: Vector3, at: Vector3, side: number?): Vector3
	local distance = math.max(HeroKit.flat(at - from).Magnitude, 1)
	local turn = CFrame.Angles(0, math.atan2((side or math.random() * 2 - 1) * SETTINGS.Miss, distance), 0)
	return from + turn:VectorToWorldSpace(at - from)
end

-- Where a projectile flying `speed` studs a second, shot at `target` `gap` studs away, is aimed: ahead of him by Lead
-- of the way he walks meanwhile, and up to Miss studs beside that.
local function aimAt(from: Vector3, target: Target, gap: number, speed: number, side: number?): Vector3
	return miss(from, target.position + HeroKit.flat(target.velocity) * (gap / speed * SETTINGS.Lead), side)
end

-- Where `instance` (a hero or a Master, else a minion's root) is now, while it lives.
local function targetOf(instance: Instance): Target?
	if not instance.Parent then
		return nil
	end
	if instance:IsA("BasePart") then
		if instance:GetAttribute("Dead") then
			return nil
		end
		return {
			instance = instance,
			position = instance.Position,
			radius = Config.Minions.Radius,
			velocity = track(instance),
			hero = false,
		}
	end
	local model = instance :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if
		model:GetAttribute("Hidden")
		or not (if humanoid then humanoid.Health > 0 else (model:GetAttribute("Health") or 0) > 0)
	then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return {
		instance = model,
		position = model:GetPivot().Position,
		radius = model:GetAttribute("Radius") or 1.5,
		velocity = if root then root.AssemblyLinearVelocity else Vector3.zero,
		hero = model:GetAttribute("Hero") ~= nil,
	}
end

-- Keeps the bot's attack under way on its target till it strikes or lets go, as a player keeps his crosshair on him:
-- most of all an attack that takes long to let go (Mavorak's ultimate hangs three seconds), which would otherwise go
-- where its target stood when it began. It faces him meanwhile, unless a leap or dash carries it.
local function follow(b: Bot)
	local aiming, root, humanoid = b.aiming, b.root, b.humanoid
	if not aiming or not root or not humanoid or not alive(b) then
		b.aiming = nil
		unface(b)
		return
	end
	local target = targetOf(aiming.target)
	local aim = if target
		then (if aiming.speed
			then aimAt(root.Position, target, gapTo(root, target), aiming.speed, aiming.side)
			else target.position)
		else nil
	if not aim or not CombatService.aim(b.actor, aim) then
		b.aiming = nil
		unface(b)
		return
	end
	if b.move and not b.move.lift then
		return
	end
	face(b, aim)
end

-- Whether `key` of the kit flies at its target: a throw, a sniper's bullet, or a flurry whose lightning does.
local function ranged(ability: any): boolean
	return ability.Kind == "Throw" or ability.Kind == "Snipe" or (ability.Kind == "Flurry" and ability.Zap == true)
end

-- Uses `key` of a close fighter's kit on `target` `gap` studs away when it reaches him, after its kind: a throw or a
-- flurry's lightning flies at him (leading him) when no wall is between, a leap lands by him, a flurry sweeps where he
-- stands and a strike falls there.
local function strike(b: Bot, key: string, target: Target, gap: number, now: number): boolean
	local root = b.root :: BasePart
	local ability = Config.Heroes[b.hero].Kit[key]
	if not ability then
		return false
	end
	if ranged(ability) then
		if gap > ability.Range - 4 or not clear(root.Position, target.position) then
			return false
		end
		local aim = if ability.ProjectileSpeed
			then aimAt(root.Position, target, gap, ability.ProjectileSpeed)
			else target.position
		return maybe(b, key, aim, now)
	elseif ability.Kind == "Leap" then
		return gap >= 5 and gap <= ability.Range - 2 and maybe(b, key, stray(target.position), now)
	elseif ability.Kind == "Dash" then
		-- A charge (Korrund's E) runs through him, so it aims at where he stands.
		return gap >= 4 and gap <= ability.Range - 4 and maybe(b, key, target.position, now)
	elseif ability.Kind == "Flurry" then
		return gap <= ability.Range - 1 and maybe(b, key, target.position, now)
	elseif ability.Kind == "Strike" or ability.Kind == "Rain" then
		return gap <= ability.Range - 2 and maybe(b, key, target.position, now)
	end
	return false
end

-- A fighter up close (Shadowren, Mortael, Brontar): his abilities on heroes as each reaches (strike), the dash to
-- close in, the combo in reach; on minions his ultimate into a crowd and what flies at them from afar.
local function brawl(b: Bot, target: Target, others: { Target }, now: number)
	local root = b.root :: BasePart
	local kit = Config.Heroes[b.hero].Kit
	local gap = gapTo(root, target)
	local used = false
	if target.hero then
		used = strike(b, "R", target, gap, now)
			or strike(b, "M2", target, gap, now)
			or strike(b, "E", target, gap, now)
			or (
				kit.Dash.Range
				and gap >= 7
				and gap <= kit.Dash.Range - 2
				and maybe(b, "Dash", stray(target.position), now)
			)
	else
		local reach = kit.R.Radius or kit.R.Range
		local crowd = 0
		for _, other in others do
			if HeroKit.flat(other.position - target.position).Magnitude <= reach then
				crowd += 1
			end
		end
		used = (crowd >= 3 and strike(b, "R", target, gap, now))
			or (gap > 6 and ranged(kit.E) and strike(b, "E", target, gap, now))
	end
	if not used and gap <= kit.M1.Hits[1].Range - 0.5 and now >= b.swingAt and use(b, "M1", target.position) then
		b.swingAt = now + math.random() * SETTINGS.Rest
	end
	if gap > 3 then
		walkTo(b, target.position, now)
	else
		circle(b, target, now)
	end
end

-- A fighter from afar (Rowan or Mavorak, whose combos shoot), who keeps his distance (Config.Bots): he hops away from
-- a hero who comes within Flee, looses his ultimate, his heavy shot (or slams a hero beside him) and his volley at
-- heroes in reach, the ultimate also into a crowd, and his shots at anything in reach; he walks up while out of reach
-- or behind a wall, and backs off from a hero within Keep.
local function shoot(b: Bot, target: Target, others: { Target }, now: number)
	local root = b.root :: BasePart
	local kit = Config.Heroes[b.hero].Kit
	local shot = kit.M1.Hits[1]
	local offset = HeroKit.flat(target.position - root.Position)
	local gap = gapTo(root, target)
	local open = clear(root.Position, target.position)
	local away = if offset.Magnitude > 0.1 then -offset.Unit else -root.CFrame.LookVector
	local used = false
	if target.hero then
		-- A vanishing trick (Kind "Vanish") goes nowhere: it only hides him from the hero who came too close.
		used = (gap <= SETTINGS.Flee and maybe(b, "Dash", root.Position + away * (kit.Dash.Range or 0), now))
			-- A rain of beams (Kind "Rain") falls where he stands, no shot that needs leading.
			or (open and gap <= kit.R.Range * SETTINGS.Fan and maybe(
				b,
				"R",
				if kit.R.ProjectileSpeed
					then aimAt(root.Position, target, gap, kit.R.ProjectileSpeed)
					else target.position,
				now
			))
			or (kit.M2.Slam and gap <= kit.M2.SlamRadius - 2 and maybe(b, "M2", target.position, now))
			or (not kit.M2.Slam and open and gap <= kit.M2.Range - 4 and maybe(
				b,
				"M2",
				aimAt(root.Position, target, gap, kit.M2.ProjectileSpeed),
				now
			))
			-- A laser beam (a Flurry's Beam) is held on him, no shot that needs leading.
			or (
				open
				and gap <= kit.E.Range - 4
				and maybe(
					b,
					"E",
					if kit.E.ProjectileSpeed
						then aimAt(root.Position, target, gap, kit.E.ProjectileSpeed)
						else target.position,
					now
				)
			)
	else
		local crowd = 0
		for _, other in others do
			if HeroKit.flat(other.position - target.position).Magnitude <= SETTINGS.Crowd then
				crowd += 1
			end
		end
		-- A sniper's one bullet is kept for heroes.
		used = open
			and crowd >= 3
			and kit.R.Kind ~= "Snipe"
			and gap <= kit.R.Range * SETTINGS.Fan
			and maybe(b, "R", target.position, now)
	end
	local aim = aimAt(root.Position, target, gap, shot.ProjectileSpeed)
	if not used and open and gap <= shot.Range - 0.5 and now >= b.swingAt and use(b, "M1", aim) then
		b.swingAt = now + math.random() * SETTINGS.Rest
	end
	if not open or gap > shot.Range - 4 then
		walkTo(b, target.position, now)
	elseif target.hero and gap < SETTINGS.Keep then
		walkTo(b, root.Position + away * 8, now)
	else
		circle(b, target, now)
	end
end

local function fight(b: Bot, target: Target, others: { Target }, now: number)
	if Config.Heroes[b.hero].Kit.M1.Hits[1].ProjectileSpeed then
		shoot(b, target, others, now)
	else
		brawl(b, target, others, now)
	end
end

-- Walks the bot, with no enemy hero alive, to the nearest of the enemy minions (`enemies`, anywhere in the arena), or
-- to its lane's gate when there are none.
local function advance(b: Bot, enemies: { Target }, now: number)
	local minions = {}
	for _, t in enemies do
		if t.instance:IsA("BasePart") then
			table.insert(minions, t)
		end
	end
	local minion = nearest(minions, (b.root :: BasePart).Position)
	walkTo(b, if minion then minion.position else Vector3.new(b.side * Config.Minions.LaneRadius, 0, 0), now)
end

-- Whether a living player's hero of `team` stands within Taken studs of `hero`.
local function playerNear(team: string, hero: Target): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			character
			and humanoid
			and humanoid.Health > 0
			and character:GetAttribute("Team") == team
			and HeroKit.flat(character:GetPivot().Position - hero.position).Magnitude <= SETTINGS.Taken
		then
			return true
		end
	end
	return false
end

-- The enemy hero `b` goes after, of `heroes` (Config.Bots): the one it chose while nobody else of its team fights him
-- too or no free one is left, else the nearest free one, else the nearest to help.
local function choosePrey(b: Bot, heroes: { Target }): Target?
	local root = b.root :: BasePart
	local free = {}
	local current: Target? = nil
	for _, hero in heroes do
		if hero.instance == b.prey then
			current = hero
		end
		local taken = playerNear(b.team, hero)
		for _, other in bots do
			if taken then
				break
			end
			taken = other ~= b and other.team == b.team and other.prey == hero.instance and alive(other)
		end
		if not taken then
			table.insert(free, hero)
		end
	end
	local choice = if current and (#free == 0 or table.find(free, current))
		then current
		else nearest(free, root.Position) or nearest(heroes, root.Position)
	b.prey = if choice then choice.instance else nil
	return choice
end

-- Spends the bot's points: the ultimate when it may, else the lower of its other ranks.
local function spend(b: Bot)
	while (b.actor:GetAttribute("Points") or 0) > 0 do
		local order = { "R", "M2", "E" }
		if Leveling.rank(b.actor :: any, "E") < Leveling.rank(b.actor :: any, "M2") then
			order = { "R", "E", "M2" }
		end
		local raised = false
		for _, key in order do
			if ProgressService.raise(b.actor, key) then
				raised = true
				break
			end
		end
		if not raised then
			break
		end
	end
end

-- The parts of `id` the bot lacks, at every depth, with the ones it holds (`pool`) taken out as they are counted.
local function missingParts(id: string, pool: { string }, out: { string })
	for _, part in Config.Items[id].From or {} do
		local found = table.find(pool, part)
		if found then
			table.remove(pool, found)
		else
			table.insert(out, part)
			missingParts(part, pool, out)
		end
	end
end

-- At the armory the bot buys the next item of its hero's build (Config.Bots.Builds, else the one the armory
-- recommends him), or while that is too dear the dearest part of it it can afford; an item it cannot carry is passed
-- over.
local function shop(b: Bot)
	if not ShopService.atShop(b.actor) then
		return
	end
	local step = b.actor:GetAttribute("BuildStep") or 1
	local id = (SETTINGS.Builds[b.hero] or Items.build(b.hero, nil))[step]
	if not id then
		return
	end
	local ok, why = Items.check(b.actor, id)
	if ok then
		ShopService.buy(b.actor, id)
		b.actor:SetAttribute("BuildStep", step + 1)
		return
	elseif why ~= "Not enough coins" then
		b.actor:SetAttribute("BuildStep", step + 1)
		return
	end
	local pool = {}
	for _, slot in Items.bag(b.actor) do
		table.insert(pool, slot.id)
	end
	local parts = {}
	missingParts(id, pool, parts)
	table.sort(parts, function(x, y)
		return Config.Items[x].Cost > Config.Items[y].Cost
	end)
	for _, part in parts do
		if Items.check(b.actor, part) then
			ShopService.buy(b.actor, part)
			return
		end
	end
end

-- A bot drinks a potion when it is low and none is healing it.
local function drink(b: Bot)
	local humanoid = b.humanoid :: Humanoid
	local ends = b.actor:GetAttribute("PotionUntil") or 0
	if
		humanoid.Health < humanoid.MaxHealth * SETTINGS.PotionAt
		and ends <= Workspace:GetServerTimeNow()
		and Items.count(b.actor, "HealthPotion") > 0
	then
		ShopService.drink(b.actor)
	end
end

-- The nearest of the bot's team's armory stalls.
local function nearestStall(b: Bot, from: Vector3): Vector3?
	local best, bestGap = nil, math.huge
	for _, spot in stalls[b.team] or {} do
		local gap = HeroKit.flat(spot - from).Magnitude
		if gap < bestGap then
			best, bestGap = spot, gap
		end
	end
	return best
end

local function think(b: Bot, now: number)
	-- Under the match's cards, before the buy phase, the bots wait on their pads like everyone (HeroService.release).
	if Workspace:GetAttribute("Phase") == "Waiting" then
		return
	end
	if not alive(b) then
		b.prey = nil
		if SETTINGS.Buys then
			shop(b)
		end
		return
	end
	if b.move then
		return
	end
	spend(b)
	if SETTINGS.Buys then
		shop(b)
		drink(b)
	end
	local root = b.root :: BasePart
	-- In the buy phase a bot that buys walks to its armory stall and shops there; the others wait on their pad.
	if not MatchService.fighting() then
		local stall = SETTINGS.Buys and nearestStall(b, root.Position)
		if stall and not ShopService.atShop(b.actor) then
			walkTo(b, stall, now)
		else
			(b.humanoid :: Humanoid):Move(Vector3.zero)
		end
		return
	end
	local heroes, enemies = enemiesNear(b.team, root.Position, math.huge)
	local others = {}
	for _, t in enemies do
		if HeroKit.flat(t.position - root.Position).Magnitude <= SETTINGS.Sight then
			table.insert(others, t)
		end
	end
	local target = choosePrey(b, heroes) or nearest(others, root.Position)
	b.aimFor = if target then target.instance else nil
	-- A hero it turns on gets a moment before the first ability, as a person needs to see him coming.
	if target and target.hero and target.instance ~= b.focus then
		b.calmUntil = math.max(b.calmUntil, now + reaction())
	end
	b.focus = if target and target.hero then target.instance else b.focus
	if target then
		fight(b, target, others, now)
	else
		advance(b, enemies, now)
	end
end

-- Carries a leaping or dashing bot along, or holds an ascending one up, as HeroControls does the player's hero.
local function carry(b: Bot, now: number)
	-- Held against an enemy's charge (HeroKit.heldAt) it goes along at his front, its own move cut short.
	local body, character = b.root, b.character
	local at = body and character and alive(b) and HeroKit.heldAt(character, body.Position.Y)
	if body and at then
		letGo(body)
		b.move = { started = now, from = at, to = at, takeoff = 0, land = 0.05 }
		b.path, b.aiming = {}, nil
		body.CFrame = CFrame.new(at) * body.CFrame.Rotation
		body.AssemblyLinearVelocity = Vector3.zero
		return
	end
	local m = b.move
	if not m then
		return
	end
	local root = b.root
	if not alive(b) or not root then
		letGo(root)
		b.move = nil
		return
	end
	local t = now - m.started
	if m.lift then
		local align = holder(root)
		align.Position = m.from + Vector3.new(0, HeroKit.lift(m.lift, t), 0)
		align.Enabled = true
		if t >= m.lift.Land then
			align.Enabled = false
			b.move = nil
		end
		return
	end
	letGo(root)
	if t < m.takeoff then
		return
	end
	local share = math.clamp((t - m.takeoff) / (m.land - m.takeoff), 0, 1)
	local alpha = if m.sharp then 1 - (1 - share) ^ 2 else share * share * (3 - 2 * share)
	local rise = if m.height then Vector3.new(0, m.height * 4 * share * (1 - share), 0) else Vector3.zero
	root.CFrame = CFrame.new(m.from:Lerp(m.to, alpha) + rise) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		b.move = nil
	end
end

local function spawnHero(b: Bot)
	if not b.active then
		return
	end
	local hero = b.hero
	local character =
		Players:CreateHumanoidModelFromDescription(HeroService.description(hero), Enum.HumanoidRigType.R15)
	if not b.active then
		character:Destroy()
		return
	end
	character.Name = hero
	local humanoid = HeroService.prepare(character, hero, b.team, b.actor)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		character:Destroy()
		return
	end
	character:PivotTo(HeroService.pad(b.team))
	character.Parent = Workspace
	root:SetNetworkOwner(nil)
	b.character, b.humanoid, b.root = character, humanoid, root
	b.path, b.waypoint, b.pathGoal, b.move = {}, 1, nil, nil
	b.checkAt, b.checkFrom, b.detourUntil = os.clock(), root.Position, 0
	Actors.setCharacter(b.actor, character)
	CombatService.track(b.actor, character)
	HeroService.enlist(character)
	humanoid.Died:Connect(function()
		HeroService.discharge(character)
		task.wait(ProgressService.heroDied(character, b.actor, character:GetPivot().Position))
		character:Destroy()
		if b.active and b.character == character then
			spawnHero(b)
		end
	end)
end

local function addBot(team: string)
	made += 1
	local actor = Instance.new("Configuration")
	actor.Name = string.format("%s bot %d", team, made)
	actor:SetAttribute("Team", team)
	ProgressService.join(actor)
	Economy.join(actor)
	actor.Parent = folder
	Actors.addBot(actor)
	local onTeam = 0
	for _, other in bots do
		if other.team == team then
			onTeam += 1
		end
	end
	local queued = waiting[team]
	local hero = if queued and #queued > 0 then table.remove(queued, 1) :: string else SETTINGS.Hero
	if not Config.Heroes[hero] then
		hero = SETTINGS.Hero
	end
	local b: Bot = {
		actor = actor,
		team = team,
		hero = hero,
		side = if onTeam % 2 == 0 then 1 else -1,
		active = true,
		character = nil,
		humanoid = nil,
		root = nil,
		path = {},
		waypoint = 1,
		pathGoal = nil,
		pathAt = 0,
		finding = false,
		move = nil,
		checkAt = 0,
		checkFrom = Vector3.zero,
		detourUntil = 0,
		calmUntil = 0,
		swingAt = 0,
		focus = nil,
		prey = nil,
		circle = if math.random() < 0.5 then 1 else -1,
		circleAt = 0,
		aimFor = nil,
		aiming = nil,
	}
	table.insert(bots, b)
	task.spawn(spawnHero, b)
end

local function removeBot(b: Bot)
	b.active = false
	local index = table.find(bots, b)
	if index then
		table.remove(bots, index)
	end
	if b.character then
		HeroService.discharge(b.character)
		b.character:Destroy()
	end
	CombatService.forget(b.actor)
	Actors.removeBot(b.actor)
	b.actor:Destroy()
end

-- Every team has TeamSize heroes: as many bots as it lacks players (by their "Team", MatchSetup). A player who leaves
-- is played on by a new bot.
local function balance()
	for _, team in Config.TeamOrder do
		local players = 0
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Team") == team then
				players += 1
			end
		end
		local wanted = math.max(0, SETTINGS.TeamSize - players)
		local mine = {}
		for _, b in bots do
			if b.team == team then
				table.insert(mine, b)
			end
		end
		for _ = #mine + 1, wanted do
			addBot(team)
		end
		for i = #mine, wanted + 1, -1 do
			removeBot(mine[i])
		end
	end
end

export type Layout = {
	daisFront: { [string]: Vector3 },
	shops: { [string]: { CFrame } },
}

-- `heroes`: per team the heroes the draft picked for its bots' places.
function BotService.start(layout: Layout, heroes: { [string]: { string } }?)
	for team, list in heroes or {} do
		waiting[team] = table.clone(list)
	end
	for team, list in layout.shops do
		stalls[team] = {}
		for _, spot in list do
			table.insert(stalls[team], spot.Position)
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = ServerStorage

	-- A bot knocked away flies from where it is, its own leap or dash cut short, and thinks again once down.
	CombatService.carryBot = function(actor: Instance, to: Vector3, height: number, length: number)
		for _, b in bots do
			if b.actor == actor and b.root and alive(b) then
				b.move = {
					started = os.clock(),
					from = b.root.Position,
					to = to,
					takeoff = 0,
					land = length,
					sharp = true,
					height = height,
				}
				b.path, b.aiming = {}, nil
				return
			end
		end
	end

	Players.PlayerAdded:Connect(function()
		task.defer(balance)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local team, hero = player:GetAttribute("Team"), player:GetAttribute("Hero")
		if typeof(team) == "string" and typeof(hero) == "string" then
			waiting[team] = waiting[team] or {}
			table.insert(waiting[team], 1, hero)
		end
		task.defer(balance)
	end)
	balance()

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, b in bots do
			carry(b, now)
		end
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = math.min(elapsed - TICK, TICK)
		walls.FilterDescendantsInstances = HeroKit.leapIgnore()
		for _, b in table.clone(bots) do
			follow(b)
			think(b, now)
		end
	end)
end

return BotService
