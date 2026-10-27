-- Shows the team minions: a copy of the rock minion template (ReplicatedStorage.MinionTemplates) on every root the
-- server moves in Workspace.Minions, smoothed between the server's steps. The minions hop while they walk, lunge when
-- they bite, spit fireballs in their team's fire that burst on their target, fade in at their doorway and crumble into
-- chunks when they die. Each carries a small HP bar in its team's colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MinionView = {}

local HEIGHT = Config.Minions.Height
-- Hops per second of walking, and how high.
local HOP_RATE, HOP_HEIGHT = 2.6, 0.7
local LUNGE_TIME, LUNGE_DISTANCE = 0.32, 1.3
local FADE_IN = 0.45
-- How long the chunks of a dead minion lie on the sand before they fade.
local CRUMBLE_TIME = 1.4
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
-- A soft white ball of light, which takes any colour cleanly.
local GLOW_TEXTURE = "rbxasset://textures/particles/explosion01_implosion_main.dds"
-- The spitter's fireball per team: its white-hot core, its flames, and their outer edge.
local FIRE = {
	Red = { Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 84, 10), Color3.fromRGB(150, 16, 8) },
	Blue = { Color3.fromRGB(110, 220, 255), Color3.fromRGB(30, 110, 255), Color3.fromRGB(18, 26, 150) },
}

type View = {
	root: BasePart,
	model: Model,
	body: BasePart,
	bodyOffset: CFrame,
	cframe: CFrame,
	phase: number,
	lungeAt: number?,
	lungeSign: number,
	fill: Frame,
	dying: boolean,
}

local views: { [BasePart]: View } = {}
local holder: Folder

