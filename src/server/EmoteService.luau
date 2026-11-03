-- The emotes in a match (Config.Emotes): a player asks for one he has (Net.Emote, from the wheel on G) while his hero
-- stands alive and still, at most once every `Cooldown` seconds, and his hero carries it as its "Emote" attribute
-- ("<id>@<server time>", so the same one again starts over) for every client to dance it (HeroAnimator). The dance ends
-- when he moves, attacks (CombatService) or is hit, and with his death.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileService = require(script.Parent.ProfileService)
local Remote = require(script.Parent.Remote)

local EmoteService = {}

local SETTINGS = Config.Emotes
-- Faster than this over the ground (studs a second), he is walking.
local MOVING = 2

local dancing: { [Model]: { health: number } } = {}
local last: { [Player]: number } = {}

local function speed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- Ends `character`'s dance, if he dances.
function EmoteService.stop(character: Model?)
	if character and dancing[character] then
		dancing[character] = nil
		character:SetAttribute("Emote", nil)
	end
end

local function begin(player: Player, id: unknown)
	if typeof(id) ~= "string" or not SETTINGS.List[id] then
		return
	end
	local data = ProfileService.get(player)
	if not data or not table.find(Profile.wheel(data), id) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if not CollectionService:HasTag(character, "Combatant") or speed(root) > MOVING then
		return
	end
	local now = os.clock()
	if now - (last[player] or -math.huge) < SETTINGS.Cooldown then
		return
	end
	last[player] = now
	dancing[character] = { health = humanoid.Health }
	character:SetAttribute("Emote", id .. "@" .. string.format("%.2f", Workspace:GetServerTimeNow()))
end

function EmoteService.start()
	Remote.event("Emote", 2, begin)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		for character, state in dancing do
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if
				not character.Parent
				or not humanoid
				or not root
				or humanoid.Health <= 0
				or humanoid.Health < state.health - 0.01
				or speed(root) > MOVING
			then
				EmoteService.stop(character)
			else
				state.health = math.max(state.health, humanoid.Health)
			end
		end
	end)
end

return EmoteService
