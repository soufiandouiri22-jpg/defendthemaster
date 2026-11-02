-- The arena's traps (Config.Spikes, FireGrates, NetStatues; Map.Features, ColosseumBuilder). The spike tiles and fire
-- grates keep the server's clock (Shared.Hazards): when a tile's spikes stand up they strike each living hero, player
-- or bot, of either team, standing on it once; while a grate burns it hurts each hero near its middle every Tick. Both
-- take a share of the hero's maximum health, whatever his Armor and Resist, shown as any hit (Net.HeroHit); an enemy
-- who hurt him just before still gets the kill. A net statue is fired by a player's hero beside it (Net.NetStatue, the
-- statue's "Index"): it carries when it was fired, by which team, and when it is ready again
-- ("FiredAt", "FiredBy", "ReadyAt", server time); its net lands Flight seconds later on every enemy of that team in
-- front of it, who carries until when it holds him ("Netted") and walks slower until then (Items.walkSpeed); the
-- clients are told whom it caught (Net.NetStatue: the statue's Index, the heroes, until when).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hazards = require(ReplicatedStorage.Shared.Hazards)
local Items = require(ReplicatedStorage.Shared.Items)
local Actors = require(script.Parent.Actors)

local HazardService = {}

local SPIKES, FIRE, NETS = Config.Spikes, Config.FireGrates, Config.NetStatues
-- A hero's root stands about this high over his feet; who is higher than this over a trap is jumping over it.
local ABOVE = 5

type Hero = {
	actor: Instance,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
}

local hitEvent: RemoteEvent
local netEvent: RemoteEvent
-- Per spike tile, the heroes its spikes already struck since they rose.
local struck: { [number]: { [Model]: boolean } } = {}
local spikesUp = false
local burnedAt = -math.huge

local function heroes(): { Hero }
	local list = {}
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and humanoid and root and humanoid.Health > 0 then
			table.insert(list, { actor = actor, character = character, humanoid = humanoid, root = root })
		end
	end
	return list
end

local function hurt(hero: Hero, share: number)
	local amount = math.round(hero.humanoid.MaxHealth * share)
	hitEvent:FireAllClients(hero.character, amount, hero.root.Position, nil)
	hero.humanoid:TakeDamage(amount)
end

-- Whether `hero` stands within `radius` of `at` on the sand.
local function on(hero: Hero, at: Vector3, radius: number): boolean
	local offset = hero.root.Position - at
	return offset.Y <= ABOVE and Vector2.new(offset.X, offset.Z).Magnitude <= radius
end

-- Whether `hero` stands on the square `half` studs to each side of the middle of `frame`, along its own sides.
local function onSquare(hero: Hero, frame: CFrame, half: number): boolean
	local offset = frame:PointToObjectSpace(hero.root.Position)
	return offset.Y <= ABOVE and math.abs(offset.X) <= half and math.abs(offset.Z) <= half
end

local function stepSpikes(now: number)
	local phase = Hazards.phase(SPIKES, now)
	local up = phase == "Strike"
	if up and not spikesUp then
		table.clear(struck)
	end
	spikesUp = up
	if not up then
		return
	end
	local list = heroes()
	for i, spot in SPIKES.Spots do
		local done = struck[i] or {}
		struck[i] = done
		local frame = CFrame.new(spot.At) * CFrame.Angles(0, math.rad(spot.Turn), 0)
		for _, hero in list do
			if not done[hero.character] and onSquare(hero, frame, SPIKES.Width / 2) then
				done[hero.character] = true
				hurt(hero, SPIKES.Damage)
			end
		end
	end
end

local function stepFire(now: number)
	local phase = Hazards.phase(FIRE, now)
	if phase ~= "Strike" or now - burnedAt < FIRE.Tick then
		return
	end
	burnedAt = now
	local list = heroes()
	for _, at in FIRE.Spots do
		for _, hero in list do
			if on(hero, at, FIRE.Radius) then
				hurt(hero, FIRE.Damage)
			end
		end
	end
end

-- Slows `hero` until `untilAt` (server time), and lets him go then unless another net caught him since.
local function net(hero: Hero, untilAt: number)
	hero.actor:SetAttribute("Netted", untilAt)
	hero.humanoid.WalkSpeed = Items.walkSpeed(hero.actor)
	task.delay(untilAt - Workspace:GetServerTimeNow(), function()
		if hero.actor:GetAttribute("Netted") == untilAt and hero.humanoid.Parent then
			hero.humanoid.WalkSpeed = Items.walkSpeed(hero.actor)
		end
	end)
end

local function fire(statue: Model, team: string)
	local now = Workspace:GetServerTimeNow()
	statue:SetAttribute("FiredAt", now)
	statue:SetAttribute("FiredBy", team)
	statue:SetAttribute("ReadyAt", now + NETS.Cooldown)
	local at = statue:GetPivot().Position
	local front = (statue:GetPivot().LookVector * Vector3.new(1, 0, 1)).Unit
	task.delay(NETS.Flight, function()
		local reach = math.cos(math.rad(NETS.Angle))
		local untilAt = Workspace:GetServerTimeNow() + NETS.Length
		local caught = {}
		for _, hero in heroes() do
			local offset = (hero.root.Position - at) * Vector3.new(1, 0, 1)
			local distance = offset.Magnitude
			if
				hero.actor:GetAttribute("Team") ~= team
				and distance <= NETS.Range
				and distance > 0
				and offset.Unit:Dot(front) >= reach
			then
				net(hero, untilAt)
				table.insert(caught, hero.character)
			end
		end
		netEvent:FireAllClients(statue:GetAttribute("Index"), caught, untilAt)
	end)
end

local function startNets(statues: Folder)
	local list = statues:GetChildren()
	for i, statue in list do
		statue:SetAttribute("Index", i)
		statue:SetAttribute("ReadyAt", 0)
	end
	netEvent = Instance.new("RemoteEvent")
	netEvent.Name = "NetStatue"
	netEvent.OnServerEvent:Connect(function(player: Player, index: unknown)
		local statue = type(index) == "number" and list[index]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local team = player:GetAttribute("Team")
		if not statue or not statue:IsA("Model") or not humanoid or not root or humanoid.Health <= 0 or not team then
			return
		end
		if (statue:GetAttribute("ReadyAt") or 0) > Workspace:GetServerTimeNow() then
			return
		end
		local offset = (root.Position - statue:GetPivot().Position) * Vector3.new(1, 0, 1)
		-- A little more than the prompt's reach, for the time the client's position takes to arrive.
		if offset.Magnitude > NETS.Reach + 3 then
			return
		end
		fire(statue, team)
	end)
	netEvent.Parent = ReplicatedStorage:WaitForChild("Net")
end

export type Layout = {
	map: Folder,
}

function HazardService.start(layout: Layout)
	hitEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("HeroHit") :: RemoteEvent
	local features = layout.map:FindFirstChild("Features")
	local statues = features and features:FindFirstChild("NetStatues")
	if statues and statues:IsA("Folder") then
		startNets(statues)
	end
	if not SPIKES.Enabled and not FIRE.Enabled then
		return
	end
	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		if SPIKES.Enabled then
			stepSpikes(now)
		end
		if FIRE.Enabled then
			stepFire(now)
		end
	end)
end

return HazardService
