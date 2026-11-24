-- The heroes' attacks (Config.Heroes[hero].Kit). A client asks for an attack through ReplicatedStorage.Net.HeroAction
-- (key, a point far along where he looks; while an attack plays, "Aim" and where he looks now, and through a Snipe's
-- scope "Fire" as he clicks); the server
-- checks the hero can (alive, not mid-motion, off cooldown), tells every client to play the motion (Net.HeroMotion:
-- character, key, combo step, landing spot) and lands each hit at its time in the motion on the enemies there: the
-- other team's minions and Combatants (heroes, Masters). A refused attack is sent back to its client
-- (Net.HeroRefused), which stops the motion it already began. Thrown daggers and shot arrows fly on the server
-- (Net.HeroProjectile: id, origin, direction, speed, range, its size and blast; Net.HeroProjectileEnd: id, where it
-- stopped, hit or not); a Snipe's bullet on a hero asks its shooter's client about the head first (Net.HeroHeadCheck,
-- Net.HeroHeadshot); one stops at the first enemy in its way, a piercing one strikes everyone it passes once, and
-- every one at the first wall or floor; one with a blast then bursts there over everyone round it. Every swing, shot and throw of every hero goes where the crosshair points, upwards and
-- downwards as well, to the point under it (HeroKit.aimDirection, owner 2026-10-29), and strikes an enemy only at the heights his body
-- reaches; a leap lands on the spot aimed at and a dash keeps to the ground.
-- Every hit is told to the clients for its feedback (Net.HeroHit: target, damage, where, the striking player). Bots
-- (Actors, BotService) attack through CombatService.act, with the same checks; they move through their leaps and
-- dashes on the server (CombatService.act gives where they land), as a player's client moves him.

local Debris = game:GetService("Debris")
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
local EmoteService = require(script.Parent.EmoteService)
local MatchService = require(script.Parent.MatchService)
local MinionService = require(script.Parent.MinionService)
local ProgressService = require(script.Parent.ProgressService)
local TraceService = require(script.Parent.TraceService)

local CombatService = {}

