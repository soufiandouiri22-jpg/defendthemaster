-- The bots (Config.Bots): AI heroes that fill both teams up to TeamSize, as many fewer on a team as it has players. A
-- bot is an Actor (a Configuration in ServerStorage.Bots) whose hero the server moves: it walks its lane (east or west,
-- in turn) behind its team's minions, turns on the nearest enemy hero in sight, else the nearest other enemy, and
-- fights with its whole kit through CombatService, as a player would: leap and flurry on heroes up close, the dagger
-- at range, the dash to close in, the combo in reach. It levels up as players do and spends its points itself, and
-- comes back on a spawn pad after it dies.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Actors = require(script.Parent.Actors)
local CombatService = require(script.Parent.CombatService)
local Economy = require(script.Parent.Economy)
local HeroService = require(script.Parent.HeroService)
local MatchService = require(script.Parent.MatchService)
local ProgressService = require(script.Parent.ProgressService)

local BotService = {}

local SETTINGS = Config.Bots
local TICK = 0.1
-- How often a bot works out its way round the walls again, and how far its goal may move before it does sooner.
local PATH_REFRESH, PATH_SLACK = 2, 6
-- How far behind its foremost minion a bot walks its lane.
local BEHIND = 6
-- A bot that gains less than STUCK_STEP studs in STUCK_TIME seconds walking takes a path for DETOUR seconds.
local STUCK_TIME, STUCK_STEP, DETOUR = 1, 1, 3

-- A leap or dash under way: the server carries the bot from `from` to `to`, as a player's client carries him.
type Move = {
	started: number,
	from: Vector3,
	to: Vector3,
	takeoff: number,
	land: number,
	sharp: boolean,
}

