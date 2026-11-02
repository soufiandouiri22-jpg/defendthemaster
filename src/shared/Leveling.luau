-- What a hero's level and ranks do (Config.Progress), the same on the server and the client. A player's progress is in
-- the server's attributes on the Player: "Level", "Xp" (into the current level), "Points" (unspent) and "Rank" .. key
-- for every key of Config.Progress.Upgrades.

local Boosts = require(script.Parent.Boosts)
local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)

local SETTINGS = Config.Progress

local Leveling = {}

function Leveling.level(player: Player): number
	return player:GetAttribute("Level") or 1
end

-- The rank of `key`: 0 while an ability of Upgrades is not learned yet.
function Leveling.rank(player: Player, key: string): number
	return player:GetAttribute("Rank" .. key) or 0
end

-- Whether the hero may use `key`: the combo and the dash always, the others once learned.
function Leveling.learned(player: Player, key: string): boolean
	return not table.find(SETTINGS.Upgrades, key) or Leveling.rank(player, key) >= 1
end

-- The XP from `level` to the next, or nil at the top level.
function Leveling.step(level: number): number?
	return SETTINGS.Steps[level]
end

-- The hero's health at `level`.
function Leveling.maxHealth(base: number, level: number): number
	return math.round(base * (1 + SETTINGS.Health * (level - 1)))
end

-- The health of `player`'s hero `hero`: its level's, and his items'.
function Leveling.heroHealth(player: Player, hero: string): number
	return Leveling.maxHealth(Config.Heroes[hero].Health, Leveling.level(player)) + Items.stats(player).Health
end

-- What the hero's `key` ability deals, as a share of the kit's damage.
function Leveling.power(player: Player, key: string): number
	local rank = if table.find(SETTINGS.Upgrades, key) then math.max(1, Leveling.rank(player, key)) else 1
	return (1 + SETTINGS.Damage * (Leveling.level(player) - 1)) * (1 + SETTINGS.RankDamage * (rank - 1))
end

-- The cooldown of the hero's `key` ability, with his items' Haste and the Star Hourglass while his team carries it
-- (Boosts).
function Leveling.cooldown(player: Player, key: string, base: number): number
	local rank = if table.find(SETTINGS.Upgrades, key) then math.max(1, Leveling.rank(player, key)) else 1
	local haste = Items.stats(player).Haste
	return base
		* (1 - SETTINGS.RankCooldown * (rank - 1))
		* 100
		/ (100 + haste)
		* (1 - Boosts.bonus(player, "Cooldown"))
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
