-- Moves every hero (a Combatant with the "Hero" attribute) with its animation pack's clips (Shared.Motion): the battle
-- idle when it stands, running forward, sideways or backward by the way it moves relative to where it faces, and the
-- jump's takeoff, flight and landing; and over that the motions of its attacks (HeroAnimator.play).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Motion = require(ReplicatedStorage.Shared.Motion)

local HeroSounds = require(script.Parent.HeroSounds)

local HeroAnimator = {}

-- The speed, in studs a second, at which each clip's feet keep up with the ground.
local RUN_SPEED = 17
local BACK_SPEED = 8
-- Off the ground for longer than this, a hero lands with the landing clip.
local LAND_AFTER = 0.35

type Hero = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motions: { [string]: string },
	motion: Motion.Motion,
	height: number,
	airborne: number,
	landingUntil: number,
}

local heroes: { [Model]: Hero } = {}
local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGround()
	ground.FilterDescendantsInstances = HeroKit.leapIgnore()
end

local function add(character: Instance)
	if not character:IsA("Model") or heroes[character] then
		return
	end
	local name = character:GetAttribute("Hero")
	local settings = name and Config.Heroes[name]
	if not settings or not settings.Pack then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	if settings.Weapons then
		character:WaitForChild("Weapons", 10)
	end
	if not character.Parent then
		return
	end
	-- Whatever an Animator still plays (the default Animate script) would fight the pack's clips.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
	local hero: Hero = {
		character = character,
		humanoid = humanoid,
		root = root,
		motions = settings.Motions,
		motion = Motion.new(character, settings.Pack),
		height = humanoid.HipHeight + root.Size.Y / 2,
		airborne = 0,
		landingUntil = 0,
	}
	local bank = HeroSounds.bank(settings.Pack)
	if bank then
		hero.motion.cues = bank.Cues
		hero.motion.onCue = function(cue)
			HeroSounds.cue(character, bank, cue)
		end
	end
	hero.motion:setBase(settings.Motions.Idle, 1)
	heroes[character] = hero
	refreshGround()
end

local function remove(character: Instance)
	heroes[character :: Model] = nil
	HeroSounds.forget(character :: Model)
	refreshGround()
end

local function locomote(hero: Hero, dt: number, now: number)
	local motions, motion, root = hero.motions, hero.motion, hero.root
	local below = Workspace:Raycast(root.Position, Vector3.new(0, -(hero.height + 0.6), 0), ground)
	if not below then
		if hero.airborne == 0 then
			motion:setBase(motions.Takeoff, 1)
			motion:restartBase()
		elseif motion.base and motion.base.id == motions.Takeoff and motion:baseDone() then
			motion:setBase(motions.Air, 1)
		end
		hero.airborne += dt
		return
	end
	if hero.airborne > LAND_AFTER then
		motion:setBase(motions.Land, 1)
		motion:restartBase()
		hero.landingUntil = now + 0.3
	end
	hero.airborne = 0

	local velocity = HeroKit.flat(root.AssemblyLinearVelocity)
	local speed = velocity.Magnitude
	if speed < 1 then
		if now >= hero.landingUntil then
			motion:setBase(motions.Idle, 1)
		end
		return
	end
	local here = root.CFrame:VectorToObjectSpace(velocity)
	local forward, right = -here.Z, here.X
	if forward >= math.abs(right) * 0.6 then
		motion:setBase(motions.Run, math.clamp(speed / RUN_SPEED, 0.4, 1.4))
	elseif forward <= -math.abs(right) * 0.6 then
		motion:setBase(motions.Back, math.clamp(speed / BACK_SPEED, 0.4, 1.8))
	elseif right > 0 then
		motion:setBase(motions.RunRight, math.clamp(speed / RUN_SPEED, 0.4, 1.4))
	else
		motion:setBase(motions.RunLeft, math.clamp(speed / RUN_SPEED, 0.4, 1.4))
	end
end

-- Plays the clip `id` once on `character`'s hero at `speed`, from `startTime` seconds in, `inPlace` without the clip's
-- own travel; returns how long it lasts.
function HeroAnimator.play(character: Model, id: string, speed: number, startTime: number?, inPlace: boolean?): number
	local hero = heroes[character]
	if not hero then
		return 0
	end
	return hero.motion:play(id, speed, startTime, inPlace)
end

-- The clip `character`'s hero plays over its base, if any.
function HeroAnimator.playing(character: Model): string?
	local hero = heroes[character]
	return hero and hero.motion:playing()
end

function HeroAnimator.stop(character: Model)
	local hero = heroes[character]
	if hero then
		hero.motion:stop()
	end
end

function HeroAnimator.start()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(function(character)
		task.spawn(add, character)
	end)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(remove)
	for _, character in CollectionService:GetTagged("Combatant") do
		task.spawn(add, character)
	end

	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		for character, hero in heroes do
			if not character.Parent then
				heroes[character] = nil
				continue
			end
			locomote(hero, dt, now)
			hero.motion:step(dt)
		end
	end)
end

return HeroAnimator
