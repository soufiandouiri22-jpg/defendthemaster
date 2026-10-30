-- Shared settings of Defend The Master.
local Config = {}

Config.HeroesPerTeam = 4

-- The colosseum (design 01): a round sand arena 250 studs across. Red's end is north (-Z), Blue's south (+Z).
Config.Arena = {
	Radius = 125,
}

-- The Master is an NPC king on his throne, a giant beside the heroes (three times their size); the throne room grows
-- with him. He never heals (MasterService). He sits until an enemy (a hero, or a minion when no hero is there) comes
-- within `Zone` studs of his dais' front, then stands up and fights: enemy heroes first, the nearest of them, else the
-- nearest minion, never going further than `Leash` studs from that spot. With nobody left in his zone for `Calm`
-- seconds he walks back and sits down again. He walks slowly (`WalkSpeed`, a hero walks Config.Combat.WalkSpeed).
-- He moves with the Greataxe Berserker's clips (`Pack`, Shared.Sequence, Docs/Third_Party.md) and holds its weapon.
-- His swing (`Swing`) cuts everyone in front of him within `Reach` studs of his middle, every `Every` seconds: its
-- clips (`Motions`) take turns, each striking `Hits` seconds in and lasting `Length`. His ground slam (`Slam`) first
-- shows a red circle of `Radius` studs round the spot `Ahead` studs before him while he works himself up (the `Frenzy`
-- clip, `FrenzyLength` seconds) and swings (the `Motion` clip, striking `Impact` seconds in and lasting `Length`), then
-- strikes everyone in it; he slams when `Crowd` enemies or more stand in it, or when a hero has stood alone before him
-- for `Alone` seconds since the slam came off its `Cooldown`. Standing up from the throne takes `Rise` seconds; he
-- falls with the `Death` clip. He is dressed from the catalogue as design 02 (`Look`): a toga with a red sash, the gold
-- crown, a red cape, short brown hair and a grim face; the blue team's Master wears his reds in blue (`TeamLook`).
Config.Master = {
	Scale = 3,
	Health = 20000,
	Zone = 50,
	Leash = 62,
	Calm = 3,
	WalkSpeed = 10,
	Rise = 1.2,
	Reach = 14,
	Pack = "GreataxeBerserker",
	-- The hip height its clips were authored at (their AuthoredHipHeight, which a game script may not read).
	PackHipHeight = 2,
	-- His gold greatsword in ServerStorage (Import 3D): its length in studs along X, the tip at +X, and where his fist
	-- closes round its grip, just under the guard, as a share of that length from the centre towards the pommel at -X.
	-- Until he draws it, it hangs on his back: that spot of the grip `At` from his upper torso (right, up, back), above
	-- his right shoulder, the blade leaning `Lean` degrees from straight down towards his left.
	Sword = {
		Name = "MasterGreatsword",
		Length = 13,
		Grip = 0.285,
		Back = { At = Vector3.new(2.6, 3.2, 2.3), Lean = 30 },
	},
	-- Once he stands he waits `Pause` seconds, reaches over his right shoulder for the grip in `Reach` seconds, and
	-- draws it into his guard; he fights `Length` seconds after he stood up.
	Draw = { Pause = 0.6, Reach = 0.5, Length = 1.8 },
	-- Back before his throne he lowers his guard (the `Unguard` clip), reaches over his shoulder in `Reach` seconds to
	-- put his sword on his back, and sits down `Length` seconds after he arrived.
	Sheath = { Reach = 0.5, Length = 1.5 },
	Swing = {
		Every = 2.4,
		Angle = 130,
		Damage = 140,
		Motions = { "Attack1", "Attack2", "Attack3" },
		Hits = { 0.5, 0.45, 0.45 },
		Length = 1.33,
	},
	Slam = {
		Cooldown = 10,
		Frenzy = "Frenzy",
		FrenzyLength = 2,
		Motion = "Slam",
		Impact = 1.3,
		Length = 2.67,
		Radius = 18,
		Ahead = 5,
		Damage = 260,
		Crowd = 2,
		Alone = 6,
	},
	Death = "Death",
	-- He draws his sword into his guard with this clip, then stands in the `Stance` clip (a wide-legged battle stance,
	-- looped) whenever he is armed and not swinging; while he walks his legs take the steps and the rest keeps it.
	Guard = "Guard",
	Stance = "Stance",
	Unguard = "Unguard",
	-- His steps while he is up, from a second pack (the Armorer's walks and turns, authored at `HipHeight`): forward,
	-- back and sideways after where he moves against where he faces, played so the feet keep pace with the ground
	-- (`Pace` studs a second at that size), and a turn on the spot when he turns faster than `Turning` radians a
	-- second without moving. Each comes over the other in `Blend` seconds. That pack has no sounds: a foot that comes
	-- down sounds with his fight pack's footsteps on sand (Shared.PackSounds), at `Steps` loudness as in his clips.
	Walk = {
		Pack = "Armorer",
		HipHeight = 2,
		Pace = 3.7,
		Turning = 0.8,
		Blend = 0.2,
		Steps = 0.35,
		Forward = "Walk",
		Back = "WalkBack",
		Left = "WalkLeft",
		Right = "WalkRight",
		TurnLeft = "TurnLeft",
		TurnRight = "TurnRight",
	},
	-- He reels from a hit of at least `Least` while he is not attacking, at most once every `Every` seconds; it only
	-- shows, his fight goes on.
	Flinch = { Motion = "Hit", Least = 80, Every = 5 },
	Look = {
		Shirt = 139322358870952,
		Pants = 89849376904198,
		HatAccessory = "137749277743768",
		BackAccessory = "16247693850",
		-- The hair is listed in the catalogue as a face accessory, as the face is.
		FaceAccessory = "104894753016090,14806562837",
		Skin = Color3.fromRGB(234, 184, 146),
	},
	-- What a team's Master wears instead: the blue one the same cape in blue (the catalogue's own colour of it) and
	-- the toga's shirt with its red turned blue (Art/Clothing, by Tools/team_recolor.py's recolouring), worn as its
	-- template.
	TeamLook = {
		Blue = { BackAccessory = "16247734805", ShirtTemplate = "rbxassetid://124992788134534" } :: {
			BackAccessory: string?,
			ShirtTemplate: string?,
		},
	},
	-- Each team's Master's painted portrait, made as the heroes' are (Art/Portraits: the red one from a Play
	-- screenshot of him, the blue one that recoloured); `Face` is the square round his head and shoulders.
	Portraits = {
		Red = { Image = "rbxassetid://86808592989754", Face = { 230, 30, 700 } },
		Blue = { Image = "rbxassetid://110619426711939", Face = { 230, 30, 700 } },
	},
}

-- Coins, in League of Legends' proportions (a hero kill is worth 14 Melee or 21 Spitter last hits, a legendary item
-- about ten kills): every hero starts with enough for one or two small items in the buy phase (Config.Match), earns
-- `Passive` coins every second once the fight began, and more by last hits on minions and by killing enemy heroes.
-- A hero's bounty, what his killer earns: `HeroBounty` at first; less after he died again without a kill in between
-- (`DeathBounty`, by those deaths: one, two or more), and `StreakBounty` more for every kill past the first since he
-- last died, at most `StreakMax` more. So a hero who keeps dying is worth little, and one on a streak a lot. The other
-- enemies who hurt him within Progress.KillCredit seconds share `Assist` of his bounty on top.
Config.Economy = {
	StartCoins = 600,
	Passive = 2,
	HeroBounty = 300,
	DeathBounty = { 270, 220, 175, 140, 110, 100 },
	StreakBounty = 100,
	StreakMax = 500,
	Assist = 0.5,
}

