-- The two Masters (Config.Master, design 02): each team's king, a Roblox character dressed from the catalogue as the
-- heroes are, three times their size, on his throne. He carries the "Master", "Team" and "Radius" attributes and the
-- "Combatant" tag, so heroes and minions fight him and MatchService shows his health; he never heals. His "State"
-- attribute tells the clients (MasterView) what he does: "Seated" on his throne (anchored), "Rising" when an enemy
-- comes into his zone, "Drawing" while he stands and draws his sword from his back, "Fight" while he chases and
-- strikes, "Returning" when he walks back to sit down, "Sheathing" before his throne while he puts his sword on his
-- back, "Dead".
-- Every strike is told to the clients first (Net.MasterAction: the Master, "Swing" or "Slam", the seconds until it
-- lands, then for a swing which of Config.Master.Swing.Motions it is, for a slam the spot on the ground and its radius,
-- for the red circle), then lands as a hero's does (Net.HeroHit). He holds his animation pack's weapon.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Damage = require(script.Parent.Damage)
local MatchService = require(script.Parent.MatchService)
local MinionService = require(script.Parent.MinionService)
local ProgressService = require(script.Parent.ProgressService)

local MasterService = {}

local SETTINGS = Config.Master
local BODY_COLOURS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
-- How fast he turns to face his target, in radians a second.
local TURN = 4
-- He stops this share of his reach short of his target, so a step back does not take it out of reach.
local CLOSE = 0.7
-- After a swing or slam lands he stands still this much longer.
local SETTLE = 0.45
-- He has sat down again once he is this close to the spot before his throne.
local ARRIVED = 2.5
-- The weapon of his pack's rig, and the joint its clips swing it by.
local WEAPON = "Greataxe"

type Foe = {
	instance: Instance,
	position: Vector3,
	radius: number,
	hero: boolean,
}

type Master = {
	team: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	throne: CFrame,
	stand: CFrame,
	front: Vector3,
	state: string,
	target: Foe?,
	calmSince: number?,
	busyUntil: number,
	nextSwing: number,
	slamReady: number,
	aloneSince: number?,
	combo: number,
}

local masters: { Master } = {}
local actionEvent: RemoteEvent
local hitEvent: RemoteEvent

local function description(team: string): HumanoidDescription
	local look = SETTINGS.Look
	local own = SETTINGS.TeamLook[team] or {}
	local d = Instance.new("HumanoidDescription")
	d.Shirt = look.Shirt
	d.Pants = look.Pants
	d.HatAccessory = look.HatAccessory
	d.BackAccessory = own.BackAccessory or look.BackAccessory
	d.FaceAccessory = look.FaceAccessory
	for _, part in BODY_COLOURS do
		(d :: any)[part] = look.Skin
	end
	-- The heroes' proportions (HeroService.description).
	d.BodyTypeScale = 0
	d.ProportionScale = 0
	return d
end

local function setState(m: Master, state: string)
	m.state = state
	m.model:SetAttribute("State", state)
end

-- The enemies of `team` within `reach` studs of `centre` (flat): heroes and minions.
local function foes(team: string, centre: Vector3, reach: number): { Foe }
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
				table.insert(found, {
					instance = root,
					position = root.Position,
					radius = Config.Minions.Radius,
					hero = false,
				})
			end
		end
	end
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("Hero") and model:GetAttribute("Team") ~= team then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local position = model:GetPivot().Position
			local radius = model:GetAttribute("Radius") or 1.5
			if humanoid and humanoid.Health > 0 and HeroKit.flat(position - centre).Magnitude <= reach + radius then
				table.insert(found, { instance = model, position = position, radius = radius, hero = true })
			end
		end
	end
	return found
end

-- The enemy `m` goes for: the nearest enemy hero in his zone, else the nearest minion there.
local function choose(m: Master, inZone: { Foe }): Foe?
	local best: Foe? = nil
	local bestGap = math.huge
	for _, foe in inZone do
		local gap = HeroKit.flat(foe.position - m.root.Position).Magnitude + (if foe.hero then 0 else 1e6)
		if gap < bestGap then
			best, bestGap = foe, gap
		end
	end
	return best
end

