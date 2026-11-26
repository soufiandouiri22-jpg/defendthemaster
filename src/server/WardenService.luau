-- The knight statues beside each throne, its Master's wardens (Config.Wardens): each burns one enemy at a time with a
-- beam that stays on him, as a tower in League of Legends shoots one, and only on its own side of the line from the
-- dais's front to the arena's middle, so never two on one enemy (owner, 2026-11-25). Their eyes are the "Eye" parts
-- ColosseumBuilder lights in their visors, in the Map's "BlueBase" and "RedBase". Each statue's target is told to the
-- clients by an ObjectValue in Net.Wardens (nil while it burns nobody), named as the statue's "Warden" attribute, for
-- its beams (WardenView); the beam burns him from Charge seconds after it was set. Its "Front" and "Half" attributes
-- are its half of the zone, for its eyes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Damage = require(script.Parent.Damage)
local MatchService = require(script.Parent.MatchService)
local MinionService = require(script.Parent.MinionService)
local ProgressService = require(script.Parent.ProgressService)

local WardenService = {}

local SETTINGS = Config.Wardens
local ZONE = Config.Master.Zone

type Side = {
	team: string,
	statue: Model,
	-- The middle of their Master's zone, his dais's front, and the flat way from the line through it to the arena's
	-- middle to this statue's side of the zone.
	front: Vector3,
	half: Vector3,
	target: Instance?,
	shown: ObjectValue,
	-- When the beam on the target began to burn, and last burnt him.
	from: number,
	burnt: number,
	-- The damage not dealt yet, under one whole point.
	owed: number,
}

local sides: { Side } = {}
-- When each hero last struck each team's Master.
local struck: { [Model]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function onSide(side: Side, position: Vector3): boolean
	return HeroKit.flat(position - side.front):Dot(side.half) >= 0
end

local function inZone(side: Side, position: Vector3, radius: number): boolean
	return HeroKit.flat(position - side.front).Magnitude <= ZONE + radius and onSide(side, position)
end

local function inReach(side: Side, position: Vector3): boolean
	return HeroKit.flat(position - side.front).Magnitude <= SETTINGS.Reach and onSide(side, position)
end

local function liveMinion(root: Instance, team: string): boolean
	return root.Parent ~= nil
		and root:IsA("BasePart")
		and root:GetAttribute("Team") ~= team
		and not root:GetAttribute("Dead")
end

local function liveHero(model: Instance, team: string): boolean
	if not model.Parent or not model:IsA("Model") or not model:GetAttribute("Hero") then
		return false
	end
	if model:GetAttribute("Team") == team or model:GetAttribute("Hidden") then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Whether the hero `model` struck `side`'s Master within Forget seconds.
local function striking(side: Side, model: Model, now: number): boolean
	local at = struck[model] and struck[model][side.team]
	return at ~= nil and now - at <= SETTINGS.Forget
end

local function radiusOf(model: Instance): number
	return model:GetAttribute("Radius") or 1.5
end

-- Whether an enemy minion stands anywhere in `team`'s Master's zone, in either warden's half: then neither of them
-- burns a hero, so a hero knows he is safe while one of them burns a minion (owner, 2026-11-25).
local function minionsIn(team: string): boolean
	local minions = Workspace:FindFirstChild("Minions")
	for _, side in sides do
		if side.team == team then
			for _, root in if minions then minions:GetChildren() else {} do
				if liveMinion(root, team) and inZone(side, (root :: BasePart).Position, Config.Minions.Radius) then
					return true
				end
			end
		end
	end
	return false
end

-- Whether `side` keeps its beam on `target`: a minion while it is in the zone, a hero while he is in it or strikes
-- their Master from outside it and no enemy minion is in the zone.
local function keeps(side: Side, target: Instance, now: number): boolean
	if target:IsA("BasePart") then
		return liveMinion(target, side.team) and inZone(side, target.Position, Config.Minions.Radius)
	end
	if not liveHero(target, side.team) or minionsIn(side.team) then
		return false
	end
	local model = target :: Model
	local position = model:GetPivot().Position
	return inReach(side, position) and (inZone(side, position, radiusOf(model)) or striking(side, model, now))
end

-- Whom `side` takes next: the enemy minion in the zone nearest its middle, else, with no enemy minion in the other
-- half either, the enemy hero there nearest it, else the nearest enemy hero who strikes their Master from outside; nil
-- when there is none.
local function choose(side: Side, now: number): Instance?
	local best: Instance? = nil
	local bestGap = math.huge
	local minions = Workspace:FindFirstChild("Minions")
	for _, root in if minions then minions:GetChildren() else {} do
		if liveMinion(root, side.team) and inZone(side, (root :: BasePart).Position, Config.Minions.Radius) then
			local gap = HeroKit.flat((root :: BasePart).Position - side.front).Magnitude
			if gap < bestGap then
				best, bestGap = root, gap
			end
		end
	end
	if best or minionsIn(side.team) then
		return best
	end
	local outside: Instance? = nil
	local outsideGap = math.huge
	for _, model in CollectionService:GetTagged("Combatant") do
		if liveHero(model, side.team) then
			local position = (model :: Model):GetPivot().Position
			local gap = HeroKit.flat(position - side.front).Magnitude
			if inZone(side, position, radiusOf(model)) then
				if gap < bestGap then
					best, bestGap = model, gap
				end
			elseif inReach(side, position) and striking(side, model :: Model, now) and gap < outsideGap then
				outside, outsideGap = model, gap
			end
		end
	end
	return best or outside
end

local function aim(side: Side, target: Instance?, now: number)
	if side.target == target then
		return
	end
	side.target = target
	side.shown.Value = target
	side.from = now + SETTINGS.Charge
	side.burnt = side.from
	side.owed = 0
end

-- `side`'s beam burns `target` for the time since it last did; not as hits (HitFeedback's knock and flash), as the
-- beam and its sound show it.
local function burn(side: Side, target: Instance, now: number)
	local seconds = now - side.burnt
	if seconds < SETTINGS.Tick then
		return
	end
	side.burnt = now
	local hero = not target:IsA("BasePart")
	local humanoid = if hero then (target :: Model):FindFirstChildOfClass("Humanoid") else nil
	if hero then
		if not humanoid then
			return
		end
		local rate = math.min(SETTINGS.Hero + SETTINGS.Ramp * (now - side.from), SETTINGS.Most)
		side.owed += Damage.mitigated(target :: Model, rate * humanoid.MaxHealth * seconds, true, nil)
	else
		side.owed += SETTINGS.Minion * (target:GetAttribute("MaxHealth") or 0) * seconds
	end
	local amount = math.floor(side.owed)
	if amount <= 0 then
		return
	end
	side.owed -= amount
	if humanoid then
		-- His death may be this warden's kill, as a minion's (ProgressService).
		ProgressService.hurtByWarden(target :: Model, side.statue)
		humanoid:TakeDamage(amount)
	else
		MinionService.damage(target :: BasePart, amount, nil)
	end
