-- The tips of a new player's first matches (owner, 2026-11-07): no lesson of its own, but in his first
-- Config.FirstMatch.TipGames real matches the HUD shows him the armory and his attacks, one tip at a time on the
-- middle (Tips.Objective, with its keys from Tips.Prompts). First the armory, until he has bought something (owner,
-- 2026-11-11): the way to his team's stall (Tips.Path), there to hold F to open it, and inside it gold frames on what
-- to buy (Tips.Focus); then learning M2 with 1 (once the fight is on it comes before the armory, unless he is in it),
-- attacking with M1 and M2 at anything, the dash, learning and using E and, from level 4, R; and the first time he dies, that B opens the armory while
-- he waits. A tip done is saved in his profile (MenuService's HintSeen, data.SeenHints) and never shows again; one not
-- done comes back in his next match.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Leveling = require(ReplicatedStorage.Shared.Leveling)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Focus = require(script.Focus)
local Objective = require(script.Objective)
local Path = require(script.Path)
local HeroControls = require(script.Parent.HeroControls)
local ProfileClient = require(script.Parent.ProfileClient)
local Shop = require(script.Parent.Shop)
local UiStyle = require(script.Parent.UiStyle)

local Tips = {}

-- How often the tip that is on is looked at.
local LOOK = 0.2

type Tip = {
	id: string,
	task: string,
	keys: { string }?,
	focus: string?,
	-- The tip that must be done before this one comes.
	after: string?,
	-- Shown while the hero is dead rather than alive.
	whileDead: boolean?,
	ready: () -> boolean,
	done: () -> boolean,
	-- Done already without the tip: saved without showing it.
	skip: (() -> boolean)?,
	-- The task and keys as they stand now, for a tip whose task changes as he goes (else `task` and `keys`).
	stage: (() -> (string, { string }?))?,
	goal: (() -> Vector3?)?,
	count: (() -> (number, number))?,
}

local player = Players.LocalPlayer
local seen: { [string]: boolean } = {}
-- The attacks used since the tip that is on came.
local used: { [string]: boolean } = {}

local function fighting(): boolean
	return Workspace:GetAttribute("Phase") == "Fight"
end

local function alive(): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

local function bagCount(): number
	local count = 0
	for _ in Items.bag(player) do
		count += 1
	end
	return count
end

-- The nearest part in Workspace[`folder`] that `wanted` takes, and how far it is.
local function nearest(folder: string, wanted: (BasePart) -> boolean): (Vector3?, number)
	local parts = Workspace:FindFirstChild(folder)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not parts or not root then
		return nil, math.huge
	end
	local best, bestDistance = nil, math.huge
	for _, p in parts:GetChildren() do
		if p:IsA("BasePart") and wanted(p) then
			local distance = (p.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = p.Position, distance
			end
		end
	end
	return best, bestDistance
end

local function learnTip(id: string, key: string, digit: string, name: string, after: string?): Tip
	return {
		id = id,
		task = "Learn your " .. name,
		keys = { digit },
		after = after,
		ready = function()
			return Leveling.canRaise(player, key)
		end,
		done = function()
			return Leveling.rank(player, key) >= 1
		end,
		skip = function()
			return Leveling.rank(player, key) >= 1
		end,
	}
end

local function useTip(id: string, key: string, name: string, after: string): Tip
	return {
		id = id,
		task = "Use your " .. name,
		keys = { key },
		after = after,
		ready = function()
			return fighting() and Leveling.learned(player, key)
		end,
		done = function()
			return used[key] == true
		end,
	}
end

-- Learning M2 waits for the armory in the buy phase, and comes before it once the fight is on, but not while he is in
-- the armory.
local learnM2 = learnTip("LearnM2", "M2", "1", "M2", nil)
learnM2.ready = function()
	return Leveling.canRaise(player, "M2") and (seen.Shop == true or (fighting() and not Shop.isOpen()))
end

-- In this order: the first not done whose `after` is done and that is ready comes, and stays until it is done, no
-- longer ready, or one before it in this list is ready (which comes in its place; the one put aside comes back).
local TIPS: { Tip } = {
	{
		id = "Respawn",
		task = "Press B to shop while you wait",
		keys = { "B" },
		whileDead = true,
		ready = fighting,
		done = function()
			return Shop.isOpen() or alive()
		end,
	},
	learnM2,
	{
		id = "Shop",
		task = "Walk to the armory",
		focus = "Shop",
		ready = function()
			return true
		end,
		-- Also when he bought it while dead (Respawn).
		done = function()
			return bagCount() > 0
		end,
		stage = function()
			if player:GetAttribute("AtShop") == true and not Shop.isOpen() then
				return "Hold F to open the armory", { "F" }
			end
			return "Walk to the armory", nil
		end,
		goal = function()
			if Shop.isOpen() or player:GetAttribute("AtShop") == true then
				return nil
			end
			return (
				nearest("Armories", function(p)
					return p:GetAttribute("Team") == player:GetAttribute("Team")
				end)
			)
		end,
	},
	{
		id = "Attack",
		task = "Attack with M1 and M2",
		keys = { "M1", "M2" },
		after = "LearnM2",
		ready = fighting,
		-- At anything or nothing.
		done = function()
			return used.M1 == true and used.M2 == true
		end,
		count = function()
			return (if used.M1 then 1 else 0) + (if used.M2 then 1 else 0), 2
		end,
	},
	{
		id = "Dash",
		task = "Dash",
		keys = { "Shift" },
		after = "Attack",
		ready = fighting,
		done = function()
			return used.Dash == true
		end,
	},
	learnTip("LearnE", "E", "2", "E", "Dash"),
	useTip("UseE", "E", "E", "LearnE"),
	learnTip("LearnR", "R", "3", "ultimate", "UseE"),
	useTip("UseR", "R", "ultimate", "LearnR"),
}

local current: Tip? = nil
-- What the task under the score board shows (the tip and its task now), and whether the one before it was done
-- (rather than left), so the next waits for it to fly away.
local shownKey: string? = nil
local lastDone = false

local function save(tip: Tip)
	seen[tip.id] = true
	task.spawn(ProfileClient.ask, "HintSeen", "Tip" .. tip.id)
end

local function fits(tip: Tip): boolean
	local phase = Workspace:GetAttribute("Phase")
	return (phase == "Buy" or phase == "Fight") and (if tip.whileDead then not alive() else alive()) and tip.ready()
end

local function pick(): Tip?
	for _, tip in TIPS do
		if seen[tip.id] or (tip.after and not seen[tip.after]) then
			continue
		end
		if tip.skip and tip.skip() then
			save(tip)
			continue
		end
		if fits(tip) then
			return tip
		end
	end
	return nil
end

local function look()
	local tip = current
	if tip then
		if tip.done() then
			save(tip)
			current, lastDone = nil, true
		elseif not fits(tip) then
			current = nil
		end
	end
	local next = pick()
	if next ~= current then
		current = next
		table.clear(used)
		Focus.set(if next then next.focus else nil)
	end
	local on = current
	local goal, keys = nil, nil
	if on then
		goal, keys = on.task, on.keys
		if on.stage then
			goal, keys = on.stage()
		end
	end
	local key = if on then on.id .. ":" .. goal else nil
	if key ~= shownKey then
		shownKey = key
		Objective.set(key, goal, keys, lastDone)
		lastDone = false
	end
	Path.set(if on and on.goal then on.goal() else nil)
	if on and on.count then
		Objective.count(on.count())
	end
end

function Tips.start()
	local data = ProfileClient.await()
	if Profile.newGames(data) >= Config.FirstMatch.TipGames then
		return
	end
	for _, tip in TIPS do
		seen[tip.id] = data.SeenHints["Tip" .. tip.id] == true
	end
	-- Only once the loading screen goes, so the match opens in order: the arena, the buy phase's banner, then the tip.
	Loading.waitGone()
	local gui = UiStyle.screen("Tips", player:WaitForChild("PlayerGui"), 9)
	Objective.build(gui)
	Focus.start()
	Path.start()
	HeroControls.onCast(function(key)
		used[key] = true
	end)
	while true do
		look()
		task.wait(LOOK)
	end
end

return Tips