local KEYS = { M1 = true, M2 = true, E = true, R = true, Dash = true }
-- After a hit lands, the next swing or ability may start this much later.
local RECOVER = 0.12
-- A command may come this much before the hero is free, as the network does not deliver at an even pace.
local EARLY = 0.12
local DASH_STEP = 0.03
-- How often a Strike's rolling weapons (its Roll) strike those they reach on their way.
local ROLL_STEP = 0.05

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
	-- A Snipe he aims now: from when he may fire (Net.HeroAction "Fire"), and what fires it.
	snipe: { ready: number, fire: () -> () }?,
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
	-- How many times as hard it strikes a hero's head (a Snipe's bullet).
	headshot: number?,
	-- Where it was let go.
	origin: Vector3,
	-- A seeking shot's (a Throw's Seek) enemy, or the point it goes to without one, and how fast it turns (radians a
	-- second).
	seek: Instance? | Vector3?,
	turn: number?,
	-- Seconds it hangs where it splits before it flies.
	wait: number?,
	-- Whether it flies on through the ground, walls and everything else (its hero's Projectile.ThroughAll).
	through: boolean?,
	-- A weapon that flies itself back into the hand (its shot's `Back`): the share of its damage it strikes with on
	-- the way back, from where and since when it is on its way back, the enemies it touches now, and those it touched
	-- as it turned, struck on the way back only once it has left them.
	back: number?,
	-- A seeking one with a `Back` turns back as far as its Range from where it left once it no longer seeks an enemy
	-- (it struck it, or there was none), as one that flies straight does at the end of its reach.
	reach: number?,
	-- The enemy a seeking one was sent at: on its way out it strikes no one else, also when it flies on through him
	-- (owner, 2026-11-15), unless he is gone before it gets there.
	sought: Instance?,
	returning: { from: Vector3, started: number }?,
	touching: { [Instance]: boolean },
	blocked: { [Instance]: boolean },
}

-- A Snipe's bullet that struck a hero, held till its shooter's client says whether it went through the head as that
-- client draws him (Net.HeroHeadCheck), or as long as HEAD_WAIT_MIN to HEAD_WAIT_MAX: the server never sees the heroes' animations, which play on
-- the clients only (Motion), so his head stands up to 1.5 studs higher and 2.6 aside of where it is seen (measured in a
-- match, 2026-11-04). His client is believed only for a hit the server found too, within HEAD_SLACK studs of where the
-- server has the head (the bullet's line, his whole way through the hero).
type HeadCheck = {
	player: Player,
	character: Model,
	enemy: Enemy,
	damage: number,
	magic: boolean,
	headshot: number,
	from: Vector3,
	to: Vector3,
}
local HEAD_SLACK = 3
-- How long it waits for his client, by his ping (there and back, and a frame to draw).
local HEAD_WAIT_MIN, HEAD_WAIT_MAX = 0.3, 1

local states: { [Instance]: State } = {}
local projectiles: { Projectile } = {}
local headChecks: { [number]: HeadCheck } = {}
local nextProjectile = 0
local net: Folder
local motionEvent: RemoteEvent
local refusedEvent: RemoteEvent
local projectileEvent: RemoteEvent
local projectileEndEvent: RemoteEvent
local hitEvent: RemoteEvent
local headCheckEvent: RemoteEvent
local headshotEvent: RemoteEvent
local knockEvent: RemoteEvent

-- Carries a knocked bot (BotService.start sets it), as a knocked player's client carries him.
CombatService.carryBot = nil :: ((actor: Instance, to: Vector3, height: number, length: number) -> ())?

local function alive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function rootOf(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- How far below and above its pivot each Combatant reaches, measured once.
local reaches: { [Model]: { number } } = setmetatable({}, { __mode = "k" }) :: any

-- The enemies of `team` within `reach` studs of `centre`. A vanished hero ("Hidden") is not among them: nothing
-- strikes him, and shots fly through him (owner, 2026-11-01).
local function enemiesNear(team: string, centre: Vector3, reach: number): { Enemy }
	local found = {}
	for _, foe in HeroKit.foes(team, reaches) do
		local body = foe.body
		if
			not foe.instance:GetAttribute("Hidden")
			and HeroKit.flat(body.position - centre).Magnitude <= reach + body.radius
		then
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

-- The part an enemy hero or minion stands on the ground by (a minion is its root).
local function partOf(target: Instance): BasePart?
	return if target:IsA("BasePart") then target elseif target:IsA("Model") then rootOf(target) else nil
end

-- Carries the enemy hero or minion `target` from where it is to `to` (over the ground), in an arc `height` studs high,
-- in `length` seconds. A player's own client carries him (Net.HeroKnock, HeroControls), BotService a bot,
-- MinionService a minion; the Masters stand fast.
local function carry(target: Instance, to: Vector3, height: number, length: number)
	if target:IsA("BasePart") then
		MinionService.knock(target, to, height, length)
		return
	end
	if not target:GetAttribute("Hero") or not alive(target :: Model) then
		return
	end
	local owner = Actors.owner(target :: Model)
	if owner and owner:IsA("Player") then
		knockEvent:FireClient(owner, to, height, length)
	elseif owner and CombatService.carryBot then
		CombatService.carryBot(owner, to, height, length)
	end
end

-- A kit's `Knockback` throws the enemy hero or minion struck by `character` away from him (or from `centre`, where
-- his strike fell): `Distance` studs over the ground (less where a wall stops it), in an arc `Height` studs high, in
-- `Time` seconds.
local function knock(character: Model, enemy: Enemy, knockback: any, centre: Vector3?)
	local from = partOf(enemy.instance)
	local by = rootOf(character)
	if not from or not by then
		return
	end
	local away = HeroKit.flat(from.Position - (centre or by.Position))
	away = if away.Magnitude > 0.1 then away.Unit else HeroKit.flat(by.CFrame.LookVector).Unit
	carry(
		enemy.instance,
		HeroKit.dashEnd(from.Position, away, knockback.Distance, HeroKit.leapIgnore()),
		knockback.Height,
		knockback.Time
	)
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

-- A kit's `Guard` braces the hero `character`: he takes `guard.Share` less damage for `guard.Time` seconds
-- (Damage.mitigated reads "Guard" and "GuardUntil"), a stronger brace outlasting a weaker one, with an iron sheen
-- round him meanwhile. The sheen stands beside him, not in him, as what is put in a hero makes Roblox fit his layered
-- clothing again.
local sheens: { [Model]: Highlight } = {}
local sheenFolder: Folder? = nil

local function brace(character: Model, guard: any)
	local now = os.clock()
	local active = (character:GetAttribute("GuardUntil") or 0) > now
	local share = if active then math.max(character:GetAttribute("Guard") or 0, guard.Share) else guard.Share
	local ends = math.max(if active then character:GetAttribute("GuardUntil") else 0, now + guard.Time)
	character:SetAttribute("Guard", share)
	character:SetAttribute("GuardUntil", ends)
	if not sheens[character] then
		if not sheenFolder or not sheenFolder.Parent then
			local folder = Instance.new("Folder")
			folder.Name = "GuardSheens"
			folder.Parent = Workspace
			sheenFolder = folder
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "Guard"
		highlight.FillColor = Color3.fromRGB(205, 210, 220)
		highlight.FillTransparency = 0.8
		highlight.OutlineColor = Color3.fromRGB(255, 214, 110)
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = character
		highlight.Parent = sheenFolder
		sheens[character] = highlight
		character.Destroying:Once(function()
			if sheens[character] == highlight then
				sheens[character] = nil
			end
			highlight:Destroy()
		end)
	end
	task.delay(ends - now, function()
		if (character:GetAttribute("GuardUntil") or 0) <= os.clock() then
			character:SetAttribute("Guard", nil)
			character:SetAttribute("GuardUntil", nil)
			local left = sheens[character]
			if left then
				sheens[character] = nil
				left:Destroy()
			end
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
	basic: boolean?,
	knockback: any?
)
	local root = rootOf(state.character)
	if not root then
		return
	end
	local origin = HeroKit.muzzle(root.Position)
	for _, enemy in enemiesNear(team, origin, range) do
		if HeroKit.swingStrikes(origin, direction, range, angle, enemy) then
			damage(player, state.character, enemy, amount, magic, basic)
			if knockback then
				knock(state.character, enemy, knockback)
			end
		end
	end
end

-- Walls and floors, which stop projectiles and stand between a seeking shot and an enemy.
local walls = RaycastParams.new()
walls.FilterType = Enum.RaycastFilterType.Exclude

-- How much farther than its Range a seeking shot flies, for its turns.
local SEEK_REACH = 1.5
-- Sends a projectile from the hero towards `direction`: `shot` gives its Range, ProjectileSpeed, Width, Pierce and Back;
-- `struck` is shared with the other projectiles of its fan; `basic` when it is an M1 shot. A seeking one (`shot.Seek`)
-- turns on its way towards `seek`, an enemy or a point, and flies SEEK_REACH times as far.
local function launch(
	player: Instance,
	state: State,
	team: string,
	direction: Vector3,
	shot: any,
	amount: number,
	magic: boolean,
	struck: { [Instance]: boolean }?,
	basic: boolean?,
	seek: (Instance | Vector3)?,
	side: number?
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
		left = if shot.Seek then shot.Range * SEEK_REACH else shot.Range,
		speed = shot.ProjectileSpeed,
		width = shot.Width,
		damage = amount,
		magic = magic,
		pierce = shot.Pierce == true,
		struck = struck or {},
		basic = basic == true,
		blast = shot.Blast,
		headshot = shot.Headshot,
		origin = origin,
		seek = if shot.Seek then seek else nil,
		turn = if shot.Seek then shot.Seek.Turn else nil,
		wait = if shot.Seek then shot.Seek.Split else nil,
		through = HeroKit.throughAll(state.character),
		back = shot.Back,
		reach = if shot.Seek and shot.Back then shot.Range else nil,
		sought = if shot.Seek and typeof(seek) == "Instance" then seek else nil,
		touching = {},
		blocked = {},
	}
	table.insert(projectiles, projectile)
	projectileEvent:FireAllClients(
		projectile.id,
		state.character,
		origin,
		direction,
		shot.ProjectileSpeed,
		projectile.left,
		shot.OrbScale,
		shot.Blast,
		projectile.seek,
		projectile.turn,
		projectile.wait,
		side
	)
end

-- Where a seeking projectile `p` goes now: its enemy's middle while that is there and alive, else its point till it
-- is nearly there; nil when it flies on straight.
local function seekPoint(p: Projectile): Vector3?
	local seek = p.seek
	if typeof(seek) == "Vector3" then
		if (seek - p.position).Magnitude < 1.5 then
			p.seek = nil
			return nil
		end
		return seek
	elseif typeof(seek) == "Instance" then
		local body = partOf(seek)
		if not body or not body:IsDescendantOf(Workspace) or (seek:IsA("Model") and not alive(seek)) then
			p.seek, p.sought = nil, nil
			return nil
		end
		return body.Position
	end
	return nil
end

-- The enemies a Throw's Seek (`kit`) can go at from `origin`, nearest first: within its Range and its Seek's Angle
-- (degrees across) of `facing`, round, with no wall between unless they fly `through` walls.
local function seekTargets(team: string, origin: Vector3, facing: Vector3, kit: any, through: boolean): { Instance }
	walls.FilterDescendantsInstances = HeroKit.leapIgnore()
	local found = {}
	for _, enemy in enemiesNear(team, origin, kit.Range) do
		local offset = HeroKit.flat(enemy.position - origin)
		local ahead = offset.Magnitude < 1
			or math.deg(math.acos(math.clamp(offset.Unit:Dot(facing), -1, 1))) <= kit.Seek.Angle / 2
		if ahead and (through or not Workspace:Raycast(origin, enemy.position - origin, walls)) then
			table.insert(found, { instance = enemy.instance, distance = offset.Magnitude })
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local targets = {}
	for i, t in found do
		targets[i] = t.instance
	end
	return targets
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

-- The Snipe's bullet `id` held in headChecks strikes, on the head when `head`; its shooter sees HEADSHOT.
local function settleHead(id: number, head: boolean)
	local check = headChecks[id]
	if not check then
		return
	end
	headChecks[id] = nil
	local target = check.enemy.instance
	TraceService.mark("snipe.hit", { hero = target:GetAttribute("Hero") or target.Name, head = head }, check.player)
	if not alive(target :: Model) then
		return
	end
	damage(
		check.player,
		check.character,
		check.enemy,
		if head then check.damage * check.headshot else check.damage,
		check.magic
	)
	if head then
		headshotEvent:FireClient(check.player)
	end
end

-- His client's word that the bullet `id` went through the head as it draws him (Net.HeroHeadCheck), believed when
-- the server's head is within HEAD_SLACK studs of the bullet's line.
local function claimHead(player: Player, id: unknown)
	local check = if type(id) == "number" then headChecks[id] else nil
	if not check or check.player ~= player then
		return
	end
	local head = check.enemy.instance:FindFirstChild("Head")
	local near = false
	if head and head:IsA("BasePart") then
		local way = check.to - check.from
		local along = math.clamp((head.Position - check.from):Dot(way) / way:Dot(way), 0, 1)
		near = (check.from + way * along - head.Position).Magnitude <= HEAD_SLACK
	end
	settleHead(id :: number, near)
end

-- A projectile `p` with a `Back` that stopped at `at` turns back for its hero's hand, striking with its share of its
-- damage everyone on the way back, once each.
local function turnBack(p: Projectile, at: Vector3)
	p.returning = { from = at, started = os.clock() }
	p.position = at
	p.damage *= p.back :: number
	p.struck = {}
	p.blocked = table.clone(p.touching)
end

-- A projectile `p` on its way back flies straight at its hero's hand, as fast as his clients draw it
-- (HeroKit.RETURN_SPEED) and through walls, and strikes everyone it touches whom it has not struck on the way back,
-- but not those it was still in as it turned until it has left them (owner, 2026-11-15). Whether it is back.
local function stepBack(p: Projectile): boolean
	local root = rootOf(p.character)
	if not root or not alive(p.character) then
		return true
	end
	local back = p.returning :: { from: Vector3, started: number }
	local way = HeroKit.muzzle(root.Position) - back.from
	local gone = (os.clock() - back.started) * p.speed * HeroKit.RETURN_SPEED
	local done = gone >= way.Magnitude
	local from = p.position
	local to = if done then back.from + way else back.from + way.Unit * gone
	local touched = {}
	for _, enemy in enemiesNear(p.team, (from + to) / 2, (to - from).Magnitude / 2 + p.width) do
		if HeroKit.shotTouch(from, to, p.width, enemy) then
			touched[enemy.instance] = true
			if not p.struck[enemy.instance] and not p.blocked[enemy.instance] then
				p.struck[enemy.instance] = true
				damage(p.player, p.character, enemy, p.damage, p.magic, p.basic)
			end
		end
	end
	for instance in p.blocked do
		if not touched[instance] then
			p.blocked[instance] = nil
		end
	end
	p.position = to
	return done
end

-- A projectile flies where it was aimed, up or down too (a seeking one turning towards its enemy), strikes an enemy
-- whose height it passes at, and stops at the first wall or floor in its way (or with a `Back` turns back there).
local function stepProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	walls.FilterDescendantsInstances = HeroKit.leapIgnore()
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		-- Seeking shots hang a moment where they split from his globe before they fly (HeroControls draws the split).
		if p.wait and p.wait > 0 then
			p.wait -= dt
			continue
		end
		if p.returning then
			if stepBack(p) then
				table.remove(projectiles, i)
			end
			continue
		end
		local point = if p.seek then seekPoint(p) else nil
		if point then
			p.direction = HeroKit.seek(p.direction, p.position, point, p.turn or 0, dt)
		end
		local travel = math.min(p.left, p.speed * dt)
		local from = p.position
		local wall = if p.through then nil else Workspace:Raycast(from, p.direction * travel, walls)
		local reach = if wall then wall.Distance / travel else 1
		local to = from + p.direction * travel
		local best: Enemy? = nil
		local bestAlong = math.huge
		local touched = {}
		for _, enemy in enemiesNear(p.team, (from + to) / 2, travel / 2 + p.width) do
			local along = HeroKit.shotTouch(from, to, p.width, enemy)
			if along and along <= reach then
				touched[enemy.instance] = true
				if p.struck[enemy.instance] or (p.sought and p.sought ~= enemy.instance) then
					continue
				elseif p.pierce then
					p.struck[enemy.instance] = true
					damage(p.player, p.character, enemy, p.damage, p.magic, p.basic)
					-- Through the enemy it sought it flies on straight, out to its reach however far its turns took it.
					if p.seek == enemy.instance then
						p.seek = nil
						if p.reach then
							p.left = math.max(p.left, p.reach)
						end
					end
				elseif along < bestAlong then
					best, bestAlong = enemy, along
				end
			end
		end
		p.touching = touched
		if best then
			local at = from:Lerp(to, bestAlong)
			p.struck[best.instance] = true
			local onHero = p.headshot ~= nil
				and best.instance:IsA("Model")
				and best.instance:GetAttribute("Hero") ~= nil
			local shooter = p.player
			if onHero and shooter:IsA("Player") then
				headChecks[p.id] = {
					player = shooter,
					character = p.character,
					enemy = best,
					damage = p.damage,
					magic = p.magic,
					headshot = p.headshot :: number,
					from = p.origin,
					-- On beyond him, so the line goes through the whole of him.
					to = at + p.direction * (best.radius + p.width) * 2,
				}
				local check = headChecks[p.id]
				headCheckEvent:FireClient(shooter, p.id, best.instance, check.from, check.to)
				local id = p.id
				task.delay(math.clamp(shooter:GetNetworkPing() * 3 + 0.2, HEAD_WAIT_MIN, HEAD_WAIT_MAX), function()
					settleHead(id, false)
				end)
			else
				-- A bot's bullet goes by the head where the server has it: no client draws for him.
				local head = best.instance:FindFirstChild("Head")
				local through = (best.radius + p.width) * 2
				local onHead = onHero
					and head ~= nil
					and head:IsA("BasePart")
					and HeroKit.headshot(at - p.direction * through, at + p.direction * through, head :: BasePart)
				damage(
					p.player,
					p.character,
					best,
					if onHead then p.damage * (p.headshot :: number) else p.damage,
					p.magic,
					p.basic
				)
			end
			burst(p, at)
			projectileEndEvent:FireAllClients(p.id, at, true)
			table.remove(projectiles, i)
			continue
		end
		if wall then
			burst(p, wall.Position)
			projectileEndEvent:FireAllClients(p.id, wall.Position, false)
			if p.back then
				turnBack(p, wall.Position)
			else
				table.remove(projectiles, i)
			end
			continue
		end
		p.position = to
		p.left -= travel
		local reached = p.reach ~= nil
			and typeof(p.seek) ~= "Instance"
			and (to - p.origin).Magnitude >= p.reach :: number
		if p.left <= 0 or reached then
			burst(p, to)
			projectileEndEvent:FireAllClients(p.id, to, false)
			if p.back then
				turnBack(p, to)
			else
				table.remove(projectiles, i)
			end
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
	EmoteService.stop(character)
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
	-- Attacking shows a vanished hero again.
	character:SetAttribute("Hidden", nil)

	if kit.Kind == "Combo" then
		local following = now <= state.comboUntil
		local step = if following then state.combo % #kit.Hits + 1 else 1
		local hit = kit.Hits[step]
		-- A hit may play faster or slower than the rest of the combo (its own Speed).
		local speed = kit.Speed * (hit.Speed or 1) * Items.attackSpeed(player)
		-- Following on, it may start part-way into its clip (the kit's `Follow`, the weapon still up); the first is
		-- held back as long, so the hits keep their pace. A hit cut out of one clip with the others plays its part.
		local start, stop, cut = HeroKit.comboPart(kit, hit, following, Motion.meta(settings.Pack, hit.Motion).duration)
		local length = (stop - start) / speed
		local eclipse = if state.eclipse then 1 + (Items.effect(player, "Eclipse") or 0) else 1
		state.eclipse = false
		state.combo = step
		state.comboUntil = now + kit.Reset - (if cut then 0 else start) / speed
		state.busyUntil = now
			+ (hit.Hit + (hit.Recover or 0) + (if cut then 0 else kit.Follow or 0) - start) / speed
			+ RECOVER
		motionEvent:FireAllClients(character, key, step, nil, start)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		later(state, (hit.Hit - start) / speed, function()
			local amount = strength(hit.Damage) * eclipse
			if hit.ProjectileSpeed and (hit.Count or 1) > 1 then
				-- Count shots fanned over Spread degrees, one out of each hand, striking each enemy once.
				local fan = HeroKit.fan(aimedNow(), hit.Count, hit.Spread or 0)
				local struck = {}
				for i, way in fan do
					launch(
						player,
						state,
						team,
						way,
						hit,
						amount,
						magic,
						struck,
						true,
						nil,
						1 - 2 * (i - 1) / (#fan - 1)
					)
				end
			elseif hit.ProjectileSpeed then
				-- Out of the hand on its `Side` (1 his right, -1 his left) when he holds a weapon in each.
				launch(player, state, team, aimedNow(), hit, amount, magic, nil, true, nil, hit.Side)
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
		-- Swings that come well after he lands hold him till then (`Busy`).
		state.busyUntil = now + (kit.Busy or kit.Land) + RECOVER
		motionEvent:FireAllClients(character, key, 0, landing)
		slow(state, (kit.Busy or kit.Land) + RECOVER, 0)
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
			for _, enemy in if kit.Damage then enemiesNear(team, landing, kit.Radius) else {} do
				if HeroKit.landingStrikes(landing, kit.Radius, enemy) then
					damage(player, character, enemy, strength(kit.Damage), magic)
				end
			end
			if kit.Guard then
				brace(character, kit.Guard)
			end
		end)
		return true, landing
	elseif kit.Kind == "Dash" then
		local from = root.Position
		if kit.Grounded then
			local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
			from = HeroKit.grounded(from, humanoid.HipHeight + root.Size.Y / 2, HeroKit.leapIgnore())
		end
		local landing = HeroKit.dashEnd(from, direction, kit.Range, HeroKit.leapIgnore())
		-- A dash whose blow comes well after it stops (its Slash) holds him till then (`Busy`).
		state.busyUntil = now + (kit.Busy or kit.Move) + RECOVER
		motionEvent:FireAllClients(character, key, 0, landing)
		slow(state, kit.Busy or kit.Move, 0)
		-- Everyone he passes through is struck once, also those who walk into his way while he dashes: the stretch he
		-- covered since the last look is searched every DASH_STEP seconds, as the client moves him (fast, then slower).
		local struck: { [Instance]: boolean } = {}
		-- With a Slash those he passed take the blow only when his weapon strikes, at its time in the motion.
		local slashed: { Enemy } = {}
		-- With a Carry those he runs into are held against his front, `Ahead` studs past their own size before his
		-- middle, till his weapon strikes (its Time in the motion): then all take the blow at once, and its
		-- Knockback. A "Held" ObjectValue in each says by whom (HeroKit.heldAt): every client draws a minion there
		-- (MinionView), a player's client holds his hero there (HeroControls), BotService a bot, MinionService the
		-- minion itself; the Masters stand fast.
		local hold = kit.Carry
		local strikes = if hold then hold.Time / (kit.Speed or 1) else math.huge
		local carried: { { enemy: Enemy, tag: ObjectValue } } = {}
		local struckAll = false
		local function strike(enemy: Enemy)
			damage(player, character, enemy, strength(kit.Damage), magic)
			if kit.Knockback then
				knock(character, enemy, kit.Knockback)
			end
		end
		local function grab(enemy: Enemy, at: Vector3)
			local target = enemy.instance
			if target:IsA("Model") and not target:GetAttribute("Hero") then
				strike(enemy)
				return
			end
			local side = HeroKit.flat(enemy.position - at):Dot(direction:Cross(Vector3.yAxis))
			local tag = Instance.new("ObjectValue")
			tag.Name = "Held"
			tag.Value = character
			tag:SetAttribute("Ahead", hold.Ahead + enemy.radius)
			tag:SetAttribute("Side", math.clamp(side, -kit.Width / 2, kit.Width / 2))
			tag.Parent = target
			-- Let go of also when the charge is cut short.
			Debris:AddItem(tag, strikes)
			table.insert(carried, { enemy = enemy, tag = tag })
		end
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
					-- A charge that carries takes only those before him in his way, not who stands behind or beside him.
					local before = not hold or HeroKit.flat(enemy.position - a):Dot(direction) >= 0
					if
						before
						and not struck[enemy.instance]
						and HeroKit.segmentDistance(a, b, enemy.position) <= enemy.radius + kit.Width / 2
					then
						struck[enemy.instance] = true
						if hold and not struckAll then
							grab(enemy, b)
						elseif kit.Slash then
							table.insert(slashed, enemy)
						else
							strike(enemy)
						end
					end
				end
			end)
		end
		if hold and kit.Damage then
			later(state, strikes, function()
				struckAll = true
				for _, held in carried do
					held.tag:Destroy()
					if held.enemy.instance.Parent then
						strike(held.enemy)
					end
				end
			end)
		end
		local slash = kit.Slash
		if slash and kit.Damage then
			later(state, slash.Time / (kit.Speed or 1), function()
				for _, enemy in enemiesNear(team, landing, slash.Range) do
					if not struck[enemy.instance] then
						struck[enemy.instance] = true
						table.insert(slashed, enemy)
					end
				end
				for _, enemy in slashed do
					if enemy.instance.Parent then
						damage(player, character, enemy, strength(kit.Damage), magic)
						if kit.Knockback then
							knock(character, enemy, kit.Knockback)
						end
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
		-- Spread degrees, each where the crosshair points as it goes (turned by its Turns where his weapon swings
		-- across). A fan strikes each enemy once, however close.
		local releases = HeroKit.releases(kit)
		state.busyUntil = now + releases[#releases] + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		for n, time in releases do
			later(state, time, function()
				local way = HeroKit.turned(kit, n, aimedNow())
				local fan = HeroKit.fan(way, kit.Count or 1, kit.Spread or 0)
				if kit.Seek then
					-- Each at an enemy it can reach (HeroKit.seekShare), each striking for itself, or all to the
					-- crosshair, as far as they reach.
					local body = rootOf(state.character)
					local muzzle = HeroKit.muzzle(if body then body.Position else root.Position)
					local facing = HeroKit.flat(way)
					facing = if facing.Magnitude > 0.1 then facing.Unit else HeroKit.flat(root.CFrame.LookVector).Unit
					local share = HeroKit.seekShare(
						seekTargets(team, muzzle, facing, kit, HeroKit.throughAll(state.character)),
						#fan
					)
					local far = if state.aim
						then math.clamp((state.aim - muzzle).Magnitude, 6, kit.Range)
						else kit.Range
					for i, shot in fan do
						local seek: (Instance | Vector3)? = share[i] or muzzle + way * far
						-- Where in the fan it splits to: 1 on his right (the fan's first), -1 on his left.
						local side = if #fan > 1 then 1 - 2 * (i - 1) / (#fan - 1) else 0
						launch(player, state, team, shot, kit, strength(kit.Damage), magic, nil, nil, seek, side)
					end
					return
				end
				local struck = {}
				for i, shot in fan do
					local side = if #fan > 1 then 1 - 2 * (i - 1) / (#fan - 1) else 0
					launch(player, state, team, shot, kit, strength(kit.Damage), magic, struck, nil, nil, side)
				end
			end)
		end
	elseif kit.Kind == "Strike" then
		-- He stays where he stands and calls strikes down on the spot aimed at as he cast it, which only strike
		-- there, at their times; his motion itself strikes no one. Not given back as a landing: he does not go there.
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local spot = HeroKit.leapLanding(
			root.Position,
			aim,
			kit.Range,
			humanoid.HipHeight + root.Size.Y / 2,
			HeroKit.leapIgnore()
		)
		local last = kit.Busy or kit.Strikes[#kit.Strikes]
		state.busyUntil = now + last + RECOVER
		motionEvent:FireAllClients(character, key, 0, spot)
		slow(state, last + RECOVER, 0)
		local roll = kit.Roll
		if roll then
			-- Its weapons roll through the ground from his feet to the spot from `Release` to the first strike,
			-- `Gap` studs apart, striking once for `Damage` everyone they roll through (within `Width` of either).
			local way = HeroKit.flat(spot - root.Position)
			local toward = if way.Magnitude > 0.5 then way.Unit else HeroKit.flat(root.CFrame.LookVector).Unit
			local aside = Vector3.new(-toward.Z, 0, toward.X) * roll.Gap / 2
			local from = root.Position + toward * 2.5
			local rolled = {}
			local rolling = kit.Strikes[1] - roll.Release
			for at = roll.Release, kit.Strikes[1] - 1e-3, ROLL_STEP do
				later(state, at, function()
					local f = math.clamp((at + ROLL_STEP - roll.Release) / rolling, 0, 1)
					local centre = from:Lerp(spot, f)
					for _, lane in { centre + aside, centre - aside } do
						for _, enemy in enemiesNear(team, lane, roll.Width) do
							if not rolled[enemy.instance] and HeroKit.landingStrikes(lane, roll.Width, enemy) then
								rolled[enemy.instance] = true
								damage(player, character, enemy, strength(roll.Damage, roll.Ratio), magic)
							end
						end
					end
				end)
			end
		end
		for i, at in kit.Strikes do
			later(state, at, function()
				for _, enemy in enemiesNear(team, spot, kit.Radius) do
					if HeroKit.landingStrikes(spot, kit.Radius, enemy) then
						damage(player, character, enemy, strength(kit.Damage), magic)
						if i == 1 and kit.Knockback then
							knock(character, enemy, kit.Knockback, spot)
						end
					end
				end
			end)
		end
	elseif kit.Kind == "Rain" then
		-- He hangs in the air (his client lifts him, a bot BotService) while beams rain on the spot aimed at as he cast
		-- it, striking everyone within Radius of it at every Every from From to To.
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local spot = HeroKit.leapLanding(
			root.Position,
			aim,
			kit.Range,
			humanoid.HipHeight + root.Size.Y / 2,
			HeroKit.leapIgnore()
		)
		state.busyUntil = now + kit.Land + RECOVER
		motionEvent:FireAllClients(character, key, 0, spot)
		slow(state, kit.Land + RECOVER, 0)
		for at = kit.From, kit.To + 1e-3, kit.Every do
			later(state, at, function()
				for _, enemy in enemiesNear(team, spot, kit.Radius) do
					if HeroKit.landingStrikes(spot, kit.Radius, enemy) then
						damage(player, character, enemy, strength(kit.Damage), magic)
					end
				end
			end)
		end
		return true, nil
	elseif kit.Kind == "Vanish" then
		state.busyUntil = now + kit.Cast + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		character:SetAttribute("Hidden", true)
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = 0
		later(state, kit.Cast, function()
			humanoid.WalkSpeed = Items.walkSpeed(player) * (kit.Haste or 1)
		end)
		-- His next attack slows him as it plays and gives him his own speed back.
		local motion = state.motion
		task.delay(kit.Duration, function()
			if state.motion == motion then
				character:SetAttribute("Hidden", nil)
				humanoid.WalkSpeed = Items.walkSpeed(player)
			end
		end)
	elseif kit.Kind == "Fury" then
		-- He stands while he works himself up; slow gives him his faster speed afterwards. His items' speed-up of the
		-- M1 for every client ("AttackSpeed") takes the fury's in and out with it.
		state.busyUntil = now + kit.Cast + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, kit.Cast, 0)
		player:SetAttribute("FuryHaste", kit.Haste)
		player:SetAttribute("FuryAttack", kit.AttackSpeed)
		player:SetAttribute("FuryPower", kit.Power)
		character:SetAttribute("Fury", true)
		character:SetAttribute("AttackSpeed", Items.attackSpeed(player))
		task.delay(kit.Duration, function()
			if not character:GetAttribute("Fury") then
				return
			end
			character:SetAttribute("Fury", nil)
			-- Dead and back meanwhile, he is out of it already (HeroService.prepare).
			if Actors.character(player) ~= character then
				return
			end
			player:SetAttribute("FuryHaste", nil)
			player:SetAttribute("FuryAttack", nil)
			player:SetAttribute("FuryPower", nil)
			character:SetAttribute("AttackSpeed", Items.attackSpeed(player))
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed >= Config.Combat.WalkSpeed then
				humanoid.WalkSpeed = Items.walkSpeed(player)
			end
		end)
	elseif kit.Kind == "Ascend" then
		-- He hangs in the air (his client lifts him, a bot BotService) and cannot walk till he stands again.
		state.busyUntil = now + kit.Land + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, kit.Land + RECOVER, 0)
		later(state, kit.Release, function()
			launch(player, state, team, aimedNow(), kit, strength(kit.Damage), magic)
		end)
	elseif kit.Kind == "Snipe" then
		-- He looks through his rifle's scope (his client), slowed, while everyone else sees where he aims (his "Scope"
		-- attribute, Scope); from Ready he may fire (Net.HeroAction "Fire"), and Hold seconds after that it fires
		-- itself, a bot's after BotHold. Firing goes on with the motion (combo step 1 for the clients).
		local hold = if player:IsA("Player") then kit.Hold else kit.BotHold
		state.busyUntil = now + kit.Ready + hold + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, kit.Ready + hold, kit.WalkSpeed)
		character:SetAttribute("Scope", aim)
		local snipe = { ready = now + kit.Ready, fire = function() end }
		snipe.fire = function()
			if state.snipe ~= snipe or not alive(character) then
				return
			end
			state.snipe = nil
			character:SetAttribute("Scope", nil)
			state.busyUntil = os.clock() + kit.Recover
			motionEvent:FireAllClients(character, key, 1)
			slow(state, kit.Recover, Config.Combat.AttackWalkSpeed)
			launch(player, state, team, aimedNow(), kit, strength(kit.Damage), magic)
		end
		state.snipe = snipe
		later(state, kit.Ready + hold, snipe.fire)
	elseif kit.Kind == "Flurry" then
		state.busyUntil = now + math.min(length, HeroKit.flurryEnd(kit) + RECOVER)
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		for hit, time in kit.Hits do
			later(state, time, function()
				-- Every sweep follows the crosshair; the slam strikes all round him, as its shockwave shows.
				local facing = aimedNow()
				local reach, angle, slam = HeroKit.flurryStrike(kit, time)
				local amount = if slam then strength(kit.SlamDamage, kit.SlamRatio) else strength(kit.Damage)
				if not kit.Zap then
					strikeCone(player, state, team, facing, reach, angle, amount, magic, nil, kit.Knockback)
					return
				end
				-- A shock strikes one of those the sweep reaches (HeroKit.zapTarget), as his client draws it.
				local standing = rootOf(character)
				if not standing then
					return
				end
				local origin = HeroKit.muzzle(standing.Position)
				local reached, positions = {}, {}
				for _, enemy in enemiesNear(team, origin, reach) do
					if HeroKit.swingStrikes(origin, facing, reach, angle, enemy) then
						table.insert(reached, enemy)
						table.insert(positions, enemy.position)
					end
				end
				local target = HeroKit.zapTarget(kit, hit, origin, positions)
				if target then
					damage(player, character, reached[target], amount, magic)
				end
			end)
		end
		if kit.Guard then
			later(state, kit.Slam or kit.Hits[1], function()
				brace(character, kit.Guard)
			end)
		end
		for _, time in kit.Pulses or {} do
			later(state, time, function()
				strikeCone(
					player,
					state,
					team,
					aimedNow(),
					kit.SlamRadius,
					360,
					strength(kit.PulseDamage, kit.PulseRatio),
					magic
				)
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

-- Points the attack under way of `state`'s hero at `aim`; a Snipe's red line goes there too.
local function aimTo(state: State, aim: Vector3)
	state.aim = aim
	if state.snipe then
		state.character:SetAttribute("Scope", aim)
	end
end

-- Points a bot's attack under way at `aim`, as a player's client does with "Aim"; false once no attack plays.
function CombatService.aim(actor: Instance, aim: Vector3): boolean
	local state = states[actor]
	if not state or os.clock() >= state.busyUntil then
		return false
	end
	aimTo(state, aim)
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
	headCheckEvent = remote("HeroHeadCheck")
	headshotEvent = remote("HeroHeadshot")
	knockEvent = remote("HeroKnock")
	headCheckEvent.OnServerEvent:Connect(claimHead)

	actionEvent.OnServerEvent:Connect(function(player, key, aim)
		if typeof(aim) ~= "Vector3" or aim ~= aim then
			return
		end
		if key == "Aim" then
			local state = states[player]
			if state and os.clock() < state.busyUntil then
				aimTo(state, aim)
			end
			return
		end
		-- A click through a Snipe's scope, once it may fire.
		if key == "Fire" then
			local state = states[player]
			local snipe = state and state.snipe
			if state and snipe and os.clock() + EARLY >= snipe.ready then
				aimTo(state, aim)
				snipe.fire()
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
