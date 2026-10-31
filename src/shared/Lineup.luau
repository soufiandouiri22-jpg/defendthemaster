-- The lineup of a match without a draft as the cards show it (VersusView): what each player's card carries, taken in
-- the lobby from what ProfileService publishes on him, and the heroes of a team's bots. The lobby sends it to the
-- match's players before their teleport, so the cards are what they see from the moment the match is found; the match
-- server comes to the same lineup (MatchSetup.slots in the queue's order, DraftService.assign with these bots).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Lineup = {}

export type Card = {
	name: string,
	hero: string?,
	mastery: number,
	shown: number?,
	division: number?,
	lp: number?,
	placements: number?,
	position: number?,
	level: number?,
}

-- What `player`'s card shows: the hero he will play and his mastery of him, his rank and his account level.
function Lineup.card(player: Player): Card
	return {
		name = player.DisplayName,
		hero = player:GetAttribute("Showcase"),
		mastery = player:GetAttribute("ShowcaseMastery") or 0,
		shown = player:GetAttribute("RankShown"),
		division = player:GetAttribute("RankDivision"),
		lp = player:GetAttribute("RankLp"),
		placements = player:GetAttribute("RankPlacements"),
		position = player:GetAttribute("RankPosition"),
		level = player:GetAttribute("AccountLevel"),
	}
end

-- The heroes of a team's `count` bots, after its players' `taken` heroes: each the first of Config.Bots.Lineup the
-- team does not play yet, else Config.Bots.Hero (as DraftService gives them).
function Lineup.botHeroes(taken: { string }, count: number): { string }
	local left = table.clone(Config.Bots.Lineup)
	for _, hero in taken do
		local at = table.find(left, hero)
		if at then
			table.remove(left, at)
		end
	end
	local heroes = {}
	for index = 1, count do
		heroes[index] = table.remove(left, 1) or Config.Bots.Hero
	end
	return heroes
end

return Lineup
