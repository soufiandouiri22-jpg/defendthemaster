-- The game's cues: the interface's, played flat (UiSound.play), and the arena's, played where they happen with the
-- heroes' falloff (UiSound.at). Each is a cut of a sound from Roblox's licensed library (Assets, Docs/Third_Party.md),
-- unless the game's own uploaded file (Shared.UiSounds, made by Tools/ui_sounds.py) has a region by its name.

local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Preferences = require(script.Parent.Preferences)

local UiSound = {}

-- Each cue: where it starts in its sound and how long it plays (seconds, to the end without a length), measured with
-- an AudioAnalyzer, and its gain, which brings the recordings to one loudness (times the asked volume). Heard in the
-- world at full strength within `near` studs, fading out to nothing at `far`.
-- The buy phase's sting swells twice: a plain kill plays its first swell, the bigger kills its second, to its end.
-- The bigger kills but one play the first roll of the drum sting, up to its loudest beat and that beat's tail; the
-- biggest the boom, whole and louder.
-- A `steady` effect is never sunk under an announcement (Preferences.STEADY).
type Cue = {
	asset: string,
	start: number,
	length: number?,
	gain: number?,
	near: number?,
	far: number?,
	steady: boolean?,
}
local BOOM: Cue = { asset = Assets.FightBoom, start = 0, gain = 2 }
local CUES: { [string]: Cue } = {
	KillSlain = { asset = Assets.BuySting, start = 0, length = 2.85 },
	KillBig = { asset = Assets.BuySting, start = 2.85 },
	KillHuge = { asset = Assets.DrumSting, start = 0, length = 3.4 },
	KillLegend = BOOM,
	Death = BOOM,
	-- A coin of a bounty landing in the counter: the first clink of a coin bouncing on wood.
	Coin = { asset = Assets.CoinBounce, start = 0, length = 0.12, gain = 0.2 },

	-- The armory: the mouse over a card, a slot or a tab; a card or slot chosen; a tab opened; a heavy cloth swung open
	-- and shut; chain mail taken up for an item bought, coins taken for one sold; what cannot be bought; a purchase
	-- taken back.
	Hover = { asset = Assets.UiHover, start = 0, length = 0.2, gain = 1.6 },
	Pick = { asset = Assets.UiSelect, start = 0, length = 0.45, gain = 1.2 },
	Tab = { asset = Assets.UiSwipe, start = 0, length = 0.5, gain = 1.3 },
	ShopOpen = { asset = Assets.ClothSwing, start = 0, length = 0.32, gain = 0.6 },
	ShopClose = { asset = Assets.ClothSwing, start = 0.33, length = 0.33, gain = 0.6 },
	Buy = { asset = Assets.ChainMail, start = 0.15, length = 0.4, gain = 0.7 },
	Sell = { asset = Assets.CoinJingle, start = 0, length = 0.35, gain = 1.8 },
	Denied = { asset = Assets.WoodThud, start = 0, length = 0.3, gain = 0.45 },
	Undo = { asset = Assets.UiBack, start = 0, length = 0.4, gain = 2.2 },

	-- The end of a match, under the VICTORY or DEFEAT title. The victory's recording is about 4.5 dB quieter than the
	-- others (RMS -19.7 dB against about -15); its gain brings it level, its loudest peak to 0.97.
	Victory = { asset = Assets.VictorySting, start = 0, length = 6.5, gain = 1.65 },
	Defeat = { asset = Assets.DefeatSting, start = 0, length = 7 },

	-- The hero grows: a level, a rank of an ability, his ultimate ready again, a potion drunk; and the scoreboard
	-- unfolded.
	LevelUp = { asset = Assets.MagicTwirl, start = 0, length = 1.4, gain = 0.9 },
	RankUp = { asset = Assets.PowerClunk, start = 0, length = 0.3, gain = 0.5 },
	UltimateReady = { asset = Assets.SwordDraw, start = 0, length = 0.45, gain = 1.5 },
	Potion = { asset = Assets.CorkPull, start = 0, length = 0.4, gain = 0.8 },
	Scoreboard = { asset = Assets.PaperHandling, start = 0.08, length = 0.37, gain = 0.27 },

	-- A sniper's scope coming to his eye, and his bullet striking a head (Scope).
	ScopeIn = { asset = Assets.PowerClunk, start = 0, length = 0.3, gain = 0.6 },
	Headshot = { asset = Assets.UiSelect, start = 0, length = 0.45, gain = 1.4 },

	-- The last three seconds of the player's turn in the draft: the buy phase's timpani tick.
	CountTick = { asset = Assets.CountTick, start = 0, length = 0.8, gain = 0.5 },

	-- A hero coming back on his pad, and a hero's healing there beginning (never sunk, owner 2026-11-01).
	Respawn = { asset = Assets.MagicExit, start = 0.15, length = 1.85, gain = 0.55 },
	PadHeal = { asset = Assets.MagicGlow, start = 0, length = 1.2, gain = 3.75, near = 10, far = 50, steady = true },

	-- The player's avatar turning into his hero on the podium (Lobby.Showcase): the power gathering and swirling round
	-- him, the blast that turns him, and the shimmer the hero stands in.
	TransformCharge = { asset = Assets.MagicTwirl, start = 0, length = 1.4, gain = 1.1 },
	TransformSwirl = { asset = Assets.MagicExit, start = 0.15, length = 1.85, gain = 0.9 },
	TransformBoom = { asset = Assets.FightBoom, start = 0, gain = 1.5 },
	TransformShimmer = { asset = Assets.FallingShimmer, start = 0.4, length = 2.5, gain = 1.1 },

	-- A boost: taken by the enemy, fading.
	BoostEnemy = { asset = Assets.EvilBell, start = 0.5, length = 3, gain = 1.35 },
	BoostFades = { asset = Assets.FallingShimmer, start = 0.4, length = 2.5, gain = 1.1 },

	-- The minions, only near: a spitter's fireball leaving and bursting, a biter's bite, a minion crumbling (its stone
	-- and its crystals).
	MinionSpit = { asset = Assets.FireWhoosh, start = 0.03, length = 0.47, gain = 0.6, near = 8, far = 45 },
	MinionBurst = { asset = Assets.FireBurst, start = 0.22, length = 0.33, gain = 0.55, near = 8, far = 45 },
	MinionBite = { asset = Assets.RockKnock, start = 0, length = 0.15, gain = 0.32, near = 8, far = 45 },
	MinionCrumble = { asset = Assets.RockBreak, start = 0.05, length = 0.35, gain = 0.55, near = 8, far = 45 },
	MinionShards = { asset = Assets.GlassShards, start = 0.03, length = 0.37, gain = 0.2, near = 8, far = 45 },

	-- A Master falling.
	MasterFalls = { asset = Assets.DeepThud, start = 0, length = 4.5, gain = 0.8 },

	-- A hero going through a portal, heard where he goes in and where he comes out (played higher than Respawn).
	PortalJump = { asset = Assets.MagicExit, start = 0.15, length = 1.5, gain = 0.8, near = 14, far = 90 },

	-- The arena's traps and ways (Config.Spikes, FireGrates, NetStatues, RuneGates, JumpPads), only near: spikes
	-- shooting up (a sword's ring), a grate's fire bursting up, the net thrown, a hero going through a Rune Gate (as
	-- a portal), a jump pad's launch.
	SpikesUp = { asset = Assets.SwordDraw, start = 0, length = 0.35, gain = 1.3, near = 10, far = 60 },
	GrateFire = { asset = Assets.FireWhoosh, start = 0.03, length = 0.47, gain = 1, near = 10, far = 60 },
	NetThrow = { asset = Assets.ClothSwing, start = 0, length = 0.32, gain = 1.1, near = 12, far = 70 },
	RuneGate = { asset = Assets.MagicExit, start = 0.15, length = 1.5, gain = 0.8, near = 14, far = 90 },
	JumpPad = { asset = Assets.PowerClunk, start = 0, length = 0.3, gain = 0.8, near = 10, far = 60 },

	-- Each shock of Brontar's zap and each bolt of his strike from the sky (Config.Heroes.Brontar.Kit.E and R): only
	-- the sharp attack at the start of Pro Sound Effects' "Zaps Sharp Attack 1" (owner, 2026-10-31), without the hum
	-- that follows it.
	Zap = { asset = Assets.ZapAttack, start = 0.2, length = 0.45, gain = 1 },
	-- The thunder rolling under the strike's bolts (owner, 2026-10-31): Pro Sound Effects' "Lightning Strike Sharp
	-- Hissing Crack 5" from its build-up, its crack 0.6 seconds in, rumbling on for about three seconds; heard far.
	Thunder = { asset = Assets.Thunder, start = 0.9, length = 3.8, gain = 1.6, near = 40, far = 150 },

	-- Every hit, by anyone on anything (HitFeedback, Config.Combat.HitSounds).
	Hit = { asset = Assets.Hit, start = 0, gain = 0.5 },
	HitLow = { asset = Assets.HitLow, start = 0, gain = 0.5 },
	HitRaw = { asset = Assets.HitRaw, start = 0, gain = 0.5 },
	-- Mixkit's, brought level with HitRaw (their loudest 50 ms: golf 14.3 dB softer, heartbeat 5.8, punch 6.4); the
	-- punch then 3.5 dB softer again (owner, 2026-10-29).
	HitGolf = { asset = Assets.HitGolf, start = 0, gain = 2.6 },
	HitHeart = { asset = Assets.HitHeart, start = 0, gain = 0.98 },
	HitPunch = { asset = Assets.HitPunch, start = 0, gain = 0.7 },
	-- The three body punches, in a row (Config.Combat.HitSounds); the file is 0.546 of HitPunch's level, so 1.28 plays
	-- them as loud as HitPunch now.
	HitBody1 = { asset = Assets.HitBody, start = 0, length = 0.411, gain = 1.28 },
	HitBody2 = { asset = Assets.HitBody, start = 0.511, length = 0.437, gain = 1.28 },
	HitBody3 = { asset = Assets.HitBody, start = 1.048, length = 0.417, gain = 1.28 },
	-- The Ranger pack's body impacts, already as loud as the punch played last.
	BodyImpact1 = { asset = Assets.HitBodyImpact, start = 0, length = 0.355 },
	BodyImpact2 = { asset = Assets.HitBodyImpact, start = 0.455, length = 0.61 },
	BodyImpact3 = { asset = Assets.HitBodyImpact, start = 1.165, length = 0.457 },
}
-- How long a cut sound takes to fade out at its end, so it stops without a click.
local FADE = 0.2
-- The longest an uncut sound may stay, should it never report its end.
local MOST = 20
-- The heroes' falloff (HeroSounds), for cues without their own.
local NEAR, FAR = 14, 80

type Bank = { Asset: string, Regions: { [string]: { number } } }
local bank: Bank? = nil
do
	local module = ReplicatedStorage.Shared:FindFirstChild("UiSounds")
	if module then
		bank = require(module) :: any
	end
	-- Roblox lets a sound's audio go once no Sound holds it, and a new one then takes a good part of a second to load:
	-- one silent Sound per asset stays in SoundService so every cue starts at once.
	local held = Instance.new("Folder")
	held.Name = "UiSoundsHeld"
	local probes = {}
	local seen = {}
	local function hold(asset: string)
		if not seen[asset] then
			seen[asset] = true
			local probe = Instance.new("Sound")
			probe.SoundId = asset
			probe.Volume = 0
			probe.Parent = held
			table.insert(probes, probe)
		end
	end
	for _, cue in CUES do
		hold(cue.asset)
	end
	if bank then
		hold(bank.Asset)
	end
	held.Parent = SoundService
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, probes)
end

