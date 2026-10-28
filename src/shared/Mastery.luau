-- Hero mastery (Config.Mastery), as League's: a hero's points and level, and the season's milestones that earn the
-- Marks of Mastery the higher levels ask. A hero's mastery is the profile's Mastery[hero] (Shared.Profile): Points
-- (all he ever earned), Level, Marks (unused this season), Milestone (the season's milestones done), Progress (games
-- towards the next one) and Season.

local Config = require(script.Parent.Config)

local SETTINGS = Config.Mastery

local Mastery = {}

export type Entry = {
	Points: number,
	Level: number,
	Marks: number,
	Milestone: number,
	Progress: number,
	Season: number,
}

-- The place of `grade` in Config.Rewards.Grades: 1 is S+, the best.
local function order(grade: string): number
	for i, step in Config.Rewards.Grades do
		if step[1] == grade then
			return i
		end
	end
	return #Config.Rewards.Grades
end

-- Whether `grade` is `need` or better.
function Mastery.meets(grade: string, need: string): boolean
	return order(grade) <= order(need)
end

-- The points level `level` asks, from the one below it.
function Mastery.step(level: number): number
	if level <= 1 then
		return 0
	end
	return SETTINGS.Steps[math.min(level - 1, #SETTINGS.Steps)]
end

-- All the points level `level` asks.
function Mastery.total(level: number): number
	local sum = 0
	for l = 2, level do
		sum += Mastery.step(l)
	end
	return sum
end

-- The Marks of Mastery level `level` asks.
function Mastery.marks(level: number): number
	if level < SETTINGS.MarksFrom then
		return 0
	end
	return if level >= SETTINGS.Title then SETTINGS.MarksTop else 1
end

-- The milestone after `done` milestones this season.
function Mastery.milestone(done: number): { Grade: string, Games: number, Marks: number }
	return SETTINGS.Track[done + 1] or SETTINGS.Bonus
end

-- `data`'s mastery of `hero`, made at level 0 when he never played him; a new season starts its milestones over.
function Mastery.entry(data: any, hero: string): Entry
	data.Mastery = data.Mastery or {}
	local entry = data.Mastery[hero]
	if not entry then
		entry = { Points = 0, Level = 0, Marks = 0, Milestone = 0, Progress = 0, Season = Config.Season.Number }
		data.Mastery[hero] = entry
	end
	if entry.Season < Config.Season.Number then
		entry.Marks, entry.Milestone, entry.Progress = 0, 0, 0
		entry.Season = Config.Season.Number
	end
	return entry
end

-- The points a match earns at `grade`.
function Mastery.points(grade: string, won: boolean): number
	local letter = string.sub(grade, 1, 1)
	local sign = string.sub(grade, 2, 2)
	local points = SETTINGS.Points[letter] or SETTINGS.Points.D
	if sign == "+" then
		points += SETTINGS.Sign
	elseif sign == "-" then
		points -= SETTINGS.Sign
	end
	return points + (if won then SETTINGS.Win else 0)
end

-- Levels `entry` up as far as its points and marks reach.
local function climb(entry: Entry)
	while true do
		local nextLevel = entry.Level + 1
		local need = Mastery.marks(nextLevel)
		if entry.Points < Mastery.total(nextLevel) or entry.Marks < need then
			return
		end
		entry.Marks -= need
		entry.Level = nextLevel
	end
end

export type Gain = {
	points: number,
	levelBefore: number,
	marks: number,
	milestone: boolean,
}

-- One match with the hero of `entry` at `grade`: his points, the milestone it may complete, and his level.
function Mastery.play(entry: Entry, grade: string, won: boolean): Gain
	local gain: Gain = { points = Mastery.points(grade, won), levelBefore = entry.Level, marks = 0, milestone = false }
	entry.Points += gain.points
	if entry.Level == 0 then
		entry.Level = 1
	end
	local goal = Mastery.milestone(entry.Milestone)
	if Mastery.meets(grade, goal.Grade) then
		entry.Progress += 1
		if entry.Progress >= goal.Games then
			entry.Progress = 0
			entry.Milestone += 1
			entry.Marks += goal.Marks
			gain.marks = goal.Marks
			gain.milestone = true
		end
	end
	climb(entry)
	return gain
end

export type View = {
	level: number,
	into: number,
	need: number,
	marks: number,
	marksNeed: number,
	goal: string,
	goalGames: number,
	progress: number,
	title: boolean,
}

-- What the screens show of `entry` (nil for a hero never played): the level, the points into the next and what it
-- asks, its marks against what the next asks, the next milestone and whether the title is his.
function Mastery.view(entry: Entry?): View
	local e = entry or { Points = 0, Level = 0, Marks = 0, Milestone = 0, Progress = 0, Season = 0 }
	local nextLevel = math.max(2, e.Level + 1)
	local goal = Mastery.milestone(e.Milestone)
	local base = Mastery.total(math.max(1, e.Level))
	return {
		level = e.Level,
		into = math.max(0, e.Points - base),
		need = Mastery.total(nextLevel) - base,
		marks = e.Marks,
		marksNeed = Mastery.marks(nextLevel),
		goal = goal.Grade,
		goalGames = goal.Games,
		progress = e.Progress,
		title = e.Level >= SETTINGS.Title,
	}
end

return Mastery
