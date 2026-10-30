-- Studio's test ground for trying heroes and the Master: with the Workspace attribute "TestGround" ticked in Studio,
-- Play opens on both Masters' throne rooms on open sand (ColosseumBuilder.buildTestGround) instead of the colosseum,
-- the fight starts at once before the Red Master's, and no bots or minion waves come; only MINIONS red minions in front
-- of the player's hero once he has loaded, each back RESPAWN seconds after it dies (TestGround.minions). A live server
-- never reads it.
-- The Workspace attribute "TestHero" (a hero's name) is the hero the player tries there; without it the default. Every
-- ability is learned there from the start (ProgressService.join). With "TestMinions" unticked no minions come (a
-- showroom of motions, Tools/Showroom), and none come back until it is ticked again.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remote = require(script.Parent.Remote)

local TestGround = {}

-- How many minions stand there, how far in front of the hero, how far apart, and how soon a dead one comes back.
local MINIONS, AHEAD, APART, RESPAWN = 2, 22, 5, 3

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

-- Puts the minions in a row in front of where the first player's hero stands once his loading screen is gone (he
-- says so through Net.TestGroundLoaded), each through `spawnAt` (MinionService.spawnAt) and again RESPAWN seconds
-- after it dies.
function TestGround.minions(spawnAt: (team: string, kind: string, at: Vector3) -> BasePart?)
	if Workspace:GetAttribute("TestMinions") == false then
		return
	end
	local loaded: Player? = nil
	Remote.event("TestGroundLoaded", 1, function(player: Player)
		loaded = loaded or player
	end)
	task.spawn(function()
		local root: BasePart? = nil
		while not root do
			local player = loaded
			root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			task.wait(0.5)
		end
		local hero = root :: BasePart
		local look = (hero.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		local right = look:Cross(Vector3.yAxis)
		for i = 1, MINIONS do
			local spot = hero.Position + look * AHEAD + right * (i - (MINIONS + 1) / 2) * APART
			local function keep()
				local minion = if Workspace:GetAttribute("TestMinions") == false
					then nil
					else spawnAt("Red", "Spitter", spot)
				if not minion then
					task.delay(RESPAWN, keep)
					return
				end
				minion:GetAttributeChangedSignal("Dead"):Once(function()
					task.delay(RESPAWN, keep)
				end)
			end
			keep()
		end
	end)
end

return TestGround
