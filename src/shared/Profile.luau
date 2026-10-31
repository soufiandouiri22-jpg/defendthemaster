-- A player's saved data (ProfileService keeps it in a ProfileStore): his account coins and XP, the heroes he owns and
-- his favourite, his rank (Shared.Ranks), his mastery of each hero he played (Shared.Mastery), his season pass, his
-- totals and his settings. The coins here are the
-- account's, spent in the menu; the coins of a match (Config.Economy) are the match's own and are never saved.

local Config = require(script.Parent.Config)

local Profile = {}

export type Settings = {
	Master: number,
	Music: number,
	Effects: number,
	Interface: number,
	MenuMusic: boolean,
	Shadows: boolean,
	DamageNumbers: boolean,
}

export type Data = {
	Coins: number,
	Xp: number,
	Heroes: { [string]: boolean },
	Favourite: string,
	Welcomed: boolean,
	LastHero: string,
	Rank: any,
	Mastery: { [string]: any },
	Pass: { Season: number, Xp: number, Claimed: { [string]: boolean }, BoostUntil: number },
	Stats: { Games: number, Wins: number, Kills: number, Deaths: number, Assists: number, Mvps: number },
	Settings: Settings,
}

function Profile.template(): Data
	return {
		Coins = Config.Account.StartCoins,
		Xp = 0,
		Heroes = {},
		Favourite = "",
		Welcomed = false,
		LastHero = "",
		Rank = {
			Season = Config.Season.Number,
			Tier = 1,
			Division = 4,
			Lp = 0,
			Rating = Config.Ranked.StartRating,
			Wins = 0,
			Losses = 0,
			Games = 0,
			Shield = 0,
			Peak = 1,
			Placements = 0,
			Ceiling = -1,
		},
		Mastery = {},
		Pass = { Season = Config.Season.Number, Xp = 0, Claimed = {}, BoostUntil = 0 },
		Stats = { Games = 0, Wins = 0, Kills = 0, Deaths = 0, Assists = 0, Mvps = 0 },
		Settings = Profile.defaultSettings(),
	}
end

function Profile.defaultSettings(): Settings
	return {
		Master = 1,
		Music = 1,
		Effects = 1,
		Interface = 1,
		MenuMusic = true,
		Shadows = true,
		DamageNumbers = true,
	}
end

-- Whether `data` owns `hero`: every starter hero, and those bought or earned.
function Profile.owns(data: Data, hero: string): boolean
	local settings = Config.Heroes[hero]
	return settings ~= nil and (settings.Starter == true or data.Heroes[hero] == true)
end

-- The heroes `data` owns, by name.
function Profile.owned(data: Data): { string }
	local list = {}
	for name in Config.Heroes do
		if Profile.owns(data, name) then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

-- The hero on the menu's podium: the favourite, else the last one played, else the default.
function Profile.showcase(data: Data): string
	for _, name in { data.Favourite, data.LastHero } do
		if name ~= "" and Profile.owns(data, name) then
			return name
		end
	end
	return Config.DefaultHero
end

return Profile