local function strike(foe: Foe, amount: number)
	local target = foe.instance
	if target:IsA("BasePart") then
		amount = math.round(amount)
		hitEvent:FireAllClients(target, amount, foe.position, nil)
		MinionService.damage(target, amount, nil)
		return
	end
	local model = target :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	amount = math.round(Damage.mitigated(model, amount, false, nil))
	hitEvent:FireAllClients(model, amount, foe.position, nil)
	ProgressService.hurtByMaster(model)
	humanoid:TakeDamage(amount)
end

-- Where his feet stand.
local function ground(m: Master): Vector3
	return m.root.Position - Vector3.new(0, m.humanoid.HipHeight + m.root.Size.Y / 2, 0)
end

local function fighting(m: Master): boolean
	return m.state == "Fight" and m.humanoid.Health > 0
end

local function swing(m: Master, now: number)
	local settings = SETTINGS.Swing
	m.combo = m.combo % #settings.Motions + 1
	local hit = settings.Hits[m.combo]
	m.busyUntil = now + math.max(hit + SETTLE, settings.Length)
	m.nextSwing = now + settings.Every
	actionEvent:FireAllClients(m.model, "Swing", hit, m.combo)
	task.delay(hit, function()
		if not fighting(m) then
			return
		end
		local origin = m.root.Position
		local facing = HeroKit.flat(m.root.CFrame.LookVector).Unit
		for _, foe in foes(m.team, origin, SETTINGS.Reach) do
			if HeroKit.inCone(origin, facing, SETTINGS.Reach, settings.Angle, foe.position, foe.radius) then
				strike(foe, settings.Damage)
			end
		end
	end)
end

local function slam(m: Master, now: number, centre: Vector3)
	local settings = SETTINGS.Slam
	local windup = settings.FrenzyLength + settings.Impact
	m.busyUntil = now + settings.FrenzyLength + math.max(settings.Impact + SETTLE, settings.Length)
	m.slamReady = now + settings.Cooldown
	m.nextSwing = math.max(m.nextSwing, m.busyUntil)
	m.aloneSince = nil
	actionEvent:FireAllClients(m.model, "Slam", windup, centre, settings.Radius)
	task.delay(windup, function()
		if not fighting(m) then
			return
		end
		for _, foe in foes(m.team, centre, settings.Radius) do
			strike(foe, settings.Damage)
		end
	end)
end

-- Turns `m` towards `point` by at most TURN * dt.
local function face(m: Master, point: Vector3, dt: number)
	local root = m.root
	local want = HeroKit.flat(point - root.Position)
	if want.Magnitude < 0.1 then
		return
	end
	local look = HeroKit.flat(root.CFrame.LookVector).Unit
	local angle = math.atan2(look:Cross(want.Unit).Y, look:Dot(want.Unit))
	local step = math.clamp(angle, -TURN * dt, TURN * dt)
	root.CFrame = root.CFrame * CFrame.Angles(0, step, 0)
end

local function sit(m: Master)
	m.root.Anchored = true
	m.humanoid:MoveTo(m.root.Position)
	m.model:PivotTo(m.throne)
	m.target = nil
	setState(m, "Seated")
end

local function rise(m: Master)
	setState(m, "Rising")
	task.delay(SETTINGS.Rise, function()
		if m.state ~= "Rising" or m.humanoid.Health <= 0 then
			return
		end
		local lift = m.humanoid.HipHeight + m.root.Size.Y / 2
		m.model:PivotTo(m.stand + Vector3.new(0, lift, 0))
		m.root.Anchored = false
		m.root:SetNetworkOwner(nil)
		m.humanoid:ChangeState(Enum.HumanoidStateType.Running)
		m.humanoid:MoveTo(m.root.Position)
		m.calmSince = nil
		setState(m, "Drawing")
		task.wait(SETTINGS.Draw.Length)
		if m.state ~= "Drawing" or m.humanoid.Health <= 0 then
			return
		end
		m.slamReady = math.max(m.slamReady, os.clock() + SETTINGS.Slam.FrenzyLength)
		setState(m, "Fight")
	end)
end

