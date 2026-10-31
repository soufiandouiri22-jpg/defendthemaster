-- Checks the crosshair's red against the server's real hits, for every attack of the hero played. The crosshair turns
-- red on an enemy the next left click would strike (HeroKit.hitReaches) and, while an ability is aimed, once an enemy
-- stands where it would strike (HeroKit.aimed, HeroKit.abilityStrikes). This test finds, for every hit of the combo
-- and every aimed ability (M2, E, R), the farthest distance from a minion at which the crosshair is red, attacks it
-- through the game's own Net.HeroAction just inside and just outside that distance, and reports whether the server
-- struck it there (its Health went down).
--
-- Run it on Studio's test ground: tick the Workspace attributes Match, TestGround and TestMinions, set TestHero to the
-- hero to check, press Play, once the hero stands give him health enough for the minions' shots in the Server
-- datamodel (his Humanoid's MaxHealth and Health 1e6) and tick the Workspace attribute TestMinionsStill (a minion that
-- walks while a shot flies or a flurry plays is missed, or struck where the crosshair was not red), and run this file
-- in the Client datamodel (the Studio MCP's
-- execute_luau). The abilities wait out their cooldowns, so it takes a few minutes: it also leaves its report in the
-- player's attribute "ReachTest" (run it in a task.spawn and read that). It puts the hero on a spot in line with the
-- minion every frame, as the minion may move: not anchored, as the server only hears where the client's hero is while
-- his physics runs, and lifted as an Ascend lifts him. A swing leading up to the hit tested is made far from it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Leveling = require(ReplicatedStorage.Shared.Leveling)

-- How far inside and outside the farthest distance in reach it attacks; how far off the swings before it are.
local MARGIN, FAR = 0.5, 80
-- The time after a hit lands (and a shot has flown) to see it; how long the hero stands on his spot before he
-- attacks, so the server has heard where he stands (he may come from the other minion, and an attack heard before
-- that strikes from there).
local SETTLE, HOLD = 0.5, 0.75
local ABILITIES = { "M2", "E", "R" }

local player = Players.LocalPlayer
local character = player.Character :: Model
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local hero = character:GetAttribute("Hero")
local kits = Config.Heroes[hero].Kit
local action = ReplicatedStorage:WaitForChild("Net"):WaitForChild("HeroAction") :: RemoteEvent
local minions = Workspace:WaitForChild("Minions")
local groundY = root.Position.Y
local height = humanoid.HipHeight + root.Size.Y / 2

-- The living red minion with the most Health, and another (the line runs away from it).
local function pick(): (BasePart?, BasePart?)
	local best, other = nil, nil
	for _, m in minions:GetChildren() do
		if m:IsA("BasePart") and m:GetAttribute("Team") == "Red" and not m:GetAttribute("Dead") then
			if not best or (m:GetAttribute("Health") or 0) > (best:GetAttribute("Health") or 0) then
				best, other = m, best
			else
				other = m
			end
		end
	end
	return best, other
end

local function lineOf(target: BasePart, other: BasePart?): Vector3
	local away = if other then HeroKit.flat(target.Position - other.Position) else Vector3.xAxis
	return if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
end

-- Where the hero stands `d` studs from `target` along `line`, and the spot on its body facing him at his muzzle's height.
local function geometry(target: BasePart, line: Vector3, d: number): (Vector3, Vector3, HeroKit.Body)
	local body = HeroKit.body(target) :: HeroKit.Body
	local at = Vector3.new(body.position.X, groundY, body.position.Z) + line * d
	local aimHeight = math.clamp(HeroKit.muzzle(at).Y, body.bottom, body.top)
	local aim = Vector3.new(body.position.X, aimHeight, body.position.Z) + line * body.radius
	return at, aim, body
end