type Bot = {
	actor: Configuration,
	team: string,
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
local fronts: { [string]: Vector3 } = {}
local made = 0
local walls = RaycastParams.new()
walls.FilterType = Enum.RaycastFilterType.Exclude

local function enemyOf(team: string): string
	return if team == "Blue" then "Red" else "Blue"
end

local function alive(b: Bot): boolean
	return b.character ~= nil and b.character.Parent ~= nil and b.humanoid ~= nil and b.humanoid.Health > 0
end

-- The enemies of `team` within `reach` studs of `from`: heroes, and the rest (minions, Masters).
local function enemiesNear(team: string, from: Vector3, reach: number): ({ Target }, { Target })
	local heroes, others = {}, {}
	for _, model in CollectionService:GetTagged("Combatant") do
		if not model:IsA("Model") or model:GetAttribute("Team") == team then
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
					velocity = Vector3.zero,
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

-- Uses `key` towards `aim`, facing it; for a leap or dash the server then carries the bot to where it lands.
local function use(b: Bot, key: string, aim: Vector3): boolean
	local root = b.root :: BasePart
	if not CombatService.ready(b.actor, key) then
		return false
	end
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	local ok, landing = CombatService.act(b.actor, key, aim)
	if ok and landing then
		local kit = Config.Heroes[SETTINGS.Hero].Kit[key]
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

-- An ability the bot could use now, used with chance Reaction.
local function maybe(b: Bot, key: string, aim: Vector3): boolean
	return CombatService.ready(b.actor, key) and math.random() < SETTINGS.Reaction and use(b, key, aim)
end

local function fight(b: Bot, target: Target, others: { Target }, now: number)
	local root = b.root :: BasePart
	local kit = Config.Heroes[SETTINGS.Hero].Kit
	local offset = HeroKit.flat(target.position - root.Position)
	local gap = offset.Magnitude - target.radius
	local used = false
	if target.hero then
		local lead = target.position + HeroKit.flat(target.velocity) * (gap / kit.E.ProjectileSpeed)
		used = (gap <= kit.R.Range - 1 and maybe(b, "R", target.position))
			or (gap >= 5 and gap <= kit.M2.Range - 2 and maybe(b, "M2", target.position))
			or (gap <= kit.E.Range - 4 and clear(root.Position, target.position) and maybe(b, "E", lead))
			or (gap >= 7 and gap <= kit.Dash.Range - 2 and maybe(b, "Dash", target.position))
	else
		local crowd = 0
		for _, other in others do
			if HeroKit.flat(other.position - root.Position).Magnitude <= kit.R.Range then
				crowd += 1
			end
		end
		used = (crowd >= 3 and maybe(b, "R", target.position))
			or (gap > 6 and gap <= 30 and clear(root.Position, target.position) and maybe(b, "E", target.position))
	end
	if not used and gap <= kit.M1.Hits[1].Range - 0.5 then
		use(b, "M1", target.position)
	end
	if gap > 3 then
		walkTo(b, target.position, now)
	else
		(b.humanoid :: Humanoid):Move(Vector3.zero)
	end
end

-- Walks the bot's lane: a few steps behind its team's foremost minion there, or at the lane's gate when there is none.
local function advance(b: Bot, now: number)
	local front = fronts[enemyOf(b.team)]
	local foremost: BasePart? = nil
	local best = math.huge
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		for _, root in minions:GetChildren() do
			if
				root:IsA("BasePart")
				and root:GetAttribute("Team") == b.team
				and not root:GetAttribute("Dead")
				and math.sign(root.Position.X) == b.side
			then
				local distance = HeroKit.flat(root.Position - front).Magnitude
				if distance < best then
					foremost, best = root, distance
				end
			end
		end
	end
	local goal = Vector3.new(b.side * Config.Minions.LaneRadius, 0, 0)
	if foremost then
		goal = foremost.Position - HeroKit.flat(front - foremost.Position).Unit * BEHIND
	end
	walkTo(b, goal, now)
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

local function think(b: Bot, now: number)
	if not alive(b) or b.move then
		return
	end
	spend(b)
	if not MatchService.fighting() then
		return
	end
	local root = b.root :: BasePart
	local heroes, others = enemiesNear(b.team, root.Position, SETTINGS.Sight)
	local target = nearest(heroes, root.Position) or nearest(others, root.Position)
	if target then
		fight(b, target, others, now)
	else
		advance(b, now)
	end
end

-- Carries a leaping or dashing bot along, as HeroControls carries the player's hero.
local function carry(b: Bot, now: number)
	local m = b.move
	if not m then
		return
	end
	local root = b.root
	if not alive(b) or not root then
		b.move = nil
		return
	end
	local t = now - m.started
	if t < m.takeoff then
		return
	end
	local alpha = math.clamp((t - m.takeoff) / (m.land - m.takeoff), 0, 1)
	alpha = if m.sharp then 1 - (1 - alpha) ^ 2 else alpha * alpha * (3 - 2 * alpha)
	root.CFrame = CFrame.new(m.from:Lerp(m.to, alpha)) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		b.move = nil
	end
end

local function spawnHero(b: Bot)
	if not b.active then
		return
	end
	local hero = SETTINGS.Hero
	local character =
		Players:CreateHumanoidModelFromDescription(HeroService.description(hero), Enum.HumanoidRigType.R15)
	if not b.active then
		character:Destroy()
		return
	end
	character.Name = hero
	local humanoid = HeroService.prepare(character, hero, b.team, Leveling.level(b.actor :: any))
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
	local b: Bot = {
		actor = actor,
		team = team,
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

-- Every team has TeamSize heroes: as many bots as it lacks players. Until the teams exist every player is Blue.
local function balance()
	for _, team in Config.TeamOrder do
		local players = if team == "Blue" then #Players:GetPlayers() else 0
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
}

function BotService.start(layout: Layout)
	fronts = layout.daisFront
	folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = ServerStorage

	Players.PlayerAdded:Connect(balance)
	Players.PlayerRemoving:Connect(function()
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
			think(b, now)
		end
	end)
end

return BotService