-- Parents `sound` to `parent` and plays it once it has loaded, then runs `started`. A new Sound can take a good part
-- of a second to load even when its asset was preloaded, so a cut's clock may only run from there.
local function playLoaded(sound: Sound, parent: Instance, started: (() -> ())?)
	Debris:AddItem(sound, MOST)
	sound.Parent = parent
	local function go()
		if sound.Parent then
			sound:Play()
			if started then
				started()
			end
		end
	end
	if sound.IsLoaded then
		go()
	else
		sound.Loaded:Once(go)
	end
end

-- A sound of the cue `name` at `volume` and `pitch`, parented to `parent` and playing as soon as it has loaded; nil
-- when there is no such cue, or while the loading screen is up (the menu behind it hears the mouse pass over it) unless
-- `over`: the sound of a screen shown over the loading screen (the match's cards, VersusView).
local function start(
	name: string,
	parent: Instance,
	volume: number?,
	pitch: number?,
	group: string,
	over: boolean?
): (Sound?, Cue?)
	if not over and not Loading.isGone() then
		return nil, nil
	end
	local speed = pitch or 1
	local sound = Instance.new("Sound")
	sound.PlaybackSpeed = speed
	sound.SoundGroup = Preferences.group(group)
	local region = bank and bank.Regions[name]
	if bank and region then
		sound.SoundId = bank.Asset
		sound.Volume = volume or 1
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region[1], region[1] + region[2])
		playLoaded(sound, parent, function()
			Debris:AddItem(sound, region[2] / speed + 0.2)
		end)
		return sound, nil
	end
	local cue = CUES[name]
	if not cue then
		sound:Destroy()
		return nil, nil
	end
	if cue.steady and group == "Effects" then
		sound.SoundGroup = Preferences.group(Preferences.STEADY)
	end
	sound.SoundId = cue.asset
	sound.Volume = (volume or 1) * (cue.gain or 1)
	local length = cue.length
	if length then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(cue.start, cue.start + length)
		local playing = length / speed
		local fade = math.min(FADE, playing / 3)
		playLoaded(sound, parent, function()
			task.delay(playing - fade, function()
				if sound.Parent then
					TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 }):Play()
				end
			end)
			Debris:AddItem(sound, playing + 0.2)
		end)
	else
		sound.TimePosition = cue.start
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		playLoaded(sound, parent)
	end
	return sound, cue