-- The armory (design 08), as League of Legends' shop: a hero walks to one of his team's two armory stalls and opens it
-- there (within `Reach` studs, holding F), or shops while dead, and carries `Slots` items. A bigger item is built from smaller
-- ones (`From`): the ones he holds count towards it, so he pays only the rest. Selling gives back `Sell` of an item's
-- price, and while he stays at the armory he can undo what he bought and sold since he came. He wears one pair of boots
-- and every legendary item once; potions stack up to `Potion.Stack` in one slot, and each heals `Potion.Heal` over
-- `Potion.Time` seconds (Q), one after another. Crown Bulwark guards within `GuardReach` studs of the hero's Master.
Config.Shop = {
	Slots = 6,
	Sell = 0.7,
	Reach = 16,
	-- The arena is small and fights are quick, so a potion heals in under two seconds (owner, 2026-10-29).
	Potion = { Heal = 120, Time = 1.875, Stack = 5 },
	GuardReach = 40,
	-- How long a wound (Bitter Thorn and the items built from it) keeps a hero's healing down.
	WoundTime = 3,
}

-- The items of the armory (Config.Shop), with their icons (Art/Icons/Items: the first 25 cut by Tools/cut_icons.py from
-- three Meshy sheets, the later ones keyed by Tools/key_icons.py from Art/Icons/keyed/Items). `Cost` is an item's whole price, its parts (`From`) included. Stats: Attack and Magic add to the hero's
-- damage as his kit's `Ratio` of them (a kit scales with its hero's `Scales`); Health adds to his health; Armor and
-- Resist take physical and magic damage down to 100 / (100 + them); AttackSpeed speeds up his M1 combo by that share;
-- Haste shortens his cooldowns to 100 / (100 + it); Lifesteal heals him by that share of the damage he deals; MoveSpeed
-- adds studs a second to his walk. An item's `Effect` is its own (Damage, CombatService); of several items with the
-- same kind of effect only the strongest counts. A wounded hero (Wound, Thorns) heals that share less from lifesteal,
-- potions and pads for Shop.WoundTime seconds. `Classes` are the classes
-- (Config.Classes) it is made for, which the armory's class filters show it under; without them it is for every class.
-- Every hero may buy every item.
Config.Items = {
	IronSword = {
		Name = "Iron Sword",
		Tier = "Basic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 350,
		Stats = { Attack = 10 },
		Icon = "rbxassetid://99540283517950",
	},
	SpellTome = {
		Name = "Spell Tome",
		Tier = "Basic",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 400,
		Stats = { Magic = 20 },
		Icon = "rbxassetid://116217108739196",
	},
	WarHelmet = {
		Name = "War Helmet",
		Tier = "Basic",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 400,
		Stats = { Health = 150 },
		Icon = "rbxassetid://133779764052643",
	},
	SteelShield = {
		Name = "Steel Shield",
		Tier = "Basic",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 300,
		Stats = { Armor = 15 },
		Icon = "rbxassetid://108574198285662",
	},
	MoonRing = {
		Name = "Moon Ring",
		Tier = "Basic",
		Category = "Defense",
		Classes = { "Mage", "Tank" },
		Cost = 450,
		Stats = { Resist = 25 },
		Icon = "rbxassetid://99349652229609",
	},
	SwiftGloves = {
		Name = "Swift Gloves",
		Tier = "Basic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 300,
		Stats = { AttackSpeed = 0.12 },
		Icon = "rbxassetid://113284480767952",
	},
	SandGlass = {
		Name = "Sand Glass",
		Tier = "Basic",
		Category = "Magic",
		Classes = { "Mage", "Assassin" },
		Cost = 400,
		Stats = { Haste = 10 },
		Icon = "rbxassetid://131491517491063",
	},
	Boots = {
		Name = "Boots",
		Tier = "Basic",
		Category = "Speed",
		Cost = 300,
		Boots = true,
		Stats = { MoveSpeed = 1.5 },
		Icon = "rbxassetid://87560735551172",
	},
	HealthPotion = {
		Name = "Health Potion",
		Tier = "Basic",
		Category = "Defense",
		Cost = 50,
		Potion = true,
		Stats = {},
		Text = "Q: heals 120 health over 1.875 seconds",
		Icon = "rbxassetid://72428616348938",
	},
	HuntingBow = {
		Name = "Hunting Bow",
		Tier = "Basic",
		Category = "Attack",
		Classes = { "Archer" },
		Cost = 350,
		Stats = { Attack = 6, AttackSpeed = 0.06 },
		Icon = "rbxassetid://82284547904948",
	},
	BitterThorn = {
		Name = "Bitter Thorn",
		Tier = "Basic",
		Category = "Defense",
		Cost = 450,
		Stats = { Health = 100 },
		Effect = { Kind = "Wound", Value = 0.25 },
		Text = "Your hits wound heroes: 25% less healing for 3 seconds",
		Icon = "rbxassetid://139493454234605",
	},

	KnightsBlade = {
		Name = "Knight's Blade",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 1100,
		From = { "IronSword", "SwiftGloves" },
		Stats = { Attack = 20, AttackSpeed = 0.15 },
		Icon = "rbxassetid://90397100055478",
	},
	HuntersFang = {
		Name = "Hunter's Fang",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 1000,
		From = { "IronSword" },
		Stats = { Attack = 15, Lifesteal = 0.08 },
		Icon = "rbxassetid://98114411131186",
	},
	GreatAxe = {
		Name = "Great Axe",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Warrior", "Assassin" },
		Cost = 1300,
		From = { "IronSword", "IronSword" },
		Stats = { Attack = 25, Haste = 10 },
		Icon = "rbxassetid://91130136299287",
	},
	MagicStaff = {
		Name = "Magic Staff",
		Tier = "Epic",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 850,
		From = { "SpellTome" },
		Stats = { Magic = 40 },
		Icon = "rbxassetid://139527394234044",
	},
	ArcaneOrb = {
		Name = "Arcane Orb",
		Tier = "Epic",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 1100,
		From = { "SpellTome", "SandGlass" },
		Stats = { Magic = 30, Haste = 15 },
		Icon = "rbxassetid://96495491528318",
	},
	TowerShield = {
		Name = "Tower Shield",
		Tier = "Epic",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 1000,
		From = { "SteelShield", "WarHelmet" },
		Stats = { Armor = 25, Health = 200 },
		Icon = "rbxassetid://97046976532754",
	},
	MoonCloak = {
		Name = "Moon Cloak",
		Tier = "Epic",
		Category = "Defense",
		Classes = { "Mage", "Tank" },
		Cost = 1000,
		From = { "MoonRing", "WarHelmet" },
		Stats = { Resist = 30, Health = 200 },
		Icon = "rbxassetid://104398164311208",
	},
	SwiftBoots = {
		Name = "Swift Boots",
		Tier = "Epic",
		Category = "Speed",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 900,
		From = { "Boots" },
		Boots = true,
		Stats = { MoveSpeed = 3, AttackSpeed = 0.12 },
		Icon = "rbxassetid://136240182495857",
	},
	IronBoots = {
		Name = "Iron Boots",
		Tier = "Epic",
		Category = "Speed",
		Classes = { "Warrior", "Tank" },
		Cost = 1000,
		From = { "Boots" },
		Boots = true,
		Stats = { MoveSpeed = 2.5, Armor = 20 },
		Icon = "rbxassetid://133668513932254",
	},
	SageBoots = {
		Name = "Sage Boots",
		Tier = "Epic",
		Category = "Speed",
		Classes = { "Mage", "Assassin" },
		Cost = 950,
		From = { "Boots" },
		Boots = true,
		Stats = { MoveSpeed = 2.5, Haste = 15 },
		Icon = "rbxassetid://124364107652496",
	},
	WardenBoots = {
		Name = "Warden Boots",
		Tier = "Epic",
		Category = "Speed",
		Classes = { "Warrior", "Mage", "Tank" },
		Cost = 950,
		From = { "Boots" },
		Boots = true,
		Stats = { MoveSpeed = 2.5, Resist = 25 },
		Icon = "rbxassetid://78919707960600",
	},
	HuntersQuiver = {
		Name = "Hunter's Quiver",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Archer" },
		Cost = 1100,
		From = { "HuntingBow", "SwiftGloves" },
		Stats = { Attack = 15, AttackSpeed = 0.2, MoveSpeed = 0.5 },
		Icon = "rbxassetid://127111671855520",
	},
	BrambleMail = {
		Name = "Bramble Mail",
		Tier = "Epic",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 1100,
		From = { "SteelShield", "BitterThorn" },
		Stats = { Armor = 30, Health = 150 },
		Effect = { Kind = "Thorns", Value = 0.25 },
		Text = "Heroes who hit you are wounded: 25% less healing for 3 seconds",
		Icon = "rbxassetid://85232802312831",
	},
	EmberWand = {
		Name = "Ember Wand",
		Tier = "Epic",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 1050,
		From = { "SpellTome", "WarHelmet" },
		Stats = { Magic = 25, Health = 200 },
		Icon = "rbxassetid://118512480367209",
	},
	BitterBlade = {
		Name = "Bitter Blade",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 1000,
		From = { "IronSword", "BitterThorn" },
		Stats = { Attack = 20 },
		Effect = { Kind = "Wound", Value = 0.25 },
		Text = "Your hits wound heroes: 25% less healing for 3 seconds",
		Icon = "rbxassetid://100532090760818",
	},
	RendingPick = {
		Name = "Rending Pick",
		Tier = "Epic",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 1000,
		From = { "IronSword" },
		Stats = { Attack = 15 },
		Effect = { Kind = "ArmorPierce", Value = 0.15 },
		Text = "Your hits ignore 15% of the target's Armor",
		Icon = "rbxassetid://107648747950795",
	},

	Kingsbane = {
		Name = "Kingsbane",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 3000,
		From = { "KnightsBlade", "HuntersFang" },
		Stats = { Attack = 45, AttackSpeed = 0.25, Lifesteal = 0.1 },
		Effect = { Kind = "Kingsbane", Value = 0.25 },
		Text = "Deals 25% more damage to the enemy Master",
		Icon = "rbxassetid://92626898355128",
	},
	EclipseEdge = {
		Name = "Eclipse Edge",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 2900,
		From = { "GreatAxe", "KnightsBlade" },
		Stats = { Attack = 55, Haste = 15 },
		Effect = { Kind = "Eclipse", Value = 0.5 },
		Text = "After an ability, the next M1 hits 50% harder",
		Icon = "rbxassetid://106708873081114",
	},
	Bloodthorn = {
		Name = "Bloodthorn",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior", "Tank", "Archer", "Assassin" },
		Cost = 3000,
		From = { "HuntersFang", "TowerShield" },
		Stats = { Attack = 35, Health = 400, Lifesteal = 0.1 },
		Effect = { Kind = "Bloodthorn", Value = 0.3 },
		Text = "Lifesteal doubles below 30% health",
		Icon = "rbxassetid://90156462163435",
	},
	Stormcrown = {
		Name = "Stormcrown",
		Tier = "Legendary",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 3000,
		From = { "MagicStaff", "ArcaneOrb" },
		Stats = { Magic = 90, Haste = 15 },
		Effect = { Kind = "Stormcrown", Value = 0.15 },
		Text = "Magic damage dealt is 15% higher",
		Icon = "rbxassetid://119905285835396",
	},
	VoidScepter = {
		Name = "Void Scepter",
		Tier = "Legendary",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 2800,
		From = { "MagicStaff", "MoonRing", "SpellTome" },
		Stats = { Magic = 75, Resist = 25 },
		Effect = { Kind = "VoidScepter", Value = 0.35 },
		Text = "Magic damage ignores 35% of the target's Resist",
		Icon = "rbxassetid://71853899576747",
	},
	CrownBulwark = {
		Name = "Crown Bulwark",
		Tier = "Legendary",
		Category = "Defense",
		Classes = { "Tank" },
		Cost = 2800,
		From = { "TowerShield", "MoonCloak" },
		Stats = { Armor = 40, Resist = 40, Health = 350 },
		Effect = { Kind = "CrownBulwark", Value = 20 },
		Text = "+20 Armor and Resist near your own Master",
		Icon = "rbxassetid://127387090758352",
	},
	FarshotLongbow = {
		Name = "Farshot Longbow",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Archer" },
		Cost = 2900,
		From = { "HuntersQuiver", "KnightsBlade" },
		Stats = { Attack = 40, AttackSpeed = 0.2, MoveSpeed = 1 },
		Effect = { Kind = "Farshot", Value = 0.2, From = 10, To = 30 },
		Text = "Up to 20% more damage the farther the target: from 10 studs, all of it from 30",
		Icon = "rbxassetid://87982741118168",
	},
	TempestString = {
		Name = "Tempest String",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Archer" },
		Cost = 2800,
		From = { "HuntersQuiver", "SwiftGloves" },
		Stats = { Attack = 30, AttackSpeed = 0.35 },
		Effect = { Kind = "Tempest", Value = 0.6, Every = 3 },
		Text = "Every third M1 hit on the same target deals 60% more",
		Icon = "rbxassetid://113062874760291",
	},
	ThornwallAegis = {
		Name = "Thornwall Aegis",
		Tier = "Legendary",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 2800,
		From = { "BrambleMail", "TowerShield" },
		Stats = { Armor = 60, Health = 350 },
		Effect = { Kind = "Thorns", Value = 0.4, Reflect = 0.2 },
		Text = "Heroes who hit you are wounded (40% less healing for 3 seconds) and take 20% of their M1 damage back",
		Icon = "rbxassetid://83892402651761",
	},
	IronrootHeart = {
		Name = "Ironroot Heart",
		Tier = "Legendary",
		Category = "Defense",
		Classes = { "Warrior", "Tank" },
		Cost = 2900,
		From = { "TowerShield", "WarHelmet" },
		Stats = { Health = 600, Armor = 20, Resist = 20 },
		Effect = { Kind = "Ironroot", Value = 0.5, Below = 0.3, Time = 3, Cooldown = 60 },
		Text = "Falling below 30% health, you take 50% less damage for 3 seconds (once a minute)",
		Icon = "rbxassetid://104103897880381",
	},
	SoulfireStaff = {
		Name = "Soulfire Staff",
		Tier = "Legendary",
		Category = "Magic",
		Classes = { "Mage" },
		Cost = 2900,
		From = { "EmberWand", "MagicStaff" },
		Stats = { Magic = 70, Health = 300 },
		Effect = { Kind = "Soulfire", Value = 0.2, Below = 0.4 },
		Text = "Magic damage is 20% higher on heroes below 40% health",
		Icon = "rbxassetid://133108180278311",
	},
	ColossusMaul = {
		Name = "Colossus Maul",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior" },
		Cost = 3000,
		From = { "GreatAxe", "TowerShield" },
		Stats = { Attack = 40, Health = 350 },
		Effect = { Kind = "Colossus", Value = 0.02 },
		Text = "Your hits on heroes deal 2% of their max health more",
		Icon = "rbxassetid://121643324960921",
	},
	NightveilDagger = {
		Name = "Nightveil Dagger",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Assassin" },
		Cost = 2900,
		From = { "GreatAxe", "SandGlass" },
		Stats = { Attack = 50, Haste = 15 },
		Effect = { Kind = "Nightveil", Value = 0.3, After = 8 },
		Text = "Your first hit on a hero you have not hit for 8 seconds deals 30% more",
		Icon = "rbxassetid://78787182037688",
	},
	Witherblade = {
		Name = "Witherblade",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 2800,
		From = { "BitterBlade", "KnightsBlade" },
		Stats = { Attack = 35, AttackSpeed = 0.2 },
		Effect = { Kind = "Wound", Value = 0.4 },
		Text = "Your hits wound heroes: 40% less healing for 3 seconds",
		Icon = "rbxassetid://96292967360603",
	},
	Sunderer = {
		Name = "Sunderer",
		Tier = "Legendary",
		Category = "Attack",
		Classes = { "Warrior", "Archer", "Assassin" },
		Cost = 2900,
		From = { "RendingPick", "GreatAxe" },
		Stats = { Attack = 45, Haste = 10 },
		Effect = { Kind = "ArmorPierce", Value = 0.35 },
		Text = "Your hits ignore 35% of the target's Armor",
		Icon = "rbxassetid://91543949753374",
	},
	SpellwardMantle = {
		Name = "Spellward Mantle",
		Tier = "Legendary",
		Category = "Defense",
		Cost = 2500,
		From = { "MoonCloak", "MoonRing" },
		Stats = { Health = 300, Resist = 40, Haste = 10 },
		Effect = { Kind = "Spellward", Value = 200, Refill = 15 },
		Text = "A shield takes the first 200 magic damage; it fills again after 15 seconds without magic damage",
		Icon = "rbxassetid://76723264550981",
	},
}

