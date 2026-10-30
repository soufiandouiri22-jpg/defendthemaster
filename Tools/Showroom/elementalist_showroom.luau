-- A showroom of the Elementalist pack's fighting motions, to choose Mavorak's attacks from (as Rowan's,
-- ranger_showroom.luau). The Elementalist's ComponentPlayer only samples its clips, so this clones the player's own
-- hero (Mavorak on the test ground, Workspace attribute "TestHero", with "TestMinions" unticked so no minions stand in
-- it) and plays the clips on each clone through Shared.Motion, as the game does, staff included.
-- Run it in Play on the client (Studio command bar on the Client, or the Studio MCP): it builds a platform high above
-- the arena with one clone per motion, each repeating its motion under a label with its number and name, and puts the
-- player's character on the platform. Nothing of it reaches the server. Run it again to rebuild it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Motion = require(ReplicatedStorage.Shared.Motion)

local PACK = "Elementalist"
local IDLE = "RA-ELM-017"

local MOTIONS = {
	{ "019", "Basic attack 1" },
	{ "020", "Basic attack 2" },
	{ "021", "Basic attack 3" },
	{ "022", "Guard pose" },
}
for n = 1, 5 do
	table.insert(MOTIONS, { string.format("%03d", 29 + n), "Cast release " .. n })
end
for n = 1, 3 do
	table.insert(MOTIONS, { string.format("%03d", 34 + n), "Casting loop " .. n })
end
for n = 1, 3 do
	table.insert(MOTIONS, { string.format("%03d", 37 + n), "Casting start " .. n })
end
for _, motion in
	{
		{ "041", "Arcane cast release 1" },
		{ "042", "Arcane cast release 2" },
		{ "043", "Arcane cast release 3" },
		{ "044", "Arcane casting loop" },
		{ "045", "Arcane casting start" },
		{ "046", "Disrupting gesture" },
		{ "047", "Focus recovery gesture" },
		{ "048", "Quick casting gesture" },
		{ "049", "Steady casting gesture" },
	}
do
	table.insert(MOTIONS, motion)
end
for n = 50, 63 do
	table.insert(MOTIONS, { string.format("%03d", n), "Ability " .. n })
end
for n = 1, 3 do
	table.insert(MOTIONS, { string.format("%03d", 63 + n), "Staff cutscene " .. n })
end

local COLUMNS = 6
local SPACING = 20
local ORIGIN = Vector3.new(0, 400, 0)
local PAUSE = 0.8
local LONGEST = 8

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
	if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("Sound") then
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

local rows = math.ceil(#MOTIONS / COLUMNS)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(COLUMNS * SPACING + 16, 1, rows * SPACING + 24)
floor.CFrame = CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, -0.5, (rows - 1) * SPACING / 2 + 6))
floor.Color = Color3.fromRGB(200, 186, 160)
floor.Material = Enum.Material.Sandstone
floor.Parent = room

local motions = {}
for index, motion in MOTIONS do
	local column = (index - 1) % COLUMNS
	local row = (index - 1) // COLUMNS
	local id = "RA-ELM-" .. motion[1]
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
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(7, 2.4)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	board.LightInfluence = 0
	board.Adornee = rig:FindFirstChild("Head") :: BasePart
	board.Parent = rig
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(28, 24, 22)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = string.format("%s\n%s", motion[1], motion[2])
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
return #MOTIONS .. " motions in the showroom"
