-- The jump pads (Config.JumpPads; Map.Features.JumpPads, ColosseumBuilder, each carrying its "Index" and where it
-- throws, "To"). The player's own hero, whose movement his client owns, is thrown by HeroControls.launch from a pad he
-- jumps onto in a high arc to that spot, landing on whatever is there (the plateau, or the sand); he may attack all the
-- way. While he flies he carries until when ("Flying", server time): set here at once for his own client, and by the
-- server for everyone else's (Net.JumpPad, JumpPadService), so every HeroAnimator holds him in the jump's flight until
-- he is down. The pad's light flares and it sounds as he leaves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroControls = require(script.Parent.HeroControls)
local UiSound = require(script.Parent.UiSound)

local JumpPadView = {}

local SETTINGS = Config.JumpPads
local player = Players.LocalPlayer
local GLOW = Color3.fromRGB(255, 214, 120)
-- A hero takes off within this many studs of a pad's edge inward, and no higher over its top than this.
local INSIDE, ABOVE = 0.8, 4.5
-- Only a hero who jumps onto a pad takes off (owner, 2026-11-02), not one who walks onto it, and only as he comes down
-- on it (one who jumps from it lands on it first): falling over it, or touched down on it at most this many seconds ago.
local LANDED = 0.25
-- A pad's light at rest and as a hero leaves it, and how long that flare lasts.
local LIGHT_REST, LIGHT_FLARE, FLARE = 0.5, 4, 0.6

type Pad = {
	index: number,
	at: Vector3,
	to: Vector3,
	top: number,
	light: PointLight,
	flared: number,
}

local pads: { Pad } = {}
local flying = false
local restingUntil = 0
local airborneAt = -math.huge
local event: RemoteEvent?

-- Where the hero lands from `pad`: on whatever is under the spot it throws to, his root over it.
local function landing(pad: Pad, character: Model, rootHeight: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(pad.to + Vector3.new(0, 80, 0), Vector3.new(0, -160, 0), params)
	local ground = if hit then hit.Position.Y else 0
	return Vector3.new(pad.to.X, ground + rootHeight, pad.to.Z)
end

local function step()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if flying or not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local state = humanoid:GetState()
	local aloft = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if aloft then
		airborneAt = now
	end
	local comingDown = if aloft then root.AssemblyLinearVelocity.Y < 0 else now - airborneAt <= LANDED
	if now < restingUntil or not comingDown then
		return
	end
	for _, pad in pads do
		local offset = root.Position - pad.at
		local flat = Vector2.new(offset.X, offset.Z).Magnitude
		if flat > SETTINGS.Width / 2 - INSIDE or root.Position.Y - pad.top > ABOVE then
			continue
		end
		local to = landing(pad, character, humanoid.HipHeight + root.Size.Y / 2)
		local length = math.max(SETTINGS.Flight, ((pad.to - pad.at) * Vector3.new(1, 0, 1)).Magnitude / SETTINGS.Speed)
		local function ended()
			flying = false
			restingUntil = os.clock() + SETTINGS.Again
			if character.Parent then
				character:SetAttribute("Flying", nil)
			end
			if event then
				event:FireServer("Land")
			end
		end
		if HeroControls.launch(to, SETTINGS.Height, length, ended) then
			flying = true
			character:SetAttribute("Flying", Workspace:GetServerTimeNow() + length)
			if event then
				event:FireServer(pad.index)
			end
			pad.flared = now
			UiSound.at("JumpPad", pad.at)
		end
		return
	end
end

local function update()
	local now = os.clock()
	for _, pad in pads do
		local flaring = math.clamp(1 - (now - pad.flared) / FLARE, 0, 1)
		pad.light.Brightness = LIGHT_REST + math.sin(now * 3) * 0.15 + flaring * LIGHT_FLARE
	end
end

function JumpPadView.start()
	if not SETTINGS.Enabled then
		return
	end
	local map = Workspace:WaitForChild("Map", 30)
	local features = map and map:WaitForChild("Features", 30)
	local folder = features and features:WaitForChild("JumpPads", 10)
	if not folder then
		return
	end
	event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("JumpPad", 10) :: RemoteEvent?
	for _, model in folder:GetChildren() do
		local index, to = model:GetAttribute("Index"), model:GetAttribute("To")
		if not model:IsA("Model") or type(index) ~= "number" or typeof(to) ~= "Vector3" then
			continue
		end
		local _, size = model:GetBoundingBox()
		local pivot = model:GetPivot().Position
		local holder = Instance.new("Part")
		holder.Name = "JumpPadLight"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(pivot + Vector3.new(0, size.Y + 1, 0))
		local light = Instance.new("PointLight")
		light.Color = GLOW
		light.Range = 10
		light.Brightness = LIGHT_REST
		light.Shadows = false
		light.Parent = holder
		holder.Parent = model
		table.insert(pads, {
			index = index,
			at = pivot * Vector3.new(1, 0, 1),
			to = to,
			top = pivot.Y + size.Y,
			light = light,
			flared = -math.huge,
		})
	end
	RunService.Heartbeat:Connect(step)
	RunService.RenderStepped:Connect(update)
end

return JumpPadView
