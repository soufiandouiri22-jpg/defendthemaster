-- What the menu asks of the server (Net.Menu, a RemoteFunction answering { ok, error?, ... }): buying a hero for coins
-- (Shared.HeroShop), choosing the favourite for the podium, claiming a reward of the season pass (Shared.Pass), saving
-- the settings, and reading the ladder (Ladder). The server checks everything; the client only shows the answer and
-- the new data (ProfileService). Settings are saved in a match too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroShop = require(ReplicatedStorage.Shared.HeroShop)
local Pass = require(ReplicatedStorage.Shared.Pass)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local Ladder = require(script.Parent.Ladder)
local ProfileService = require(script.Parent.ProfileService)
local Remote = require(script.Parent.Remote)

local MenuService = {}

type Answer = { ok: boolean, error: string?, [string]: any }

local function fail(message: string): Answer
	return { ok = false, error = message }
end

-- Gives `data` the pass reward `reward`.
function MenuService.grant(data: Profile.Data, reward: Pass.Reward)
	local r = reward :: any
	if r.Coins then
		data.Coins += r.Coins
	elseif r.Boost then
		data.Pass.BoostUntil = math.max(os.time(), data.Pass.BoostUntil) + r.Boost
	elseif r.Hero and Config.Heroes[r.Hero] then
		data.Heroes[r.Hero] = true
	end
end

local function buyHero(player: Player, hero: any): Answer
	if typeof(hero) ~= "string" or not HeroShop.forSale(hero) then
		return fail("This hero is not for sale.")
	end
	local price = Config.Heroes[hero].Price
	return ProfileService.update(player, function(data): Answer
		if Profile.owns(data, hero) then
			return fail("You already own " .. hero .. ".")
		elseif data.Coins < price then
			return fail("Not enough coins.")
		end
		data.Coins -= price
		data.Heroes[hero] = true
		return { ok = true }
	end) or fail("Your data is still loading.")
end

local function favourite(player: Player, hero: any): Answer
	if typeof(hero) ~= "string" then
		return fail("Unknown hero.")
	end
	return ProfileService.update(player, function(data): Answer
		if not Profile.owns(data, hero) then
			return fail("You do not own this hero.")
		end
		data.Favourite = hero
		return { ok = true }
	end) or fail("Your data is still loading.")
end

local function claim(player: Player, level: any, track: any): Answer
	if typeof(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > Config.Pass.Levels then
		return fail("Unknown reward.")
	end
	if track == "Premium" then
		return fail("The premium pass is coming soon.")
	end
	return ProfileService.update(player, function(data): Answer
		local key = tostring(level)
		if data.Pass.Claimed[key] then
			return fail("Already claimed.")
		elseif (Pass.level(data.Pass.Xp)) < level then
			return fail("Reach level " .. level .. " first.")
		end
		data.Pass.Claimed[key] = true
		MenuService.grant(data, Pass.free(level))
		return { ok = true }
	end) or fail("Your data is still loading.")
end

local function settings(player: Player, values: any): Answer
	if typeof(values) ~= "table" then
		return fail("Bad settings.")
	end
	return ProfileService.update(player, function(data): Answer
		local defaults = Profile.defaultSettings() :: any
		local saved = data.Settings :: any
		for key, default in defaults do
			local value = values[key]
			if typeof(default) == "number" and typeof(value) == "number" and value == value then
				saved[key] = math.clamp(math.round(value * 100) / 100, 0, 1)
			elseif typeof(default) == "boolean" and typeof(value) == "boolean" then
				saved[key] = value
			end
		end
		return { ok = true }
	end) or fail("Your data is still loading.")
end

local function ladder(player: Player, tab: any): Answer
	local data = ProfileService.get(player)
	local entries = if tab == "Friends" then Ladder.friends(player) else Ladder.top()
	local you = nil
	if data and data.Rank.Games > 0 then
		you = { position = Ladder.position(player.UserId), score = Ranks.score(data.Rank) }
	end
	return { ok = true, entries = entries, you = you }
end

local ACTIONS: { [string]: (player: Player, ...any) -> Answer } = {
	BuyHero = buyHero,
	Favourite = favourite,
	Claim = claim,
	Settings = settings,
	Ladder = ladder,
}

function MenuService.start()
	Remote.func("Menu", 4, function(player, action, ...)
		local handler = typeof(action) == "string" and ACTIONS[action]
		if not handler then
			return fail("Unknown request.")
		end
		local ok, answer = pcall(handler, player, ...)
		if not ok then
			warn("[MenuService]", action, answer)
			return fail("Something went wrong. Try again.")
		end
		return answer
	end)
end

return MenuService