-- The start of a match: after the draft (Config.Draft) the heroes have `BuyTime` seconds to shop before the fight
-- begins. Until then nobody can attack, no minions come and no passive coins are paid; the match clock starts with the
-- fight. A match without a queue record (Studio) waits `WaitForPlayer` seconds for its first player.
Config.Match = {
	BuyTime = 15,
	WaitForPlayer = 20,
}

-- The Sun Crown, the objective on the plateau in the middle: it appears `FirstAt` seconds into the fight and floats
-- `Float` studs over the plateau's top. The first hero to touch it (within `Reach` studs) takes it at once. While a
-- hero carries it he deals `Carrier` more and the rest of his team `Damage` more, wherever they are. It fades `Lasts`
-- seconds after it was first taken, and the next one comes `Gap` seconds later. A carrier who dies drops it where he
-- fell, for anyone to take. Whenever it is taken, a banner (KillFeed) shows who took it, with `Texts` as seen by its
-- taker, his team and his enemies, and another when it fades; while a team has it, its players see the time it has
-- left (Hud).
Config.Crown = {
	FirstAt = 0,
	Float = 4,
	Reach = 4,
	Damage = 0.08,
	Carrier = 0.15,
	Lasts = 90,
	Gap = 60,
	Texts = {
		Own = "YOU HAVE THE SUN CROWN",
		Ally = "YOUR TEAM HAS THE SUN CROWN",
		Enemy = "THE ENEMY HAS THE SUN CROWN",
		Fades = "THE SUN CROWN FADES",
	},
}

