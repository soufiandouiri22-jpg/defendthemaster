-- The hero on the hall's podium behind the menu (design 10): the player's showcase hero (Shared.Profile.showcase: his
-- favourite, else the hero he played last), a copy of the server's model (ReplicatedStorage.Showcase) in his showcase
-- pose (Config.Heroes[hero].Showcase.Motion, through Shared.Motion) with his aura round him: wisps of his colour
-- rising, embers, and a glow on the podium. Over the glow the pad lights up as the spawn pads do in a match (PadView):
-- a rune circle turning slowly, a soft light and motes drifting up, in the hero's aura colour. The camera stands
-- still where the hall says (the Workspace attribute "MenuCamera"), breathing a little.
--
-- Until the player has chosen his hero (his favourite is still empty) his own Roblox avatar stands there instead
-- (ShowcaseService's Avatars), idling, and the welcome screen (Lobby.Welcome) lets him pick one: the camera moves the
-- podium into the screen's left half (Showcase.view), and becoming him plays the transformation (Showcase.transform): the runes flare and race, the
-- avatar rises spinning in a vortex of his colour while light gathers into a pillar round him, glows white and
-- crumbles away, a blast and a shockwave, and the hero drops onto the podium as a white silhouette that fades into
-- him, with his name slammed across the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Emote = require(ReplicatedStorage.Shared.Emote)
local LightningEffects = require(script.Parent.Parent.LightningEffects)
local Motion = require(ReplicatedStorage.Shared.Motion)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileClient = require(script.Parent.Parent.ProfileClient)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)

local Showcase = {}

-- The name the player's own avatar goes by on the podium.
Showcase.Avatar = "@avatar"

local DEFAULT_AURA = Color3.fromRGB(255, 196, 90)
local WHITE = Color3.new(1, 1, 1)
-- The camera sways this many studs, this slowly.
local SWAY, SWAY_SPEED = 0.12, 0.35
-- The podium's rune circle: its width in studs (as on a spawn pad, PadView) and its turn in degrees a second.
local RUNE_WIDTH, RUNE_TURN = 4.8, 6
-- The camera's field of view in the menu.
local FOV = 40
-- Roblox's standard R15 idle, for the avatar.
local AVATAR_IDLE = "rbxassetid://507766666"
-- How long the avatar's own idle (his animation pack's) may take to load before the standard one stays.
local IDLE_WAIT = 10
-- How long a model on the podium may wait for the last of its pieces to come over from the server.
local PARTS_WAIT = 10
-- How high the avatar rises while he turns, and how long the transformation's parts take in seconds.
local RISE = 1.2
local CHARGE, DROP = 1.9, 0.42
-- How long each foot takes stepping into his pose after his entrance, unless it says otherwise (its `Step`).
local STEP = 0.45
-- The ribbons of light whirling round him.
local STRANDS = 9

type Entry = {
	hero: string,
	model: Model,
	motion: any?,
	pivot: CFrame,
	update: ((dt: number) -> ())?,
	-- The emote he dances (Showcase.dance).
	dance: Emote.Dance?,
}

local current: Entry? = nil
local wanted = ""
local busy = false
local holding = false
local pending: Profile.Data? = nil
local plate: { runes: ImageLabel, light: PointLight, motes: ParticleEmitter }? = nil
local runeTurn = Instance.new("NumberValue")
runeTurn.Value = RUNE_TURN

-- Where the camera looks: the podium at `x` of the screen's width, with this field of view, pushed this many studs
-- in; the view eases towards its goal at `rate`. `shake` is the camera's shaking, dying away.
local view = { x = 0.5, fov = FOV, up = 0 }
local goal = { x = 0.5, fov = FOV, up = 0, rate = 3 }
local shake = 0

local function tween(object: Instance, seconds: number, properties: { [string]: any }, style: any?, direction: any?)
	local t = TweenService:Create(
		object,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		properties
	)
	t:Play()
	return t
end

local function podium(): CFrame
	return Workspace:GetAttribute("ShowcaseAt") :: CFrame
end

local function colourOf(hero: string): Color3
	local settings = Config.Heroes[hero]
	local showcase = settings and settings.Showcase
	return if showcase and showcase.Aura
		then showcase.Aura
		elseif showcase and showcase.Colour then showcase.Colour
		else DEFAULT_AURA
end

-- Whether `hero` stands in an aura on the podium: not with `Aura = false` (the Gunslinger, owner 2026-11-04).
local function glows(hero: string): boolean
	local settings = Config.Heroes[hero]
	local showcase = settings and settings.Showcase
	return not (showcase and showcase.Aura == false)