local function tween(instance: Instance, time: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function healthBar(body: BasePart, team: string): Frame
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromScale(3.2, 0.34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	gui.LightInfluence = 0
	-- Only the minions near the fight, measured from the camera.
	gui.MaxDistance = 55
	gui.Adornee = body
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(22, 20, 24)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(10, 8, 10)
	stroke.Thickness = 1
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Config.Teams[team].Color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner:Clone().Parent = fill
	gui.Parent = body
	return fill
end

local function updateHealth(view: View)
	local health = view.root:GetAttribute("Health") or 0
	local max = view.root:GetAttribute("MaxHealth") or 1
	view.fill.Size = UDim2.fromScale(math.clamp(health / max, 0, 1), 1)
end

local function effectPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- A burst of `count` particles of `texture` at `position`, gone after `life` seconds.
local function burst(position: Vector3, texture: string, count: number, props: { [string]: any }, life: number)
	local anchor = effectPart({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(position) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Rate = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightInfluence = 0
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = anchor
	anchor.Parent = holder
	emitter:Emit(count)
	task.delay(life, function()
		anchor:Destroy()
	end)
end

-- The minion crumbles: it falls apart into chunks of its stone and splinters of its crystals that tumble over the
-- sand in a puff of dust, then fade.
local function crumble(view: View)
	if view.dying then
		return
	end
	view.dying = true
	local bar = view.body:FindFirstChild("HealthBar")
	if bar then
		bar:Destroy()
	end
	local centre = view.cframe.Position + Vector3.new(0, HEIGHT * 0.45, 0)
	local crystal = view.model:FindFirstChild("Crystal") :: BasePart?
	for _, d in view.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("PointLight") then
			d.Enabled = false
		end
	end
	local rng = Random.new()
	local pieces = {}
	for k = 1, 11 do
		local shardPiece = k > 8
		local size = if shardPiece
			then Vector3.new(0.3, rng:NextNumber(0.6, 0.9), 0.3)
			else Vector3.new(rng:NextNumber(0.6, 1.2), rng:NextNumber(0.5, 1.0), rng:NextNumber(0.6, 1.2))
		local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-1.2, 1.4), rng:NextNumber(-1.2, 1.2))
		local piece = effectPart({
			Anchored = false,
			CanCollide = true,
			CastShadow = true,
			Size = size,
			CFrame = CFrame.new(centre + offset) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Color = if shardPiece and crystal then crystal.Color else view.body.Color,
			Material = if shardPiece then Enum.Material.Glass else view.body.Material,
		})
		piece.Parent = holder
		piece.AssemblyLinearVelocity = offset.Unit * rng:NextNumber(8, 14) + Vector3.new(0, rng:NextNumber(8, 14), 0)
		piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		table.insert(pieces, piece)
	end
	burst(view.cframe.Position + Vector3.new(0, 1, 0), "rbxasset://textures/particles/smoke_main.dds", 14, {
		Color = ColorSequence.new(Color3.fromRGB(226, 200, 156)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(3, 7),
		Drag = 4,
	}, 1.5)
	task.delay(CRUMBLE_TIME, function()
		for _, piece in pieces do
			tween(piece, 0.6, { Transparency = 1 })
		end
	end)
	task.delay(CRUMBLE_TIME + 0.7, function()
		for _, piece in pieces do
			piece:Destroy()
		end
	end)
end

local function remove(root: BasePart)
	local view = views[root]
	if not view then
		return
	end
	views[root] = nil
	if not view.dying then
		view.model:Destroy()
		return
	end
	view.model:Destroy()
end

local function add(root: Instance)
	if not root:IsA("BasePart") or views[root] then
		return
	end
	local templates = ReplicatedStorage:WaitForChild("MinionTemplates")
	local template = templates:FindFirstChild((root:GetAttribute("Team") or "") .. (root:GetAttribute("Kind") or ""))
	if not template then
		return
	end
	local model = template:Clone() :: Model
	local body = model.PrimaryPart :: BasePart
	local cframe = root.CFrame * CFrame.new(0, -HEIGHT / 2, 0)
	local view: View = {
		root = root,
		model = model,
		body = body,
		bodyOffset = body.PivotOffset:Inverse(),
		cframe = cframe,
		phase = 0,
		lungeAt = nil,
		lungeSign = 1,
		fill = healthBar(body, root:GetAttribute("Team")),
		dying = false,
	}
	-- The whole model moves into place before it enters the world, where its welds take hold of the parts as they lie.
	model:PivotTo(cframe)
	-- Out of the doorway's dark: every part fades in to its own transparency.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local own = d.Transparency
			d.Transparency = 1
			tween(d, FADE_IN, { Transparency = own })
		end
	end
	-- The crosshair tells enemies from allies by it.
	model:SetAttribute("Team", root:GetAttribute("Team"))
	model.Parent = holder
	views[root] = view
	updateHealth(view)
	root:GetAttributeChangedSignal("Health"):Connect(function()
		updateHealth(view)
	end)
	root:GetAttributeChangedSignal("Dead"):Connect(function()
		if root:GetAttribute("Dead") then
			crumble(view)
		end
	end)
	if root:GetAttribute("Dead") then
		crumble(view)
	end
end

local function targetPoint(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

local function fireSequence(colors: { Color3 }): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.35, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})
end

-- A fireball in the team's fire: a hot core wrapped in glowing flames, throwing off embers and trailing a streak of
-- flame.
local function newFireball(colors: { Color3 }): BasePart
	local core = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		Material = Enum.Material.Neon,
		Color = colors[1],
	})
	local flameColors = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]:Lerp(colors[2], 0.4)),
		ColorSequenceKeypoint.new(0.4, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})

	-- The ball's body: soft puffs of glow in the team's fire, drawn mostly in their own colours so they stay orange or
	-- blue on the bright sand; the puffs left behind make its tail.
	local body = Instance.new("ParticleEmitter")
	body.Name = "Body"
	body.Texture = GLOW_TEXTURE
	body.Rate = 130
	body.Lifetime = NumberRange.new(0.16, 0.3)
	body.Speed = NumberRange.new(0.2, 0.8)
	body.SpreadAngle = Vector2.new(180, 180)
	body.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 0.8) })
	body.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	body.Color = flameColors
	body.LightEmission = 0.3
	body.LightInfluence = 0
	body.ZOffset = 0.4
	body.Parent = core

	-- Licks of flame over it, added as light.
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "Flames"
	flames.Texture = FIRE_TEXTURE
	flames.Rate = 70
	flames.Lifetime = NumberRange.new(0.15, 0.3)
	flames.Speed = NumberRange.new(0.5, 1.5)
	flames.SpreadAngle = Vector2.new(180, 180)
	flames.Rotation = NumberRange.new(0, 360)
	flames.RotSpeed = NumberRange.new(-200, 200)
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.4) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	flames.Color = ColorSequence.new(colors[1], colors[2])
	flames.LightEmission = 0.7
	flames.LightInfluence = 0
	flames.ZOffset = 0.6
	flames.Parent = core

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Rate = 30
	embers.Lifetime = NumberRange.new(0.3, 0.5)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = ColorSequence.new(colors[1])
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Parent = core

	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.7, 0)
	bottom.Position = Vector3.new(0, -0.7, 0)
	top.Parent, bottom.Parent = core, core
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.LightEmission = 0.2
	trail.LightInfluence = 0
	trail.Color = flameColors
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = core

	local light = Instance.new("PointLight")
	light.Color = colors[2]
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = core
	return core
end

