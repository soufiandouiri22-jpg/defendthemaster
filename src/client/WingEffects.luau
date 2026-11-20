-- Kraeven's wings of see-through blue light for his ultimate (a Leap's `Wings`; owner, 2026-11-20): two great wings
-- burst out of his back in a flash as it starts, beat at the kit's `Flaps` as each beat lifts him (HeroKit.lift),
-- spread while he hangs, sweep back as he dives at the spot and fade into sparkles as he lands, a crow's creepy caws
-- as they burst out and each beat heard (UiSound). The wings are the Creator Store's rigged "Angel Wings"
-- (Docs/Third_Party.md), kept in the place as `ReplicatedStorage.AngelWings` (Rojo cannot set a MeshPart's mesh): one
-- mesh, each wing a chain of bones from shoulder to elbow, wrist and tip, turned here so the wings beat, their hands
-- trailing as they rise and whipping through as they strike. Built and moved on each client from his root part;
-- nothing of it is on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UiSound = require(script.Parent.UiSound)

local WingEffects = {}

local MIST = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- The wings' width as kept in the place, and where in it their shoulders meet (studs from its middle: right, up,
-- back), from where they hang on his back.
local WIDTH = 20
local ROOT = Vector3.new(0.05, 0.01, -1.69)
-- Each wing's bones from the shoulder out, its right one first.
local CHAINS = {
	{ "Bone.001", "Bone.005", "Bone.004", "Bone.003" },
	{ "Bone.002", "Bone.008", "Bone.007", "Bone.006" },
}

-- The wings' layers of the mesh: its material, colour and clearness, and how much larger than the wings it is: a
-- shimmering see-through blue, with a faint glow round it (owner's pick of five, 2026-11-20).
type Layer = { material: Enum.Material, colour: Color3, clear: number, grow: number? }
local LAYERS: { Layer } = {
	{ material = Enum.Material.ForceField, colour = Color3.fromRGB(80, 170, 255), clear = 0 },
	{ material = Enum.Material.Neon, colour = Color3.fromRGB(90, 170, 255), clear = 0.82, grow = 1.04 },
}

-- Seconds the wings take to burst open, springing a little past their size and unfolding from his back, and how
-- brightly the light round him flashes then.
local OPEN, FLASH = 0.35, 4
-- The wings' angle up from level as they glide, at the top of a beat and at its bottom (radians); how long before a
-- beat they rise, how long the stroke down takes and how long they take back to gliding; how far they sway as they
-- glide, and how fast.
local GLIDE, TOP, BOTTOM = math.rad(5), math.rad(45), math.rad(-40)
local RAISE, STROKE, SETTLE = 0.2, 0.16, 0.35
local SWAY, SWAY_SPEED = math.rad(5), 7
-- How far forward they reach at the bottom of a beat; how far each joint of the hand bends for each radian a second
-- the wings turn, and the most it bends either way; how folded they start (back and down).
local REACH = math.rad(25)
local BEND, MOST_BEND = 0.05, math.rad(35)
local FOLD_BACK, FOLD_DOWN = math.rad(70), math.rad(50)
-- How far back they sweep as he dives and how long that takes; how long they take to fade as he lands, how much
-- larger they grow meanwhile, and how long the sparkles they leave linger after.
local SWEEP, SWEEP_TIME = math.rad(55), 0.15
local FADE, BLOW, LINGER = 0.3, 0.25, 1.2
-- Where on his back the wings meet (studs from his root part: right, up, back).
local BACK = Vector3.new(0, 1.35, 0.45)

-- A bone and the axes it turns about, seen from it: the wings' forward axis (beating up and down) and their up axis
-- (sweeping back and forth).
type Joint = { bone: Bone, beat: Vector3, sweep: Vector3 }
type Shell = { model: Model, mesh: MeshPart, layer: Layer, joints: { { Joint } } }

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- From 0 out past 1 and back to it, for the wings bursting open.
local function spring(a: number): number
	a = math.clamp(a, 0, 1) - 1
	return 1 + 2.4 * a * a * a + 1.4 * a * a
end

-- The wings' angle `t` seconds in: gliding with a slight sway, each beat rising before its time, struck down and
-- settling again, each rising from wherever the last one left them.
local function beatAngle(t: number, flaps: { number }): number
	local angle = GLIDE + math.sin(t * SWAY_SPEED) * SWAY
	for _, at in flaps do
		if t >= at - RAISE and t < at then
			angle += (TOP - angle) * ease((t - at + RAISE) / RAISE)
		elseif t >= at and t < at + STROKE then
			local a = (t - at) / STROKE
			angle = TOP + (BOTTOM - TOP) * a * a
		elseif t >= at + STROKE and t < at + STROKE + SETTLE then
			angle = BOTTOM + (angle - BOTTOM) * ease((t - at - STROKE) / SETTLE)
		end
	end
	return angle
end

local function emitter(texture: string, colour: Color3, size: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.LightInfluence = 0
	e.Rate = rate
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	if texture == SPARKLE then
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), colour)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.5, 1)
		e.Speed = NumberRange.new(0.5, 2)
		e.Drag = 2
		e.Acceleration = Vector3.new(0, -2, 0)
	else
		e.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.5), colour)
		e.LightEmission = 0.7
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Speed = NumberRange.new(0.3, 1)
		e.RotSpeed = NumberRange.new(-60, 60)
	end
	return e