-- The calls on a hero's death (ProgressService, shown by KillFeed). One call per kill, the first that fits: FirstBlood
-- (the match's first kill), Quad, Triple and Double (the killer's kills each within `MultiWindow` seconds of the one
-- before; four is a whole team alone), Shutdown (the victim had `ShutdownStreak` kills or more without dying), the
-- killer's streak of kills without dying (`Streaks`, the highest reached), else Slain. A hero killed by a minion or a
-- Master is "Died". When a death leaves the victim's whole team down, Wipeout follows as a second call, after a Quad
-- as well. `Texts` is what the screen shows, `Tiers` how big (1 the plainest, 4 the biggest).
Config.Kills = {
	MultiWindow = 10,
	ShutdownStreak = 3,
	Streaks = {
		{ kills = 3, call = "OnFire" },
		{ kills = 5, call = "Unstoppable" },
		{ kills = 7, call = "Legend" },
	},
	Texts = {
		FirstBlood = "FIRST BLOOD!",
		Shutdown = "SHUTDOWN!",
		Wipeout = "WIPEOUT!",
		Quad = "QUAD KILL!",
		Triple = "TRIPLE KILL!",
		Double = "DOUBLE KILL!",
		OnFire = "ON FIRE!",
		Unstoppable = "UNSTOPPABLE!",
		Legend = "LEGEND!",
		Slain = "ENEMY SLAIN",
		Died = "SLAIN",
		Own = "YOU HAVE BEEN SLAIN",
	},
	Tiers = {
		Slain = 1,
		Died = 1,
		Own = 1,
		FirstBlood = 2,
		Double = 2,
		OnFire = 2,
		Shutdown = 3,
		Triple = 3,
		Unstoppable = 3,
		Wipeout = 4,
		Quad = 4,
		Legend = 4,
	},
}

-- Levels, as in League of Legends: when an enemy dies, the heroes of the other team within `Share` studs (and its
-- killer, wherever he is) share its XP evenly. `Steps` is the XP from each level to the next. Every level adds
-- `Health` and `Damage` of the hero's base, and a point to spend on raising M2, E or R one rank with the keys 1, 2 and 3
-- (`Upgrades`); the hero starts with one point at level 1. The combo (M1) and the dash are always there; M2, E and R
-- start unlearned (rank 0) and are learned with their first rank. A rank past the first adds `RankDamage` to its
-- ability's damage and takes `RankCooldown` off its cooldown; rank `n` of an ability needs the hero level
-- `Needs[key][n]`: as in League, a basic ability's rank is at most half the level rounded up, and the ultimate comes
-- at a third of `MaxLevel`. `MaxLevel` is the number of ranks, so every rank is full exactly at the top level.
Config.Progress = {
	MaxLevel = 12,
	Steps = { 120, 160, 200, 240, 280, 320, 360, 400, 440, 480, 520 },
	Share = 36,
	MinionXp = { Melee = 40, Spitter = 30 },
	HeroXp = 140,
	HeroXpPerLevel = 25,
	-- Damage on a hero counts for his kill this long.
	KillCredit = 10,
	Health = 0.08,
	Damage = 0.04,
	StartPoints = 1,
	MaxRank = 4,
	RankDamage = 0.2,
	RankCooldown = 0.1,
	Upgrades = { "M2", "E", "R" },
	Needs = {
		M2 = { 1, 3, 5, 7 },
		E = { 1, 3, 5, 7 },
		R = { 4, 6, 8, 10 },
	},
}

-- The team minions (concept G, rock creatures with crystals): a wave leaves both of a team's doorways on its own half every
-- `WaveInterval` seconds, the first `FirstWave` seconds after the fight began, and marches on the other team's Master,
-- fighting every enemy hero it meets on the way; minions never fight each other. Only the last hit earns the bounty. Ranges are from edge to edge, speeds in
-- studs a second (a hero walks 16).
Config.Minions = {
	FirstWave = 10,
	WaveInterval = 30,
	-- Per doorway and wave, in marching order: two doorways a team, so twelve minions a wave in all.
	Wave = { "Spitter", "Spitter", "Spitter" },
	MaxPerTeam = 15,
	-- The lanes pass the east and west gates this far from the centre, between the cover arcs and the pillars.
	LaneRadius = 82,
	Radius = 1.8,
	Height = 5.2,
	-- A minion turns on an enemy hero or Master this close, and gives up the chase this far from where it left its path.
	Acquire = 18,
	Leash = 30,
	-- An enemy hero who attacks a hero this close to a minion becomes its target, for this many seconds.
	CallForHelp = 18,
	CallTime = 3,
	-- Minions do this share of their damage to a Master.
	VsMaster = 0.5,
	-- Every hop lands on the sand with the footsteps of this pack's sounds (Shared.PackSounds), this loud: softer than
	-- a hero's step, as there are many of them.
	Steps = { Pack = "GreataxeBerserker", Volume = 0.25 },
	-- Each team's minions' painted portrait, the killer's in the kill feed when a minion fells a hero (made as the
	-- heroes' are, Art/Portraits: the red one from a Play screenshot of a red minion, the blue one that recoloured
	-- with Tools/team_recolor.py --no-skin); `Face` is the square round its body and crystals.
	Portraits = {
		Red = { Image = "rbxassetid://82001793757256", Face = { 150, 40, 880 } },
		Blue = { Image = "rbxassetid://121972646515298", Face = { 150, 40, 880 } },
	},
	-- A Melee minion's bite is physical damage, a Spitter's spit magic (Config.Items: Armor and Resist).
	Kinds = {
		Melee = { Health = 450, Damage = 12, Interval = 1.25, Range = 1.2, Speed = 11, Bounty = 21, Magic = false },
		Spitter = {
			Health = 280,
			Damage = 22,
			Interval = 1.6,
			Range = 18,
			Speed = 11,
			Bounty = 14,
			SpitSpeed = 45,
			Magic = true,
		},
	},
}

