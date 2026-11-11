-- The way to a tip's goal in the first matches (Tips, Path.set): a smooth gold line of dashes lying on the sand from
-- the player's feet along the way the pathfinder finds round walls and pillars, its curves rounded off, the dashes
-- marching towards the goal (a bright core in a wider glow) over a faint glow showing the whole way; at the goal
-- a beacon (a column of light, a ring pulsing on the ground and a bouncing arrow over it, seen through walls); and while
-- the goal is off the screen, a gold arrow round the screen's middle pointing to it.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)

local Path = {}

local GOLD = Color3.fromRGB(255, 206, 74)
-- The line: how far apart its points lie, how many at most (so how long it is), how far before the player's feet it
-- begins, and over how many studs it fades in there and out before the goal.
local STEP, POINTS, FIRST = 1.5, 90, 1.5
local FADE_IN, FADE_OUT = 4, 5
-- It is laid as these lines over each other, the core first: how wide each is, how strongly it shows, its colour, how
-- much it glows and whether it is dashed.
local LAYERS = {
	{ Width = 0.7, Strength = 1, Color = Color3.fromRGB(255, 226, 120), Glow = 0.6, Dashed = true },
	{ Width = 1.6, Strength = 0.55, Color = Color3.fromRGB(255, 176, 40), Glow = 0.3, Dashed = true },
	{ Width = 2.8, Strength = 0.12, Color = Color3.fromRGB(255, 176, 40), Glow = 0.3, Dashed = false },
}
-- The dashes: how long each is, the gap after it, how softly its ends fade and how fast they march to the goal
-- (studs a second). They are counted back from the goal, so they stay put on the sand as the player walks along them.
local DASH, GAP, SOFT, MARCH = 1.8, 1, 0.35, 3
-- Each piece of a dashed layer is this many straight bits, its fading worked out at their ends (at most 19, the
-- most a NumberSequence holds less one).
local SEGMENTS = 16
-- How far it and the beacon's ring lie over the sand (over its lighter and darker patches too, which lie up to 0.18
-- over it and are not hit by the ray down), and how far the player must move before it is laid again.
local LIFT, RELAY = 0.3, 0.25
-- How often the way is looked for again, and how far the goal or the player must have moved for it.
local REPATH, MOVED = 0.5, 3
-- Within this many studs of the goal the line gives way to the beacon alone.
local NEAR = 6
local BEACON_HEIGHT = 26
local EDGE = 70
-- The pointer goes round the middle of the screen on this oval (1080-high units), clear of the tip over it and the
-- HUD at the screen's edges.
local EDGE_RX, EDGE_RY = 400, 200

local player = Players.LocalPlayer
local folder: Folder
-- The line's points (attachments on one part) and the pieces between them, with how far along each point lies.
local line: Part
local knots: { Attachment } = {}
local pieces: { { Beam } } = {}
local along: { number } = {}
local laid = 0
local laidFrom = Vector3.zero
local laidWay: { Vector3 }? = nil
local beacon: { base: Part, column: Part, ring: ImageLabel, sign: BillboardGui, arrow: ImageLabel }
local edge: ImageLabel
local target: Vector3? = nil

local way: { Vector3 } = {}
local wayFrom, wayTo = Vector3.zero, Vector3.zero
local lookedAt = 0
local looking = false

local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Include

local function part(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = folder
	return p
end

-- A flat, unlit image lying on `p`'s top face, its top towards the part's front.
local function decal(p: Part, image: string, colour: Color3): ImageLabel
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = 2.5
	surface.CanvasSize = Vector2.new(256, 256)
	surface.Parent = p
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Image = image
	label.ImageColor3 = colour
	label.Parent = surface
	return label
end

-- The sand under `at`, and which way it faces.
local function floorAt(at: Vector3): (Vector3?, Vector3)
	local map = Workspace:FindFirstChild("Map")
	groundRay.FilterDescendantsInstances = if map then { map } else {}
	local hit = Workspace:Raycast(at + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundRay)
	return if hit then hit.Position else nil, if hit then hit.Normal else Vector3.yAxis
end

-- The sand under `at`.
local function ground(at: Vector3): Vector3?
	return (floorAt(at))
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Looks for the way from `from` to `to` round what stands between, in the background; a straight line until found.
local function lookForWay(from: Vector3, to: Vector3)
	if looking then
		return
	end
	looking = true
	wayFrom, wayTo, lookedAt = from, to, os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
			WaypointSpacing = 4,
		})
		local ok = pcall(function()
			path:ComputeAsync(from, to)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			way = points
		else
			way = { from, to }
		end
		looking = false
	end)
end

-- The point `t` (0 to 1) of the way from `b` to `c`, rounded off through `a` before it and `d` after it (Catmull-Rom).
local function rounded(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * b) + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
end

