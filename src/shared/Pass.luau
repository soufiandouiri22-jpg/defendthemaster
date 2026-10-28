-- The season pass (Config.Pass, design 13): its level from the pass XP, and the reward of every level on the free and
-- the premium track. A player is level 1 from the start, so its first reward is waiting for him.

local Config = require(script.Parent.Config)

local SETTINGS = Config.Pass

local Pass = {}

export type Reward = { Coins: number? } | { Boost: number? } | { Hero: string? }

-- The level of `xp`, the XP into it and what the next asks (both 0 at the last level).
function Pass.level(xp: number): (number, number, number)
	local level = math.min(SETTINGS.Levels, 1 + xp // SETTINGS.XpPerLevel)
	if level >= SETTINGS.Levels then
		return SETTINGS.Levels, 0, 0
	end
	return level, xp - (level - 1) * SETTINGS.XpPerLevel, SETTINGS.XpPerLevel
end

-- The free track: coins growing with the level, and a boost at every fifth.
function Pass.free(level: number): Reward
	if level % 5 == 0 then
		return { Boost = SETTINGS.Boost }
	end
	return { Coins = 100 + 50 * (level // 6) }
end

-- The premium track: more coins, and the season's hero at the last level.
function Pass.premium(level: number): Reward
	if level == SETTINGS.Levels then
		return { Hero = SETTINGS.Hero }
	end
	return { Coins = if level % 5 == 0 then 1500 else 1000 }
end

-- When the season ends (os.time).
function Pass.endsAt(): number
	return os.time(Config.Season.Ends :: any)
end

return Pass