-- The heroes. Each looks like a Roblox R15 avatar put together from catalog items (Docs/Third_Party.md): a classic
-- shirt and pants, hair, a face accessory, a hat or hood and a cape when he has them (`HatAccessory`, `BackAccessory`),
-- and one skin colour on every body part. Faces come from the catalog too: R15
-- heads are dynamic heads, on which a Decal face does not render. Every player plays the hero he picked in the draft
-- (`DefaultHero` when there is none), and comes back on a spawn pad after dying (Config.Respawn).
--
-- A hero moves and attacks with the motions of a bought animation pack (`Pack`, a folder in ReplicatedStorage with the
-- pack's player and rig, Docs/Third_Party.md). The pack's rig has the R15 proportions of BodyTypeScale 0 and
-- ProportionScale 0, so the hero's body has them too, and wears the pack's weapons (`Weapons`, from the rig's
-- Components). `Motions` names the pack's clips the hero moves with; `Death` is the pack's own fall, which carries his
-- weapons down with him and is held once it ends.
--
-- The kit: M1 a combo of hits, M2, E and R abilities. Times are seconds into the motion at speed 1 (`Speed` plays it
-- faster), ranges in studs from the hero to the target's edge, angles the cone's full width in degrees. Every hit
-- lands at its time in the motion, on the server. For every hero, every swing, shot and throw goes where the crosshair
-- points, upwards and downwards as well (owner, 2026-10-29); a leap lands on the spot aimed at, a dash keeps to the
-- ground. Indicators (design 06): "Arrow" (a skillshot), "Zone" (a range
-- round the hero and the spot aimed at), "Cone", "Ring" (what a slam round him reaches). A combo hit with a `ProjectileSpeed` is a shot instead of a swing,
-- and its `Recover` the seconds after its hit before the next. A "Throw" lets go at its `Release` (or each of its
-- `Releases`), `Count` projectiles fanned over `Spread` degrees; each stops at the first enemy in its way, or with
-- `Pierce` strikes everyone it passes once. A "Dash" without `Damage` only moves him, and `Trail = false` leaves out
-- the shadow along its way; its `Shot` is a projectile he lets go on the way, at `Release` seconds into its motion.
-- An "Ascend" plays its `Motion` and then its `Then`, lifting him off the ground meanwhile (HeroKit.lift), and lets
-- one projectile go at `Release`, `OrbScale` times his usual orb, which bursts over `Blast` studs where it stops.
-- `Projectile` is how his projectiles look in flight: a component of his pack, `Turn`ed to fly point first.
--
-- In the armory his class's build is recommended (Config.ClassBuilds), or his own `Build` when he has one.
--
-- In the menu (the lobby): `Role` is his class (Config.Classes), `Description` his line on the cards. A `Starter`
-- hero is every player's from the start; one with a `Price` is sold for coins in the heroes' shop (Shared.HeroShop),
-- and an `Exclusive` one only comes from the season pass (Config.Pass) and is never sold. `Showcase` is how he stands
-- on the menu's podium, in 3D in the hall (owner, 2026-10-28): the clip he holds there, the degrees he stands `Turn`ed
-- when that clip looks aside, and the colour of his aura.
-- Every hero gets one, a pose from his own pack as Shadowren's weapon pose.
Config.Heroes = {
	Shadowren = {
		Role = "Assassin",
		Description = "Strikes from the shadows and vanishes.",
		Starter = true,
		Showcase = { Motion = "RA-SHD-076", Aura = Color3.fromRGB(146, 64, 236) },
		Health = 900,
		-- His kit deals physical damage, growing with Attack (each key's `Ratio` of it, Config.Items).
		Scales = "Attack",
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
		-- The ability bar's icons per key (Art/Icons/Shadowren, each a GenerateImage drawing on green in
		-- Art/Icons/keyed/Shadowren, keyed by Tools/key_icons.py --glow).
		Icons = {
			M1 = "rbxassetid://76266948792174",
			M2 = "rbxassetid://113004879139290",
			E = "rbxassetid://73253955950887",
			R = "rbxassetid://84723458776390",
			Dash = "rbxassetid://72946588578679",
		},
		Pack = "ShadowDuelist",
		Weapons = { "DaggerRight", "DaggerLeft" },
		-- His thrown dagger in flight (HeroControls): the pack's left dagger, spinning end over end in shadow.
		Projectile = {
			Component = "DaggerLeft",
			Spin = 22,
			Turn = CFrame.Angles(-math.pi / 2, 0, 0),
			Trail = { Color3.fromRGB(120, 60, 200), Color3.fromRGB(20, 10, 40) },
			Glow = Color3.fromRGB(120, 60, 200),
			Burst = true,
		},
		Motions = {
			Idle = "RA-SHD-015",
			Run = "RA-SHD-005",
			RunLeft = "RA-SHD-006",
			RunRight = "RA-SHD-007",
			Back = "RA-SHD-002",
			Takeoff = "RA-SHD-011",
			Air = "RA-SHD-012",
			Land = "RA-SHD-013",
			Death = "RA-SHD-033",
		},
		Kit = {
			M1 = {
				Kind = "Combo",
				Speed = 1.25,
				Ratio = 0.6,
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
				Ratio = 1,
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
				Ratio = 1.1,
			},
			-- Fast sweeps in a cone ahead of him.
			R = {
				Kind = "Flurry",
				Motion = "RA-SHD-071",
				Indicator = "Cone",
				Cooldown = 40,
				Hits = { 0.27, 0.43, 0.60, 0.97, 1.57, 2.13 },
				-- He comes down from his leap and strikes the ground, in a shockwave of shadow: that hit, the kit's
				-- strongest, deals SlamDamage (with SlamRatio) all round him, SlamRadius studs (the shockwave's shade);
				-- the sweeps before it deal Damage in the cone where he faces at each.
				Slam = 2.13,
				SlamRadius = 12,
				SlamDamage = 120,
				SlamRatio = 1,
				Damage = 24,
				Ratio = 0.2,
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
				Ratio = 0.3,
				-- He moves from Start to Move seconds after the press, and the lunge fades out at Stop.
				Start = 0.04,
				Move = 0.34,
				Stop = 0.55,
			},
		},
	},
	Rowan = {
		Role = "Archer",
		Description = "Rains arrows on his foes from afar.",
		Starter = true,
		Showcase = { Motion = "RA-RNG-014", Aura = Color3.fromRGB(110, 200, 120) },
		Health = 760,
		Scales = "Attack",
		Look = {
			Shirt = 6985101011,
			Pants = 102410804434863,
			HairAccessory = "136456876434698",
			-- An animated head with a cool, striking anime stare.
			Head = 71608108882725,
			Mood = 14618207727,
			Skin = Color3.fromRGB(232, 196, 168),
		},
		Portrait = { Image = "rbxassetid://96167601016805", Face = { 200, 40, 620 } },
		Icons = {
			M1 = "rbxassetid://74397042098977",
			M2 = "rbxassetid://94119815193611",
			E = "rbxassetid://113948018234539",
			R = "rbxassetid://117092938457390",
			Dash = "rbxassetid://104572602673907",
		},
		Pack = "Ranger",
		-- The bow and the arrow are skinned to the pack's bones, the quiver is rigid on his back (Shared.Motion).
		Weapons = { "Bow", "Arrow", "Quiver" },
		-- His arrows in flight (HeroControls): the pack's arrow, point first (its +X), with a streak of leaf-green wind
		-- behind it and a soft green light, as on his icons.
		Projectile = {
			Component = "Arrow",
			Turn = CFrame.Angles(0, math.pi / 2, 0),
			Trail = { Color3.fromRGB(176, 236, 92), Color3.fromRGB(84, 160, 42) },
			TrailHalf = 0.18,
			TrailFade = 0.25,
			Glow = Color3.fromRGB(150, 230, 90),
		},
		Motions = {
			Idle = "RA-RNG-015",
			Run = "RA-RNG-005",
			RunLeft = "RA-RNG-006",
			RunRight = "RA-RNG-007",
			Back = "RA-RNG-002",
			Takeoff = "RA-RNG-011",
			Air = "RA-RNG-012",
			Land = "RA-RNG-013",
			Death = "RA-RNG-030",
		},
		-- The times below are when the pack's clips let the arrow go (its opacity), seconds at speed 1.
		Kit = {
			-- One shot per click, at the first enemy in its way. About three quarters of Shadowren's combo damage per
			-- second (48 against 67), as the price of hitting from 34 studs instead of 6.
			M1 = {
				Kind = "Combo",
				Speed = 0.8,
				Ratio = 0.5,
				Reset = 1.5,
				Hits = {
					{ Motion = "RA-RNG-036", Hit = 0.40, Damage = 30, Range = 34, ProjectileSpeed = 110, Width = 1.5 },
				},
			},
			-- A drawn-out heavy shot that goes through everyone in its line.
			M2 = {
				Kind = "Throw",
				Motion = "RA-RNG-040",
				Indicator = "Arrow",
				Cooldown = 8,
				Release = 0.867,
				ProjectileSpeed = 130,
				Range = 45,
				Width = 2,
				Pierce = true,
				Damage = 120,
				Ratio = 1.2,
			},
			-- Five arrows in quick turn, each where he aims as it goes. All five a little more than Shadowren's dagger
			-- (130 against 110), as they must all hit over more than a second.
			E = {
				Kind = "Throw",
				Motion = "RA-RNG-041",
				Indicator = "Arrow",
				Cooldown = 10,
				Releases = { 0.300, 0.633, 0.900, 1.100, 1.333 },
				ProjectileSpeed = 110,
				Range = 38,
				Width = 1.5,
				Damage = 26,
				Ratio = 0.25,
			},
			-- A somersault, and at its top a fan of arrows that each go through everyone they meet; each enemy is
			-- struck once, by the first arrow of the fan to reach him. Less on one enemy than Shadowren's ultimate
			-- (160 against 240), as it reaches many from afar.
			R = {
				Kind = "Throw",
				Motion = "RA-RNG-048",
				Indicator = "Cone",
				Cooldown = 40,
				Release = 0.967,
				Count = 7,
				Spread = 60,
				ProjectileSpeed = 100,
				Range = 40,
				Width = 2,
				Pierce = true,
				Damage = 160,
				Ratio = 1.2,
			},
			-- A quick hop to where he aims (Shift), shooting an arrow that way in the air.
			Dash = {
				Kind = "Dash",
				Motion = "RA-RNG-058",
				Speed = 1.2,
				Cooldown = 6,
				Range = 14,
				Width = 3,
				Trail = false,
				Start = 0.08,
				Move = 0.55,
				Stop = 0.7,
				Shot = { Release = 0.30, Damage = 35, Ratio = 0.4, Range = 34, ProjectileSpeed = 110, Width = 1.5 },
			},
		},
	},
	Mavorak = {
		Role = "Mage",
		Description = "Hurls dark magic from his staff.",
		Starter = true,
		-- His ready stance looks aside, so he stands turned until his face nearly meets the camera, with his raised hand
		-- still clear of it.
		Showcase = { Motion = "RA-ELM-017", Turn = -28, Aura = Color3.fromRGB(150, 70, 230) },
		Health = 720,
		-- His kit deals magic damage, growing with Magic (Config.Items).
		Scales = "Magic",
		Look = {
			Shirt = 2715706272,
			Pants = 2715707499,
			-- Long black hair falling from under his hood, as on his portrait.
			HairAccessory = "15796404798",
			HatAccessory = "127306972712760",
			BackAccessory = "13374923791",
			-- Rowan's skin under an animated head with purple cyber eyes in shadow.
			Head = 80336341746719,
			Mood = 14618207727,
			Skin = Color3.fromRGB(232, 196, 168),
		},
		Portrait = { Image = "rbxassetid://82768668500650", Face = { 235, 40, 620 } },
		-- The ability bar's icons per key (Art/Icons/Mavorak, each a GenerateImage drawing on green in
		-- Art/Icons/keyed/Mavorak, keyed by Tools/key_icons.py --glow).
		Icons = {
			M1 = "rbxassetid://131342780006544",
			M2 = "rbxassetid://95895466142267",
			E = "rbxassetid://126999387085945",
			R = "rbxassetid://113799512510557",
			Dash = "rbxassetid://134137025780012",
		},
		Pack = "Elementalist",
		-- The staff hangs from his right hand (Tools/keyframe_pack.py).
		Weapons = { "Staff" },
		-- His spells in flight (HeroControls): a dark vortex.
		Projectile = {
			-- No ball but a dark vortex (owner 2026-10-30): two near-black vortices with violet arms turning against
			-- each other in crackling energy, about `Size` times 3.2 studs across, leaving dark smoke and violet
			-- sparks behind (HeroControls' projectileModel).
			Orb = { Size = 1.1, Color = Color3.fromRGB(150, 40, 255), Swirl = true },
			Trail = { Color3.fromRGB(140, 40, 230), Color3.fromRGB(10, 0, 20) },
			TrailHalf = 0.4,
			Glow = Color3.fromRGB(120, 30, 220),
			Burst = true,
		},
		Motions = {
			Idle = "RA-ELM-017",
			Run = "RA-ELM-005",
			RunLeft = "RA-ELM-006",
			RunRight = "RA-ELM-007",
			Back = "RA-ELM-002",
			Takeoff = "RA-ELM-011",
			Air = "RA-ELM-012",
			Land = "RA-ELM-013",
			Death = "RA-ELM-028",
		},
		-- The times are where the staff or a hand thrusts forward, or the staff strikes the ground, in the pack's
		-- clips (measured on the hero; the pack's sound markers fall there too).
		Kit = {
			-- Three orbs in turn, each at the first enemy in its way: a staff swing, a push of both hands and a
			-- sweeping cast, the last the hardest. A little under Rowan's damage a second (46 against 48), from a little
			-- less far: a mage's strength is in his spells (owner, 2026-10-30).
			--
			-- His Ratios are lower than the others' as Magic comes about twice as fast from items as Attack (Spell Tome
			-- 20 against Iron Sword's 10, Stormcrown 90 against Eclipse Edge's 55), so he grows as fast as they do.
			M1 = {
				Kind = "Combo",
				Speed = 1.2,
				Ratio = 0.35,
				Reset = 1.5,
				Hits = {
					{
						Motion = "RA-ELM-020",
						Hit = 0.30,
						Recover = 0.25,
						Damage = 26,
						Range = 30,
						ProjectileSpeed = 90,
						Width = 2,
					},
					{
						Motion = "RA-ELM-034",
						Hit = 0.37,
						Recover = 0.30,
						Damage = 30,
						Range = 30,
						ProjectileSpeed = 90,
						Width = 2,
					},
					{
						Motion = "RA-ELM-041",
						Hit = 0.45,
						Recover = 0.40,
						Damage = 40,
						Range = 30,
						ProjectileSpeed = 90,
						Width = 2,
					},
				},
			},
			-- He swings his staff up and strikes it into the ground: a shockwave of dark magic strikes everyone
			-- round him at once (owner, 2026-10-30), SlamRadius studs, as far as the shockwave's shade (Range).
			M2 = {
				Kind = "Flurry",
				Motion = "RA-ELM-053",
				Indicator = "Ring",
				Cooldown = 9,
				Hits = { 0.75 },
				Slam = 0.75,
				SlamRadius = 12,
				SlamDamage = 120,
				SlamRatio = 0.8,
				Damage = 120,
				Ratio = 0.8,
				Range = 12,
				Angle = 360,
			},
			-- Three orbs fanned out ahead of him: strong on a group, mostly one of them on a single foe.
			E = {
				Kind = "Throw",
				Motion = "RA-ELM-062",
				Indicator = "Cone",
				Cooldown = 10,
				Release = 0.53,
				Count = 3,
				Spread = 30,
				ProjectileSpeed = 90,
				Range = 34,
				Width = 2,
				Damage = 80,
				Ratio = 0.5,
			},
			-- He rises into the air (Motion), gathers a great orb over his head while he hangs there (Then) and
			-- hurls it where he aims (owner, 2026-10-30): it bursts at the first enemy, wall or floor it meets, or at
			-- the end of its range, striking everyone within Blast studs of it.
			R = {
				Kind = "Ascend",
				Motion = "RA-ELM-050",
				Then = "RA-ELM-060",
				Indicator = "Arrow",
				Cooldown = 40,
				-- He rises Rise studs from RiseStart to RiseEnd seconds after the cast, comes down from Fall and
				-- stands again at Land; the orb leaves his hands at Release, as he flings his arms open (Then's 1.70
				-- seconds, its fastest move, owner 2026-10-30).
				Rise = 6,
				RiseStart = 0.1,
				RiseEnd = 1.1,
				Release = 3.0,
				Fall = 3.95,
				Land = 4.35,
				ProjectileSpeed = 70,
				Range = 45,
				Width = 4,
				-- How much larger than his other orbs it is.
				OrbScale = 4,
				Blast = 10,
				-- The game's hardest blow, to everyone in the blast, as he hangs still for three seconds before it
				-- and anyone can step out of its way (owner, 2026-10-30): more than Shadowren's 240 on one foe.
				Damage = 320,
				Ratio = 1,
			},
			-- A quick blink to where he aims (Shift), in a trail of shadow, letting one orb go that way as his hands
			-- rise (owner 2026-10-30); as much as Rowan's arrow in his hop.
			Dash = {
				Kind = "Dash",
				Motion = "RA-ELM-050",
				Speed = 1.5,
				Cooldown = 6,
				Range = 14,
				Width = 3,
				Start = 0.05,
				Move = 0.3,
				Stop = 0.5,
				Shot = { Release = 0.30, Damage = 35, Ratio = 0.25, Range = 30, ProjectileSpeed = 90, Width = 2 },
			},
		},
	},
}
Config.DefaultHero = "Shadowren"

-- A dead hero waits `Base` seconds and `PerLevel` more for every level past the first, so deaths cost more as the
-- match goes on; and `Streak` more for each time he died within `StreakWindow` seconds of his last death, at most
-- `StreakMax` more. Surviving StreakWindow seconds clears it.
-- A hero on one of his own team's spawn pads heals `Heal` of his health a second, in ticks of `Tick` seconds, unless
-- an enemy (a hero, a minion or a Master) hit him in the last `CombatPause` seconds, so he cannot camp there and heal
-- through a fight (owner, 2026-10-30; design 03).
Config.Pads = {
	Heal = 0.10,
	Tick = 1,
	CombatPause = 5,
}

Config.Respawn = {
	Base = 6,
	PerLevel = 2.5,
	StreakWindow = 60,
	Streak = 3,
	StreakMax = 9,
}

-- Bots fill both teams up to `TeamSize` heroes, each picking in the draft the first hero of `Lineup` his team has
-- not picked yet (players' picks count too), else `Hero` (a player who leaves is played on by a bot with his hero),
-- each with its own hero's kit. A bot goes after an enemy hero anywhere in the
-- arena: the nearest one nobody of its team fights yet (no other bot chose him and no player of its team is within
-- `Taken` studs of him), and only when every one is taken the nearest of them, to help. With no enemy hero alive it
-- fights the nearest other enemy within `Sight` studs, else the nearest enemy minion, else waits at its lane's gate. It
-- plays as a person would, not
-- perfectly: after an ability, and on a new target, it waits `Reaction` seconds (between Min and Max) before its next
-- ability; between its swings it rests up to `Rest` seconds; what it shoots or throws leads its target by `Lead` of
-- the way and flies up to `Miss` studs beside that, near or far (owner, 2026-10-30: the archers missed everything with
-- 15 degrees and 0.2), kept on him till it lets go as a player keeps his crosshair on him, its leaps and dashes land up
-- to `Stray` studs from where it aimed. An
-- archer (a hero whose combo shoots, as Rowan) keeps `Keep` studs from an enemy hero, hops away from one within
-- `Flee`, looses his fan of arrows at a hero within `Fan` of its range, and into minions when 3 stand within `Crowd`
-- studs of the one he aims at. Only while `Buys` is on does a bot shop: at the armory it buys its hero's build in
-- `Builds`, or else the one the armory recommends him (Config.ClassBuilds), in order, its parts first while the whole
-- is too dear, and it drinks a potion below `PotionAt` of its health.
Config.Bots = {
	TeamSize = 4,
	Hero = "Shadowren",
	-- Two Shadowren, a Rowan and a Mavorak a team, whichever of them a player picks (owner, 2026-10-30); Mavorak last,
	-- so a bot picking before the player leaves him free.
	Lineup = { "Shadowren", "Rowan", "Shadowren", "Mavorak" },
	Sight = 25,
	Taken = 20,
	Reaction = { Min = 1.3, Max = 2.6 },
	Rest = 0.9,
	Lead = 0.85,
	Miss = 2,
	Stray = 6,
	Keep = 18,
	Flee = 8,
	Fan = 0.6,
	Crowd = 8,
	Buys = false,
	Builds = {
		Shadowren = {
			"IronSword",
			"HealthPotion",
			"HealthPotion",
			"Boots",
			"HuntersFang",
			"KnightsBlade",
			"Kingsbane",
			"SwiftBoots",
			"EclipseEdge",
			"Bloodthorn",
		},
	},
	PotionAt = 0.45,
}

-- Every hero walks `WalkSpeed`, and `AttackWalkSpeed` while a motion of his kit plays. Commands from a client for a
-- hit further than `Slack` studs beyond the server's ranges are ignored.
Config.Combat = {
	WalkSpeed = 16,
	AttackWalkSpeed = 5,
	Slack = 4,
	-- The sounds of every hit, for everyone on everything (HitFeedback), in turn, the first again after
	-- `HitSeriesReset` seconds without a hit: the Ranger pack's three body impacts, for every hero (owner,
	-- 2026-10-30; the Shadow Duelist pack holds the same ones). The other candidates stay in UiSound: "HitBody1",
	-- "HitBody2", "HitBody3" (Mixkit's three punches to the body), "HitPunch" (the single strong punch), "Hit", "HitLow",
	-- "HitRaw" (Tools/hit_sound.py), "HitGolf", "HitHeart".
	HitSounds = { "BodyImpact1", "BodyImpact2", "BodyImpact3" },
	HitSeriesReset = 1,
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

-- The heroes' classes, in the order of the menu's and the armory's filters.
Config.Classes = { "Warrior", "Mage", "Archer", "Tank", "Assassin" }

-- Each class's build in buying order (Config.Items), as League's recommended items: the armory's Recommended tab shows
-- the build of the hero's class, or another class's when its filter is chosen. A hero's own `Build` (Config.Heroes)
-- goes before his class's.
Config.ClassBuilds = {
	Warrior = {
		"IronSword",
		"HealthPotion",
		"Boots",
		"GreatAxe",
		"IronBoots",
		"TowerShield",
		"ColossusMaul",
		"Bloodthorn",
		"EclipseEdge",
	},
	Mage = {
		"SpellTome",
		"HealthPotion",
		"Boots",
		"MagicStaff",
		"SageBoots",
		"Stormcrown",
		"EmberWand",
		"SoulfireStaff",
		"VoidScepter",
	},
	Archer = {
		"HuntingBow",
		"HealthPotion",
		"SwiftGloves",
		"HuntersQuiver",
		"Boots",
		"SwiftBoots",
		"KnightsBlade",
		"FarshotLongbow",
		"TempestString",
		"Kingsbane",
	},
	Tank = {
		"WarHelmet",
		"HealthPotion",
		"Boots",
		"BitterThorn",
		"BrambleMail",
		"IronBoots",
		"ThornwallAegis",
		"IronrootHeart",
		"CrownBulwark",
	},
	Assassin = {
		"IronSword",
		"HealthPotion",
		"Boots",
		"GreatAxe",
		"SandGlass",
		"SwiftBoots",
		"NightveilDagger",
		"EclipseEdge",
		"Kingsbane",
	},
}

-- The experience's places (Shared.Places): the lobby with the menu, where players come in and queue, and the match
-- place, whose reserved servers play one match each. Both carry the same code. They may be one place: its public
-- servers are then the lobby and its reserved servers the matches.
Config.Places = {
	Lobby = 78170556317933 :: number?,
	Match = 78170556317933,
}

-- The season, for the ranks and the pass: its number and when it ends (UTC).
Config.Season = {
	Number = 1,
	Ends = { year = 2026, month = 12, day = 31, hour = 23, min = 59, sec = 0 },
}

-- A player's account (Shared.Account): what he starts with, and the account XP each level asks, `First` for the first
-- and `PerLevel` more for every one after it up to level `Plateau`, the same after it; there is no top level.
Config.Account = {
	StartCoins = 500,
	First = 300,
	PerLevel = 50,
	Plateau = 30,
}

-- Ranked (Shared.Ranks), as League of Legends (Docs/League_Reference.md): the tiers in order, the first `Divided` with
-- divisions IV to I of `DivisionLp` LP each; Legend above them with open LP, and Sunborn and Master the top `Top` of the
-- ladder among Legend's players. A player's first `Placements` matches only move his hidden rating (Elo, `K`, twice as
-- fast while placing, starting at `StartRating`); after them he is placed at the rank of his rating, at most at
-- `PlaceCap` (tier and division). A win then gives `Win` LP and a loss takes `Loss`, up to `Swing` more or less by how
-- far his rating stands above or below his rank's (one LP of swing per `SwingPer` rating), so at an even win rate he
-- stays where he is and only a better player climbs. LP over 100 rolls into the next division, LP under 0 into the one
-- below; after reaching a new tier he cannot drop out of it for `Shield` matches, and dropping out of a tier puts him
-- at one of `DemoteLp` (low, middle, high) by whether his rating stands `DemoteBand` below, near or above his new rank.
-- Ranked opens at account level `Level` after `QuickPlays` other matches, and once the game has `Heroes` heroes for
-- those who own that many. A new season (Config.Season, a year as League's) pays the `Coins` of the highest of
-- `SeasonRewards` his best tier reached, lowers his rank `Reset` divisions and asks his placements again, which then
-- place him no higher than that.
-- Each tier's `Badge` is its shield (one GenerateImage sheet in design 14's look, Art/Icons/concepts/rank_badges_sheet.jpg;
-- each shield drawn again alone on magenta, Art/Icons/keyed/Ranks, and keyed by Tools/key_icons.py into Art/Icons/Ranks).
Config.Ranked = {
	Tiers = {
		{ Name = "Recruit", Badge = "rbxassetid://108783564091585" },
		{ Name = "Squire", Badge = "rbxassetid://92445097392397" },
		{ Name = "Gladiator", Badge = "rbxassetid://93313899570806" },
		{ Name = "Knight", Badge = "rbxassetid://132364992531557" },
		{ Name = "Champion", Badge = "rbxassetid://77862907021114" },
		{ Name = "Warlord", Badge = "rbxassetid://93747066981753" },
		{ Name = "Titan", Badge = "rbxassetid://94796196631740" },
		{ Name = "Legend", Badge = "rbxassetid://127667467620464" },
		{ Name = "Sunborn", Badge = "rbxassetid://100216658200527", Top = 100 },
		{ Name = "Master", Badge = "rbxassetid://112182969756625", Top = 10 },
	},
	Divided = 7,
	DivisionLp = 100,
	Win = 20,
	Loss = 20,
	Swing = 10,
	SwingPer = 20,
	K = 32,
	StartRating = 1000,
	Placements = 5,
	PlaceCap = { Tier = 7, Division = 3 },
	Shield = 10,
	DemoteLp = { 25, 50, 75 },
	DemoteBand = 100,
	Level = 15,
	QuickPlays = 10,
	Heroes = 8,
	Reset = 4,
	SeasonRewards = {
		{ Tier = 3, Coins = 1000 },
		{ Tier = 4, Coins = 2000 },
		{ Tier = 5, Coins = 3500 },
	},
}

-- The season pass (design 13, Shared.Pass): `Levels` levels of `XpPerLevel` pass XP each. Every level has a reward on
-- the free track and one on the premium track: coins, or a boost that doubles the account and pass XP of the matches
-- played in the next `Boost` seconds. The premium track's last reward is the season's exclusive hero (`Hero`, nil until
-- he is built); the premium track opens later, for Robux.
Config.Pass = {
	Levels = 30,
	XpPerLevel = 500,
	Boost = 3600,
	Hero = nil :: string?,
	Premium = false,
}

-- What a match earns every player in it (MatchEnd): coins, account XP and pass XP for a win or a loss, more coins for a
-- better grade (`GradeCoins` by its letter), and twice the XP while a pass boost runs. The grade (S+ to D-, as
-- League's) comes from a match score: kills, assists
-- and deaths count `Kill`, `Assist` and `Death`, the share of his team's damage to heroes `Damage`, to the enemy Master
-- `Master`, and every Sun Crown taken `Crown`; `Grades` are the least score of each grade. The best score of the winners
-- is the MVP.
Config.Rewards = {
	Coins = { Win = 100, Loss = 50 },
	AccountXp = { Win = 200, Loss = 120 },
	PassXp = { Win = 150, Loss = 100 },
	GradeCoins = { S = 40, A = 25, B = 15, C = 5, D = 0 },
	Score = { Kill = 3, Assist = 1.5, Death = -1.5, Damage = 20, Master = 15, Crown = 3 },
	Grades = {
		{ "S+", 22 },
		{ "S", 19 },
		{ "S-", 16 },
		{ "A+", 14 },
		{ "A", 12 },
		{ "A-", 10 },
		{ "B+", 8.7 },
		{ "B", 7.3 },
		{ "B-", 6 },
		{ "C+", 4.7 },
		{ "C", 3.3 },
		{ "C-", 2 },
		{ "D+", 1 },
		{ "D", 0 },
		{ "D-", -math.huge },
	},
}

-- Hero mastery (Shared.Mastery), as League's champion mastery (Docs/League_Reference.md): every match with a hero
-- earns him the `Points` of the player's grade letter, `Sign` more or less for its plus or minus, and `Win` more for a
-- win. A level asks the points of `Steps` (to level 2, 3, ...; the last for every level after), and from level
-- `MarksFrom` also Marks of Mastery: one per level, `MarksTop` from level `Title` on. Marks come from the season's
-- milestones (`Track`: so many games at a grade or better earn so many marks), then from `Bonus` again and again; the
-- milestones and unused marks start over each season, the points and levels stay. There is no top level: the crest
-- (Assets.MasteryCrests) grows up to `Title`, where the hero's title unlocks ("Master of <hero>"), and shows the number
-- after it. A match lasts about half of League's game, so a level-10 hero takes about as many hours.
Config.Mastery = {
	Points = { S = 600, A = 500, B = 400, C = 300, D = 200 },
	Sign = 30,
	Win = 100,
	Steps = { 1800, 4200, 6600, 9000, 10000, 11000 },
	MarksFrom = 5,
	MarksTop = 2,
	Title = 10,
	Track = {
		{ Grade = "A-", Games = 1, Marks = 1 },
		{ Grade = "A-", Games = 1, Marks = 1 },
		{ Grade = "S-", Games = 1, Marks = 2 },
		{ Grade = "S-", Games = 1, Marks = 2 },
	},
	Bonus = { Grade = "S-", Games = 2, Marks = 1 },
}

-- The heroes' shop (design 12, Shared.HeroShop): a Featured hero that changes every `FeaturedDays` days and up to
-- `Daily` others that change every day, at midnight UTC.
Config.HeroShop = {
	FeaturedDays = 3,
	Daily = 4,
}

-- The queue (QueueService): parties of up to `PartySize` wait for a match of two teams of Config.HeroesPerTeam. Players
-- are matched within `Window` rating of the one who waited longest, `Grow` more for every second he waited. After
-- `FillAfter` seconds bots fill the empty places: in Quick Play always, in Ranked only once each team has `RankedHumans`
-- real players.
Config.Queue = {
	Modes = { "QuickPlay", "Ranked" },
	PartySize = 4,
	Window = 150,
	Grow = 10,
	FillAfter = 30,
	RankedHumans = 2,
}

-- The draft (design 07, DraftService): the teams pick in `Order`, `Turn` seconds each; a bot picks after a moment
-- between `BotDelay`'s two. Each hero once per match, while the picker has an untaken one of his own. After the last
-- pick the heroes are shown for `Ready` seconds. The match waits `Arrive` seconds for its players to come in.
Config.Draft = {
	Order = { "Blue1", "Red1", "Red2", "Blue2", "Blue3", "Red3", "Red4", "Blue4" },
	Turn = 25,
	BotDelay = { 1.2, 2.5 },
	Ready = 4,
	Arrive = 30,
}

-- The end of a match (design 16): the camera holds on the fallen Master for `Hold` seconds before the results, and
-- after `Return` seconds everyone goes back to the lobby.
Config.MatchEnd = {
	Hold = 3,
	Return = 60,
}

return Config
