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

-- What stops a party with a hero twice from queueing, since a team plays every hero at most once (owner, 2026-11-01):
-- the first hero two of `heroes` (the members' heroes) share, else nil.
function Lineup.clash(heroes: { string }): string?
	for index, hero in heroes do
		if table.find(heroes, hero, index + 1) then
			return hero
		end
	end
	return nil
end

-- The order in which `team`'s bots take their heroes: Config.Bots.Lineup shuffled by the match's `seed`, which the
-- lobby draws for the match and gives both its lineup and the match's record, so the cards and the match agree.
function Lineup.botOrder(seed: number, team: string): { string }
	local order = table.clone(Config.Bots.Lineup)
	local random = Random.new(seed + (table.find(Config.TeamOrder, team) or 0))
	for index = #order, 2, -1 do
		local other = random:NextInteger(1, index)
		order[index], order[other] = order[other], order[index]
	end
	return order
end

-- The heroes of a team's `count` bots, after its players' `taken` heroes: each the first of the team's `order`
-- (Lineup.botOrder) the team does not play yet, else Config.Bots.Hero (as DraftService gives them).
function Lineup.botHeroes(order: { string }, taken: { string }, count: number): { string }
	local left = table.clone(order)
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
