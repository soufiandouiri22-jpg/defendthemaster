-- The heroes' attacks (Config.Heroes[hero].Kit). A client asks for an attack through ReplicatedStorage.Net.HeroAction
-- (key, the point aimed at); the server checks the hero can (alive, not mid-motion, off cooldown), tells every client
-- to play the motion (Net.HeroMotion: character, key, combo step, landing spot) and lands each hit at its time in the
-- motion on the enemies there: the other team's minions and Combatants (heroes, Masters). A refused attack is sent
-- back to its client (Net.HeroRefused), which stops the motion it already began. Thrown daggers fly on the server
-- (Net.HeroProjectile: id, origin, direction, speed, range; Net.HeroProjectileEnd: id, where it stopped, hit or not).
-- Every hit is told to the clients for its feedback (Net.HeroHit: target, damage, where, the striking player).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Motion = require(ReplicatedStorage.Shared.Motion)
local MinionService = require(script.Parent.MinionService)

local CombatService = {}

local KEYS = { M1 = true, M2 = true, E = true, R = true, Dash = true }
-- After a hit lands, the next swing or ability may start this much later.
local RECOVER = 0.12
-- A command may come this much before the hero is free, as the network does not deliver at an even pace.
local EARLY = 0.12
local DASH_STEP = 0.03

type State = {
	character: Model,
	busyUntil: number,
	combo: number,
	comboUntil: number,
	cooldowns: { [string]: number },
	-- Bumped by every new motion, so the hits of one that was cut short no longer land.
	motion: number,
}

-- An enemy in reach: a minion's root part or a Combatant model.
type Enemy = {
	instance: Instance,
	position: Vector3,
	radius: number,
}

type Projectile = {
	id: number,
	player: Player,
	character: Model,
	team: string,
	position: Vector3,
	direction: Vector3,
	left: number,
	speed: number,
	width: number,
	damage: number,
}

local states: { [Player]: State } = {}
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

-- The enemies of `team` within `reach` studs of `centre`.
local function enemiesNear(team: string, centre: Vector3, reach: number): { Enemy }
	local found = {}
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		for _, root in minions:GetChildren() do
			if
				root:IsA("BasePart")
				and root:GetAttribute("Team") ~= team
				and not root:GetAttribute("Dead")
				and HeroKit.flat(root.Position - centre).Magnitude <= reach + Config.Minions.Radius
			then
				table.insert(found, { instance = root, position = root.Position, radius = Config.Minions.Radius })
			end
		end
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Team") ~= team then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local living = if humanoid then humanoid.Health > 0 else (model:GetAttribute("Health") or 0) > 0
			local position = model:GetPivot().Position
			local radius = model:GetAttribute("Radius") or 1.5
			if living and HeroKit.flat(position - centre).Magnitude <= reach + radius then
				table.insert(found, { instance = model, position = position, radius = radius })
			end
		end
	end
	return found
end

local function damage(player: Player, character: Model, enemy: Enemy, amount: number)
	local target = enemy.instance
	hitEvent:FireAllClients(target, amount, enemy.position, player)
	if target:IsA("BasePart") then
		MinionService.damage(target, amount, player)
		return
	end
	local model = target :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(amount)
		if model:GetAttribute("Hero") then
			MinionService.heroAttacked(character, model)
		end
	else
		model:SetAttribute("Health", math.max(0, (model:GetAttribute("Health") or 0) - amount))
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
			humanoid.WalkSpeed = Config.Combat.WalkSpeed
		end
	end)
end

local function strikeCone(
	player: Player,
	state: State,
	team: string,
	direction: Vector3,
	range: number,
	angle: number,
	amount: number
)
	local root = rootOf(state.character)
	if not root then
		return
	end
	local origin = root.Position
	for _, enemy in enemiesNear(team, origin, range) do
		if HeroKit.inCone(origin, direction, range, angle, enemy.position, enemy.radius) then
			damage(player, state.character, enemy, amount)
		end
	end
end

local function launch(player: Player, state: State, team: string, direction: Vector3, kit: any)
	local root = rootOf(state.character)
	if not root then
		return
	end
	nextProjectile += 1
	local origin = root.Position + Vector3.new(0, 0.6, 0) + direction * 1.5
	local projectile: Projectile = {
		id = nextProjectile,
		player = player,
		character = state.character,
		team = team,
		position = origin,
		direction = direction,
		left = kit.Range,
		speed = kit.ProjectileSpeed,
		width = kit.Width,
		damage = kit.Damage,
	}
	table.insert(projectiles, projectile)
	projectileEvent:FireAllClients(projectile.id, state.character, origin, direction, kit.ProjectileSpeed, kit.Range)
