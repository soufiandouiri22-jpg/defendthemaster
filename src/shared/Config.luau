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
}

-- Coins: every hero starts with enough for a potion and a small first item, and earns more by last hits.
Config.Economy = {
	StartCoins = 500,
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
Config.Heroes = {
	Shadowren = {
		Role = "Assassin",
		Look = {
			Shirt = 13403820292,
			Pants = 10703036251,
			HairAccessory = "123654118197750",
			FaceAccessory = "97583676955915",
			-- The face accessory is a mask round the whole head, so the head under it is hidden.
			HideHead = true,
			Skin = Color3.fromRGB(20, 20, 22),
		},
	},
}
Config.DefaultHero = "Shadowren"
Config.RespawnTime = 5

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
