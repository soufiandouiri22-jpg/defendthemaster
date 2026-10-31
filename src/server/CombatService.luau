-- The heroes' attacks (Config.Heroes[hero].Kit). A client asks for an attack through ReplicatedStorage.Net.HeroAction
-- (key, a point far along where he looks; while an attack plays, "Aim" and where he looks now); the server
-- checks the hero can (alive, not mid-motion, off cooldown), tells every client to play the motion (Net.HeroMotion:
-- character, key, combo step, landing spot) and lands each hit at its time in the motion on the enemies there: the
-- other team's minions and Combatants (heroes, Masters). A refused attack is sent back to its client
-- (Net.HeroRefused), which stops the motion it already began. Thrown daggers and shot arrows fly on the server
-- (Net.HeroProjectile: id, origin, direction, speed, range, its size and blast; Net.HeroProjectileEnd: id, where it
-- stopped, hit or not); one stops at the first enemy in its way, a piercing one strikes everyone it passes once, and
-- every one at the first wall or floor; one with a blast then bursts there over everyone round it. Every swing, shot and throw of every hero goes where the crosshair points, upwards and
-- downwards as well, to the point under it (HeroKit.aimDirection, owner 2026-10-29), and strikes an enemy only at the heights his body
-- reaches; a leap lands on the spot aimed at and a dash keeps to the ground.
-- Every hit is told to the clients for its feedback (Net.HeroHit: target, damage, where, the striking player). Bots
-- (Actors, BotService) attack through CombatService.act, with the same checks; they move through their leaps and
-- dashes on the server (CombatService.act gives where they land), as a player's client moves him.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Motion = require(ReplicatedStorage.Shared.Motion)
local Actors = require(script.Parent.Actors)
local Damage = require(script.Parent.Damage)
local MatchService = require(script.Parent.MatchService)
local MinionService = require(script.Parent.MinionService)
local ProgressService = require(script.Parent.ProgressService)

local CombatService = {}

local KEYS = { M1 = true, M2 = true, E = true, R = true, Dash = true }
-- After a hit lands, the next swing or ability may start this much later.
local RECOVER = 0.12
-- A command may come this much before the hero is free, as the network does not deliver at an even pace.
local EARLY = 0.12
local DASH_STEP = 0.03

type State = {
	actor: Instance,
	character: Model,
	busyUntil: number,
	combo: number,
	comboUntil: number,
	cooldowns: { [string]: number },
	-- Bumped by every new motion, so the hits of one that was cut short no longer land.
	motion: number,
	-- Whether his next M1 swing is Eclipse Edge's, after an ability.
	eclipse: boolean,
	-- Where his crosshair points now, sent by his client while an attack plays (Net.HeroAction "Aim").
	aim: Vector3?,
}

-- An enemy in reach: a minion's root part or a Combatant model, standing from the height `bottom` to `top`.
type Enemy = {
	instance: Instance,
	position: Vector3,
	radius: number,
	bottom: number,
	top: number,
}

type Projectile = {
	id: number,
	player: Instance,
	character: Model,
	team: string,
	position: Vector3,
	direction: Vector3,
	left: number,
	speed: number,
	width: number,
	damage: number,
	magic: boolean,
	pierce: boolean,
	-- Those it struck, shared by the projectiles of one fan so it strikes each enemy once.
	struck: { [Instance]: boolean },
	-- Whether it is an M1 shot.
	basic: boolean,
	-- How far round where it stops it bursts, striking everyone there it did not strike yet.
	blast: number?,
}

local states: { [Instance]: State } = {}
local projectiles: { Projectile } = {}
local nextProjectile = 0
local net: Folder
local motionEvent: RemoteEvent
local refusedEvent: RemoteEvent
local projectileEvent: RemoteEvent
local projectileEndEvent: RemoteEvent
local hitEvent: RemoteEvent

local function alive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- How far below and above its pivot each Combatant reaches, measured once.
local reaches: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any

-- The enemies of `team` within `reach` studs of `centre`.
local function enemiesNear(team: string, centre: Vector3, reach: number): { Enemy }
	local found = {}
	for _, foe in HeroKit.foes(team, reaches) do
		local body = foe.body
		if HeroKit.flat(body.position - centre).Magnitude <= reach + body.radius then
			table.insert(found, {
				instance = foe.instance,
				position = body.position,
				radius = body.radius,
				bottom = body.bottom,
				top = body.top,
			})
		end
	end
	return found
