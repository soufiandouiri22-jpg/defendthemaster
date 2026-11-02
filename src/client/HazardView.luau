-- The arena's traps as the players see them (Config.Spikes, FireGrates, NetStatues; HazardService), on the server's
-- beat (Shared.Hazards). A spike tile's holes glow ever faster while it warns, then its spikes shoot up out of the
-- sand with a ring of steel and dust, and sink back after. A grate's ring of warning glows on it, then fire roars up
-- out of it with embers. A net statue shows its prompt (F) to a living hero near it while it is ready and how long it
-- reloads otherwise; fired (its "FiredAt"), it throws a net in an arc ahead of it, and the net lies over each hero it
-- caught (Net.NetStatue) until it lets him go.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Hazards = require(ReplicatedStorage.Shared.Hazards)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local HazardView = {}

local SPIKES, FIRE, NETS = Config.Spikes, Config.FireGrates, Config.NetStatues
local player = Players.LocalPlayer

local WARN = Color3.fromRGB(255, 110, 40)
local FLAME = Color3.fromRGB(255, 150, 50)
local ROPE = Color3.fromRGB(196, 160, 104)
-- How long the spikes take to shoot up and to sink back, and how far up they come (their tips this far over the
-- tile's top at their height).
local RISE, SINK = 0.08, 0.3
local LIFT = SPIKES.Height + 0.3
-- A warning's glow: how much it shows at its brightest, and how many times a second it pulses at its start and end.
local GLOW, PULSE_FROM, PULSE_TO = 0.75, 2, 7
-- The thrown net: how wide it opens, and how high its arc rises; the net over a caught hero.
local NET_WIDE, NET_ARC, NET_WORN = 12, 6, 5
-- The net leaves the mouth of the statue's launcher, this high up its height and this far of it in front of its
-- middle (measured on the kit's net_statue), and lands this far into its reach.
local NET_FROM, NET_OUT, NET_LANDS = 0.65, 0.37, 0.6

type Tile = {
	at: Vector3,
	spikes: { { model: Model, rest: CFrame } },
	glows: { BasePart },
	light: PointLight,
	dust: ParticleEmitter,
	lift: number,
	phase: string,
}

type Grate = {
	at: Vector3,
	ring: ImageLabel,
	fires: { Fire },
	embers: ParticleEmitter,
	light: PointLight,
	phase: string,
}

type Statue = {
	model: Model,
	prompt: ProximityPrompt,
	label: TextLabel,
	at: Vector3,
	front: Vector3,
}

local effects: Folder
local tiles: { Tile } = {}
local grates: { Grate } = {}
local statues: { [number]: Statue } = {}

local function part(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	return p
end

local function emitter(color: Color3, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Rate = 0
	return e
end

-- How brightly a warning `t` seconds in of `length` glows now: pulsing ever faster.
local function pulse(t: number, length: number): number
	local share = math.clamp(t / length, 0, 1)
	local speed = PULSE_FROM + (PULSE_TO - PULSE_FROM) * share
	return (0.5 + 0.5 * math.sin(t * speed * math.pi * 2)) * (0.4 + 0.6 * share)
end

local function addTile(model: Model)
	local spikes = model:FindFirstChild("Spikes")
	local tile: Tile = {
		at = model:GetPivot().Position,
		spikes = {},
		glows = {},
		light = Instance.new("PointLight"),
		dust = emitter(Color3.fromRGB(214, 190, 150), 1.2),
		lift = 0,
		phase = "",
	}
	local piece = model:FindFirstChild("spike_tile")
	if piece and piece:IsA("Model") then
		tile.at = piece:GetPivot().Position * Vector3.new(1, 0, 1)
	end
	for _, spike in if spikes then spikes:GetChildren() else {} do
		if spike:IsA("Model") then
			local rest = spike:GetPivot()
			table.insert(tile.spikes, { model = spike, rest = rest })
			local hole =
				part("SpikeGlow", Vector3.new(0.05, 1.3, 1.3), CFrame.new(rest.Position.X, 0.03, rest.Position.Z))
			hole.Shape = Enum.PartType.Cylinder
			hole.CFrame *= CFrame.Angles(0, 0, math.rad(90))
			hole.Material = Enum.Material.Neon
			hole.Color = WARN
			hole.Parent = effects
			table.insert(tile.glows, hole)
		end
	end
	local base =
		part("SpikeLight", Vector3.new(SPIKES.Width, 0.1, SPIKES.Width), CFrame.new(tile.at + Vector3.new(0, 0.4, 0)))
	tile.light.Color = WARN
	tile.light.Range = 14
	tile.light.Brightness = 0
	tile.light.Shadows = false
	tile.light.Parent = base
	tile.dust.Lifetime = NumberRange.new(0.4, 0.8)
	tile.dust.Speed = NumberRange.new(4, 9)
	tile.dust.SpreadAngle = Vector2.new(70, 70)
	tile.dust.Acceleration = Vector3.new(0, -10, 0)
	tile.dust.Parent = base
	base.Parent = effects
	table.insert(tiles, tile)
end

local function stepTile(tile: Tile, phase: string, t: number)
	local entered = phase ~= tile.phase
	tile.phase = phase
	local glow = if phase == "Warn" then pulse(t, SPIKES.Warn) else 0
	for _, hole in tile.glows do
		hole.Transparency = 1 - glow * GLOW
	end
	tile.light.Brightness = glow * 3
	local lift = 0
	if phase == "Strike" then
		lift = math.min(1, t / RISE)
		if entered then
			UiSound.at("SpikesUp", tile.at)
			tile.dust:Emit(24)
		end
	elseif phase == "Rest" then
		lift = math.max(0, 1 - t / SINK)
	end
	if lift ~= tile.lift then
		tile.lift = lift
		for _, spike in tile.spikes do
			spike.model:PivotTo(spike.rest * CFrame.new(0, LIFT * lift, 0))
		end
	end
end

local function addGrate(model: Model)
	local _, size = model:GetBoundingBox()
	local at = model:GetPivot().Position * Vector3.new(1, 0, 1)
	local top = model:GetPivot().Position.Y + size.Y
	local width = FIRE.Radius * 2
	local plate = part("GrateWarn", Vector3.new(width, 0.05, width), CFrame.new(at.X, top + 0.05, at.Z))
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = 2
	surface.CanvasSize = Vector2.new(512, 512)
	surface.Parent = plate
	local ring = Instance.new("ImageLabel")
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	ring.Image = Assets.IndicatorRing
	ring.ImageColor3 = WARN
	ring.ImageTransparency = 1
	ring.Parent = surface
	local fires = {}
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		local spot = Vector3.new(math.cos(a), 0, math.sin(a)) * FIRE.Radius * 0.45
		local holder = part("GrateFire", Vector3.one * 2, CFrame.new(at.X + spot.X, top + 0.5, at.Z + spot.Z))
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 16
		fire.Color = FLAME
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Enabled = false
		fire.Parent = holder
		holder.Parent = effects
		table.insert(fires, fire)
	end
	local embers = emitter(FLAME, 0.35)
	embers.LightEmission = 1
	embers.Lifetime = NumberRange.new(0.6, 1.4)
	embers.Speed = NumberRange.new(6, 14)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.Parent = plate
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 18
	light.Brightness = 0
	light.Shadows = false
	light.Parent = plate
	plate.Parent = effects
	table.insert(grates, { at = at, ring = ring, fires = fires, embers = embers, light = light, phase = "" })
end

local function stepGrate(grate: Grate, phase: string, t: number)
	local entered = phase ~= grate.phase
	grate.phase = phase
	local burning = phase == "Strike"
	local glow = if phase == "Warn" then pulse(t, FIRE.Warn) else 0
	grate.ring.ImageTransparency = 1 - glow * 0.9
	grate.light.Brightness = if burning then 2.5 + math.sin(t * 18) * 0.5 else glow * 1.5
	grate.embers.Rate = if burning then 30 else 0
	if entered then
		for _, fire in grate.fires do
			fire.Enabled = burning
		end
		if burning then
			UiSound.at("GrateFire", grate.at, nil, 0.7)
		end
	end
end

-- A net of rope, `width` studs wide: its lines either way round an unseen middle.
local function netModel(width: number): Model
	local net = Instance.new("Model")
	net.Name = "Net"
	local lines = 5
	local middle = part("NetMiddle", Vector3.new(0.1, 0.1, 0.1), CFrame.new())
	middle.Parent = net
	net.PrimaryPart = middle
	for i = 1, lines do
		local offset = (i - (lines + 1) / 2) * width / (lines - 1)
		for _, across in { false, true } do
			local size = if across then Vector3.new(width, 0.14, 0.14) else Vector3.new(0.14, 0.14, width)
			local at = if across then Vector3.new(0, 0, offset) else Vector3.new(offset, 0, 0)
			local line = part("NetLine", size, CFrame.new(at))
			line.Transparency = 0
			line.Color = ROPE
			line.Material = Enum.Material.Fabric
			line.Parent = net
		end
	end
	return net
end

local function throw(statue: Statue)
	UiSound.at("NetThrow", statue.at)
	local from = statue.at + Vector3.new(0, NETS.Height * NET_FROM, 0) + statue.front * NETS.Height * NET_OUT
	local to = statue.at + statue.front * NETS.Range * NET_LANDS + Vector3.new(0, 0.3, 0)
	local net = netModel(NET_WIDE)
	net.Parent = effects
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local s = math.min(1, (os.clock() - started) / NETS.Flight)
		local at = from:Lerp(to, s) + Vector3.new(0, NET_ARC * 4 * s * (1 - s), 0)
		net:ScaleTo(0.1 + 0.9 * s)
		net:PivotTo(CFrame.lookAt(at, at + statue.front) * CFrame.Angles(math.rad(20 * (1 - s)), 0, 0))
		if s >= 1 then
			connection:Disconnect()
			task.delay(0.4, function()
				net:Destroy()
			end)
		end
	end)
end

-- The net over each hero `caught` until `untilAt` (server time).
local function wear(caught: { Model }, untilAt: number)
	for _, character in caught do
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local net = netModel(NET_WORN)
		net.Parent = effects
		local spin = math.random() * math.pi * 2
		local connection
		connection = RunService.RenderStepped:Connect(function()
			if Workspace:GetServerTimeNow() >= untilAt or not root.Parent then
				connection:Disconnect()
				net:Destroy()
				return
			end
			net:PivotTo(CFrame.new(root.Position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0.25, spin, 0.15))
		end)
	end
end

local function addStatue(model: Model)
	local index = model:GetAttribute("Index")
	local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if type(index) ~= "number" or not anchorPart then
		return
	end
	local at = model:GetPivot().Position
	local front = model:GetPivot().LookVector * Vector3.new(1, 0, 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fire"
	prompt.ObjectText = "Net Thrower"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = NETS.Reach
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = anchorPart
	local net = ReplicatedStorage:WaitForChild("Net"):WaitForChild("NetStatue") :: RemoteEvent
	prompt.Triggered:Connect(function()
		net:FireServer(index)
	end)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(120, 50)
	board.StudsOffsetWorldSpace = Vector3.new(0, NETS.Height + 2, 0)
	board.MaxDistance = 90
	board.AlwaysOnTop = true
	local holder = part("NetStatueBoard", Vector3.one, CFrame.new(at))
	board.Adornee = holder
	board.Parent = holder
	holder.Parent = effects
	local label = UiStyle.text(board, "", 34, UiStyle.Colors.Cream, UiStyle.Colors.Edge)
	label.Size = UDim2.fromScale(1, 1)
	local statue = { model = model, prompt = prompt, label = label, at = at, front = front.Unit }
	statues[index] = statue
	local thrown = model:GetAttribute("FiredAt")
	model:GetAttributeChangedSignal("FiredAt"):Connect(function()
		if model:GetAttribute("FiredAt") ~= thrown then
			thrown = model:GetAttribute("FiredAt")
			throw(statue)
		end
	end)
end

local function stepStatue(statue: Statue, now: number)
	local left = (statue.model:GetAttribute("ReadyAt") or 0) - now
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	statue.prompt.Enabled = left <= 0 and humanoid ~= nil and humanoid.Health > 0
	statue.label.Text = if left > 0 then tostring(math.ceil(left)) else ""
end

local function update()
	local now = Workspace:GetServerTimeNow()
	if #tiles > 0 then
		local phase, t = Hazards.phase(SPIKES, now)
		for _, tile in tiles do
			stepTile(tile, phase, t)
		end
	end
	if #grates > 0 then
		local phase, t = Hazards.phase(FIRE, now)
		for _, grate in grates do
			stepGrate(grate, phase, t)
		end
	end
	for _, statue in statues do
		stepStatue(statue, now)
	end
end

function HazardView.start()
	if not SPIKES.Enabled and not FIRE.Enabled and not NETS.Enabled then
		return
	end
	local map = Workspace:WaitForChild("Map", 30)
	local features = map and map:WaitForChild("Features", 30)
	if not features then
		return
	end
	effects = Instance.new("Folder")
	effects.Name = "HazardEffects"
	effects.Parent = Workspace
	local spikes = SPIKES.Enabled and features:WaitForChild("Spikes", 10)
	for _, model in if spikes then spikes:GetChildren() else {} do
		if model:IsA("Model") then
			addTile(model)
		end
	end
	local fire = FIRE.Enabled and features:WaitForChild("FireGrates", 10)
	for _, model in if fire then fire:GetChildren() else {} do
		if model:IsA("Model") then
			addGrate(model)
		end
	end
	local nets = NETS.Enabled and features:WaitForChild("NetStatues", 10)
	if nets then
		for _, model in nets:GetChildren() do
			if model:IsA("Model") then
				-- Its Index comes from HazardService once it has started.
				if model:GetAttribute("Index") == nil then
					model:GetAttributeChangedSignal("Index"):Wait()
				end
				addStatue(model)
			end
		end
		local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("NetStatue") :: RemoteEvent
		event.OnClientEvent:Connect(function(_index: number, caught: { Model }, untilAt: number)
			wear(caught, untilAt)
		end)
	end
	RunService.RenderStepped:Connect(update)
end

return HazardView