end

-- Plays `name` flat, at `volume` (1 when not given) and a little higher or lower by `pitch` (1 is as recorded); with
-- `over` also while the loading screen is up, for a screen shown over it.
function UiSound.play(name: string, volume: number?, pitch: number?, over: boolean?)
	start(name, SoundService, volume, pitch, "Interface", over)
end

-- An announcement goes before every other sound (owner, 2026-10-30): the music and the effects sink to DUCK of
-- their volume within DUCK_IN seconds while it plays and come back over DUCK_OUT, and a new one fades the one before
-- out over CUT seconds instead of playing over it. They come back as soon as the sting dies away (owner, 2026-10-30):
-- once it has played HELD seconds and stayed under TAIL of its loudest for QUIET seconds, its tail plays over them.
local DUCK, DUCK_IN, DUCK_OUT, CUT = 0.35, 0.1, 0.6, 0.15
local HELD, TAIL, QUIET = 0.5, 0.3, 0.15
local announcement: Sound? = nil
local duckLevel = Instance.new("NumberValue")
duckLevel.Value = 1
duckLevel.Changed:Connect(function(level)
	Preferences.duck(level)
end)
local duckTween: Tween? = nil
local function duckTo(level: number, seconds: number)
	if duckTween then
		duckTween:Cancel()
	end
	duckTween = TweenService:Create(duckLevel, TweenInfo.new(seconds), { Value = level })
	duckTween:Play()
