-- Shows every hit a hero lands (Net.HeroHit from the server: the target, the damage, where, and who struck): the target
-- flashes white for a moment, brighter the harder the hit, and the striker sees the damage pop up from it and arc away,
-- to the left and right in turn. How hard a hit was reads at a glance from its tier (TIERS): light hits small and
-- white, medium ones gold, heavy ones big, red-hot and with a burst of sparks. Hits sound as a series
-- (Config.Combat.HitSounds, none when it is empty), each striker's next one in turn and the first again after a pause: flat
-- for the striker and the one struck, from where it lands for everyone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MinionView = require(script.Parent.MinionView)
local Preferences = require(script.Parent.Preferences)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local HitFeedback = {}

type Tier = {
	from: number,
	size: number,
	top: Color3,
	bottom: Color3,
	edge: Color3,
	stroke: number,
	-- How far it overshoots when it pops up (the back-ease's constant: 2 about 13 %, 3 25 %, 4.5 45 %), and how bright the
	-- target flashes (0 white, 1 not at all).
	pop: number,
	flash: number,
	sparks: number,
}

-- From the lightest; a hit takes the last tier whose `from` it reaches.
local TIERS: { Tier } = {
	{
		from = 0,
		size = 30,
		top = Color3.fromRGB(255, 255, 255),
		bottom = Color3.fromRGB(214, 224, 236),
		edge = Color3.fromRGB(34, 38, 56),
		stroke = 2.5,
		pop = 2,
		flash = 0.45,
		sparks = 0,
	},
	{
		from = 50,
		size = 40,
		top = Color3.fromRGB(255, 240, 150),
		bottom = Color3.fromRGB(255, 176, 30),
		edge = Color3.fromRGB(86, 44, 0),
		stroke = 3,
		pop = 3,
		flash = 0.25,
		sparks = 0,
	},
	{
		from = 90,
		size = 54,
		top = Color3.fromRGB(255, 168, 64),
		bottom = Color3.fromRGB(232, 28, 22),
		edge = Color3.fromRGB(60, 4, 0),
		stroke = 3.5,
		pop = 4.5,
		flash = 0.05,
		sparks = 14,
	},
}

-- A heal from a spawn pad (HitFeedback.heal), in the health bar's green.
local HEAL: Tier = {
	from = 0,
	size = 38,
	top = Color3.fromRGB(196, 255, 150),
	bottom = Color3.fromRGB(70, 214, 60),
	edge = Color3.fromRGB(14, 64, 10),
	stroke = 3,
	pop = 3,
	flash = 1,
	sparks = 0,
}

local FLASH_TIME = 0.18
-- The least time between two flat hit sounds, so one swing through a crowd sounds once rather than louder.
local SOUND_GAP = 0.05
-- A number pops up over POP seconds, flies for LIFE seconds in all, and fades over the last FADE of them.
local POP, LIFE, FADE = 0.16, 0.85, 0.3
-- Its arc: it starts this high over the hit, rises at RISE studs a second against GRAVITY, and drifts SPREAD studs aside.
local START_HEIGHT, RISE, GRAVITY, SPREAD = 3.2, 6.5, 12, 1.6

type Number = {
	gui: BillboardGui,
	scale: UIScale,
	label: TextLabel,
	stroke: UIStroke,
	tier: Tier,
	started: number,
	side: Vector3,
	tilt: number,
}

local player = Players.LocalPlayer
local flashing: { [Instance]: Highlight } = {}
local live: { Number } = {}
local nextSide = 1
local lastSound = 0
-- Per striker (the player's own hits and those on him together) the last of Config.Combat.HitSounds played, and when.
local series: { [any]: { step: number, at: number } } = setmetatable({}, { __mode = "k" }) :: any

local function tierOf(amount: number): Tier
	local found = TIERS[1]
	for _, tier in TIERS do
		if amount >= tier.from then
			found = tier
		end
	end
	return found
end

local function flash(target: Instance, tier: Tier)
	local model = if target:IsA("BasePart") then MinionView.modelOf(target) else target
	if not model then
		return
	end
	local highlight = flashing[model]
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.OutlineTransparency = 1
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.Adornee = model
		highlight.Parent = model
		flashing[model] = highlight
	end
	local h = highlight :: Highlight
	h.FillTransparency = math.min(h.FillTransparency, tier.flash)
	TweenService:Create(h, TweenInfo.new(FLASH_TIME), { FillTransparency = 1 }):Play()
	task.delay(FLASH_TIME + 0.05, function()
		if flashing[model] == h and h.FillTransparency >= 0.99 then
			flashing[model] = nil
			h:Destroy()
		end
	end)
end

local function sparks(anchor: BasePart, tier: Tier)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(tier.top, tier.bottom)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0)
	emitter.Lifetime = NumberRange.new(0.18, 0.32)
	emitter.Speed = NumberRange.new(14, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.ZOffset = 2
	emitter.Parent = anchor
	emitter:Emit(tier.sparks)
end

local function number(at: Vector3, text: string, tier: Tier)
	if Preferences.get("DamageNumbers") == false then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = at

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 90)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.StudsOffsetWorldSpace = Vector3.new(0, START_HEIGHT, 0)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = UiStyle.Font
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = tier.size
	label.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(tier.top, tier.bottom)
	gradient.Rotation = 90
	gradient.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = tier.edge
	stroke.Thickness = tier.stroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label
	gui.Parent = anchor
	anchor.Parent = Workspace:FindFirstChild("Effects") or Workspace
	if tier.sparks > 0 then
		sparks(anchor, tier)
	end

	local camera = Workspace.CurrentCamera
	local right = if camera then camera.CFrame.RightVector else Vector3.xAxis
	nextSide = -nextSide
	table.insert(live, {
		gui = gui,
		scale = scale,
		label = label,
		stroke = stroke,
		tier = tier,
		started = os.clock(),
		side = right * nextSide * SPREAD * (0.75 + math.random() * 0.5),
		tilt = nextSide * (if tier.sparks > 0 then 8 else 3),
	})
	task.delay(LIFE + 0.4, function()
		anchor:Destroy()
	end)
end

local function easeOutBack(a: number, overshoot: number): number
	local c = overshoot
	return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
end

local function update()
	local now = os.clock()
	for i = #live, 1, -1 do
		local n = live[i]
		local t = now - n.started
		if t >= LIFE or not n.gui.Parent then
			n.gui.Enabled = false
			table.remove(live, i)
			continue
		end
		local pop = math.clamp(t / POP, 0, 1)
		local size = easeOutBack(pop, n.tier.pop)
		local fade = math.clamp((t - (LIFE - FADE)) / FADE, 0, 1)
		n.scale.Scale = math.max(0.05, size * (1 - 0.35 * fade))
		n.label.Rotation = n.tilt * (1 - pop)
		n.label.TextTransparency = fade
		n.stroke.Transparency = fade
		local drift = math.min(1, t / LIFE)
		n.gui.StudsOffsetWorldSpace = Vector3.new(0, START_HEIGHT + RISE * t - GRAVITY * t * t / 2, 0) + n.side * drift
	end
end

-- Shows the player's hero healing `amount` at `at`, as a green "+amount".
function HitFeedback.heal(at: Vector3, amount: number)
	number(at, "+" .. math.round(amount), HEAL)
end

-- The next of the hit sounds in `key`'s series, from the first again after a pause.
local function nextSound(key: any): string
	local sounds = Config.Combat.HitSounds
	local now = os.clock()
	local last = series[key]
	if not last or now - last.at > Config.Combat.HitSeriesReset then
		last = { step = 0, at = now }
		series[key] = last
	end
	last.step = last.step % #sounds + 1
	last.at = now
	return sounds[last.step]
end

function HitFeedback.start()
	local net = ReplicatedStorage:WaitForChild("Net")
	local event = net:WaitForChild("HeroHit") :: RemoteEvent
	event.OnClientEvent:Connect(function(target: Instance, amount: number, at: Vector3, striker: Player?)
		local tier = tierOf(amount)
		if target and target.Parent then
			flash(target, tier)
		end
		if striker == player then
			number(at, tostring(math.round(amount)), tier)
		end
		if #Config.Combat.HitSounds == 0 then
			return
		elseif striker == player or (target and target == player.Character) then
			local now = os.clock()
			if now - lastSound >= SOUND_GAP then
				lastSound = now
				UiSound.play(nextSound(player))
			end
		else
			UiSound.at(nextSound(striker or target), at)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return HitFeedback
