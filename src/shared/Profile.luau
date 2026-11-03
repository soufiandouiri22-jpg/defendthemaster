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
	-- The mouse's speed on the camera, as the slider stands (Preferences.sensitivity: the middle is the usual speed).
	Sensitivity: number,
}

export type Data = {
	Coins: number,
	Xp: number,
	Heroes: { [string]: boolean },
	-- The emotes earned (Config.Emotes; the defaults are everyone's without being here).
	Emotes: { [string]: boolean },
	-- The emotes he put in the wheel's slots, in their order (Profile.wheel fills the rest), and those earned that he
	-- has seen in the lobby's wheel since (until then they are new).
	Wheel: { string },
	SeenEmotes: { [string]: boolean },
	Favourite: string,
	Welcomed: boolean,
	LastHero: string,
	Rank: any,
	Mastery: { [string]: any },
	-- The pass he plays (Shared.Pass's number, 0 the test pass before the launch) and his progress in it.
	Pass: { Number: number, Xp: number, Claimed: { [string]: boolean }, BoostUntil: number },
	Stats: { Games: number, Wins: number, Kills: number, Deaths: number, Assists: number, Mvps: number },
	Settings: Settings,
}

function Profile.template(): Data
	return {
		Coins = Config.Account.StartCoins,
		Xp = 0,
		Heroes = {},
		Emotes = {},
		Wheel = {},
		SeenEmotes = {},
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
		Pass = { Number = 0, Xp = 0, Claimed = {}, BoostUntil = 0 },
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
		Sensitivity = 0.5,
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

-- Whether `data` has emote `id`: every default, and those earned.
function Profile.hasEmote(data: Data, id: string): boolean
	local emote = Config.Emotes.List[id]
	return emote ~= nil and (emote.Default == true or (data.Emotes or {})[id] == true)
end

-- The emotes `data` has, in the collection's order (Config.Emotes.Order).
function Profile.emotes(data: Data): { string }
	local list = {}
	for _, id in Config.Emotes.Order do
		if Profile.hasEmote(data, id) then
			table.insert(list, id)
		end
	end
	return list
end

-- The emotes in `data`'s wheel, slot by slot: those he put there that he still has, then, while slots are left, the
-- others he has in the collection's order.
function Profile.wheel(data: Data): { string }
	local list = {}
	for _, id in data.Wheel or {} do
		if #list < Config.Emotes.Slots and Profile.hasEmote(data, id) and not table.find(list, id) then
			table.insert(list, id)
		end
	end
	for _, id in Profile.emotes(data) do
		if #list < Config.Emotes.Slots and not table.find(list, id) then
			table.insert(list, id)
		end
	end
	return list
end

-- Whether emote `id` is new to `data`: earned and not yet seen in the lobby's wheel.
function Profile.newEmote(data: Data, id: string): boolean
	local emote = Config.Emotes.List[id]
	return emote ~= nil and not emote.Default and (data.Emotes or {})[id] == true and not (data.SeenEmotes or {})[id]
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