end

-- Thornwall's share `amount` of an M1 that `owner`'s hero `victim` took, sent back to the attacker's hero `character`
-- as magic damage.
local function reflect(owner: Instance, victim: Model, character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	amount = math.round(Damage.mitigated(character, amount, true, owner))
	if amount <= 0 then
		return
	end
	local by = if owner:IsA("Player") then owner else nil
	hitEvent:FireAllClients(character, amount, character:GetPivot().Position, by)
	humanoid:TakeDamage(amount)
	ProgressService.hurt(character, owner)
	MinionService.heroAttacked(victim, character)
end

-- `player`'s hit of `amount` (Damage: his items' effects, the target's defence, his lifesteal, wounds and thorns);
-- `basic` when it is an M1 hit.
local function damage(player: Instance, character: Model, enemy: Enemy, amount: number, magic: boolean, basic: boolean?)
	local target = enemy.instance
	amount = Damage.outgoing(player, amount, magic, target, basic)
	local raw = amount
	if target:IsA("Model") and target:GetAttribute("Hero") then
		amount = Damage.mitigated(target, amount, magic, player)
	end
	amount = math.round(amount)
	Damage.leech(player, character, amount)
	hitEvent:FireAllClients(target, amount, enemy.position, if player:IsA("Player") then player else nil)
	if target:IsA("BasePart") then
		MinionService.damage(target, amount, player :: any)
		return
	end
	local model = target :: Model
	-- What a hero did to enemy heroes and Masters, for the match's end (MatchEnd).
	local counter = if model:GetAttribute("Hero")
		then "HeroDamage"
		elseif model:GetAttribute("Master") then "MasterDamage"
		else nil
	if counter then
		player:SetAttribute(counter, (player:GetAttribute(counter) or 0) + amount)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(amount)
		if model:GetAttribute("Hero") then
			ProgressService.hurt(model, player)
			local back = Damage.struck(player, model, raw, basic)
			local owner = Actors.owner(model)
			if back > 0 and owner then
				reflect(owner, model, character, back)
			end
		end
	else
		model:SetAttribute("Health", math.max(0, (model:GetAttribute("Health") or 0) - amount))
	end
	if model:GetAttribute("Hero") or model:GetAttribute("Master") then
		MinionService.heroAttacked(character, model)
	end
end

-- Runs `hit` `delay` seconds from now if the motion it belongs to is still the hero's and the hero still lives.
local function later(state: State, delay: number, hit: () -> ())
	local motion = state.motion
	task.delay(delay, function()
		if state.motion == motion and alive(state.character) then
			hit()
		end
	end)
end

local function slow(state: State, length: number, speed: number)
	local humanoid = state.character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = speed
	local motion = state.motion
	task.delay(length, function()
		if state.motion == motion and humanoid.Parent then
			humanoid.WalkSpeed = Items.walkSpeed(state.actor)
		end
	end)
end

local function strikeCone(
	player: Instance,
	state: State,
	team: string,
	direction: Vector3,
	range: number,
	angle: number,
	amount: number,
	magic: boolean,
	basic: boolean?
)
	local root = rootOf(state.character)
	if not root then
		return
	end
	local origin = HeroKit.muzzle(root.Position)
	for _, enemy in enemiesNear(team, origin, range) do
		if HeroKit.swingStrikes(origin, direction, range, angle, enemy) then
			damage(player, state.character, enemy, amount, magic, basic)
		end
	end
end

-- Sends a projectile from the hero towards `direction`: `shot` gives its Range, ProjectileSpeed, Width and Pierce;
-- `struck` is shared with the other projectiles of its fan; `basic` when it is an M1 shot.
local function launch(
	player: Instance,
	state: State,
	team: string,
	direction: Vector3,
	shot: any,
	amount: number,
	magic: boolean,
	struck: { [Instance]: boolean }?,
	basic: boolean?
)
	local root = rootOf(state.character)
	if not root then
		return
	end
	nextProjectile += 1
	local origin = HeroKit.shotOrigin(HeroKit.muzzle(root.Position), direction)
	local projectile: Projectile = {
		id = nextProjectile,
		player = player,
		character = state.character,
		team = team,
		position = origin,
		direction = direction,
		left = shot.Range,
		speed = shot.ProjectileSpeed,
		width = shot.Width,
		damage = amount,
		magic = magic,
		pierce = shot.Pierce == true,
		struck = struck or {},
		basic = basic == true,
		blast = shot.Blast,
	}
	table.insert(projectiles, projectile)
	projectileEvent:FireAllClients(
		projectile.id,
		state.character,
		origin,
		direction,
		shot.ProjectileSpeed,
		shot.Range,
		shot.OrbScale,
		shot.Blast
	)
end

-- A bursting projectile `p` stopped at `at`: everyone within its blast it has not struck yet is struck.
local function burst(p: Projectile, at: Vector3)
	local reach = p.blast
	if not reach then
		return
	end
	for _, enemy in enemiesNear(p.team, at, reach) do
		if not p.struck[enemy.instance] and HeroKit.burstStrikes(at, reach, enemy) then
			p.struck[enemy.instance] = true
			damage(p.player, p.character, enemy, p.damage, p.magic, p.basic)
		end
	end
end

-- A projectile flies where it was aimed, up or down too, strikes an enemy whose height it passes at, and stops at the
-- first wall or floor in its way.
local walls = RaycastParams.new()
walls.FilterType = Enum.RaycastFilterType.Exclude

local function stepProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	walls.FilterDescendantsInstances = HeroKit.leapIgnore()
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local travel = math.min(p.left, p.speed * dt)
		local from = p.position
		local wall = Workspace:Raycast(from, p.direction * travel, walls)
		local reach = if wall then wall.Distance / travel else 1
		local to = from + p.direction * travel
		local best: Enemy? = nil
		local bestAlong = math.huge
		for _, enemy in enemiesNear(p.team, (from + to) / 2, travel / 2 + p.width) do
			local along = HeroKit.shotTouch(from, to, p.width, enemy)
			if along and along <= reach and not p.struck[enemy.instance] then
				if p.pierce then
					p.struck[enemy.instance] = true
					damage(p.player, p.character, enemy, p.damage, p.magic, p.basic)
				elseif along < bestAlong then
					best, bestAlong = enemy, along
				end
			end
		end
		if best then
			local at = from:Lerp(to, bestAlong)
			p.struck[best.instance] = true
			damage(p.player, p.character, best, p.damage, p.magic, p.basic)
			burst(p, at)
			projectileEndEvent:FireAllClients(p.id, at, true)
			table.remove(projectiles, i)
			continue
		end
		if wall then
			burst(p, wall.Position)
			projectileEndEvent:FireAllClients(p.id, wall.Position, false)
			table.remove(projectiles, i)
			continue
		end
		p.position = to
		p.left -= travel
		if p.left <= 0 then
			burst(p, to)
			projectileEndEvent:FireAllClients(p.id, to, false)
			table.remove(projectiles, i)
		end
	end
end

local function refuse(player: Instance, key: string): (boolean, Vector3?)
	if player:IsA("Player") then
		refusedEvent:FireClient(player, key)
	end
	return false, nil
end

-- `player` (or a bot) attacks with `key` towards `aim`. Whether the attack began, and for a leap or a dash where the
-- hero lands.
local function act(player: Instance, key: string, aim: Vector3): (boolean, Vector3?)
	local state = states[player]
	local character = Actors.character(player)
	if
		not MatchService.fighting()
		or not state
		or not character
		or state.character ~= character
		or not alive(character)
	then
		return refuse(player, key)
	end
	local hero = character:GetAttribute("Hero")
	local settings = hero and Config.Heroes[hero]
	local root = rootOf(character)
	if not settings or not root then
		return refuse(player, key)
	end
	local kit = settings.Kit[key]
	local now = os.clock()
	if
		not kit
		or not Leveling.learned(player :: any, key)
		or now + EARLY < state.busyUntil
		or now + EARLY < (state.cooldowns[key] or 0)
	then
		return refuse(player, key)
	end
	local team = character:GetAttribute("Team") or "Blue"
	-- Round only, for where a dash goes; every swing, shot and throw goes up or down to the crosshair as well.
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	local aimed = HeroKit.aimDirection(HeroKit.muzzle(root.Position), aim, direction)
	local power = Leveling.power(player :: any, key)
	local scales = settings.Scales or "Attack"
	local magic = scales == "Magic"
	-- What a hit of the kit's `base` damage deals: with `ratio` (else the kit's Ratio) of his items' Attack or Magic,
	-- his level and rank.
	local function strength(base: number, ratio: number?): number
		return (base + (ratio or kit.Ratio or 0) * Items.stats(player)[scales]) * power
	end
	-- Where a hit goes as it lands or leaves his hand (HeroKit.follows): where his client last said the crosshair
	-- points, else where a player aimed at the cast, or for a bot where he faces, as high or low as it aimed.
	local function aimedNow(): Vector3
		local body = rootOf(state.character)
		if not body then
			return aimed
		end
		local facing = HeroKit.flat(body.CFrame.LookVector)
		facing = if facing.Magnitude > 0.1 then facing.Unit else direction
		if state.aim then
			return HeroKit.aimDirection(HeroKit.muzzle(body.Position), state.aim, facing)
		end
		if player:IsA("Player") then
			return aimed
		end
		local level = HeroKit.flat(aimed).Magnitude
		return Vector3.new(facing.X * level, aimed.Y, facing.Z * level)
	end
	state.aim = nil
	state.motion += 1

	if kit.Kind == "Combo" then
		local step = if now <= state.comboUntil then state.combo % #kit.Hits + 1 else 1
		local hit = kit.Hits[step]
		local speed = kit.Speed * Items.attackSpeed(player)
		local length = Motion.meta(settings.Pack, hit.Motion).duration / speed
		local eclipse = if state.eclipse then 1 + (Items.effect(player, "Eclipse") or 0) else 1
		state.eclipse = false
		state.combo = step
		state.comboUntil = now + kit.Reset
		state.busyUntil = now + (hit.Hit + (hit.Recover or 0)) / speed + RECOVER
		motionEvent:FireAllClients(character, key, step)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		later(state, hit.Hit / speed, function()
			local amount = strength(hit.Damage) * eclipse
			if hit.ProjectileSpeed then
				launch(player, state, team, aimedNow(), hit, amount, magic, nil, true)
			else
				strikeCone(player, state, team, aimedNow(), hit.Range, hit.Angle, amount, magic, true)
			end
		end)
		return true, nil
	end

	local length = Motion.meta(settings.Pack, kit.Motion).duration
	state.cooldowns[key] = now + Leveling.cooldown(player :: any, key, kit.Cooldown)
	state.comboUntil = 0
	state.eclipse = Items.effect(player, "Eclipse") ~= nil
	if kit.Kind == "Leap" then
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local landing = HeroKit.leapLanding(
			root.Position,
			aim,
			kit.Range,
			humanoid.HipHeight + root.Size.Y / 2,
			HeroKit.leapIgnore()
		)
		state.busyUntil = now + kit.Land + RECOVER
		motionEvent:FireAllClients(character, key, 0, landing)
		slow(state, kit.Land + RECOVER, 0)
		local swings = kit.Swings
		for _, at in if swings then swings.Hits else {} do
			later(state, at, function()
				strikeCone(
					player,
					state,
					team,
					direction,
					swings.Range,
					360,
					strength(swings.Damage, swings.Ratio),
					magic
				)
			end)
		end
		later(state, kit.Land, function()
			for _, enemy in enemiesNear(team, landing, kit.Radius) do
				if HeroKit.landingStrikes(landing, kit.Radius, enemy) then
					damage(player, character, enemy, strength(kit.Damage), magic)
				end
			end
		end)
		return true, landing
	elseif kit.Kind == "Dash" then
		local from = root.Position
		local landing = HeroKit.dashEnd(from, direction, kit.Range, HeroKit.leapIgnore())
		state.busyUntil = now + kit.Move + RECOVER
		motionEvent:FireAllClients(character, key, 0, landing)
		slow(state, kit.Move, 0)
		-- Everyone he passes through is struck once, also those who walk into his way while he dashes: the stretch he
		-- covered since the last look is searched every DASH_STEP seconds, as the client moves him (fast, then slower).
		local struck: { [Instance]: boolean } = {}
		local covered = 0
		local steps = math.ceil((kit.Move - kit.Start) / DASH_STEP)
		for i = 1, steps do
			later(state, kit.Start + (kit.Move - kit.Start) * i / steps, function()
				local x = i / steps
				local reached = 1 - (1 - x) ^ 2
				local a, b = from:Lerp(landing, covered), from:Lerp(landing, reached)
				covered = reached
				if not kit.Damage then
					return
				end
				for _, enemy in enemiesNear(team, a:Lerp(b, 0.5), HeroKit.flat(b - a).Magnitude / 2 + kit.Width) do
					if
						not struck[enemy.instance]
						and HeroKit.segmentDistance(a, b, enemy.position) <= enemy.radius + kit.Width / 2
					then
						struck[enemy.instance] = true
						damage(player, character, enemy, strength(kit.Damage), magic)
					end
				end
			end)
		end
		-- A shot on the way, where the motion (played at the dash's Speed) lets it go, at the crosshair then.
		local shot = kit.Shot
		if shot then
			later(state, shot.Release / (kit.Speed or 1), function()
				launch(player, state, team, aimedNow(), shot, strength(shot.Damage, shot.Ratio), magic)
			end)
		end
		return true, landing
	elseif kit.Kind == "Throw" then
		-- One release (a dagger, a shot) or several in turn (a volley), each sending Count projectiles fanned over
		-- Spread degrees, each where the crosshair points as it goes. A fan strikes each enemy once, however close.
		local releases = HeroKit.releases(kit)
		state.busyUntil = now + releases[#releases] + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		for _, time in releases do
			later(state, time, function()
				local struck = {}
				for _, way in HeroKit.fan(aimedNow(), kit.Count or 1, kit.Spread or 0) do
					launch(player, state, team, way, kit, strength(kit.Damage), magic, struck)
				end
			end)
		end
	elseif kit.Kind == "Ascend" then
		-- He hangs in the air (his client lifts him, a bot BotService) and cannot walk till he stands again.
		state.busyUntil = now + kit.Land + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, kit.Land + RECOVER, 0)
		later(state, kit.Release, function()
			launch(player, state, team, aimedNow(), kit, strength(kit.Damage), magic)
		end)
	elseif kit.Kind == "Flurry" then
		state.busyUntil = now + length
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		for _, time in kit.Hits do
			later(state, time, function()
				-- Every sweep follows the crosshair; the slam strikes all round him, as its shockwave shows.
				local facing = aimedNow()
				local reach, angle, slam = HeroKit.flurryStrike(kit, time)
				local amount = if slam then strength(kit.SlamDamage, kit.SlamRatio) else strength(kit.Damage)
				strikeCone(player, state, team, facing, reach, angle, amount, magic)
			end)
		end
	end
	return true, nil
end

CombatService.act = act

-- Starts keeping the attacks of `player`'s (or a bot's) hero `character`.
function CombatService.track(player: Instance, character: Model)
	states[player] = {
		actor = player,
		character = character,
		busyUntil = 0,
		combo = 0,
		comboUntil = 0,
		cooldowns = {},
		motion = 0,
		eclipse = false,
	}
