-- A player's account level from his account XP (Config.Account). As League's, it has no top: the XP a level asks
-- grows up to level Config.Account.Plateau and stays the same after it.

local Config = require(script.Parent.Config)

local SETTINGS = Config.Account

local Account = {}

-- The account XP level `level` asks to reach the next.
function Account.need(level: number): number
	return SETTINGS.First + SETTINGS.PerLevel * (math.min(level, SETTINGS.Plateau) - 1)
end

-- The level of `xp`, the XP into it and what it asks.
function Account.level(xp: number): (number, number, number)
	local level = 1
	local need = Account.need(level)
	while xp >= need do
		xp -= need
		level += 1
		need = Account.need(level)
	end
	return level, xp, need
end

return Account