end
-- The podium pad's rune circle, light and motes, made once and coloured `colour`.
local function lightPlate(at: CFrame, colour: Color3)
	if not plate then
		local disc = Instance.new("Part")
		disc.Name = "PodiumRunes"
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Transparency = 1
		disc.Size = Vector3.new(RUNE_WIDTH, 0.05, RUNE_WIDTH)
		disc.CFrame = at * CFrame.new(0, 0.11, 0)
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Top
		surface.LightInfluence = 0
		surface.Brightness = 2
		surface.CanvasSize = Vector2.new(512, 512)
		surface.Parent = disc
		local runes = Instance.new("ImageLabel")
		runes.BackgroundTransparency = 1
		runes.Size = UDim2.fromScale(1, 1)
		runes.Image = Assets.PadRunes
		runes.ImageTransparency = 0.1
		runes.Parent = surface
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = disc
		local motes = Instance.new("ParticleEmitter")
		motes.LightEmission = 1
		motes.LightInfluence = 0
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		motes.EmissionDirection = Enum.NormalId.Top
		motes.Shape = Enum.ParticleEmitterShape.Disc
		motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		motes.Rate = 5
		motes.Lifetime = NumberRange.new(2.5, 4)
		motes.Speed = NumberRange.new(1.5, 3)
		motes.Acceleration = Vector3.new(0, 0.6, 0)
		motes.Parent = disc
		disc.Parent = Workspace
		plate = { runes = runes, light = light, motes = motes }
	end
	local p = plate :: { runes: ImageLabel, light: PointLight, motes: ParticleEmitter }
	local soft = colour:Lerp(WHITE, 0.3)
	p.runes.ImageColor3 = soft
	p.light.Color = soft
	p.motes.Color = ColorSequence.new(WHITE, soft)
end

-- Whether `hero`'s aura burns (Showcase.Fire): hotter flames under dark smoke, where his colour alone would melt into
-- the hall's warm light.
local function burns(hero: string): boolean
	local settings = Config.Heroes[hero]
	local showcase = settings and settings.Showcase
	return showcase ~= nil and showcase.Fire == true
end

local function aura(model: Model, colour: Color3, at: CFrame, fire: boolean)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Aura"
	attachment.Parent = root

	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "Wisps"
	wisps.Texture = "rbxasset://textures/particles/fire_main.dds"
	wisps.Color = if fire
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 110)),
			ColorSequenceKeypoint.new(0.4, colour),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 30, 10)),
		})
		else ColorSequence.new(colour:Lerp(WHITE, 0.25), colour)
	wisps.LightEmission = 0.8
	wisps.LightInfluence = 0
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.Lifetime = NumberRange.new(0.9, 1.6)
	wisps.Rate = if fire then 48 else 26
	wisps.Speed = NumberRange.new(1.2, 2.4)
	wisps.SpreadAngle = Vector2.new(25, 25)
	wisps.Acceleration = Vector3.new(0, 2.2, 0)
	wisps.RotSpeed = NumberRange.new(-80, 80)
	wisps.Rotation = NumberRange.new(0, 360)
	wisps.Shape = Enum.ParticleEmitterShape.Cylinder
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	wisps.Parent = attachment

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 150, 60))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1.8, 3)
	embers.Rate = if fire then 30 else 14
	embers.Speed = NumberRange.new(0.6, 1.4)
	embers.SpreadAngle = Vector2.new(70, 70)
	embers.Acceleration = Vector3.new(0, 1.2, 0)
	embers.Parent = attachment

	if fire then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(40, 34, 32), Color3.fromRGB(12, 10, 10))
		smoke.LightInfluence = 0.3
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 2.4),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(1.6, 2.6)
		smoke.Rate = 14
		smoke.Speed = NumberRange.new(1, 2)
		smoke.SpreadAngle = Vector2.new(20, 20)
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.RotSpeed = NumberRange.new(-30, 30)
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.Shape = Enum.ParticleEmitterShape.Cylinder
		smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		smoke.Parent = attachment
	end

	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = if fire then 3 else 1.6
	light.Range = 11
	light.Parent = attachment

	-- A glow on the podium under him.
	local glow = Instance.new("Part")
	glow.Name = "AuraGlow"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Shape = Enum.PartType.Cylinder
	glow.Size = Vector3.new(0.05, 4.6, 4.6)
	glow.CFrame = at * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
	glow.Material = Enum.Material.Neon
	glow.Color = colour
	glow.Transparency = if fire then 0.6 else 0.82
	glow.Parent = model
