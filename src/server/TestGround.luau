-- Studio's test ground for trying heroes and the Master: with the Workspace attribute "TestGround" ticked in Studio,
-- Play opens on both Masters' throne rooms on open sand (ColosseumBuilder.buildTestGround) instead of the colosseum,
-- the fight starts at once before the Red Master's, and no bots or minion waves come. A live server never reads it.
-- The Workspace attribute "TestHero" (a hero's name) is the hero the player tries there; without it the default. Every
-- ability is learned there from the start (ProgressService.join).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TestGround = {}

function TestGround.on(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute("TestGround") == true
end

-- The hero to try on the test ground, if one is named.
function TestGround.hero(): string?
	local hero = Workspace:GetAttribute("TestHero")
	return if TestGround.on() and type(hero) == "string" and hero ~= "" then hero else nil
end

-- The teams whose Master sits on a throne there.
TestGround.MASTERS = { "Blue", "Red" }

return TestGround