-- Lays the line along `points` from the player's feet at `from`, its corners rounded off, from FIRST studs before him
-- up to where the sand ends under it or its POINTS run out.
local function layLine(points: { Vector3 }, from: Vector3)
	-- From the waypoint nearest the player on, so the way already walked is left out.
	local start, best = 1, math.huge
	for i, p in points do
		local gap = HeroKit.flat(p - from).Magnitude
		if gap < best then
			start, best = i, gap
		end
	end
	local corners = { from }
	for i = start, #points do
		if HeroKit.flat(points[i] - corners[#corners]).Magnitude > 0.5 then
			table.insert(corners, points[i])
		end
	end
	local spots: { { at: Vector3, normal: Vector3, walked: number } } = {}
	local walked = 0
	local previous = from
	local ended = false
	for i = 1, #corners - 1 do
		local a, b, c, d = corners[math.max(i - 1, 1)], corners[i], corners[i + 1], corners[math.min(i + 2, #corners)]
		local steps = math.max(1, math.ceil(HeroKit.flat(c - b).Magnitude / STEP))
		for s = 1, steps do
			local at = rounded(a, b, c, d, s / steps)
			walked += HeroKit.flat(at - previous).Magnitude
			previous = at
			if walked >= FIRST then
				local floor, normal = floorAt(at)
				if not floor or #spots >= POINTS then
					ended = true
					break
				end
				table.insert(spots, { at = floor + normal * LIFT, normal = normal, walked = walked })
			end
		end
		if ended then
			break
		end
	end
	laid = if #spots >= 2 then #spots else 0
	for k = 1, laid do
		local spot = spots[k]
		local ahead = spots[math.min(k + 1, laid)].at - spots[math.max(k - 1, 1)].at
		local across = ahead:Cross(spot.normal)
		if across.Magnitude < 1e-3 then
			across = Vector3.xAxis
		end
		-- A piece of the line lies flat where its ends' X axes point up.
		knots[k].WorldCFrame = CFrame.fromMatrix(spot.at, spot.normal, across.Unit)
		along[k] = spot.walked - spots[1].walked
	end
	for k, piece in pieces do
		for _, layer in piece do
			layer.Enabled = k < laid
		end
	end
end

-- How much of the line shows `s` studs along it: faded in at the player and out at the goal.
local function faded(s: number): number
	return math.min(math.clamp(s / FADE_IN, 0, 1), math.clamp((along[laid] - s) / FADE_OUT, 0, 1))
end

-- How much of a dash lies `s` studs along the line at `now`: all of it on a dash, none in a gap, soft at its ends.
local function dashed(s: number, now: number): number
	local p = (s - along[laid] - now * MARCH) % (DASH + GAP)
	return math.min(math.clamp(p / SOFT, 0, 1), math.clamp((DASH - p) / SOFT, 0, 1))
end

local function paintLine()
	local now = os.clock()
	for k = 1, laid - 1 do
		local from, to = along[k], along[k + 1]
		local fade: { number } = {}
		local dash: { number } = {}
		for i = 0, SEGMENTS do
			local s = from + (to - from) * i / SEGMENTS
			fade[i + 1], dash[i + 1] = faded(s), dashed(s, now)
		end
		for i, layer in pieces[k] do
			local look = LAYERS[i]
			if look.Dashed then
				local keys = table.create(SEGMENTS + 1)
				for j = 0, SEGMENTS do
					keys[j + 1] =
						NumberSequenceKeypoint.new(j / SEGMENTS, 1 - fade[j + 1] * dash[j + 1] * look.Strength)
				end
				layer.Transparency = NumberSequence.new(keys)
			else
				layer.Transparency =
					NumberSequence.new(1 - fade[1] * look.Strength, 1 - fade[SEGMENTS + 1] * look.Strength)
			end
		end
	end
end

local function hideLine()
	laid = 0
	laidWay = nil
	for _, piece in pieces do
		for _, layer in piece do
			layer.Enabled = false
		end
	end
end

-- Puts the beacon at `at` (nil hides it).
local function placeBeacon(at: Vector3?, from: Vector3?)
	if not at then
		beacon.base.Parent = nil
		beacon.column.Parent = nil
		return
	end
	local floor = ground(at) or at
	local now = os.clock()
	beacon.base.Parent = folder
	beacon.column.Parent = folder
	beacon.base.CFrame = CFrame.new(floor + Vector3.new(0, LIFT, 0))
	beacon.column.CFrame = CFrame.new(floor + Vector3.new(0, BEACON_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beacon.column.Transparency = 0.72 + 0.08 * math.sin(now * 3)
	local pulse = (now * 0.8) % 1
	beacon.ring.Size = UDim2.fromScale(0.4 + 0.6 * pulse, 0.4 + 0.6 * pulse)
	beacon.ring.ImageTransparency = 0.1 + 0.9 * pulse
	beacon.arrow.Position = UDim2.new(0.5, 0, 0, 6 * math.abs(math.sin(now * 4)))
	local distance = if from then math.floor(HeroKit.flat(floor - from).Magnitude) else 0
	local label = beacon.sign:FindFirstChild("Distance") :: TextLabel
	label.Text = distance .. "m"
end

-- The arrow round the screen's middle towards `at` while it is off the screen.
local function pointEdge(at: Vector3?)
	local camera = Workspace.CurrentCamera
	if not at or not camera then
		edge.Visible = false
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(at + Vector3.new(0, 3, 0))
	local size = camera.ViewportSize
	if onScreen and point.Z > 0 then
		edge.Visible = false
		return
	end
	local centre = size / 2
	local direction = Vector2.new(point.X, point.Y) - centre
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	direction = direction.Unit
	local scale = math.max(0.6, size.Y / 1080)
	local k = 1 / math.sqrt((direction.X / (EDGE_RX * scale)) ^ 2 + (direction.Y / (EDGE_RY * scale)) ^ 2)
	local spot = centre + direction * k
	edge.Visible = true
	edge.Position = UDim2.fromOffset(spot.X, spot.Y)
	edge.Rotation = math.deg(math.atan2(direction.X, -direction.Y))
	local bob = 1 + 0.08 * math.sin(os.clock() * 6)
	edge.Size = UDim2.fromOffset(EDGE * scale * bob, EDGE * scale * bob)
end

function Path.start()
	folder = Instance.new("Folder")
	folder.Name = "TipsPath"
	folder.Parent = Workspace
	line = part("Line", Vector3.one)
	line.CFrame = CFrame.new()
	for i = 1, POINTS do
		local knot = Instance.new("Attachment")
		knot.Parent = line
		table.insert(knots, knot)
		if i > 1 then
			local piece = {}
			for _, look in LAYERS do
				local layer = Instance.new("Beam")
				layer.Attachment0, layer.Attachment1 = knots[i - 1], knot
				layer.FaceCamera = false
				layer.Segments = if look.Dashed then SEGMENTS else 1
				layer.Width0, layer.Width1 = look.Width, look.Width
				layer.Color = ColorSequence.new(look.Color)
				layer.LightEmission = look.Glow
				layer.LightInfluence = 0
				layer.Brightness = 1.4
				layer.Enabled = false
				layer.Parent = line
				table.insert(piece, layer)
			end
			table.insert(pieces, piece)
		end
	end
	local base = part("BeaconRing", Vector3.new(9, 0.05, 9))
	local ringImage = decal(base, Assets.PadRing, GOLD)
	ringImage.AnchorPoint = Vector2.one / 2
	ringImage.Position = UDim2.fromScale(0.5, 0.5)
	local column = part("BeaconColumn", Vector3.new(BEACON_HEIGHT, 1.6, 1.6))
	column.Shape = Enum.PartType.Cylinder
	column.Material = Enum.Material.Neon
	column.Color = GOLD
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(90, 110)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = true
	sign.LightInfluence = 0
	sign.Adornee = base
	sign.Parent = base
	local arrow = Instance.new("ImageLabel")
	arrow.BackgroundTransparency = 1
	arrow.Image = Assets.TutorialEdgeArrow
	arrow.Rotation = 180
	arrow.Size = UDim2.fromOffset(64, 64)
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Parent = sign
	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.BackgroundTransparency = 1
	distance.Size = UDim2.new(1, 0, 0, 36)
	distance.Position = UDim2.fromOffset(0, 70)
	distance.Font = Enum.Font.FredokaOne
	distance.TextSize = 30
	distance.TextColor3 = Color3.fromRGB(255, 240, 200)
	distance.TextStrokeTransparency = 0.2
	distance.Text = ""
	distance.Parent = sign
	beacon = { base = base, column = column, ring = ringImage, sign = sign, arrow = arrow }
	base.Parent, column.Parent = nil, nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "TipsEdge"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = player:WaitForChild("PlayerGui")
	screen.DisplayOrder = 9
	edge = Instance.new("ImageLabel")
	edge.BackgroundTransparency = 1
	edge.Image = Assets.TutorialEdgeArrow
	edge.AnchorPoint = Vector2.one / 2
	edge.Visible = false
	edge.Parent = screen

	RunService.RenderStepped:Connect(function()
		local from = rootPosition()
		local goal = target
		if not goal or not from then
			hideLine()
			placeBeacon(nil)
			pointEdge(nil)
			return
		end
		placeBeacon(goal, from)
		pointEdge(goal)
		if HeroKit.flat(goal - from).Magnitude <= NEAR then
			hideLine()
			return
		end
		local stale = os.clock() - lookedAt > REPATH
			and (
				HeroKit.flat(goal - wayTo).Magnitude > MOVED
				or HeroKit.flat(from - wayFrom).Magnitude > MOVED
				or #way == 0
			)
		if stale then
			lookForWay(from, goal)
		end
		if laid == 0 or laidWay ~= way or HeroKit.flat(from - laidFrom).Magnitude > RELAY then
			local points = if #way > 0 then table.clone(way) else { from, goal }
			points[#points] = goal
			layLine(points, from)
			laidWay, laidFrom = way, from
		end
		paintLine()
	end)
end

-- Leads the way to `at` (nil for nowhere).
function Path.set(at: Vector3?)
	target = at
end

return Path