end

-- The server's model of `hero` (or of the player's avatar), waiting for it when it is not there yet.
local function source(hero: string): Model?
	local folder = ReplicatedStorage:WaitForChild("Showcase", 30)
	if not folder then
		return nil
	end
	local model: Model? = nil
	if hero == Showcase.Avatar then
		local avatars = folder:WaitForChild("Avatars", 30)
		model = avatars and avatars:WaitForChild(tostring(Players.LocalPlayer.UserId), 30) :: Model?
	else
		model = folder:WaitForChild(hero, 30) :: Model?
	end
	-- A model can be here before all its pieces (his head, hat, a hand) are: wait for the count the server gave it.
	local parts = model and model:GetAttribute("Parts")
	if model and typeof(parts) == "number" then
		local started = os.clock()
		while #model:GetDescendants() < parts and os.clock() - started < PARTS_WAIT do
			task.wait(0.05)
		end
	end
	return model
end

-- `hero`'s entrance on the podium (Config's Showcase.Enter), if he has one.
local function entrance(hero: string): { [string]: any }?
	local settings = Config.Heroes[hero]
	return settings and settings.Showcase and settings.Showcase.Enter
end

-- The degrees `hero` stands turned on the podium: facing the camera while he makes his entrance and when he keeps its
-- last frame, else turned by his pose's `Turn` when it looks aside.
local function turnOf(hero: string, entering: boolean?): number
	local settings = Config.Heroes[hero]
	local enter = entrance(hero)
	if enter and (entering or enter.Then == "Breathe") then
		return 0
	end
	return settings and settings.Showcase and settings.Showcase.Turn or 0
end

-- Where `model` stands on the podium, `offset` from its middle: on his feet, facing the camera (+Z), turned `turn`
-- degrees.
local function standing(model: Model, turn: number, offset: Vector3?): CFrame
	local at = podium()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local height = if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else 3
	return at
		* CFrame.new(offset or Vector3.zero)
		* CFrame.new(0, height, 0)
		* CFrame.Angles(0, math.pi + math.rad(turn), 0)
end

-- A copy of `hero`'s model standing on the podium, not yet in the world; `entering` as he begins his entrance.
local function make(hero: string, entering: boolean?): Entry?
	local model = source(hero)
	if not model then
		return nil
	end
	local copy = model:Clone()
	local pivot = standing(copy, turnOf(hero, entering))
	copy:PivotTo(pivot)
	return { hero = hero, model = copy, motion = nil, pivot = pivot }
end

-- Puts `entry` in the world and starts his pose: a hero's showcase pose, the avatar's standard idle. With an entrance
-- he stands where it ends, or `entering` on the frame it starts from until Showcase.transform lets it play
-- (playEntrance).
local function animate(entry: Entry, entering: boolean?)
	entry.model.Parent = Workspace
	local settings = Config.Heroes[entry.hero]
	if settings and settings.Pack then
		local motion = Motion.new(entry.model, settings.Pack)
		local enter = entrance(entry.hero)
		local idle = settings.Showcase and settings.Showcase.Motion or settings.Motions.Idle
		if idle then
			motion:setBase(idle, 1)
		end
		if enter and enter.Low then
			motion:keepLow()
		end
		if enter and entering then
			motion:play(enter.Motion, 1, enter.From, true, true)
			motion:setSpeed(0)
		elseif enter and enter.Then == "Breathe" then
			local stop = enter.Until or Motion.meta(settings.Pack, enter.Motion).duration
			motion:play(enter.Motion, 1, stop, true, true)
			motion:setSpeed(0)
			motion:breathe()
		end
		entry.motion = motion
	elseif entry.hero == Showcase.Avatar then
		local humanoid = entry.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			local function load(id: string): AnimationTrack?
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				local ok, track = pcall(function()
					return (animator :: Animator):LoadAnimation(animation)
				end)
				return if ok then track else nil
			end
			local standard = load(AVATAR_IDLE)
			if standard then
				standard.Looped = true
				standard:Play(0)
			end
			-- His animation pack's idle takes over once it has loaded; the standard one stays when it never does.
			local own = entry.model:GetAttribute("Idle")
			local track = if typeof(own) == "string" then load(own) else nil
			if track then
				task.spawn(function()
					local waited = 0
					while track.Length == 0 and waited < IDLE_WAIT and entry.model.Parent do
						waited += task.wait(0.1)
					end
					if track.Length > 0 and entry.model.Parent then
						track.Looped = true
						track:Play(0.3)
						if standard then
							standard:Stop(0.3)
						end
					end
				end)
			end
		end
	end