-- Whether the crosshair is red for `key` (`hit` the combo's hit for M1) `d` studs from `target`, as HeroControls
-- decides it.
local function red(key: string, hit: any, target: BasePart, line: Vector3, d: number): boolean
	local at, aim, body = geometry(target, line, d)
	if key == "M1" then
		return HeroKit.hitReaches(hit, at, aim, -line, body)
	end
	local kit = kits[key]
	local landing, shots = HeroKit.aimed(kit, at, aim, -line, height, HeroKit.leapIgnore())
	return HeroKit.abilityStrikes(kit, at, aim, -line, landing, shots, body)
end

local function farthest(key: string, hit: any, target: BasePart, line: Vector3): number
	local low, high = 0, 150
	for _ = 1, 40 do
		local middle = (low + high) / 2
		if red(key, hit, target, line, middle) then
			low = middle
		else
			high = middle
		end
	end
	return low
end

local glued: RBXScriptConnection? = nil
-- Keeps the hero `d` studs from `target` along `line`, and lifted as `lift` (an Ascend's kit) does from `castAt`.
local function glue(target: BasePart, line: Vector3, d: number, lift: any?, castAt: number?)
	if glued then
		glued:Disconnect()
	end
	glued = RunService.Heartbeat:Connect(function()
		local at = geometry(target, line, d)
		if lift and castAt then
			at += Vector3.new(0, HeroKit.lift(lift, os.clock() - castAt), 0)
		end
		local body = target.Position
		character:PivotTo(CFrame.lookAt(at, Vector3.new(body.X, at.Y, body.Z)))
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

-- Fires `key` at `target` from `d` studs once he has stood there `hold` seconds (else HOLD) and waits `after` seconds;
-- whether the server struck it meanwhile.
local function attack(
	key: string,
	target: BasePart,
	line: Vector3,
	d: number,
	after: number,
	lift: any?,
	hold: number?
): boolean
	glue(target, line, d)
	task.wait(hold or HOLD)
	local _, aim = geometry(target, line, d)
	local before = target:GetAttribute("Health")
	if lift then
		glue(target, line, d, lift, os.clock())
	end
	action:FireServer(key, aim)
	task.wait(after)
	return (target:GetAttribute("Health") or 0) < before or target:GetAttribute("Dead") == true
end

-- Swings the combo up to `step`, the swings before it FAR studs off; whether the last struck `target`. He goes to his
-- spot once the swing before it has struck, and the last swing goes just before the combo would start again, so the
-- server has heard where he stands.
local function swing(step: number, target: BasePart, line: Vector3, d: number): boolean
	local kit = kits.M1
	local speed = kit.Speed * (character:GetAttribute("AttackSpeed") or 1)
	local hit = kit.Hits[step]
	local flight = if hit.ProjectileSpeed then (d + 2) / hit.ProjectileSpeed else 0
	if step == 1 then
		task.wait(kit.Reset + 0.3)
		return attack("M1", target, line, d, hit.Hit / speed + flight + SETTLE)
	end
	glue(target, line, FAR)
	task.wait(kit.Reset + 0.3)
	for i = 1, step - 1 do
		local before = kit.Hits[i]
		local firedAt = os.clock()
		local _, aim = geometry(target, line, FAR)
		action:FireServer("M1", aim)
		local ready = (before.Hit + (before.Recover or 0)) / speed + 0.15
		task.wait(before.Hit / speed + 0.2)
		if i == step - 1 then
			glue(target, line, d)
			ready = math.max(ready, kit.Reset - 0.25)
		end
		task.wait(math.max(0, firedAt + ready - os.clock()))
	end
	return attack("M1", target, line, d, hit.Hit / speed + flight + SETTLE, nil, 0)
end

-- How long after its cast an ability has struck all it will: its last hit, release or landing and a shot's flight.
local function strikesBy(kit: any): number
	local flight = if kit.ProjectileSpeed then kit.Range / kit.ProjectileSpeed else 0
	if kit.Kind == "Leap" then
		return kit.Land
	elseif kit.Kind == "Flurry" then
		return kit.Hits[#kit.Hits]
	elseif kit.Kind == "Ascend" then
		return kit.Release + flight
	end
	local releases = HeroKit.releases(kit)
	return releases[#releases] + flight
end

local readyAt: { [string]: number } = {}

local function run(): string
	local lines = {}
	local failed = 0
	local function case(name: string, key: string, hit: any, cast: (BasePart, Vector3, number) -> boolean)
		for _, inside in { true, false } do
			local target, other = pick()
			while not target do
				task.wait(0.5)
				target, other = pick()
			end
			local t = target :: BasePart
			local line = lineOf(t, other)
			local edge = farthest(key, hit, t, line)
			local d = if inside then edge - MARGIN else edge + MARGIN
			local struck = cast(t, line, d)
			local ok = struck == inside
			failed += if ok then 0 else 1
			table.insert(
				lines,
				string.format(
					"%s %s: red up to %.2f studs; at %.2f %s the server %s  %s",
					hero,
					name,
					edge,
					d,
					if inside then "(red)" else "(not red)",
					if struck then "struck" else "missed",
					if ok then "PASS" else "FAIL"
				)
			)
		end
	end
	for step, hit in kits.M1.Hits do
		local name =
			string.format("M1 hit %d (%s %.1f)", step, if hit.ProjectileSpeed then "shot" else "swing", hit.Range)
		case(name, "M1", hit, function(target, line, d)
			return swing(step, target, line, d)
		end)
	end
	for _, key in ABILITIES do
		local kit = kits[key]
		if kit and (kit.Kind == "Leap" or kit.Kind == "Throw" or kit.Kind == "Flurry" or kit.Kind == "Ascend") then
			case(string.format("%s (%s)", key, kit.Kind), key, nil, function(target, line, d)
				local wait = (readyAt[key] or 0) - os.clock()
				if wait > 0 then
					task.wait(wait)
				end
				task.wait(kits.M1.Reset)
				local struck =
					attack(key, target, line, d, strikesBy(kit) + SETTLE, if kit.Kind == "Ascend" then kit else nil)
				readyAt[key] = os.clock() + Leveling.cooldown(player, key, kit.Cooldown) + 0.3
				return struck
			end)
		end
	end
	if glued then
		glued:Disconnect()
	end
	table.insert(lines, if failed == 0 then "ALL PASS" else string.format("%d FAILED", failed))
	return table.concat(lines, "\n")
end

local result = run()
player:SetAttribute("ReachTest", result)
return result
