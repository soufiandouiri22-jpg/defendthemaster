-- The geometry of the heroes' kits (Config.Heroes[hero].Kit), the same on the server, which decides every hit, and on
-- the client, which shows where it will land.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

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
-- does. A leap lands on the spot chosen at its cast and a dash keeps its path; only a dash's shot follows.
function HeroKit.follows(kit: any): boolean
	if kit.Kind == "Leap" then
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