end

function CombatService.forget(player: Instance)
	states[player] = nil
end

-- Whether `player`'s hero is free to use `key` now: learned, not in a motion, and off its cooldown.
function CombatService.ready(player: Instance, key: string): boolean
	local state = states[player]
	local now = os.clock()
	return state ~= nil
		and Leveling.learned(player :: any, key)
		and now >= state.busyUntil
		and now >= (state.cooldowns[key] or 0)
end

-- Points a bot's attack under way at `aim`, as a player's client does with "Aim"; false once no attack plays.
function CombatService.aim(actor: Instance, aim: Vector3): boolean
	local state = states[actor]
	if not state or os.clock() >= state.busyUntil then
		return false
	end
	state.aim = aim
	return true
end

function CombatService.start()
	net = ReplicatedStorage:WaitForChild("Net") :: Folder
	local function remote(name: string): RemoteEvent
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = net
		return event
	end
	local actionEvent = remote("HeroAction")
	motionEvent = remote("HeroMotion")
	refusedEvent = remote("HeroRefused")
	projectileEvent = remote("HeroProjectile")
	projectileEndEvent = remote("HeroProjectileEnd")
	hitEvent = remote("HeroHit")

	actionEvent.OnServerEvent:Connect(function(player, key, aim)
		if typeof(aim) ~= "Vector3" or aim ~= aim then
			return
		end
		if key == "Aim" then
			local state = states[player]
			if state and os.clock() < state.busyUntil then
				state.aim = aim
			end
			return
		end
		if typeof(key) ~= "string" or not KEYS[key] then
			return
		end
		act(player, key, aim)
	end)

	local function track(player: Player)
		local function added(character: Model)
			CombatService.track(player, character)
		end
		player.CharacterAdded:Connect(added)
		if player.Character then
			added(player.Character)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	RunService.Heartbeat:Connect(stepProjectiles)
end

return CombatService