local function update(m: Master, dt: number, now: number)
	if
		m.humanoid.Health <= 0
		or m.state == "Rising"
		or m.state == "Drawing"
		or m.state == "Sheathing"
		or m.state == "Dead"
	then
		return
	end
	local inZone = if MatchService.fighting() then foes(m.team, m.front, SETTINGS.Zone) else {}
	if m.state == "Seated" then
		if #inZone > 0 then
			rise(m)
		end
		return
	end

	if #inZone == 0 then
		m.calmSince = m.calmSince or now
	else
		m.calmSince = nil
		if m.state == "Returning" then
			setState(m, "Fight")
		end
	end

	local busy = now < m.busyUntil
	m.humanoid.WalkSpeed = if busy then 0 else SETTINGS.WalkSpeed

	if m.state == "Fight" and m.calmSince and now - m.calmSince >= SETTINGS.Calm and not busy then
		setState(m, "Returning")
	end
	if m.state == "Returning" then
		local home = m.stand.Position
		if HeroKit.flat(home - m.root.Position).Magnitude <= ARRIVED then
			m.humanoid:MoveTo(m.root.Position)
			setState(m, "Sheathing")
			task.delay(SETTINGS.Sheath.Length, function()
				if m.state == "Sheathing" and m.humanoid.Health > 0 then
					sit(m)
				end
			end)
		else
			m.humanoid:MoveTo(home)
		end
		return
	end

	local target = choose(m, inZone)
	m.target = target
	if not target then
		m.humanoid:MoveTo(m.root.Position)
		return
	end
	face(m, target.position, dt)
	if busy then
		m.humanoid:MoveTo(m.root.Position)
		return
	end

	local gap = HeroKit.flat(target.position - m.root.Position).Magnitude - target.radius
	local direction = HeroKit.direction(m.root.Position, target.position, m.root.CFrame.LookVector)
	local settings = SETTINGS.Slam
	if now >= m.slamReady then
		local centre = ground(m) + direction * settings.Ahead
		local crowd = #foes(m.team, centre, settings.Radius)
		if target.hero and gap <= SETTINGS.Reach then
			m.aloneSince = m.aloneSince or now
		else
			m.aloneSince = nil
		end
		if
			(crowd >= settings.Crowd and gap <= settings.Radius)
			or (m.aloneSince ~= nil and now - m.aloneSince >= settings.Alone)
		then
			slam(m, now, centre)
			return
		end
	end
	if gap <= SETTINGS.Reach then
		m.humanoid:MoveTo(m.root.Position)
		if now >= m.nextSwing then
			swing(m, now)
		end
		return
	end
	local goal = target.position - direction * SETTINGS.Reach * CLOSE
	local out = HeroKit.flat(goal - m.front)
	if out.Magnitude > SETTINGS.Leash then
		goal = m.front + out.Unit * SETTINGS.Leash
	end
	m.humanoid:MoveTo(goal)
end

-- His hands are as wide as his forearms, so where a hand lies in its sleeve their sides would share one plane and
-- flicker between skin and cloth: his forearms grow this much wider, their sleeves closing round his wrists.
local CUFF = 1.03

local function cuffs(model: Model)
	for _, name in { "LeftLowerArm", "RightLowerArm" } do
		local part = model:FindFirstChild(name) :: BasePart?
		if part then
			part.Size = Vector3.new(part.Size.X * CUFF, part.Size.Y, part.Size.Z * CUFF)
		end
	end
end

