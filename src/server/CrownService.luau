-- The Sun Crown (Config.Crown), the objective on the plateau in the middle. Its state is on Workspace for the clients:
-- "Crown" ("Waiting", "Ready" on the plateau, "Carried" or "Dropped"), "CrownAt" (the server time it appears while
-- waiting), "CrownSpot" (where it floats while ready or dropped), "CrownEnds" (the server time it fades, once taken),
-- and "CrownTeam" (the carrier's team). The carrier's hero has the attribute "Crown". Damage gives the carrier's team
-- its extra damage.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Actors = require(script.Parent.Actors)

local SETTINGS = Config.Crown
local TICK = 0.1
-- A hero's root stands this high over his feet.
local ROOT_HEIGHT = 3

local CrownService = {}

type Hero = { actor: Instance, character: Model, root: BasePart, humanoid: Humanoid, team: string }

local top: Vector3
local map: Folder
local carrier: Hero? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function heroes(): { Hero }
	local all = {}
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local team = character and character:GetAttribute("Team")
		if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and team then
			table.insert(all, { actor = actor, character = character, root = root, humanoid = humanoid, team = team })
		end
	end
	return all
end

-- The floor under `at`, from the map.
local function ground(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local hit = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else Vector3.new(at.X, 0, at.Z)
end

local function place(state: string, spot: Vector3?)
	Workspace:SetAttribute("Crown", state)
	Workspace:SetAttribute("CrownSpot", spot)
end

local function take(hero: Hero)
	carrier = hero
	hero.character:SetAttribute("Crown", true)
	if not Workspace:GetAttribute("CrownEnds") then
		Workspace:SetAttribute("CrownEnds", now() + SETTINGS.Lasts)
	end
	Workspace:SetAttribute("CrownTeam", hero.team)
	place("Carried", nil)
end

local function letGo()
	if carrier and carrier.character.Parent then
		carrier.character:SetAttribute("Crown", nil)
	end
	carrier = nil
	Workspace:SetAttribute("CrownTeam", nil)
end

local function fade(at: number)
	letGo()
	Workspace:SetAttribute("CrownEnds", nil)
	Workspace:SetAttribute("CrownAt", at)
	place("Waiting", nil)
end

-- The hero nearest the crown at `spot` who touches it: within `Reach` of it, his feet near the floor under it.
local function toucher(spot: Vector3): Hero?
	local floor = spot.Y - SETTINGS.Float
	local nearest: Hero? = nil
	local best = SETTINGS.Reach
	for _, hero in heroes() do
		local distance = HeroKit.flat(hero.root.Position - spot).Magnitude
		if distance <= best and math.abs(hero.root.Position.Y - ROOT_HEIGHT - floor) < 3 then
			nearest, best = hero, distance
		end
	end
	return nearest
end

local function step()
	local state = Workspace:GetAttribute("Crown")
	local ends = Workspace:GetAttribute("CrownEnds")
	if ends and now() >= ends then
		fade(now() + SETTINGS.Gap)
		return
	end
	if state == "Waiting" then
		if now() >= (Workspace:GetAttribute("CrownAt") or math.huge) then
			place("Ready", top + Vector3.new(0, SETTINGS.Float, 0))
		end
	elseif state == "Carried" then
		local hero = carrier
		local alive = hero
			and hero.character.Parent ~= nil
			and Actors.character(hero.actor) == hero.character
			and hero.humanoid.Health > 0
		if hero and not alive then
			local fell = ground(hero.root.Position)
			letGo()
			place("Dropped", fell + Vector3.new(0, SETTINGS.Float, 0))
		end
	elseif state == "Ready" or state == "Dropped" then
		local spot = Workspace:GetAttribute("CrownSpot")
		local hero = if typeof(spot) == "Vector3" then toucher(spot) else nil
		if hero then
			take(hero)
		end
	end
end

export type Layout = { map: Folder }

function CrownService.start(layout: Layout)
	map = layout.map
	top = ground(Vector3.new(0, 30, 0))
	Workspace:SetAttribute("Crown", "Waiting")
	task.spawn(function()
		while not Workspace:GetAttribute("MatchStart") do
			task.wait(0.2)
		end
		Workspace:SetAttribute("CrownAt", Workspace:GetAttribute("MatchStart") + SETTINGS.FirstAt)
		while true do
			step()
			task.wait(TICK)
		end
	end)
end

return CrownService