end

-- Plays `entry`'s entrance (at its `Speed`): its clip from `From` up to `Until`, then he keeps that frame,
-- breathing, or steps into his pose, turning as he steps to the way it faces.
local function playEntrance(entry: Entry)
	local settings = Config.Heroes[entry.hero]
	local enter = entrance(entry.hero)
	local motion = entry.motion
	if not (settings and enter and motion) then
		return
	end
	motion:play(enter.Motion, enter.Speed or 1, enter.From, true, true)
	motion:stopAt(enter.Until or Motion.meta(settings.Pack, enter.Motion).duration)
	local stepping: number? = nil
	local from, to = turnOf(entry.hero, true), turnOf(entry.hero)
	local left = enter.Step or STEP
	local right = enter.StepRight or left
	local held: number? = nil
	entry.update = function(dt: number)
		if not stepping then
			if not motion:reached() then
				return
			end
			if enter.Then ~= "Pose" then
				motion:breathe()
				entry.update = nil
				return
			end
			if enter.Hold then
				if not held then
					held = 0
					motion:breathe()
				end
				held += dt
				if held < enter.Hold then
					return
				end
			end
			motion:stepInto(left, right)
			stepping = 0
		end
		stepping += dt
		local t = math.clamp(stepping / (left + right), 0, 1)
		entry.pivot = standing(entry.model, from + (to - from) * t * t * (3 - 2 * t))
		entry.model:PivotTo(entry.pivot)
		if t >= 1 then
			entry.update = nil
		end
	end
end

-- Eases `entry` from a dance back into his pose: the last frame of his entrance he keeps, or his showcase pose.
local function rest(entry: Entry)
	local settings = Config.Heroes[entry.hero]
	local enter = entrance(entry.hero)
	local motion = entry.motion
	if not motion then
		return
	end
	motion:crossfade(Emote.FADE)
	if enter and enter.Then ~= "Pose" then
		motion:play(enter.Motion, 1, enter.Until or Motion.meta(settings.Pack, enter.Motion).duration, true, true)
		motion:setSpeed(0)
	else
		motion:stop()
	end
end

-- Dances emote `id` (Config.Emotes) on the podium, or with nil ends the dance; only a hero who stands in his pose
-- (his entrance played, no transformation under way). Whether he dances.
function Showcase.dance(id: string?): boolean
	local entry = current
	if busy or not entry or not entry.motion or entry.update then
		return false
	end
	if entry.dance then
		entry.dance = nil
		if not id then
			rest(entry)
			return false
		end
	end
	if not id then
		return false
	end
	entry.dance = Emote.dance(entry.motion, id)
	return entry.dance ~= nil
end

-- Whether the hero on the podium dances an emote.
function Showcase.dancing(): boolean
	return current ~= nil and current.dance ~= nil
end

-- Puts `hero` on the podium, or keeps him there when he already stands on it.
function Showcase.show(hero: string)
	wanted = hero
	if busy or (current and current.hero == hero) then
		return
	end
	local entry = make(hero)
	if not entry then
		return
	end
	if busy or wanted ~= hero or (current and current.hero == hero) then
		entry.model:Destroy()
		return
	end
	if current then
		current.model:Destroy()
		current = nil
	end
	animate(entry)
	local colour = colourOf(hero)
	if hero ~= Showcase.Avatar then
		if glows(hero) then
			aura(entry.model, colour, podium(), burns(hero))
		end
		LightningEffects.crackle(entry.model)
	end
	lightPlate(podium(), colour)
	current = entry
end

-- Who stands on the podium for `data`: his own avatar until he has chosen his hero.
function Showcase.wanted(data: Profile.Data): string
	if (data.Favourite or "") == "" then
		return Showcase.Avatar
	end
	return Profile.showcase(data)
end

-- The model standing on the podium, nil until the first one is there.
function Showcase.model(): Model?
	return if current then current.model else nil
end