end

local function stepProjectiles(dt: number)
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local travel = math.min(p.left, p.speed * dt)
		local from, to = p.position, p.position + p.direction * travel
		local best: Enemy? = nil
		local bestAlong = math.huge
		for _, enemy in enemiesNear(p.team, (from + to) / 2, travel / 2 + p.width) do
			local distance, along = HeroKit.segmentDistance(from, to, enemy.position)
			if distance <= enemy.radius + p.width / 2 and along < bestAlong then
				best, bestAlong = enemy, along
			end
		end
		if best then
			local at = from:Lerp(to, bestAlong)
			damage(p.player, p.character, best, p.damage)
			projectileEndEvent:FireAllClients(p.id, at, true)
			table.remove(projectiles, i)
			continue
		end
		p.position = to
		p.left -= travel
		if p.left <= 0 then
			projectileEndEvent:FireAllClients(p.id, to, false)
			table.remove(projectiles, i)
		end
	end
end

local function act(player: Player, key: string, aim: Vector3)
	local state = states[player]
	local character = player.Character
	if not state or not character or state.character ~= character or not alive(character) then
		return refusedEvent:FireClient(player, key)
	end
	local hero = character:GetAttribute("Hero")
	local settings = hero and Config.Heroes[hero]
	local root = rootOf(character)
	if not settings or not root then
		return refusedEvent:FireClient(player, key)
	end
	local kit = settings.Kit[key]
	local now = os.clock()
	if not kit or now + EARLY < state.busyUntil or now + EARLY < (state.cooldowns[key] or 0) then
		return refusedEvent:FireClient(player, key)
	end
	local team = character:GetAttribute("Team") or "Blue"
	local direction = HeroKit.direction(root.Position, aim, root.CFrame.LookVector)
	state.motion += 1

	if kit.Kind == "Combo" then
		local step = if now <= state.comboUntil then state.combo % #kit.Hits + 1 else 1
		local hit = kit.Hits[step]
		local length = Motion.meta(settings.Pack, hit.Motion).duration / kit.Speed
		state.combo = step
		state.comboUntil = now + kit.Reset
		state.busyUntil = now + hit.Hit / kit.Speed + RECOVER
		motionEvent:FireAllClients(character, key, step)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		later(state, hit.Hit / kit.Speed, function()
			strikeCone(player, state, team, direction, hit.Range, hit.Angle, hit.Damage)
		end)
		return
	end

	local length = Motion.meta(settings.Pack, kit.Motion).duration
	state.cooldowns[key] = now + kit.Cooldown
	state.comboUntil = 0
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
		later(state, kit.Land, function()
			for _, enemy in enemiesNear(team, landing, kit.Radius) do
				if HeroKit.inCone(landing, direction, kit.Radius, 360, enemy.position, enemy.radius) then
					damage(player, character, enemy, kit.Damage)
				end
			end
		end)
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
				for _, enemy in enemiesNear(team, a:Lerp(b, 0.5), HeroKit.flat(b - a).Magnitude / 2 + kit.Width) do
					if
						not struck[enemy.instance]
						and HeroKit.segmentDistance(a, b, enemy.position) <= enemy.radius + kit.Width / 2
					then
						struck[enemy.instance] = true
						damage(player, character, enemy, kit.Damage)
					end
				end
			end)
		end
	elseif kit.Kind == "Throw" then
		state.busyUntil = now + kit.Release + RECOVER
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		later(state, kit.Release, function()
			launch(player, state, team, direction, kit)
		end)
	elseif kit.Kind == "Flurry" then
		state.busyUntil = now + length
		motionEvent:FireAllClients(character, key, 0)
		slow(state, length, Config.Combat.AttackWalkSpeed)
		for _, time in kit.Hits do
			later(state, time, function()
				strikeCone(player, state, team, direction, kit.Range, kit.Angle, kit.Damage)
			end)
		end
	end
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
		if typeof(key) ~= "string" or not KEYS[key] or typeof(aim) ~= "Vector3" or aim ~= aim then
			return
		end
		act(player, key, aim)
	end)

	local function track(player: Player)
		local function added(character: Model)
			states[player] = {
				character = character,
				busyUntil = 0,
				combo = 0,
				comboUntil = 0,
				cooldowns = {},
				motion = 0,
			}
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
