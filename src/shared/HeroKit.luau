-- The geometry of the heroes' kits (Config.Heroes[hero].Kit), the same on the server, which decides every hit, and on
-- the client, which shows where it will land.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local HeroKit = {}

function HeroKit.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The times a Throw lets go, in order: its `Releases`, or its one `Release`.
function HeroKit.releases(kit: any): { number }
	return kit.Releases or { kit.Release }
end

-- How high an Ascend (`kit`) holds the hero above where he cast it, `t` seconds after: easing up from RiseStart to
-- RiseEnd, hanging at Rise, and easing down from Fall to Land.
function HeroKit.lift(kit: any, t: number): number
	local function ease(a: number): number
		a = math.clamp(a, 0, 1)
		return a * a * (3 - 2 * a)
	end
	if t < kit.Fall then
		return kit.Rise * ease((t - kit.RiseStart) / (kit.RiseEnd - kit.RiseStart))
	end
	return kit.Rise * (1 - ease((t - kit.Fall) / (kit.Land - kit.Fall)))
end

-- Whether the hits of `kit` go where the crosshair points as each lands or leaves his hand rather than where it
-- pointed at the cast, so turning while the attack plays hits whoever he turns to: every swing, throw, shot and sweep
-- does. A leap lands on, and a strike from the sky falls on, the spot chosen at its cast and a dash keeps its path;
-- only a dash's shot follows.
function HeroKit.follows(kit: any): boolean
	if kit.Kind == "Leap" or kit.Kind == "Strike" or kit.Kind == "Rain" then
		return false
	elseif kit.Kind == "Dash" then
		return kit.Shot ~= nil
	end
	return true
end

