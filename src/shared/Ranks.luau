-- The ranked ladder (Config.Ranked), as League of Legends: tiers with divisions IV to I, LP within a division, a hidden
-- rating that makes a win worth more for a player who stands below his skill, protection after a promotion. A rank is
-- the profile's Rank table (Shared.Profile): Tier (1-8, the stored tier), Division (4 to 1), Lp, Rating, Wins, Losses,
-- Games, Shield (matches left without dropping out of the tier), Peak (the best tier this season), Placements (the
-- placement matches played) and Ceiling (the highest ladder score the season's placements may give, -1 for none).
-- Sunborn and Master are never stored: a Legend shows as one by his place on the ladder (Ranks.shown).

local Account = require(script.Parent.Account)
local Config = require(script.Parent.Config)
local Profile = require(script.Parent.Profile)

local SETTINGS = Config.Ranked

local Ranks = {}

export type Rank = {
	Tier: number,
	Division: number,
	Lp: number,
	Rating: number,
	Wins: number,
	Losses: number,
	Games: number,
	Shield: number,
	Peak: number,
	Season: number,
	Placements: number,
	Ceiling: number,
}

-- The stored tier above the divided ones: Legend.
Ranks.LEGEND = SETTINGS.Divided + 1
local ROMAN = { "I", "II", "III", "IV" }

function Ranks.divided(tier: number): boolean
	return tier <= SETTINGS.Divided
end

-- The ladder's score of `rank`: every division and LP below it counted, so higher is better.
function Ranks.score(rank: Rank): number
	if Ranks.divided(rank.Tier) then
		return ((rank.Tier - 1) * 4 + (4 - rank.Division)) * SETTINGS.DivisionLp + rank.Lp
	end
	return SETTINGS.Divided * 4 * SETTINGS.DivisionLp + rank.Lp
end

-- The tier, division and LP of a ladder score (Ranks.score).
function Ranks.fromScore(score: number): (number, number, number)
	local per = SETTINGS.DivisionLp
	local divisions = SETTINGS.Divided * 4
	local steps = score // per
	if steps >= divisions then
		return Ranks.LEGEND, 1, score - divisions * per
	end
	return steps // 4 + 1, 4 - steps % 4, score % per
end

-- The tier `rank` shows: a Legend in the ladder's top as Sunborn or Master, by his `position` (1 is the best).
function Ranks.shown(rank: Rank, position: number?): number
	if rank.Tier < Ranks.LEGEND or not position then
		return rank.Tier
	end
	for tier = #SETTINGS.Tiers, Ranks.LEGEND + 1, -1 do
		local top = SETTINGS.Tiers[tier].Top
		if top and position <= top then
			return tier
		end
	end
	return rank.Tier
end

function Ranks.name(tier: number): string
	return SETTINGS.Tiers[tier].Name
end

function Ranks.badge(tier: number): string
	return SETTINGS.Tiers[tier].Badge
end

-- "Knight II", or "Legend" for a tier without divisions.
function Ranks.label(tier: number, division: number?): string
	if Ranks.divided(tier) and division then
		return Ranks.name(tier) .. " " .. ROMAN[division]
	end
	return Ranks.name(tier)
end

-- What a tier's card says under its name: "IV - I", or how one gets there.
function Ranks.span(tier: number): string
	if Ranks.divided(tier) then
		return "IV - I"
	end
	local top = SETTINGS.Tiers[tier].Top
	return if top then "TOP " .. top else "OPEN LP"
end

-- The rating a player of `rank` is expected to have.
function Ranks.rankRating(rank: Rank): number
	return SETTINGS.StartRating + (Ranks.score(rank) - 4 * 2 * SETTINGS.DivisionLp) / 2
end

-- The ladder score whose expected rating is `rating` (the inverse of Ranks.rankRating).
local function ratingScore(rating: number): number
	return (rating - SETTINGS.StartRating) * 2 + 4 * 2 * SETTINGS.DivisionLp
end

-- Whether `rank` has played its placements.
function Ranks.placed(rank: Rank): boolean
	return (rank.Placements or 0) >= SETTINGS.Placements
end

-- Whether `data` may play Ranked; else why not, for the player.
function Ranks.unlocked(data: Profile.Data): (boolean, string?)
	if (Account.level(data.Xp)) < SETTINGS.Level then
		return false, "Ranked opens at account level " .. SETTINGS.Level .. "."
	end
	local others = data.Stats.Games - data.Rank.Games
	if others < SETTINGS.QuickPlays then
		return false, "Ranked opens after " .. SETTINGS.QuickPlays .. " Quick Play matches (" .. others .. " played)."
	end
	local heroes = 0
	for _ in Config.Heroes do
		heroes += 1
	end
	if heroes >= SETTINGS.Heroes and #Profile.owned(data) < SETTINGS.Heroes then
		return false, "Ranked needs " .. SETTINGS.Heroes .. " heroes of your own."
	end
	return true, nil
end

-- Sets `rank` to the ladder `score`, with its LP.
local function setScore(rank: Rank, score: number)
	rank.Tier, rank.Division, rank.Lp = Ranks.fromScore(math.max(0, score))
end

-- The LP a player dropping out of a tier lands on: low, middle or high by his rating against his new rank's.
local function demoteLp(rank: Rank): number
	local gap = rank.Rating - Ranks.rankRating(rank)
	local lp = SETTINGS.DemoteLp
	return if gap < -SETTINGS.DemoteBand then lp[1] elseif gap > SETTINGS.DemoteBand then lp[3] else lp[2]
end

export type Change = {
	lp: number,
	promoted: boolean,
	demoted: boolean,
	protected: boolean,
	placing: boolean,
	placed: boolean,
}

-- Plays one ranked match into `rank`: won or lost against players of rating `against`. Returns what changed.
function Ranks.apply(rank: Rank, won: boolean, against: number): Change
	local placing = not Ranks.placed(rank)
	local k = if placing then SETTINGS.K * 2 else SETTINGS.K
	local expected = 1 / (1 + 10 ^ ((against - rank.Rating) / 400))
	rank.Rating = math.round(rank.Rating + k * ((if won then 1 else 0) - expected))
	rank.Games += 1
	if won then
		rank.Wins += 1
	else
		rank.Losses += 1
	end
	local change: Change =
		{ lp = 0, promoted = false, demoted = false, protected = false, placing = placing, placed = false }

	if placing then
		rank.Placements = (rank.Placements or 0) + 1
		if Ranks.placed(rank) then
			local cap = SETTINGS.PlaceCap
			local top = Ranks.score({ Tier = cap.Tier, Division = cap.Division, Lp = 0 } :: any)
			local ceiling = rank.Ceiling or -1
			if ceiling >= 0 then
				top = math.min(top, ceiling)
			end
			setScore(rank, math.min(ratingScore(rank.Rating), top))
			rank.Lp = 0
			rank.Ceiling = -1
			rank.Shield = 0
			rank.Peak = math.max(rank.Peak, rank.Tier)
			change.placed = true
		end
		return change
	end

	local swing =
		math.clamp((rank.Rating - Ranks.rankRating(rank)) / SETTINGS.SwingPer, -SETTINGS.Swing, SETTINGS.Swing)
	local delta = if won then math.round(SETTINGS.Win + swing) else -math.round(SETTINGS.Loss - swing)
	change.lp = delta
	local shielded = rank.Shield > 0
	rank.Shield = math.max(0, rank.Shield - 1)
	rank.Lp += delta
	if won then
		local tier = rank.Tier
		while Ranks.divided(rank.Tier) and rank.Lp >= SETTINGS.DivisionLp do
			rank.Lp -= SETTINGS.DivisionLp
			if rank.Division > 1 then
				rank.Division -= 1
			else
				rank.Tier += 1
				rank.Division = if Ranks.divided(rank.Tier) then 4 else 1
			end
			change.promoted = true
		end
		if rank.Tier > tier then
			rank.Shield = SETTINGS.Shield
		end
	elseif rank.Lp < 0 then
		local bottom = rank.Tier == 1 and rank.Division == 4
		if bottom then
			change.lp -= rank.Lp
			rank.Lp = 0
		elseif Ranks.divided(rank.Tier) and rank.Division < 4 then
			-- Within a tier the LP rolls over into the division below.
			rank.Division += 1
			rank.Lp += SETTINGS.DivisionLp
			change.demoted = true
		elseif shielded then
			change.lp -= rank.Lp
			rank.Lp = 0
			change.protected = true
		else
			rank.Tier = math.min(rank.Tier - 1, SETTINGS.Divided)
			rank.Division = 1
			rank.Lp = 0
			rank.Lp = demoteLp(rank)
			change.demoted = true
		end
	end
	rank.Peak = math.max(rank.Peak, rank.Tier)
	return change
end

-- A new season: `rank` drops Config.Ranked.Reset divisions and plays its placements again, which then place it no
-- higher than that.
function Ranks.reset(rank: Rank)
	local score = Ranks.score(rank)
	local cap = Ranks.score({ Tier = SETTINGS.Divided, Division = 1, Lp = 0 } :: any)
	local lowered = math.max(0, math.min(score, cap) - SETTINGS.Reset * SETTINGS.DivisionLp)
	if Ranks.placed(rank) then
		rank.Ceiling = lowered
	end
	setScore(rank, lowered)
	rank.Lp = 0
	rank.Shield = 0
	rank.Placements = 0
	rank.Peak = rank.Tier
end

return Ranks
