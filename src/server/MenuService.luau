-- What the menu asks of the server (Net.Menu, a RemoteFunction answering { ok, error?, ... }): buying a hero for coins
-- (Shared.HeroShop), choosing the favourite for the podium, claiming a reward of the season pass (Shared.Pass), filling
-- the emote wheel's slots (Profile.wheel) and marking new emotes seen, saving the settings, and reading the ladder (Ladder). The server checks everything; the client only shows the answer and
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
		if Pass.refresh(data) then
			return fail("A new pass has begun.")
		end
		local key = tostring(level)
		if data.Pass.Claimed[key] then
			return fail("Already claimed.")
		elseif (Pass.level(data.Pass.Xp)) < level then
			return fail("Reach level " .. level .. " first.")
		end
		data.Pass.Claimed[key] = true
		Pass.grant(data, Pass.free(level, data.Pass.Number))
		return { ok = true }
	end) or fail("Your data is still loading.")
end

-- Puts emote `id` in the wheel's slot `slot` (one of Profile.wheel's: until they are all full every emote is in);
-- one already in another slot trades places with what was there.
local function emoteSlot(player: Player, slot: any, id: any): Answer
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Config.Emotes.Slots then
		return fail("Unknown slot.")
	elseif typeof(id) ~= "string" then
		return fail("Unknown emote.")
	end
	return ProfileService.update(player, function(data): Answer
		if not Profile.hasEmote(data, id) then
			return fail("You do not have this emote.")
		end
		local wheel = Profile.wheel(data)
		if slot > #wheel then
			return fail("Unknown slot.")
		end
		local was = table.find(wheel, id)
		if was then
			wheel[was] = wheel[slot]
		end
		wheel[slot] = id
		data.Wheel = wheel
		return { ok = true, wheel = table.clone(wheel) }
	end) or fail("Your data is still loading.")
end

-- Marks every emote the player has as seen (Profile.newEmote), once he has looked at them in the lobby's wheel.
local function emotesSeen(player: Player): Answer
	return ProfileService.update(player, function(data): Answer
		for _, id in Profile.emotes(data) do
			if Profile.newEmote(data, id) then
				data.SeenEmotes[id] = true
			end
		end
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
	EmoteSlot = emoteSlot,
	EmotesSeen = emotesSeen,
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
