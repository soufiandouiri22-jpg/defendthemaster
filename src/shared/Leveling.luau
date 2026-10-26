-- What a hero's level and ranks do (Config.Progress), the same on the server and the client. A player's progress is in
-- the server's attributes on the Player: "Level", "Xp" (into the current level), "Points" (unspent) and "Rank" .. key
-- for every key of Config.Progress.Upgrades.

local Config = require(script.Parent.Config)

local SETTINGS = Config.Progress

local Leveling = {}

function Leveling.level(player: Player): number
	return player:GetAttribute("Level") or 1
end

function Leveling.rank(player: Player, key: string): number
	return player:GetAttribute("Rank" .. key) or 1
end

-- The XP from `level` to the next, or nil at the top level.
function Leveling.step(level: number): number?
	return SETTINGS.Steps[level]
end

-- The hero's health at `level`.
function Leveling.maxHealth(base: number, level: number): number
	return math.round(base * (1 + SETTINGS.Health * (level - 1)))
end

-- What the hero's `key` ability deals, as a share of the kit's damage.
function Leveling.power(player: Player, key: string): number
	local rank = if table.find(SETTINGS.Upgrades, key) then Leveling.rank(player, key) else 1
	return (1 + SETTINGS.Damage * (Leveling.level(player) - 1)) * (1 + SETTINGS.RankDamage * (rank - 1))
end

-- The cooldown of the hero's `key` ability.
function Leveling.cooldown(player: Player, key: string, base: number): number
	local rank = if table.find(SETTINGS.Upgrades, key) then Leveling.rank(player, key) else 1
	return base * (1 - SETTINGS.RankCooldown * (rank - 1))
end

-- Whether the player can raise `key` a rank now.
function Leveling.canRaise(player: Player, key: string): boolean
	local needs = SETTINGS.Needs[key]
	local next = Leveling.rank(player, key) + 1
	return needs ~= nil
		and (player:GetAttribute("Points") or 0) > 0
		and next <= SETTINGS.MaxRank
		and Leveling.level(player) >= needs[next]
end

return Leveling