-- Who stands on the podium now ("" before anyone, Showcase.Avatar for the player's own avatar).
function Showcase.current(): string
	return if current then current.hero else ""
end

-- While held, a change of the profile does not change who stands on the podium (a transformation is about to show
-- it); letting go puts the right one there.
function Showcase.hold(on: boolean)
	holding = on
	if not on and pending then
		local data = pending
		pending = nil
		task.spawn(Showcase.show, Showcase.wanted(data))
	end
end

-- Moves the camera so the podium stands at `x` of the screen's width (0.5 the middle), at field of view `fov`, tilted
-- `up` degrees, in about `seconds`.
function Showcase.view(x: number, fov: number?, seconds: number?, up: number?)
	goal.x = x
	goal.fov = fov or FOV
	goal.up = up or 0
	goal.rate = 4 / math.max(0.05, seconds or 0.8)
end

-- Shakes the camera, `amount` 1 a big blast.
function Showcase.shake(amount: number)
	shake = math.max(shake, amount)
end

-- A glowing, collision-free part for the transformation's effects.
local function glowPart(parent: Instance, shape: Enum.PartType, size: Vector3, at: CFrame, colour: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = colour
	p.Size = size
	p.CFrame = at
	p.Transparency = 1
	p.Parent = parent
	return p
end

local function sparkles(parent: Instance, colour: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(WHITE, colour)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	e.Parent = parent
	return e
end

-- The hero's name slammed across the screen under him, with "YOU BECAME" over it and his class under it.
local function title(hero: string, colour: Color3): ScreenGui
	local gui = UiStyle.screen("Transform", Players.LocalPlayer:WaitForChild("PlayerGui"), 40)
	local holder = UiStyle.frame(gui, UDim2.fromOffset(1400, 330), UDim2.fromScale(0.5, 0.79), Vector2.new(0.5, 0.5))
	holder.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 2.6
	scale.Parent = holder

	local above = UiStyle.text(holder, "YOU BECAME", 46, UiStyle.Colors.Cream, UiStyle.Colors.Edge)
	above.Size = UDim2.new(1, 0, 0, 56)
	above.TextTransparency = 1
	local aboveEdge = above:FindFirstChildOfClass("UIStroke") :: UIStroke
	aboveEdge.Transparency = 1

	local name = UiStyle.text(holder, string.upper(hero), 168, WHITE, UiStyle.Colors.Edge)
	name.Size = UDim2.new(1, 0, 0, 180)
	name.Position = UDim2.fromOffset(0, 50)
	name.TextTransparency = 1
	local nameEdge = name:FindFirstChildOfClass("UIStroke") :: UIStroke
	nameEdge.Thickness = 9
	nameEdge.Transparency = 1
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colour:Lerp(WHITE, 0.75)),
		ColorSequenceKeypoint.new(0.55, colour:Lerp(WHITE, 0.3)),
		ColorSequenceKeypoint.new(1, colour),
	})
	fill.Rotation = 90
	fill.Parent = name

	local settings = Config.Heroes[hero]
	local role = UiStyle.text(holder, string.upper(settings and settings.Role or ""), 44, UiStyle.Colors.Xp)
	role.Size = UDim2.new(1, 0, 0, 52)
	role.Position = UDim2.fromOffset(0, 236)
	role.TextTransparency = 1
	local roleEdge = Instance.new("UIStroke")
	roleEdge.Color = UiStyle.Colors.Edge
	roleEdge.Thickness = 4
	roleEdge.Transparency = 1
	roleEdge.Parent = role

	-- Slams in, then the class and the line over it fade in after.
	tween(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(name, 0.12, { TextTransparency = 0 })
	tween(nameEdge, 0.12, { Transparency = 0 })
	task.delay(0.2, function()
		tween(above, 0.3, { TextTransparency = 0 })
		tween(aboveEdge, 0.3, { Transparency = 0 })
		tween(role, 0.3, { TextTransparency = 0 })
		tween(roleEdge, 0.3, { Transparency = 0 })
	end)
	task.delay(2.5, function()
		for _, label in { above, name, role } do
			tween(label, 0.5, { TextTransparency = 1 })
			local edge = label:FindFirstChildOfClass("UIStroke")
			if edge then
				tween(edge, 0.5, { Transparency = 1 })
			end
		end
		tween(scale, 0.5, { Scale = 1.08 })
	end)
	return gui
end

-- Turns whoever stands on the podium into `hero`, and returns when the hero stands there (about four seconds).
function Showcase.transform(hero: string)
	busy = true
	wanted = hero
	local at = podium()
	local colour = colourOf(hero)
	local bright = colour:Lerp(WHITE, 0.45)
	local before = current
	local after = make(hero, true)
	if not after then
		busy = false
		Showcase.show(hero)
		return
	end
	local fx = Instance.new("Folder")
	fx.Name = "TransformFx"
	fx.Parent = Workspace
	local chest = at * CFrame.new(0, 2.8, 0)
	local p = plate

	-- The flash over the screen, white then in his colour.
	local screen = UiStyle.screen("TransformFlash", Players.LocalPlayer:WaitForChild("PlayerGui"), 39)
	local flash = UiStyle.frame(screen, UDim2.fromScale(1, 1))
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	local tint = UiStyle.frame(screen, UDim2.fromScale(1, 1))
	tint.BackgroundColor3 = colour
	tint.BackgroundTransparency = 1
	local edges = Instance.new("UIGradient")
	edges.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.9),
		NumberSequenceKeypoint.new(0.7, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	edges.Parent = tint

	-- 1. The charge: the runes race in his colour, the light swells, motes stream up, the avatar glows and rises
	-- spinning in a vortex while light is pulled into him and a pillar of light grows round him.
	UiSound.play("TransformCharge", 1)
	Showcase.view(0.5, 35, CHARGE, 3.5)
	tween(runeTurn, CHARGE, { Value = 720 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if p then
		lightPlate(at, bright)
		tween(p.light, CHARGE, { Brightness = 8, Range = 26 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(p.motes, CHARGE * 0.6, { Rate = 90 })
		p.motes.Speed = NumberRange.new(4, 8)
	end
	tween(tint, CHARGE, { BackgroundTransparency = 0.72 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local glow: Highlight? = nil
	if before then
		local h = Instance.new("Highlight")
		h.FillColor = bright
		h.OutlineColor = WHITE
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = before.model
		tween(
			h,
			CHARGE * 0.8,
			{ FillTransparency = 0.05, OutlineTransparency = 0 },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		glow = h
	end

	local spinner = glowPart(fx, Enum.PartType.Block, Vector3.one, chest, colour)
	local strands = {}
	for i = 1, STRANDS do
		local low = Instance.new("Attachment")
		local high = Instance.new("Attachment")
		low.Parent = spinner
		high.Parent = spinner
		local trail = Instance.new("Trail")
		trail.Attachment0 = low
		trail.Attachment1 = high
		trail.Color = ColorSequence.new(bright, colour)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.Lifetime = 0.45
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = spinner
		table.insert(strands, {
			low = low,
			high = high,
			trail = trail,
			phase = (i - 1) * 2 * math.pi / STRANDS,
			height = (i % 3 - 1) * 1.1,
		})
	end

	local well = glowPart(fx, Enum.PartType.Ball, Vector3.one * 10, chest, colour)
	local gather = sparkles(well, bright)
	gather.Shape = Enum.ParticleEmitterShape.Sphere
	gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	gather.Speed = NumberRange.new(7, 9)
	gather.Lifetime = NumberRange.new(0.5, 0.6)
	gather.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.4) })
	tween(gather, CHARGE * 0.7, { Rate = 110 })

	-- The pillar of light: a wide soft shaft in his colour round a thin white core.
	local upright = at * CFrame.new(0, 30, 0) * CFrame.Angles(0, 0, math.rad(90))
	local pillar = glowPart(fx, Enum.PartType.Cylinder, Vector3.new(60, 0.4, 0.4), upright, colour)
	local core = glowPart(fx, Enum.PartType.Cylinder, Vector3.new(60, 0.1, 0.1), upright, WHITE)
	task.delay(CHARGE * 0.45, function()
		local grow = TweenInfo.new(CHARGE * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(pillar, grow, { Size = Vector3.new(60, 3.6, 3.6), Transparency = 0.62 }):Play()
		TweenService:Create(core, grow, { Size = Vector3.new(60, 1.1, 1.1), Transparency = 0.25 }):Play()
	end)
	task.delay(CHARGE * 0.3, function()
		UiSound.play("TransformSwirl", 1)
	end)

	-- The rise, the spin and the vortex, every frame until the blast.
	local started = os.clock()
	local charging = true
	local angle = 0
	local spin = 0
	local frame = RunService.RenderStepped:Connect(function(dt)
		local t = math.clamp((os.clock() - started) / CHARGE, 0, 1)
		if charging and before then
			local lift = RISE * (1 - (1 - t) ^ 2)
			spin += dt * (1 + 16 * t * t)
			before.model:PivotTo(before.pivot * CFrame.new(0, lift, 0) * CFrame.Angles(0, spin, 0))
			shake = math.max(shake, 0.12 * t)
		end
		angle += dt * (3 + 14 * t)
		local radius = 3.4 - 1.8 * t
		spinner.CFrame = chest * CFrame.Angles(0, angle, 0)
		for i, s in strands do
			local a = s.phase
			local y = s.height + math.sin(angle * 0.6 + i) * 0.9
			local where = Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
			s.low.Position = where - Vector3.new(0, 0.09, 0)
			s.high.Position = where + Vector3.new(0, 0.09, 0)
		end
	end)

	-- The avatar crumbles away from his feet up, the last part of the charge.
	local crumble = CHARGE * 0.35
	task.wait(CHARGE - crumble)
	if before then
		local parts = {}
		for _, d in before.model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, d)
			end
		end
		table.sort(parts, function(a, b)
			return a.Position.Y < b.Position.Y
		end)
		local dust = glowPart(fx, Enum.PartType.Block, Vector3.one * 0.5, chest, bright)
		local bits = sparkles(dust, bright)
		bits.Speed = NumberRange.new(2, 6)
		bits.SpreadAngle = Vector2.new(180, 180)
		bits.Lifetime = NumberRange.new(0.4, 0.9)
		bits.Acceleration = Vector3.new(0, 6, 0)
		bits.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		local step = crumble / math.max(1, #parts)
		for _, part in parts do
			dust.CFrame = part.CFrame
			bits:Emit(4)
			part.Transparency = 1
			for _, child in part:GetChildren() do
				if child:IsA("Decal") then
					child.Transparency = 1
				end
			end
			task.wait(step)
		end
	else
		task.wait(crumble)
	end

	-- 2. The blast: a white flash, a boom, the camera shaking, a burst of sparks, a sphere of light and a shockwave
	-- racing over the floor; the avatar is gone and the hero hangs in the air as a white silhouette.
	charging = false
	UiSound.play("TransformBoom", 1)
	Showcase.shake(1)
	flash.BackgroundTransparency = 0
	tween(flash, 0.7, { BackgroundTransparency = 1 })
	tween(tint, 1.1, { BackgroundTransparency = 1 })
	for _, s in strands do
		s.trail.Enabled = false
	end
	gather.Rate = 0
	if glow then
		glow:Destroy()
	end
	if before then
		before.model:Destroy()
	end
	current = nil

	local sphere = glowPart(fx, Enum.PartType.Ball, Vector3.one * 2, chest, WHITE)
	sphere.Transparency = 0
	tween(sphere, 0.5, { Size = Vector3.one * 16, Transparency = 1, Color = colour })
	local ring = glowPart(
		fx,
		Enum.PartType.Cylinder,
		Vector3.new(0.25, 3, 3),
		at * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		bright
	)
	ring.Transparency = 0.1
	tween(ring, 0.8, { Size = Vector3.new(0.25, 44, 44), Transparency = 1 })
	local burst = sparkles(well, bright)
	burst.Speed = NumberRange.new(18, 34)
	burst.Drag = 5
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Lifetime = NumberRange.new(0.8, 1.5)
	burst.Acceleration = Vector3.new(0, -4, 0)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	burst.Shape = Enum.ParticleEmitterShape.Box
	well.Size = Vector3.one
	burst:Emit(140)
	tween(pillar, 0.6, { Size = Vector3.new(60, 7, 7), Transparency = 1 })
	tween(core, 0.4, { Size = Vector3.new(60, 0.05, 0.05), Transparency = 1 })

	local silhouette = Instance.new("Highlight")
	silhouette.FillColor = WHITE
	silhouette.OutlineColor = bright
	silhouette.FillTransparency = 0
	silhouette.OutlineTransparency = 0
	silhouette.DepthMode = Enum.HighlightDepthMode.Occluded
	silhouette.Parent = after.model
	after.model:PivotTo(after.pivot * CFrame.new(0, RISE, 0))
	animate(after, true)
	current = after

	-- 3. The landing: the hero drops onto the podium, a smaller shockwave and embers, the camera settles back, his
	-- aura lights up, the silhouette fades into him and his name slams across the screen.
	Showcase.view(0.5, FOV, 1.3)
	local dropped = os.clock()
	local fall = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - dropped) / DROP, 0, 1)
		after.model:PivotTo(after.pivot * CFrame.new(0, RISE * (1 - t * t), 0))
	end)
	task.wait(DROP)
	fall:Disconnect()
	frame:Disconnect()
	after.model:PivotTo(after.pivot)
	playEntrance(after)
	Showcase.shake(0.45)
	UiSound.play("TransformShimmer", 1)
	local land = glowPart(
		fx,
		Enum.PartType.Cylinder,
		Vector3.new(0.2, 2, 2),
		at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		colour
	)
	land.Transparency = 0.2
	tween(land, 0.55, { Size = Vector3.new(0.2, 16, 16), Transparency = 1 })
	local embers = sparkles(well, Color3.fromRGB(255, 170, 70))
	well.CFrame = at * CFrame.new(0, 0.5, 0)
	well.Size = Vector3.new(4, 0.2, 4)
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Speed = NumberRange.new(6, 14)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.Drag = 2
	embers.Lifetime = NumberRange.new(1, 1.8)
	embers.Acceleration = Vector3.new(0, -3, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	embers:Emit(60)

	if glows(hero) then
		aura(after.model, colour, at, burns(hero))
	end
	LightningEffects.crackle(after.model)
	lightPlate(at, colour)
	tween(runeTurn, 1.6, { Value = RUNE_TURN })
	if p then
		tween(p.light, 1.6, { Brightness = 1.2, Range = 14 })
		tween(p.motes, 1.6, { Rate = 5 })
		p.motes.Speed = NumberRange.new(1.5, 3)
	end
	tween(silhouette, 0.9, { FillTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(silhouette, 1.6, { OutlineTransparency = 1 })
	local words = title(hero, colour)
	task.delay(1.7, function()
		silhouette:Destroy()
	end)
	task.delay(3.4, function()
		words:Destroy()
		screen:Destroy()
		fx:Destroy()
	end)
	task.wait(1.6)
	busy = false
	if wanted ~= hero then
		task.spawn(Showcase.show, wanted)
	end
end

function Showcase.start()
	local camera = Workspace.CurrentCamera
	while not Workspace:GetAttribute("MenuCamera") do
		Workspace:GetAttributeChangedSignal("MenuCamera"):Wait()
	end
	local base = Workspace:GetAttribute("MenuCamera") :: CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	camera.CFrame = base
	local random = Random.new()
	RunService.RenderStepped:Connect(function(dt)
		camera.CameraType = Enum.CameraType.Scriptable
		local ease = math.min(1, dt * goal.rate)
		view.x += (goal.x - view.x) * ease
		view.fov += (goal.fov - view.fov) * ease
		view.up += (goal.up - view.up) * ease
		-- The podium's distance along the camera's look, and the sideways step that puts it at `view.x`.
		local at = Workspace:GetAttribute("ShowcaseAt") :: CFrame?
		local shift = 0
		if at then
			local depth = math.max(1, (at.Position - base.Position):Dot(base.LookVector))
			local size = camera.ViewportSize
			local half = depth * math.tan(math.rad(view.fov) / 2) * size.X / math.max(1, size.Y)
			shift = (0.5 - view.x) * 2 * half
		end
		local t = os.clock() * SWAY_SPEED
		local sway = CFrame.new(math.sin(t) * SWAY, math.sin(t * 1.3) * SWAY * 0.5, 0)
		local trembling = CFrame.identity
		if shake > 0.01 then
			trembling = CFrame.new(random:NextNumber(-1, 1) * shake * 0.35, random:NextNumber(-1, 1) * shake * 0.35, 0)
				* CFrame.Angles(0, 0, random:NextNumber(-1, 1) * shake * 0.025)
			shake *= math.exp(-dt * 5)
		else
			shake = 0
		end
		camera.FieldOfView = view.fov
		camera.CFrame = base * CFrame.new(shift, 0, 0) * CFrame.Angles(math.rad(view.up), 0, 0) * sway * trembling
		if plate then
			plate.runes.Rotation = (plate.runes.Rotation + runeTurn.Value * dt) % 360
		end
		local c = current
		if c and c.motion then
			c.motion:step(dt)
			if c.update then
				c.update(dt)
			end
			if c.dance and not Emote.going(c.dance) then
				c.dance = nil
				rest(c)
			end
		end
	end)
	ProfileClient.watch(function(data)
		if holding then
			pending = data
			return
		end
		task.spawn(Showcase.show, Showcase.wanted(data))
	end)
	-- Without his profile after a while (a studio test without data), the default hero stands there.
	task.delay(8, function()
		if not current and not ProfileClient.get() then
			Showcase.show(Config.DefaultHero)
		end
	end)
end

return Showcase
