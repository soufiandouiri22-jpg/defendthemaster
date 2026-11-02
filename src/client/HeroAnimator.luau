-- Moves every hero (a Combatant with the "Hero" attribute) with its animation pack's clips (Shared.Motion): the battle
-- idle when it stands, running forward, sideways or backward by the way it moves relative to where it faces, and the
-- jump's takeoff, flight and landing (a jump pad's flight, its "Flying" attribute, in the air all the way, JumpPadView);
-- and over that the motions of its attacks (HeroAnimator.play). When it dies, the
-- pack's fall. Every hero's feet sound as Shadowren's (FEET): his pack's footsteps on the sand where the hero's clips
-- put a foot down, and his takeoff's and landing's steps when it jumps, whatever the hero's own pack has for those.

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
-- The hero whose feet every hero's sound like.
local FEET = Config.Heroes.Shadowren

type Hero = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motions: { [string]: string },
	motion: Motion.Motion,
	feet: HeroSounds.Bank?,
	height: number,
	airborne: number,
	landingUntil: number,
	dead: boolean,
}

local heroes: { [Model]: Hero } = {}
local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGround()
	ground.FilterDescendantsInstances = HeroKit.leapIgnore()
end

-- A dead hero falls with his pack's own fall (`Death`), which carries his weapons down with him, where the server
-- holds his root part (HeroService), and lies as it ends until his body is gone. He stays posed by his Motion till then:
-- the Animator sets the player's own hero back to rest every frame once he is dead. His body's joints are switched back
-- on (Motion.holdJoints) on Died itself, as the Humanoid lets go of them only then, which can be after he left the fight.
local function fall(hero: Hero)
	if hero.dead then
		return
	end
	hero.dead = true
	local death = hero.motions.Death
	if death then
		hero.motion:play(death, 1, nil, false, true)
	end
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
		feet = HeroSounds.bank(FEET.Pack),
		height = humanoid.HipHeight + root.Size.Y / 2,
		airborne = 0,
		landingUntil = 0,
		dead = false,
	}
	humanoid.Died:Connect(function()
		fall(hero)
		Motion.holdJoints(character)
	end)
	local bank = HeroSounds.bank(settings.Pack)
	local feet = hero.feet
	if bank then
		-- The jump's steps are FEET's own (jumpSteps), not those the hero's takeoff and landing clips have.
		local cues = table.clone(bank.Cues)
		cues[settings.Motions.Takeoff or ""] = nil
		cues[settings.Motions.Land or ""] = nil
		hero.motion.cues = cues
		hero.motion.onCue = function(cue)
			if not cue.Footstep then
				HeroSounds.cue(character, bank, cue)
			elseif feet then
				HeroSounds.step(character, root, feet, cue.Volume)
			end
		end
	end
	hero.motion:setBase(settings.Motions.Idle, 1)
	heroes[character] = hero
	refreshGround()
end

-- A hero leaves the fight only by dying (HeroService.discharge); his body is let go once it is gone.
local function remove(character: Instance)
	local hero = heroes[character :: Model]
	if hero then
		fall(hero)
	end
	refreshGround()
end

-- The steps of FEET's clip `clip` (his takeoff or landing), at the times his clip has them.
local function jumpSteps(hero: Hero, clip: string?)
	local feet = hero.feet
	local cues = feet and clip and feet.Cues[clip]
	if not feet or not cues then
		return
	end
	for _, cue in cues do
		if cue.Footstep then
			task.delay(cue.Time, function()
				if hero.character.Parent and not hero.dead then
					HeroSounds.step(hero.character, hero.root, feet, cue.Volume)
				end
			end)
		end
	end
end

local function locomote(hero: Hero, dt: number, now: number)
	local motions, motion, root = hero.motions, hero.motion, hero.root
	-- A jump pad's flight is in the air from takeoff to landing, whatever it passes over (the pad itself, cover).
	local flying = hero.character:GetAttribute("Flying")
	local below = if type(flying) == "number" and flying > Workspace:GetServerTimeNow()
		then nil
		else Workspace:Raycast(root.Position, Vector3.new(0, -(hero.height + 0.6), 0), ground)
	if not below then
		if hero.airborne == 0 then
			motion:setBase(motions.Takeoff, 1)
			motion:restartBase()
			jumpSteps(hero, FEET.Motions.Takeoff)
		elseif motion.base and motion.base.id == motions.Takeoff and motion:baseDone() then
			motion:setBase(motions.Air, 1)
		end
		hero.airborne += dt
		return
	end
	if hero.airborne > LAND_AFTER then
		motion:setBase(motions.Land, 1)
		motion:restartBase()
		jumpSteps(hero, FEET.Motions.Land)
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
-- own travel ("Grounded" without its rise into the air either); returns how long it lasts.
function HeroAnimator.play(
	character: Model,
	id: string,
	speed: number,
	startTime: number?,
	inPlace: (boolean | string)?
): number
	local hero = heroes[character]
	if not hero or hero.dead then
		return 0
	end
	return hero.motion:play(id, speed, startTime, inPlace)
end

-- Plays the clip `character`'s hero plays over its base on at `speed` from now.
function HeroAnimator.setSpeed(character: Model, speed: number)
	local hero = heroes[character]
	if hero and not hero.dead then
		hero.motion:setSpeed(speed)
	end
end

-- The clip `character`'s hero plays over its base, if any.
function HeroAnimator.playing(character: Model): string?
	local hero = heroes[character]
	return hero and hero.motion:playing()
end

function HeroAnimator.stop(character: Model)
	local hero = heroes[character]
	if hero and not hero.dead then
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
				HeroSounds.forget(character)
				continue
			end
			if not hero.dead then
				locomote(hero, dt, now)
			end
			hero.motion:step(dt)
		end
	end)
end

return HeroAnimator
