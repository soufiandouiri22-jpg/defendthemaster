-- The spawn pads heal (design 03, Config.Pads): every Tick each hero, player or bot, who stands on one of his own
-- team's pads gains Heal of his health, unless an enemy (a hero, a minion or a Master) hurt him in the last
-- CombatPause seconds, so nobody can wait there for his attackers and win on its healing. Each heal is
-- told to the clients (Net.PadHeal: the hero, how much) for its light and its number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Actors = require(script.Parent.Actors)
local Damage = require(script.Parent.Damage)
local ProgressService = require(script.Parent.ProgressService)

local PadService = {}

local SETTINGS = Config.Pads
-- How far above a pad's top a hero's root may be and still stand on it.
local REACH_UP = 6

type Pad = {
	team: string,
	centre: Vector3,
	radius: number,
	top: number,
}

local pads: { Pad } = {}
local healEvent: RemoteEvent

local function onOwnPad(team: string, position: Vector3): boolean
	for _, pad in pads do
		if
			pad.team == team
			and HeroKit.flat(position - pad.centre).Magnitude <= pad.radius
			and position.Y >= pad.top - 1
			and position.Y <= pad.top + REACH_UP
		then
			return true
		end
	end
	return false
end

local function heal()
	local now = os.clock()
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		local missing = humanoid.MaxHealth - humanoid.Health
		local hurt = ProgressService.hurtAt(character)
		if
			missing >= 1
			and (not hurt or now - hurt >= SETTINGS.CombatPause)
			and onOwnPad(character:GetAttribute("Team"), root.Position)
		then
			local amount = math.min(missing, humanoid.MaxHealth * SETTINGS.Heal * SETTINGS.Tick * Damage.healing(actor))
			humanoid.Health += amount
			healEvent:FireAllClients(character, math.round(amount))
		end
	end
end

export type Layout = {
	map: Folder,
}

function PadService.start(layout: Layout)
	for _, model in layout.map:GetDescendants() do
		if model:IsA("Model") and model.Name == "SpawnPad" then
			local box, size = model:GetBoundingBox()
			table.insert(pads, {
				team = model:GetAttribute("Team"),
				centre = box.Position,
				radius = math.max(size.X, size.Z) / 2,
				top = box.Position.Y + size.Y / 2,
			})
		end
	end
	local net = ReplicatedStorage:WaitForChild("Net")
	healEvent = Instance.new("RemoteEvent")
	healEvent.Name = "PadHeal"
	healEvent.Parent = net
	task.spawn(function()
		while true do
			task.wait(SETTINGS.Tick)
			heal()
		end
	end)
end

return PadService
