-- A showroom of every motion of the Scythe Wielder pack, to choose Mortael's attacks from (as Mavorak's,
-- elementalist_showroom.luau). It clones the player's own hero (Mortael on the test ground, Workspace attribute
-- "TestHero", with "TestMinions" unticked so no minions stand in it) and plays the clips on each clone through
-- Shared.Motion, as the game does, scythe included. A clip Mortael uses now carries its key in its label.
-- Run it in Play on the client (Studio command bar on the Client, or the Studio MCP): it builds a platform high above
-- the arena with one clone per motion, each repeating its motion under a label with its number and name, and puts the
-- player's character on the platform. Nothing of it reaches the server. Run it again to rebuild it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Motion = require(ReplicatedStorage.Shared.Motion)

local PACK = "ScytheWielder"
local IDLE = "RA-SCW-015"
local CLIPS = 86

local COLUMNS = 10
local SPACING = 20
local ORIGIN = Vector3.new(0, 400, 0)
local PAUSE = 0.8
local LONGEST = 8

-- The keys each clip is on now.
local keys: { [string]: { string } } = {}
local function mark(id: string?, key: string)
	if id then
		keys[id] = keys[id] or {}
		table.insert(keys[id], key)
	end
end
for key, kit in Config.Heroes.Mortael.Kit do
	if kit.Hits and kit.Kind == "Combo" then
		for step, hit in kit.Hits do
			mark(hit.Motion, key .. " " .. step)
		end
	else
		mark(kit.Motion, key)
	end
end
for name, id in Config.Heroes.Mortael.Motions do
	mark(id, name)
end

local old = workspace:FindFirstChild("Showroom")
if old then
	old:Destroy()
end
local room = Instance.new("Folder")
room.Name = "Showroom"
room.Parent = workspace

local character = Players.LocalPlayer.Character
assert(character and character:FindFirstChild("Weapons"), "the hero has not loaded yet")
character.Archivable = true
local template = character:Clone()
character.Archivable = false
for _, d in template:GetDescendants() do
	-- A Highlight would be the white flash of his spawn or a hit, caught at the moment of cloning.
	if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("Highlight") then
		d:Destroy()
	end
end
-- Without the hero's tags and attributes the game's HeroAnimator leaves the clones alone, instead of standing them in
-- their idle every frame.
for _, tag in template:GetTags() do
	template:RemoveTag(tag)
end
for name in template:GetAttributes() do
	template:SetAttribute(name, nil)
end
local humanoid = template:FindFirstChildOfClass("Humanoid") :: Humanoid
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
humanoid.EvaluateStateMachine = false

local rows = math.ceil(CLIPS / COLUMNS)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(COLUMNS * SPACING + 16, 1, rows * SPACING + 24)
floor.CFrame = CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, -0.5, (rows - 1) * SPACING / 2 + 6))
floor.Color = Color3.fromRGB(70, 64, 60)
floor.Material = Enum.Material.Slate
floor.Parent = room

local motions = {}
for index = 1, CLIPS do
	local column = (index - 1) % COLUMNS
	local row = (index - 1) // COLUMNS
	local id = string.format("RA-SCW-%03d", index)
	local meta = Motion.meta(PACK, id)
	local rig = template:Clone()
	rig.Name = id
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	-- The clones face the player's start at the platform's front edge (towards -Z), standing on the floor.
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local height = hum.HipHeight + root.Size.Y / 2
	local target = CFrame.lookAt(
		ORIGIN + Vector3.new(column * SPACING, height, row * SPACING),
		ORIGIN + Vector3.new(column * SPACING, height, row * SPACING - 1)
	)
	rig:PivotTo(target * root.CFrame:ToObjectSpace(rig:GetPivot()))
	-- The game's health bar (HeroBar) finds every hero model; here it would cover the labels.
	rig.ChildAdded:Connect(function(child)
		if child.Name == "HeroBar" then
			task.defer(child.Destroy, child)
		end
	end)
	rig.Parent = room

	-- Sized in studs, so the labels shrink with distance and never cover each other.
	local used = keys[id]
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(8, if used then 3.4 else 2.6)
	board.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	board.LightInfluence = 0
	board.Adornee = rig:FindFirstChild("Head") :: BasePart
	board.Parent = rig
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = if used then Color3.fromRGB(120, 44, 12) else Color3.fromRGB(28, 24, 22)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = string.format("%03d  %.1fs\n%s", index, meta.duration, (meta :: any).name or "")
	if used then
		label.Text ..= "\n[" .. table.concat(used, ", ") .. "]"
	end
	label.Parent = board

	local m = Motion.new(rig, PACK)
	m:setBase(IDLE, 1)
	table.insert(motions, { motion = m, id = id, next = 0 })
end

-- Restarted from the frame loop: threads spawned by a Studio command end when the command does.
local clock = 0
local connection
connection = RunService.RenderStepped:Connect(function(dt)
	if not room.Parent then
		connection:Disconnect()
		return
	end
	clock += dt
	for _, entry in motions do
		if clock >= entry.next then
			local length = entry.motion:play(entry.id, 1, 0, true)
			entry.next = clock + math.min(length, LONGEST) + PAUSE
		end
		entry.motion:step(dt)
	end
end)

character:PivotTo(CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, 4, -6)))
return CLIPS .. " motions in the showroom"