end

-- Plays `name` flat as an announcement (a kill's sting), at `volume`.
function UiSound.announce(name: string, volume: number?)
	local before = announcement
	if before and before.Parent then
		TweenService:Create(before, TweenInfo.new(CUT), { Volume = 0 }):Play()
		Debris:AddItem(before, CUT + 0.05)
	end
	local sound = start(name, SoundService, volume, nil, "Interface")
	announcement = sound
	if not sound then
		return
	end
	duckTo(DUCK, DUCK_IN)
	task.spawn(function()
		local waited = os.clock()
		while sound.Parent and not sound.IsPlaying and os.clock() - waited < 3 do
			task.wait(0.05)
		end
		local began = os.clock()
		local loudest, quietSince = 0, nil
		while sound.Parent and sound.IsPlaying and sound.Volume > 0 do
			local loudness = sound.PlaybackLoudness
			loudest = math.max(loudest, loudness)
			if loudness < loudest * TAIL then
				quietSince = quietSince or os.clock()
				if os.clock() - began >= HELD and os.clock() - quietSince >= QUIET then
					break
				end
			else
				quietSince = nil
			end
			task.wait(0.05)
		end
		if announcement == sound then
			duckTo(1, DUCK_OUT)
		end
		while sound.Parent and sound.IsPlaying and sound.Volume > 0 do
			task.wait(0.05)
		end
		if announcement == sound then
			announcement = nil
		end
	end)
end

-- Whether an announcement is playing now.
function UiSound.announcing(): boolean
	return announcement ~= nil and announcement.Parent ~= nil
end

-- Plays `name` in the world: from `where`, a part (following it) or a point, fading out with distance.
function UiSound.at(name: string, where: BasePart | Vector3, volume: number?, pitch: number?)
	local parent: Instance
	if typeof(where) == "Vector3" then
		local spot = Instance.new("Attachment")
		spot.WorldPosition = where
		spot.Parent = Workspace.Terrain
		Debris:AddItem(spot, MOST)
		parent = spot
	else
		parent = where
	end
	local sound, cue = start(name, parent, volume, pitch, "Effects")
	if sound then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = cue and cue.near or NEAR
		sound.RollOffMaxDistance = cue and cue.far or FAR
	end
end

return UiSound
