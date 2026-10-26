-- Shared settings of Defend The Master.
local Config = {}

Config.HeroesPerTeam = 4

-- The colosseum (design 01): a round sand arena 250 studs across. Red's end is north (-Z), Blue's south (+Z).
Config.Arena = {
	Radius = 125,
}

-- The Master is an NPC king on his throne, clearly bigger than the heroes.
Config.Master = {
	Scale = 1.8,
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
