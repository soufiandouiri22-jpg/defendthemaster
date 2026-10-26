-- Shared settings of Defend The Master.
local Config = {}

Config.HeroesPerTeam = 4

-- The colosseum (design 01): a round sand arena 250 studs across. Red's end is north (-Z), Blue's south (+Z).
Config.Arena = {
	Radius = 125,
}

-- The Master is an NPC king on his throne, a giant beside the heroes (three times their size); the throne room grows
-- with him.
Config.Master = {
	Scale = 3,
	Health = 20000,
}

-- Coins: every hero starts with enough for a potion and a small first item, and earns more by last hits on minions
-- and the killing blow on an enemy hero.
Config.Economy = {
	StartCoins = 500,
	HeroBounty = 150,
}

-- Levels, as in League of Legends: when an enemy dies, the heroes of the other team within `Share` studs (and its
-- killer, wherever he is) share its XP evenly. `Steps` is the XP from each level to the next. Every level adds
-- `Health` and `Damage` of the hero's base, and a point to spend on raising M2, E or R one rank with the keys 1, 2 and 3
-- (`Upgrades`). A rank adds `RankDamage` to its ability's damage and takes `RankCooldown` off its cooldown; rank `n`
-- of an ability needs the hero level `Needs[key][n]`.
Config.Progress = {
	MaxLevel = 10,
	Steps = { 120, 160, 200, 240, 280, 320, 360, 400, 440 },
	Share = 36,
	MinionXp = { Melee = 40, Spitter = 30 },
	HeroXp = 140,
	HeroXpPerLevel = 25,
	-- Damage on a hero counts for his kill this long.
	KillCredit = 10,
	Health = 0.08,
	Damage = 0.04,
	MaxRank = 3,
	RankDamage = 0.2,
	RankCooldown = 0.1,
	Upgrades = { "M2", "E", "R" },
	Needs = {
		M2 = { 1, 2, 4 },
		E = { 1, 2, 4 },
		R = { 1, 6, 9 },
	},
}

-- The team minions (concept G, rock creatures with crystals): a wave leaves both of a team's doorways on its own half every
-- `WaveInterval` seconds and marches on the other team's Master, fighting every enemy it meets on the way. Only the last
-- hit earns the bounty. Ranges are from edge to edge, speeds in studs a second (a hero walks 16).
Config.Minions = {
	FirstWave = 20,
	WaveInterval = 30,
	-- Per doorway and wave, in marching order: two doorways a team, so twelve minions a wave in all.
	Wave = { "Spitter", "Spitter", "Spitter" },
	MaxPerTeam = 15,
	-- The lanes pass the east and west gates this far from the centre, between the cover arcs and the pillars.
	LaneRadius = 82,
	Radius = 1.8,
	Height = 5.2,
	-- A minion turns on an enemy this close, and gives up the chase this far from where it left its path.
	Acquire = 18,
	Leash = 30,
	-- An enemy hero who attacks a hero this close to a minion becomes its target, for this many seconds.
	CallForHelp = 18,
	CallTime = 3,
	-- Minions do this share of their damage to a Master.
	VsMaster = 0.5,
	Kinds = {
		Melee = { Health = 450, Damage = 12, Interval = 1.25, Range = 1.2, Speed = 11, Bounty = 20 },
		Spitter = { Health = 280, Damage = 22, Interval = 1.6, Range = 18, Speed = 11, Bounty = 15, SpitSpeed = 45 },
	},
}

