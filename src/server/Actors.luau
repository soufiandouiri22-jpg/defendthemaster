-- Everyone who plays a hero: the players, and the bots (BotService) that fill the teams. A bot is a Configuration in
-- ServerStorage.Bots with the attributes a Player has (Team, Level, Xp, Points, Rank .. key, Coins), so Leveling,
-- ProgressService, Economy and CombatService treat both alike; its hero is the character BotService moves.

local Players = game:GetService("Players")

local Actors = {}

local bots: { Instance } = {}
local characters: { [Instance]: Model } = {}

-- The players, then the bots.
function Actors.all(): { Instance }
	local all: { Instance } = {}
	for _, player in Players:GetPlayers() do
		table.insert(all, player)
	end
	table.move(bots, 1, #bots, #all + 1, all)
	return all
end

-- The hero `actor` plays now, if any.
function Actors.character(actor: Instance): Model?
	if actor:IsA("Player") then
		return actor.Character
	end
	return characters[actor]
end

-- The player or bot who plays the hero `character`, if any.
function Actors.owner(character: Model): Instance?
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return player
	end
	for bot, model in characters do
		if model == character then
			return bot
		end
	end
	return nil
end

function Actors.addBot(bot: Instance)
	table.insert(bots, bot)
end

function Actors.removeBot(bot: Instance)
	local index = table.find(bots, bot)
	if index then
		table.remove(bots, index)
	end
	characters[bot] = nil
end

function Actors.setCharacter(bot: Instance, character: Model?)
	characters[bot] = character
end

return Actors
