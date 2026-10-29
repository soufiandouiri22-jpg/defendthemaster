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

-- Whether a target of `radius` at `position` is in the cone from `origin` along `direction`, `range` studs to the
-- target's edge and `angle` degrees wide (360 all round).
function HeroKit.inCone(
	origin: Vector3,
	direction: Vector3,
	range: number,
	angle: number,
	position: Vector3,
	radius: number
): boolean
	local offset = HeroKit.flat(position - origin)
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

-- Where a hero whose root part is at `from`, `height` studs above the ground, lands when leaping towards `aim` at most
-- `range` studs: the furthest spot on that line with ground at about the same height and nothing in the way. `exclude`
-- are the instances the rays ignore (characters, minions).
function HeroKit.leapLanding(from: Vector3, aim: Vector3, range: number, height: number, exclude: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local direction = HeroKit.direction(from, aim, Vector3.zAxis)
	local distance = math.min(range, HeroKit.flat(aim - from).Magnitude)
	local ground = from.Y - height
	local d = distance
	while d > 0.5 do
		local spot = from + direction * d
		local wall = Workspace:Spherecast(from, 1.1, direction * d, params)
		if not wall then
			local below = Workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
			if below and math.abs(below.Position.Y - ground) < 2.5 then
				return Vector3.new(spot.X, below.Position.Y + height, spot.Z)
			end
		end
		d -= 1
	end
	return from
end

return HeroKit