end

-- A copy of the wings in `layer`, under `holder`, with each of its bones' axes.
local function shell(template: MeshPart, holder: Instance, layer: Layer): Shell
	local mesh = template:Clone()
	mesh.Material = layer.material
	mesh.Color = layer.colour
	mesh.Transparency = layer.clear
	mesh.CFrame = CFrame.new()
	local model = Instance.new("Model")
	model.Name = "Wings"
	mesh.Parent = model
	model.PrimaryPart = mesh
	model.Parent = holder
	local joints = {}
	for _, chain in CHAINS do
		local list = {}
		for _, name in chain do
			local bone = mesh:FindFirstChild(name, true) :: Bone
			local rest = bone.WorldCFrame
			table.insert(list, {
				bone = bone,
				beat = rest:VectorToObjectSpace(Vector3.zAxis),
				sweep = rest:VectorToObjectSpace(Vector3.yAxis),
			})
		end
		table.insert(joints, list)
	end
	return { model = model, mesh = mesh, layer = layer, joints = joints }
end

-- Spreads `character`'s wings for the Leap `kit` (its `Wings` the look: `Span` studs from tip to tip, `Color` the
-- light they shed) diving at `landing`, from now till it lands.
function WingEffects.spread(character: Model, kit: any, landing: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local template = ReplicatedStorage:FindFirstChild("AngelWings") :: MeshPart?
	if not root or not humanoid or not template then
		return
	end
	local look = kit.Wings
	local flaps = kit.Flaps or {}
	local holder = Instance.new("Folder")
	holder.Name = "Wings"
	local shells: { Shell } = {}
	for _, layer in LAYERS do
		table.insert(shells, shell(template, holder, layer))
	end
	local first = shells[1]
	local sparkles, mist = {}, {}
	for _, chain in first.joints do
		for i = 2, #chain do
			local e = emitter(SPARKLE, look.Color, look.Span * 0.02, 10)
			e.Parent = chain[i].bone
			table.insert(sparkles, e)
		end
		local m = emitter(MIST, look.Color, look.Span * 0.05, 6)
		m.Parent = chain[#chain].bone
		table.insert(mist, m)
	end
	local light = Instance.new("PointLight")
	light.Color = look.Color
	light.Range = look.Span * 0.8
	light.Brightness = 0
	light.Parent = first.mesh
	holder.Parent = effects()
	UiSound.at("CrowCaw", root)

	local started = os.clock()
	local facing = root.CFrame.Rotation
	local beaten = 0
	local fading: number? = nil
	local burst = false
	local last = 0
	local lastAngle = beatAngle(0, flaps)
	local bend = 0
	local hung: CFrame? = nil
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if not fading and (t >= kit.Land or not root.Parent or humanoid.Health <= 0) then
			fading = t
			UiSound.at("WingsFade", root.Position)
			for _, e in sparkles do
				e.Rate = 0
				e.Speed = NumberRange.new(4, 12)
				e:Emit(14)
			end
			for _, e in mist do
				e.Rate = 0
				e:Emit(4)
			end
		end
		if fading and t >= fading + FADE + LINGER then
			connection:Disconnect()
			holder:Destroy()
			return
		end
		local gone = if fading then math.clamp((t - fading) / FADE, 0, 1) else 0
		local opening = math.clamp(t / OPEN, 0, 1)
		local size = look.Span / WIDTH * spring(opening) * (1 + BLOW * gone)
		local flash = 1 + FLASH * (1 - opening)
		light.Brightness = 3 * (1 - gone) * flash

		local angle = beatAngle(t, flaps)
		local step = t - last
		local turning = if step > 0 then (angle - lastAngle) / step else 0
		last, lastAngle = t, angle
		bend += (math.clamp(turning * BEND, -MOST_BEND, MOST_BEND) - bend) * math.min(1, 12 * step)
		local reach = REACH * math.clamp((GLIDE - angle) / (GLIDE - BOTTOM), 0, 1)
		local sweep = if t >= kit.Fall then SWEEP * ease((t - kit.Fall) / SWEEP_TIME) else 0
		local folded = 1 - ease(opening)
		local frame = root.CFrame.Rotation
		if t >= kit.Fall then
			-- Turned from where he faced to face the way he dives.
			local way = Vector3.new(landing.X - root.Position.X, 0, landing.Z - root.Position.Z)
			local dive = if way.Magnitude > 0.5 then CFrame.lookAt(Vector3.zero, way) else facing
			frame = facing:Lerp(dive, ease((t - kit.Fall) / SWEEP_TIME))
		else
			facing = frame
		end
		-- Left hanging where they were once they start to fade.
		local back = hung
		if not back or not fading then
			back = CFrame.new(root.Position + frame:VectorToWorldSpace(BACK)) * frame
			hung = back
		end
		assert(back, "the wings hang somewhere")

		for _, s in shells do
			local scale = size * (s.layer.grow or 1)
			s.model:ScaleTo(scale)
			s.mesh.CFrame = back * CFrame.new(-ROOT * scale)
			s.mesh.Transparency = s.layer.clear + (1 - s.layer.clear) * gone
			for side, chain in s.joints do
				local sign = if side == 1 then 1 else -1
				local shoulder = chain[1]
				shoulder.bone.Transform = CFrame.fromAxisAngle(shoulder.beat, sign * (angle - FOLD_DOWN * folded))
					* CFrame.fromAxisAngle(shoulder.sweep, -sign * (sweep + FOLD_BACK * folded - reach))
				for i = 2, 3 do
					local joint = chain[i]
					joint.bone.Transform = CFrame.fromAxisAngle(joint.beat, -sign * bend)
				end
			end
		end

		-- A burst of starlight out of his back as they open, and a shower off every feather on each beat's stroke.
		if not burst then
			burst = true
			for _, e in sparkles do
				e:Emit(8)
			end
			for _, e in mist do
				e:Emit(2)
			end
		end
		while beaten < #flaps and t >= flaps[beaten + 1] do
			beaten += 1
			UiSound.at("WingBeat", root)
			for _, e in sparkles do
				e:Emit(5)
			end
			for _, e in mist do
				e:Emit(2)
			end
		end
	end)
end

return WingEffects