-- The heroes. Each looks like a Roblox R15 avatar put together from catalog items (Docs/Third_Party.md): a classic
-- shirt and pants, hair, a face accessory, and one skin colour on every body part. Faces come from the catalog too: R15
-- heads are dynamic heads, on which a Decal face does not render. Until the draft exists every player plays
-- `DefaultHero`, and comes back on a spawn pad `RespawnTime` seconds after dying.
--
-- A hero moves and attacks with the motions of a bought animation pack (`Pack`, a folder in ReplicatedStorage with the
-- pack's player and rig, Docs/Third_Party.md). The pack's rig has the R15 proportions of BodyTypeScale 0 and
-- ProportionScale 0, so the hero's body has them too, and wears the pack's weapons (`Weapons`, from the rig's
-- Components). `Motions` names the pack's clips the hero moves with.
--
-- The kit: M1 a combo of hits, M2, E and R abilities. Times are seconds into the motion at speed 1 (`Speed` plays it
-- faster), ranges in studs from the hero to the target's edge, angles the cone's full width in degrees. Every hit
-- lands at its time in the motion, on the server. Indicators (design 06): "Arrow" (a skillshot), "Zone" (a range
-- round the hero and the spot aimed at), "Cone".
Config.Heroes = {
	Shadowren = {
		Role = "Assassin",
		Health = 900,
		Look = {
			Shirt = 13403820292,
			Pants = 10703036251,
			HairAccessory = "123654118197750",
			FaceAccessory = "97583676955915",
			-- The face accessory is a mask round the whole head, so the head under it is hidden.
			HideHead = true,
			Skin = Color3.fromRGB(20, 20, 22),
		},
		-- The hero's painted portrait (Art/Portraits, Meshy image-to-image from a screenshot of the hero in the style of
		-- design 07's cards), the same for everyone who plays him; `Face` is the square round his head and shoulders, in
		-- the image's pixels, for the HUD.
		Portrait = { Image = "rbxassetid://71875745938433", Face = { 190, 40, 620 } },
		-- The ability bar's icons per key (Art/Icons, cut by Tools/cut_icons.py from one Meshy sheet).
		Icons = {
			M1 = "rbxassetid://74233759096248",
			M2 = "rbxassetid://81695145972830",
			E = "rbxassetid://114127186056136",
			R = "rbxassetid://76679849457171",
			Dash = "rbxassetid://101991460104367",
		},
		Pack = "ShadowDuelist",
		Weapons = { "DaggerRight", "DaggerLeft" },
		Motions = {
			Idle = "RA-SHD-015",
			Run = "RA-SHD-005",
			RunLeft = "RA-SHD-006",
			RunRight = "RA-SHD-007",
			Back = "RA-SHD-002",
			Takeoff = "RA-SHD-011",
			Air = "RA-SHD-012",
			Land = "RA-SHD-013",
		},
		Kit = {
			M1 = {
				Kind = "Combo",
				Speed = 1.25,
				-- The combo starts again after this long without a swing.
				Reset = 1.5,
				Hits = {
					{ Motion = "RA-SHD-024", Hit = 0.40, Damage = 30, Range = 6, Angle = 110 },
					{ Motion = "RA-SHD-023", Hit = 0.35, Damage = 35, Range = 6, Angle = 110 },
					-- The turning sweep hits all round him.
					{ Motion = "RA-SHD-044", Hit = 1.13, Damage = 60, Range = 7, Angle = 360 },
				},
			},
			-- A leap to the spot aimed at, landing in a ring of damage.
			M2 = {
				Kind = "Leap",
				Motion = "RA-SHD-058",
				Indicator = "Zone",
				Cooldown = 7,
				Range = 14,
				Radius = 8,
				Damage = 90,
				-- He leaves the ground and lands at these times.
				Takeoff = 0.33,
				Land = 1.55,
			},
			-- A shadow dagger thrown from the left hand, which hits the first enemy in its way.
			E = {
				Kind = "Throw",
				Motion = "RA-SHD-035",
				Indicator = "Arrow",
				Cooldown = 8,
				Release = 0.4,
				ProjectileSpeed = 90,
				Range = 40,
				Width = 2,
				Damage = 110,
			},
			-- Fast sweeps in a cone ahead of him.
			R = {
				Kind = "Flurry",
				Motion = "RA-SHD-071",
				Indicator = "Cone",
				Cooldown = 40,
				Hits = { 0.27, 0.43, 0.60, 0.97, 1.57, 2.13 },
				-- He comes down from his leap and strikes the ground, in a shockwave of shadow.
				Slam = 2.13,
				Damage = 40,
				Range = 10,
				Angle = 70,
			},
			-- A low lunge through the shadows to where he aims (Shift), nicking every enemy he passes through once.
			Dash = {
				Kind = "Dash",
				Motion = "RA-SHD-059",
				Speed = 1.3,
				Cooldown = 5,
				Range = 16,
				Width = 4,
				Damage = 20,
				-- He moves from Start to Move seconds after the press, and the lunge fades out at Stop.
				Start = 0.04,
				Move = 0.34,
				Stop = 0.55,
			},
		},
	},
}
Config.DefaultHero = "Shadowren"
Config.RespawnTime = 5

-- Every hero walks `WalkSpeed`, and `AttackWalkSpeed` while a motion of his kit plays. Commands from a client for a
-- hit further than `Slack` studs beyond the server's ranges are ignored.
Config.Combat = {
	WalkSpeed = 16,
	AttackWalkSpeed = 5,
	Slack = 4,
}

-- The arena's light, one of `Presets` by name: "Day" is the warm, sunny afternoon of the designs, "Cool" the same
-- afternoon a little darker, with less yellow and bluish shade and sky. `Flame` scales the braziers' lights
-- (brightness, reach).
Config.Lighting = {
	Preset = "Cool",
	Presets = {
		Day = {
			ClockTime = 14.2,
			Brightness = 3.2,
			Ambient = Color3.fromRGB(120, 110, 104),
			OutdoorAmbient = Color3.fromRGB(170, 160, 150),
			ColorShiftTop = Color3.new(0, 0, 0),
			EnvironmentDiffuseScale = 0.8,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.2,
			Exposure = 0,
			Atmosphere = {
				Density = 0.18,
				Offset = 0.05,
				Color = Color3.fromRGB(220, 230, 240),
				Decay = Color3.fromRGB(150, 170, 200),
				Glare = 0.2,
				Haze = 0.4,
			},
			Grade = { Saturation = 0.18, Contrast = 0.1, Brightness = 0.03, Tint = Color3.fromRGB(255, 250, 240) },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
			Flame = { Brightness = 1.4, Range = 6 },
		},
		Cool = {
			ClockTime = 15.6,
			Brightness = 2.5,
			Ambient = Color3.fromRGB(100, 104, 122),
			OutdoorAmbient = Color3.fromRGB(132, 138, 160),
			ColorShiftTop = Color3.fromRGB(225, 232, 255),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.6,
			ShadowSoftness = 0.15,
			Exposure = -0.1,
			Atmosphere = {
				Density = 0.28,
				Offset = 0.08,
				Color = Color3.fromRGB(196, 208, 230),
				Decay = Color3.fromRGB(104, 118, 156),
				Glare = 0.1,
				Haze = 0.9,
			},
			Grade = { Saturation = 0.08, Contrast = 0.16, Brightness = -0.03, Tint = Color3.fromRGB(236, 241, 255) },
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.25 },
			Flame = { Brightness = 2, Range = 7 },
		},
	},
}

Config.Teams = {
	Blue = {
		Name = "Blue",
		Color = Color3.fromRGB(64, 132, 255),
		DarkColor = Color3.fromRGB(28, 52, 120),
	},
	Red = {
		Name = "Red",
		Color = Color3.fromRGB(235, 64, 64),
		DarkColor = Color3.fromRGB(110, 24, 24),
	},
}
Config.TeamOrder = { "Blue", "Red" }

return Config
