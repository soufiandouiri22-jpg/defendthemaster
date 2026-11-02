-- The four portals (design 03, Config.Portals, Shared.Portals): the kit's stone ring on its round pad beside each
-- armory stall, in two pairs across the centre (Map.Portals, each a model with its "Portal" name). The ring's mesh
-- does not collide (its own collision would close the opening); unseen stones in its place do, round the opening, and
-- its pad's two steps. Every frame the server looks who crossed an opening since the last: a living hero, player or
-- bot, who walked through one, from either side, comes out of the one it leads to, Exit studs past its ring on the
-- side he was walking to and facing that way, so he walks on as he went; then for Again seconds no portal takes him.
-- Each jump is told to the clients (Net.PortalJump: from, to, the hero) for its light and sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Portals = require(ReplicatedStorage.Shared.Portals)
local Actors = require(script.Parent.Actors)
local ColosseumBuilder = require(script.Parent.ColosseumBuilder)

local PortalService = {}

local SETTINGS = Config.Portals
local Kit = ColosseumBuilder.Kit
-- A hero's root stands this high over his feet.
local ROOT_HEIGHT = 3
-- How far inside the opening's edge a hero's root must pass to go through (his own breadth).
local BREADTH = 0.8
-- The unseen stones round the opening: how many, and from where to where they run (degrees from the ring's right,
-- over the top; the ring stands on the pad below that).
local STONES, FROM, TO = 14, -40, 220

local portals = Portals.all()
local last: { [Model]: Vector3 } = {}
local resting: { [Model]: number } = {}
local jumpEvent: RemoteEvent

local function blocker(parent: Instance, size: Vector3, cf: CFrame, round: boolean?)
	local p = Instance.new("Part")
	p.Name = "PortalCollision"
	p.Anchored = true
	p.Transparency = 1
	p.CastShadow = false
	p.CanTouch = false
	if round then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
end

local function build(parent: Instance, portal: Portals.Portal)
	local model = Instance.new("Model")
	model.Name = "Portal"
	model:SetAttribute("Portal", portal.name)
	Kit.kit(model, "portal_ring", portal.frame, SETTINGS.Scale, false)
	for _, step in portal.steps do
		local cf = portal.frame * CFrame.new(0, step.top / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		blocker(model, Vector3.new(step.top, step.radius * 2, step.radius * 2), cf, true)
	end
	local middle = (portal.holeRadius + portal.stonesOut) / 2
	local turn = math.rad(TO - FROM) / STONES
	for i = 0, STONES - 1 do
		local a = math.rad(FROM) + turn * (i + 0.5)
		local at = portal.hole + Vector3.new(math.cos(a), math.sin(a), 0) * middle
		local size = Vector3.new(
			portal.stonesOut - portal.holeRadius,
			2 * middle * math.sin(turn / 2) + 0.4,
			portal.stonesDepth * 2
		)
		blocker(model, size, portal.frame * CFrame.new(at) * CFrame.Angles(0, 0, a))
	end
	model.Parent = parent
end

-- Which way (+1 or -1 along the ring's Z) the root going from `before` to `now` crossed `portal`'s opening, if it did.
local function crossed(portal: Portals.Portal, before: Vector3, now: Vector3): number?
	local a = portal.frame:PointToObjectSpace(before)
	local b = portal.frame:PointToObjectSpace(now)
	if (a.Z < 0) == (b.Z < 0) or math.abs(b.Z - a.Z) > portal.stonesOut then
		return nil
	end
	local at = a:Lerp(b, a.Z / (a.Z - b.Z))
	if Vector2.new(at.X, at.Y - portal.hole.Y).Magnitude > portal.holeRadius - BREADTH then
		return nil
	end
	return if b.Z > a.Z then 1 else -1
end

local function jump(character: Model, from: Portals.Portal, way: number)
	local to = portals[Portals.other(from.name)]
	local heading = from.frame:VectorToWorldSpace(Vector3.new(0, 0, way))
	local side = if to.frame:VectorToObjectSpace(heading).Z > 0 then 1 else -1
	local at = to.frame * Vector3.new(0, to.top + ROOT_HEIGHT + 0.2, side * SETTINGS.Exit)
	character:PivotTo(CFrame.lookAt(at, at + heading))
	last[character] = at
	resting[character] = os.clock() + SETTINGS.Again
	jumpEvent:FireAllClients(from.name, to.name, character)
end

local function step()
	local now = os.clock()
	local seen = {}
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		seen[character] = true
		local position = root.Position
		local before = last[character]
		last[character] = position
		if not before or (resting[character] or 0) > now then
			continue
		end
		for _, portal in portals do
			local way = crossed(portal, before, position)
			if way then
				jump(character, portal, way)
				break
			end
		end
	end
	for character in last do
		if not seen[character] then
			last[character] = nil
			resting[character] = nil
		end
	end
end

export type Layout = {
	map: Folder,
}

function PortalService.start(layout: Layout)
	if not SETTINGS.Enabled then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Portals"
	for _, portal in portals do
		build(folder, portal)
	end
	folder.Parent = layout.map
	jumpEvent = Instance.new("RemoteEvent")
	jumpEvent.Name = "PortalJump"
	jumpEvent.Parent = ReplicatedStorage:WaitForChild("Net")
	RunService.Heartbeat:Connect(step)
end

return PortalService