end

local function masterAlive(team: string): boolean
	local masters = Workspace:FindFirstChild("Masters")
	for _, model in if masters then masters:GetChildren() else {} do
		if model:GetAttribute("Team") == team then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			return humanoid ~= nil and humanoid.Health > 0
		end
	end
	return false
end

local function update(side: Side, now: number)
	if not MatchService.fighting() or not masterAlive(side.team) then
		aim(side, nil, now)
		return
	end
	local target = side.target
	if target and not keeps(side, target, now) then
		target = nil
	end
	target = target or choose(side, now)
	aim(side, target, now)
	if target and now >= side.from then
		burn(side, target, now)
	end
end

-- The hero `attacker` struck `victim`; when that is a Master, his wardens may burn `attacker` from outside his zone.
function WardenService.struck(attacker: Model, victim: Model)
	if not victim:GetAttribute("Master") or not attacker:GetAttribute("Hero") then
		return
	end
	local team = victim:GetAttribute("Team")
	if not team or attacker:GetAttribute("Team") == team then
		return
	end
	local times = struck[attacker] or {}
	times[team] = os.clock()
	struck[attacker] = times
end

export type Layout = {
	daisFront: { [string]: Vector3 },
	map: Folder,
}

function WardenService.start(layout: Layout)
	local net = ReplicatedStorage:WaitForChild("Net") :: Folder
	local folder = Instance.new("Folder")
	folder.Name = "Wardens"
	folder.Parent = net

	for team, front in layout.daisFront do
		local base = layout.map:FindFirstChild(team .. "Base")
		local statues: { [Instance]: true } = {}
		for _, eye in if base then base:GetDescendants() else {} do
			if eye.Name == "Eye" and eye:IsA("BasePart") and eye.Parent and eye.Parent:IsA("Model") then
				statues[eye.Parent] = true
			end
		end
		local middle = HeroKit.flat(front)
		local inward = (-middle).Unit
		-- Seen from the dais, looking at the arena's middle.
		local right = Vector3.new(-inward.Z, 0, inward.X)
		for statue in statues do
			local away = HeroKit.flat((statue :: Model):GetPivot().Position - middle)
			local half = if away:Dot(right) >= 0 then right else -right
			local name = team .. (if half == right then "Right" else "Left")
			statue:SetAttribute("Warden", name)
			-- For the eyes waking as an enemy comes near its half of the zone (WardenView).
			statue:SetAttribute("Front", middle)
			statue:SetAttribute("Half", half)
			local shown = Instance.new("ObjectValue")
			shown.Name = name
			shown.Parent = folder
			table.insert(sides, {
				team = team,
				statue = statue :: Model,
				front = middle,
				half = half,
				target = nil,
				shown = shown,
				from = 0,
				burnt = 0,
				owed = 0,
			})
		end
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, side in sides do
			update(side, now)
		end
	end)
end

return WardenService