-- The flat direction from `from` towards `to`; `fallback` when they stand on one spot.
function HeroKit.direction(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local offset = HeroKit.flat(to - from)
	if offset.Magnitude < 0.05 then
		return HeroKit.flat(fallback).Unit
	end
	return offset.Unit
end

-- Where a hero's projectiles leave him and his strikes are measured from, his root part at `root`: a little above it.
function HeroKit.muzzle(root: Vector3): Vector3
	return root + Vector3.new(0, 0.6, 0)
end

-- The direction from `from` towards `to`, upwards and downwards as well as round, as every swing, shot and throw goes
-- where the player looks (owner, 2026-10-29); `fallback` when they are on one spot.
function HeroKit.aimDirection(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local offset = to - from
	if offset.Magnitude < 0.05 then
		return fallback.Unit
	end
	return offset.Unit
end

-- The point of an upright target's axis, through `position` from the height `bottom` to `top`, nearest to the line
-- from `origin` along the unit `direction` (or to `origin` where the target stands behind it).
function HeroKit.axisPoint(origin: Vector3, direction: Vector3, position: Vector3, bottom: number, top: number): Vector3
	local w = origin - Vector3.new(position.X, 0, position.Z)
	local tilt = direction.Y
	local square = 1 - tilt * tilt
	local height = if square > 1e-4 then (w.Y - tilt * direction:Dot(w)) / square else origin.Y
	height = math.clamp(height, bottom, top)
	local point = Vector3.new(position.X, height, position.Z)
	if (point - origin):Dot(direction) < 0 then
		point = Vector3.new(position.X, math.clamp(origin.Y, bottom, top), position.Z)
	end
	return point
end

-- Whether a target of `radius` at `position` is in the cone from `origin` along `direction`, `range` studs to the
-- target's edge and `angle` degrees wide (360 all round). Given the heights the target reaches from `bottom` to `top`,
-- the cone points where `direction` does, up and down too, measured to the point of the target's upright axis nearest
-- its line; without them it lies flat.
function HeroKit.inCone(
	origin: Vector3,
	direction: Vector3,
	range: number,
	angle: number,
	position: Vector3,
	radius: number,
	bottom: number?,
	top: number?
): boolean
	local offset = HeroKit.flat(position - origin)
	if bottom and top then
		local point = if angle >= 360
			then Vector3.new(position.X, math.clamp(origin.Y, bottom, top), position.Z)
			else HeroKit.axisPoint(origin, direction, position, bottom, top)
		offset = point - origin
	end
	local distance = offset.Magnitude
	if distance - radius > range then
		return false
	end
	if angle >= 360 or distance <= radius + 0.5 then
		return true
	end
	local spread = math.rad(angle / 2) + math.asin(math.clamp(radius / distance, 0, 1))
	return math.acos(math.clamp(offset.Unit:Dot(direction), -1, 1)) <= spread
end

-- The nearest distance from the flat point `p` to the flat segment from `a` to `b`, and how far along it that is (0-1).
function HeroKit.segmentDistance(a: Vector3, b: Vector3, p: Vector3): (number, number)
	local ab, ap = HeroKit.flat(b - a), HeroKit.flat(p - a)
	local length = ab:Dot(ab)
	local t = if length > 0 then math.clamp(ap:Dot(ab) / length, 0, 1) else 0
	return (ap - ab * t).Magnitude, t
end

-- A fighter as every hit sees it: where it stands, how wide it is, and the heights its body reaches from `bottom` to
-- `top`.
export type Body = { position: Vector3, radius: number, bottom: number, top: number }

-- The body of a minion's root part (Workspace.Minions) or a Combatant model. `extents` keeps a model's heights round
-- its pivot as first measured, as its bounding box moves with its animation.
function HeroKit.body(instance: Instance, extents: { [Model]: { number } }?): Body?
	if instance:IsA("BasePart") then
		local position = instance.Position
		local half = Config.Minions.Height / 2
		return {
			position = position,
			radius = Config.Minions.Radius,
			bottom = position.Y - half,
			top = position.Y + half,
		}
	elseif instance:IsA("Model") then
		local position = instance:GetPivot().Position
		local extent = extents and extents[instance]
		if not extent then
			local box, size = instance:GetBoundingBox()
			extent = { box.Position.Y - size.Y / 2 - position.Y, box.Position.Y + size.Y / 2 - position.Y }
			if extents then
				extents[instance] = extent
			end
		end
		return {
			position = position,
			radius = instance:GetAttribute("Radius") or 1.5,
			bottom = position.Y + extent[1],
			top = position.Y + extent[2],
		}
	end
	return nil
end

-- Where a projectile leaves a hero whose muzzle (HeroKit.muzzle) is at `muzzle`, flying along `direction`.
function HeroKit.shotOrigin(muzzle: Vector3, direction: Vector3): Vector3
	return muzzle + direction * 1.5
end

-- Where along its way from `from` to `to` (0-1) a projectile `width` studs wide touches `body`, if it does: within its
-- width of the body's edge, at a height the body reaches.
function HeroKit.shotTouch(from: Vector3, to: Vector3, width: number, body: Body): number?
	local distance, along = HeroKit.segmentDistance(from, to, body.position)
	local height = from.Y + (to.Y - from.Y) * along
	local half = width / 2
	if distance <= body.radius + half and height >= body.bottom - half and height <= body.top + half then
		return along
	end
	return nil
end

-- Whether `hit`, one of a hero's combo hits (Kit.M1.Hits), struck from a hero whose root part is at `root` towards
-- `aim` (`facing` when he aims at himself), reaches `body`: a swing as CombatService's strikeCone measures it, a shot
-- anywhere on the way it flies as its stepProjectiles does. Walls in a shot's way are left to the caller.
function HeroKit.hitReaches(hit: any, root: Vector3, aim: Vector3, facing: Vector3, body: Body): boolean
	local muzzle = HeroKit.muzzle(root)
	local direction = HeroKit.aimDirection(muzzle, aim, facing)
	if not hit.ProjectileSpeed then
		return HeroKit.inCone(
			muzzle,
			direction,
			hit.Range,
			hit.Angle,
			body.position,
			body.radius,
			body.bottom,
			body.top
		)
	end
	local from = HeroKit.shotOrigin(muzzle, direction)
	return HeroKit.shotTouch(from, from + direction * hit.Range, hit.Width, body) ~= nil
end

-- A fighter a hit may strike, with its body.
export type Foe = { instance: Instance, body: Body }

-- Every living fighter not of `team` that hits strike: the minions (their root parts in Workspace.Minions) and the
-- Combatants (heroes, Masters). `extents` as for HeroKit.body.
function HeroKit.foes(team: string, extents: { [Model]: { number } }?): { Foe }
	local found = {}
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		for _, root in minions:GetChildren() do
			if root:IsA("BasePart") and root:GetAttribute("Team") ~= team and not root:GetAttribute("Dead") then
				table.insert(found, { instance = root, body = HeroKit.body(root) :: Body })
			end
		end
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Team") ~= team then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if if humanoid then humanoid.Health > 0 else (model:GetAttribute("Health") or 0) > 0 then
				table.insert(found, { instance = model, body = HeroKit.body(model, extents) :: Body })
			end
		end
	end
	return found
end

-- Whether a swing from `origin` along `direction`, `range` studs to the target's edge and `angle` degrees wide (360
-- all round), strikes `body`, at the heights its body reaches.
function HeroKit.swingStrikes(origin: Vector3, direction: Vector3, range: number, angle: number, body: Body): boolean
	return HeroKit.inCone(origin, direction, range, angle, body.position, body.radius, body.bottom, body.top)
end

-- Whether a leap's landing at `landing` strikes `body`: within `radius` studs of its edge, all round.
function HeroKit.landingStrikes(landing: Vector3, radius: number, body: Body): boolean
	return HeroKit.flat(body.position - landing).Magnitude - body.radius <= radius
end

-- The directions of a fan of `count` projectiles over `spread` degrees round `direction` (round the vertical).
function HeroKit.fan(direction: Vector3, count: number, spread: number): { Vector3 }
	local directions = {}
	for n = 1, count do
		local offset = if count > 1 then -spread / 2 + spread * (n - 1) / (count - 1) else 0
		table.insert(directions, CFrame.fromAxisAngle(Vector3.yAxis, math.rad(offset)):VectorToWorldSpace(direction))
	end
	return directions
end

-- What one strike of a Flurry (`kit`) at `time` seconds into it reaches: a sweep along the crosshair (Range, Angle),
-- or from its Slam on the slam all round him (SlamRadius); and whether it is the slam.
function HeroKit.flurryStrike(kit: any, time: number): (number, number, boolean)
	local slam = kit.Slam ~= nil and time >= kit.Slam
	return if slam then kit.SlamRadius else kit.Range, if slam then 360 else kit.Angle, slam
end

-- Which of the enemies a Zap flurry's (`kit`) `hit`th shock (from 1) reaches, at `positions`, it strikes (an index
-- into them), seen from `origin`: the nearest `kit.Targets` of them take its shocks in turn, nearest first, so one
-- enemy takes them all and two share them, the nearer taking the extra one. Nil when it reaches no one.
function HeroKit.zapTarget(kit: any, hit: number, origin: Vector3, positions: { Vector3 }): number?
	if #positions == 0 then
		return nil
	end
	local order = {}
	for i in positions do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		return (positions[a] - origin).Magnitude < (positions[b] - origin).Magnitude
	end)
	return order[(hit - 1) % math.min(#order, kit.Targets or #order) + 1]
end

-- Whether a projectile bursting at `at` strikes `body`: within `reach` studs of its edge round, and of its heights.
function HeroKit.burstStrikes(at: Vector3, reach: number, body: Body): boolean
	return HeroKit.flat(body.position - at).Magnitude <= reach + body.radius
		and at.Y >= body.bottom - reach
		and at.Y <= body.top + reach
end

-- A projectile's way: where it leaves and where it stops (at the end of its range, or a wall the caller found).
export type Shot = { from: Vector3, to: Vector3 }

-- The ways of the projectiles of a Throw or an Ascend (`kit`) cast by a hero whose root part is at `root` towards `aim`
-- (`facing` when he aims at himself): each fan's projectiles from where he lets them go (an Ascend's from where it has
-- lifted him), as far as they fly.
function HeroKit.shots(kit: any, root: Vector3, aim: Vector3, facing: Vector3): { Shot }
	if kit.Kind == "Ascend" then
		root += Vector3.new(0, HeroKit.lift(kit, kit.Release), 0)
	end
	local muzzle = HeroKit.muzzle(root)
	local ways = {}
	for _, direction in HeroKit.fan(HeroKit.aimDirection(muzzle, aim, facing), kit.Count or 1, kit.Spread or 0) do
		local from = HeroKit.shotOrigin(muzzle, direction)
		table.insert(ways, { from = from, to = from + direction * kit.Range })
	end
	return ways
end

-- Where an ability (`kit`) aimed now by a hero whose root part is at `root`, `height` studs above the ground, towards
-- `aim` (`facing` when he aims at himself) would land and fly: a leap's landing, or its projectiles' ways up to the
-- first wall in each (rays that pass through `exclude`, HeroKit.leapIgnore).
function HeroKit.aimed(
	kit: any,
	root: Vector3,
	aim: Vector3,
	facing: Vector3,
	height: number,
	exclude: { Instance }
): (Vector3?, { Shot }?)
	if kit.Kind == "Leap" or kit.Kind == "Strike" or kit.Kind == "Rain" then
		return HeroKit.leapLanding(root, aim, kit.Range, height, exclude), nil
	elseif kit.Kind == "Throw" or kit.Kind == "Ascend" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude
		local ways = HeroKit.shots(kit, root, aim, facing)
		for _, way in ways do
			local wall = Workspace:Raycast(way.from, way.to - way.from, params)
			if wall then
				way.to = wall.Position
			end
		end
		return nil, ways
	end
	return nil, nil
end

-- Whether an ability aimed now (a Leap, Throw, Flurry or Ascend, `kit`) strikes `body` where it stands, as
-- CombatService.act lands it: a leap's ring round `landing`, the projectiles' `shots` (both HeroKit.aimed), or the
-- flurry's sweeps and slam from the hero's root part at
-- `root` towards `aim`; a projectile with a Blast also bursts where it stops.
function HeroKit.abilityStrikes(
	kit: any,
	root: Vector3,
	aim: Vector3,
	facing: Vector3,
	landing: Vector3?,
	shots: { Shot }?,
	body: Body
): boolean
	if kit.Kind == "Leap" or kit.Kind == "Strike" or kit.Kind == "Rain" then
		return landing ~= nil and HeroKit.landingStrikes(landing, kit.Radius, body)
	elseif kit.Kind == "Throw" or kit.Kind == "Ascend" then
		for _, shot in shots or {} do
			if
				HeroKit.shotTouch(shot.from, shot.to, kit.Width, body)
				or (kit.Blast and HeroKit.burstStrikes(shot.to, kit.Blast, body))
			then
				return true
			end
		end
		return false
	elseif kit.Kind == "Flurry" then
		local muzzle = HeroKit.muzzle(root)
		local direction = HeroKit.aimDirection(muzzle, aim, facing)
		for _, time in kit.Hits do
			local range, angle = HeroKit.flurryStrike(kit, time)
			if HeroKit.swingStrikes(muzzle, direction, range, angle, body) then
				return true
			end
		end
	end
	return false
end

-- Where a dash from `from` (the root part) `range` studs along the flat `direction` ends: short of the first wall in
-- its way, at the same height (falling afterwards is left to the hero's physics).
function HeroKit.dashEnd(from: Vector3, direction: Vector3, range: number, exclude: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local wall = Workspace:Spherecast(from, 1.1, direction * range, params)
	local distance = if wall then math.max(0, wall.Distance - 0.5) else range
	return from + direction * distance
end

-- What the rays of a leap pass through: everyone who fights, and the clients' effects.
function HeroKit.leapIgnore(): { Instance }
	local ignore: { Instance } = {}
	for _, name in { "Minions", "Effects", "MinionViews" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		table.insert(ignore, model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	return ignore
end

-- How high a leap clears above the root part, so it goes over what stands low (the spawn pads, crates, low cover)
-- and onto the bases' daises; how far above or below where he leapt from he may land; and the steepest ground (the
-- up-pointing share of its normal) he lands on.
local LEAP_LIFT = 7
local LEAP_UP, LEAP_DOWN = 9, 14
local LEAP_FLAT = 0.7
-- He lands only where he can stand: the ground this far round the spot on each side lies within FOOTING_STEP of it,
-- so not on a shrub, a statue's head or a brazier.
local FOOTING, FOOTING_STEP = 1.5, 2.5
local FOOTING_SIDES = {
	Vector3.new(FOOTING, 0, 0),
	Vector3.new(-FOOTING, 0, 0),
	Vector3.new(0, 0, FOOTING),
	Vector3.new(0, 0, -FOOTING),
}

-- Where a hero whose root part is at `from`, `height` studs above the ground, lands when leaping towards `aim` at most
-- `range` studs: the furthest spot on that line he can clear at the leap's height, with ground below it no more than
-- LEAP_UP above or LEAP_DOWN below where he stands; without such a spot he still goes that way along the ground until
-- something stops him (HeroKit.dashEnd). `exclude` are the instances the rays ignore (characters, minions).
function HeroKit.leapLanding(from: Vector3, aim: Vector3, range: number, height: number, exclude: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local direction = HeroKit.direction(from, aim, Vector3.zAxis)
	local distance = math.min(range, HeroKit.flat(aim - from).Magnitude)
	local ground = from.Y - height
	-- Up first, as far as nothing overhead stops him.
	local roof = Workspace:Spherecast(from, 1.1, Vector3.new(0, LEAP_LIFT, 0), params)
	local top = from + Vector3.new(0, if roof then math.max(0, roof.Distance - 0.5) else LEAP_LIFT, 0)
	local depth = (top.Y - ground) + LEAP_DOWN + 1
	local d = distance
	while d > 0.5 do
		local spot = top + direction * d
		local wall = Workspace:Spherecast(top, 1.1, direction * d, params)
		if not wall then
			local below = Workspace:Raycast(spot, Vector3.new(0, -depth, 0), params)
			if below and below.Normal.Y >= LEAP_FLAT then
				local rise = below.Position.Y - ground
				local steady = true
				for _, side in FOOTING_SIDES do
					local foot = Workspace:Raycast(spot + side, Vector3.new(0, -depth, 0), params)
					if not foot or math.abs(foot.Position.Y - below.Position.Y) > FOOTING_STEP then
						steady = false
						break
					end
				end
				if steady and rise <= LEAP_UP and rise >= -LEAP_DOWN then
					return Vector3.new(spot.X, below.Position.Y + height, spot.Z)
				end
			end
		end
		d -= 1
	end
	return HeroKit.dashEnd(from, direction, distance, exclude)
end

return HeroKit
