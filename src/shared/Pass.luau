-- The season pass (Config.Pass, design 13): which pass runs and when it ends, its level from the pass XP, and the
-- reward of every level on the free and the premium track (its emotes its own, the rest the same in every pass). A player is level 1 from the start, so its first reward is
-- waiting for him. A new pass starts his progress over and gives him the free rewards he reached and left unclaimed.

local Config = require(script.Parent.Config)

local SETTINGS = Config.Pass
local DAY = 86400

local Pass = {}

export type Reward = { Coins: number? } | { Boost: number? } | { Hero: string? } | { Emote: string }

-- The Netherlands' hours ahead of UTC at `t`: two in summer time (from 01:00 UTC on the last Sunday of March to the
-- last Sunday of October), else one.
local function dutchOffset(t: number): number
	local year = (os.date("!*t", t) :: any).year
	local function lastSunday(month: number): number
		local day31 = os.time({ year = year, month = month, day = 31, hour = 1, min = 0, sec = 0 } :: any)
		return day31 - ((os.date("!*t", day31) :: any).wday - 1) * DAY
	end
	return if t >= lastSunday(3) and t < lastSunday(10) then 2 else 1
end

-- When pass `number` (1 the first) begins (os.time): the launch's Friday plus `Weeks` weeks for each before it, at
-- `Hour` o'clock Dutch time.
local function startOf(number: number): number
	local launch = SETTINGS.Launch :: any
	local midnight = os.time({ year = launch.year, month = launch.month, day = launch.day, hour = 0, min = 0, sec = 0 })
	local utc = midnight + (number - 1) * SETTINGS.Weeks * 7 * DAY + SETTINGS.Hour * 3600
	return utc - dutchOffset(utc - 3 * 3600) * 3600
end

-- The pass running at `now` (os.time, now when not given): its number (0 the test pass before the launch), when it
-- began (nil for the test pass) and when it ends (nil while the launch is not known).
function Pass.current(now: number?): (number, number?, number?)
	local t = math.floor(now or os.time())
	if not SETTINGS.Launch then
		return 0, nil, nil
	end
	local first = startOf(1)
	if t < first then
		return 0, nil, first
	end
	local n = 1 + (t - first) // (SETTINGS.Weeks * 7 * DAY)
	-- Summer time moves the hour against UTC: step to the pass that holds `t`.
	while n > 1 and t < startOf(n) do
		n -= 1
	end
	while t >= startOf(n + 1) do
		n += 1
	end
	return n, startOf(n), startOf(n + 1)
end

-- When the pass running at `now` ends (os.time), or nil while the launch is not known.
function Pass.endsAt(now: number?): number?
	local _, _, ends = Pass.current(now)
	return ends
end

-- `seconds` left for the screen: in days, on the last day in hours, in the last hour in minutes.
function Pass.left(seconds: number): string
	local function count(n: number, unit: string): string
		return n .. " " .. unit .. (if n == 1 then "" else "S")
	end
	if seconds > DAY then
		return count(math.ceil(seconds / DAY), "DAY")
	elseif seconds > 3600 then
		return count(math.ceil(seconds / 3600), "HOUR")
	end
	return count(math.max(1, math.ceil(seconds / 60)), "MINUTE")
end

-- The pass's name for the screen: "PASS 3", or "TEST PASS" before the launch.
function Pass.name(number: number): string
	return if number == 0 then "TEST PASS" else "PASS " .. number
end

-- The level of `xp`, the XP into it and what the next asks (both 0 at the last level).
function Pass.level(xp: number): (number, number, number)
	local level = math.min(SETTINGS.Levels, 1 + xp // SETTINGS.XpPerLevel)
	if level >= SETTINGS.Levels then
		return SETTINGS.Levels, 0, 0
	end
	return level, xp - (level - 1) * SETTINGS.XpPerLevel, SETTINGS.XpPerLevel
end

-- The emote of pass `number`'s `track` ("Free" or "Premium") at `level`, if it has one there.
local function emoteAt(number: number, track: string, level: number): string?
	local emotes = SETTINGS.Emotes[number]
	local at = table.find((SETTINGS.EmoteLevels :: any)[track], level)
	return if emotes and at then (emotes :: any)[track][at] else nil
end

-- The free track of pass `number` (the one running now when not given): coins growing with the level, a boost at every
-- fifth, and its emotes.
function Pass.free(level: number, number: number?): Reward
	local emote = emoteAt(number or Pass.current(), "Free", level)
	if emote then
		return { Emote = emote }
	elseif level % 5 == 0 then
		return { Boost = SETTINGS.Boost }
	end
	return { Coins = 100 + 50 * (level // 6) }
end

-- The premium track: more coins, its emotes, and the pass's hero at the last level.
function Pass.premium(level: number, number: number?): Reward
	local emote = emoteAt(number or Pass.current(), "Premium", level)
	if emote then
		return { Emote = emote }
	elseif level == SETTINGS.Levels then
		return { Hero = SETTINGS.Hero }
	end
	return { Coins = if level % 5 == 0 then 1500 else 1000 }
end

-- Gives `data` (a Profile.Data) the pass reward `reward`.
function Pass.grant(data: any, reward: Reward)
	local r = reward :: any
	if r.Coins then
		data.Coins += r.Coins
	elseif r.Boost then
		data.Pass.BoostUntil = math.max(os.time(), data.Pass.BoostUntil) + r.Boost
	elseif r.Hero and Config.Heroes[r.Hero] then
		data.Heroes[r.Hero] = true
	elseif r.Emote and Config.Emotes.List[r.Emote] then
		data.Emotes[r.Emote] = true
	end
end

-- Starts `data`'s pass over when another has begun since its last (its Number), first giving it the free rewards it
-- reached and left unclaimed; a running boost goes on. Whether it started over.
function Pass.refresh(data: any, now: number?): boolean
	local number = Pass.current(now)
	local pass = data.Pass
	if pass.Number == number then
		return false
	end
	local reached = Pass.level(pass.Xp)
	for level = 1, reached do
		if not pass.Claimed[tostring(level)] then
			Pass.grant(data, Pass.free(level, pass.Number))
		end
	end
	data.Pass = { Number = number, Xp = 0, Claimed = {}, BoostUntil = data.Pass.BoostUntil }
	return true
end

return Pass
