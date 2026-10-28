-- Studio's test ground for trying heroes and the Master: with the Workspace attribute "TestGround" ticked in Studio,
-- Play opens on both Masters' throne rooms on open sand (ColosseumBuilder.buildTestGround) instead of the colosseum,
-- the fight starts at once before the Red Master's, and no bots or minion waves come. A live server never reads it.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TestGround = {}

function TestGround.on(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute("TestGround") == true
end

-- The teams whose Master sits on a throne there.
TestGround.MASTERS = { "Blue", "Red" }

return TestGround