-- Gives him the pack's weapon joint in his right hand, as on the pack's rig, with an unseen stand-in for the pack's
-- axe on it, so its clips move that exactly as they move the axe. His sword hangs on his back (SwordRest, from his
-- upper torso, Config.Master.Sword.Back) or, once he draws it (MasterView switches the two), lies in his fist on the
-- stand-in (SwordHold): its grip where the pack's hand closes round the axe's haft, its blade along the haft towards
-- the axe's head.
local function arm(model: Model)
	local scale = SETTINGS.Scale
	local function grow(frame: CFrame): CFrame
		return CFrame.new(frame.Position * scale) * frame.Rotation
	end
	local rig = ReplicatedStorage:WaitForChild(SETTINGS.Pack):WaitForChild("Rig")
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	local motor: Motor6D? = nil
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == WEAPON then
			motor = d
		end
	end
	local sword = SETTINGS.Sword
	local source = ServerStorage:FindFirstChild(sword.Name) :: BasePart?
	if not motor or not hand or not torso or not source then
		warn("[MasterService] cannot arm the Master:", sword.Name)
		return
	end
	local function loose(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end

	local carrier = Instance.new("Part")
	carrier.Name = WEAPON
	carrier.Size = Vector3.one * 0.2
	carrier.Transparency = 1
	carrier.CastShadow = false
	loose(carrier)
	carrier.CFrame = hand.CFrame * grow(motor.C0) * grow(motor.C1):Inverse()
	carrier.Parent = model
	local joint = Instance.new("Motor6D")
	joint.Name = WEAPON
	joint.Part0 = hand
	joint.Part1 = carrier
	joint.C0 = grow(motor.C0)
	joint.C1 = grow(motor.C1)
	joint.Parent = hand

	local weapon = source:Clone()
	weapon.Name = "MasterSword"
	loose(weapon)
	weapon.Size = source.Size * (sword.Length / source.Size.X)
	local hold = weapon.Size.X * sword.Grip
	local back = sword.Back
	local lean = math.rad(back.Lean)
	local down = Vector3.new(-math.sin(lean), -math.cos(lean), 0)
	local rest = Instance.new("Weld")
	rest.Name = "SwordRest"
	rest.Part0 = torso
	rest.Part1 = weapon
	rest.C0 = CFrame.fromMatrix(back.At + down * hold, down, Vector3.new(0, 0, 1):Cross(down))
	rest.Parent = weapon
	local inHand = Instance.new("Weld")
	inHand.Name = "SwordHold"
	inHand.Part0 = carrier
	inHand.Part1 = weapon
	inHand.C0 = CFrame.fromMatrix(grow(motor.C1).Position + Vector3.yAxis * hold, Vector3.yAxis, -Vector3.xAxis)
	inHand.Enabled = false
	inHand.Parent = weapon
	weapon.CFrame = torso.CFrame * rest.C0
	weapon.Parent = model
end

local function create(team: string, layout: Layout): Master
	local model = Players:CreateHumanoidModelFromDescription(description(team), Enum.HumanoidRigType.R15)
	model.Name = team .. "Master"
	local shirt = model:FindFirstChildOfClass("Shirt")
	local template = (SETTINGS.TeamLook[team] or {}).ShirtTemplate
	if shirt and template then
		shirt.ShirtTemplate = template
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	model:ScaleTo(SETTINGS.Scale)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	-- His body has its size now; the Humanoid would grow his weapon over again.
	humanoid.AutomaticScalingEnabled = false
	cuffs(model)
	arm(model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	humanoid.MaxHealth = SETTINGS.Health
	humanoid.Health = SETTINGS.Health
	humanoid.WalkSpeed = SETTINGS.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- Anchored on his throne he would count as falling, and lie for seconds once he stands up.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	model:SetAttribute("Master", true)
	model:SetAttribute("Team", team)
	model:SetAttribute("Radius", 1.5 * SETTINGS.Scale)

	local m: Master = {
		team = team,
		model = model,
		humanoid = humanoid,
		root = root,
		throne = layout.thrones[team],
		stand = layout.masterSpawn[team],
		front = layout.daisFront[team],
		state = "Seated",
		target = nil,
		calmSince = nil,
		busyUntil = 0,
		nextSwing = 0,
		slamReady = 0,
		aloneSince = nil,
		combo = 0,
	}
	root.Anchored = true
	model:PivotTo(m.throne)
	setState(m, "Seated")
	model.Parent = Workspace:FindFirstChild("Masters")
	CollectionService:AddTag(model, "Combatant")
	-- He falls with his pack's clip (MasterView), where he stands.
	humanoid.Died:Connect(function()
		setState(m, "Dead")
		root.Anchored = true
	end)
	return m
end

export type Layout = {
	thrones: { [string]: CFrame },
	masterSpawn: { [string]: CFrame },
	daisFront: { [string]: Vector3 },
}

-- Seats a Master on each of `teams`' thrones, every team's unless given.
function MasterService.start(layout: Layout, teams: { string }?)
	local net = ReplicatedStorage:WaitForChild("Net") :: Folder
	actionEvent = Instance.new("RemoteEvent")
	actionEvent.Name = "MasterAction"
	actionEvent.Parent = net
	hitEvent = net:WaitForChild("HeroHit") :: RemoteEvent

	local folder = Instance.new("Folder")
	folder.Name = "Masters"
	folder.Parent = Workspace
	for _, team in teams or Config.TeamOrder do
		table.insert(masters, create(team, layout))
	end

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, m in masters do
			update(m, dt, now)
		end
	end)
end

return MasterService
