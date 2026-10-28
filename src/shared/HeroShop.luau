-- The heroes' shop (design 12, Config.HeroShop): of the heroes for sale (with a Price, neither a Starter nor
-- Exclusive) one is Featured for FeaturedDays days and up to Daily others are on offer each day. Every server draws
-- the same from the date, so the offer turns at midnight UTC everywhere at once. Any hero for sale can be bought, also
-- from the heroes' page; the shop shows which ones stand out today.

local Config = require(script.Parent.Config)

local SETTINGS = Config.HeroShop
local DAY = 86400

local HeroShop = {}

function HeroShop.forSale(hero: string): boolean
	local settings = Config.Heroes[hero]
	return settings ~= nil and settings.Price ~= nil and not settings.Starter and not settings.Exclusive
end

local function sale(): { string }
	local list = {}
	for name in Config.Heroes do
		if HeroShop.forSale(name) then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

local function shuffled(list: { string }, seed: number): { string }
	local copy = table.clone(list)
	local rng = Random.new(seed)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

export type Offer = { featured: string?, featuredEnds: number, daily: { string }, dailyEnds: number }

-- The offer at `now` (os.time, now when not given).
function HeroShop.offer(now: number?): Offer
	local at = now or os.time()
	local day = at // DAY
	local period = day // SETTINGS.FeaturedDays
	local list = sale()
	local featured = shuffled(list, 7919 * period + 11)[1]
	local daily = {}
	for _, name in shuffled(list, 104729 * day + 3) do
		if name ~= featured and #daily < SETTINGS.Daily then
			table.insert(daily, name)
		end
	end
	return {
		featured = featured,
		featuredEnds = (period + 1) * SETTINGS.FeaturedDays * DAY,
		daily = daily,
		dailyEnds = (day + 1) * DAY,
	}
end

return HeroShop