-- The fireball bursts: a flash, sparks of flame flung out, and its light dying away.
local function explode(position: Vector3, colors: { Color3 })
	local flash = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		Material = Enum.Material.Neon,
		Color = colors[2],
		Transparency = 0.3,
		CFrame = CFrame.new(position),
	})
	local light = Instance.new("PointLight")
	light.Color = colors[2]
	light.Range = 10
	light.Brightness = 2
	light.Parent = flash
	flash.Parent = holder
	tween(flash, 0.22, { Size = Vector3.one * 3.4, Transparency = 1 })
	tween(light, 0.35, { Brightness = 0 })
	burst(position, FIRE_TEXTURE, 18, {
		Color = fireSequence(colors),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(7, 13),
		Drag = 5,
		LightEmission = 0.2,
		Rotation = NumberRange.new(0, 360),
	}, 0.8)
	task.delay(0.4, function()
		flash:Destroy()
	end)
end

-- A fireball flying in a low arc from the spitter's mouth to `target`, bursting on it after `travel` seconds.
local function spit(view: View, target: Instance, travel: number)
	local colors = FIRE[view.root:GetAttribute("Team")] or FIRE.Red
	local from = (view.cframe * CFrame.new(0, 1.9, -2.2)).Position
	local fireball = newFireball(colors)
	fireball.CFrame = CFrame.new(from)
	fireball.Parent = holder
	local emitters = {}
	for _, d in fireball:GetChildren() do
		if d:IsA("ParticleEmitter") then
			table.insert(emitters, d)
		end
	end
	local started = os.clock()
	local last = from
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - started) / travel)
		local to = targetPoint(target) or last
		local arc = math.sin(t * math.pi) * math.min(3, (to - from).Magnitude * 0.12)
		fireball.CFrame = CFrame.new(from:Lerp(to, t) + Vector3.new(0, arc, 0))
		last = to
		if t >= 1 then
			connection:Disconnect()
			explode(fireball.Position, colors)
			-- The flames already in the air burn out before the fireball goes.
			for _, emitter in emitters do
				emitter.Enabled = false
			end
			for _, d in fireball:GetDescendants() do
				if d:IsA("PointLight") then
					d.Enabled = false
				end
			end
			fireball.Transparency = 1
			task.delay(0.5, function()
				fireball:Destroy()
			end)
		end
	end)
end

local function onAttack(root: BasePart, target: Instance, travel: number)
	local view = views[root]
	if not view or view.dying then
		return
	end
	view.lungeAt = os.clock()
	if root:GetAttribute("Kind") == "Spitter" then
		view.lungeSign = -0.5
		if target then
			spit(view, target, travel)
		end
	else
		view.lungeSign = 1
	end
end

local function step(dt: number)
	local now = os.clock()
	local smoothing = 1 - math.exp(-dt * 10)
	for root, view in views do
		if view.dying then
			view.cframe *= CFrame.new(0, -dt * 2.2, 0)
			view.body.CFrame = view.cframe * view.bodyOffset
			continue
		end
		local goal = root.CFrame * CFrame.new(0, -HEIGHT / 2, 0)
		local before = view.cframe.Position
		view.cframe = view.cframe:Lerp(goal, smoothing)
		local speed = (view.cframe.Position - before).Magnitude / math.max(dt, 1e-3)
		if speed > 1.5 then
			view.phase += dt * HOP_RATE * math.pi
		else
			-- Land at the end of the hop it is in.
			local rest = math.ceil(view.phase / math.pi) * math.pi
			view.phase = math.min(rest, view.phase + dt * HOP_RATE * math.pi)
		end
		local hop = math.abs(math.sin(view.phase))
		local lunge = 0
		if view.lungeAt then
			local t = (now - view.lungeAt) / LUNGE_TIME
			if t >= 1 then
				view.lungeAt = nil
			else
				lunge = math.sin(t * math.pi) * LUNGE_DISTANCE * view.lungeSign
			end
		end
		-- In the air it leans forward a little; it lands flat.
		local pose = CFrame.new(0, hop * HOP_HEIGHT, -lunge) * CFrame.Angles(-math.rad(7) * hop, 0, 0)
		view.body.CFrame = view.cframe * pose * view.bodyOffset
	end
end

-- The rock minion shown on the server's root part `root`, while it lives.
function MinionView.modelOf(root: Instance): Model?
	local view = views[root :: BasePart]
	return if view and not view.dying then view.model else nil
end

function MinionView.start()
	holder = Instance.new("Folder")
	holder.Name = "MinionViews"
	holder.Parent = Workspace
	local minions = Workspace:WaitForChild("Minions")
	minions.ChildAdded:Connect(add)
	minions.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			remove(child)
		end
	end)
	for _, child in minions:GetChildren() do
		add(child)
	end
	local net = ReplicatedStorage:WaitForChild("Net")
	local attackEvent = net:WaitForChild("MinionAttack") :: RemoteEvent
	attackEvent.OnClientEvent:Connect(onAttack)
	RunService.RenderStepped:Connect(step)
end

return MinionView
