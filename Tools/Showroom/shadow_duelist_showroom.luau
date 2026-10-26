-- A showroom of the Shadow Duelist pack's attack motions, to choose a hero's attacks from. Run it in Play on the
-- client (Studio command bar on the Client, or the Studio MCP): it builds a platform high above the arena with one
-- of the pack's rigs per motion, each repeating its motion under a label with its number and name, and puts the
-- player's character on the platform. Nothing of it reaches the server. Run it again to rebuild it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComponentPlayer = require(ReplicatedStorage.ShadowDuelist.ComponentPlayer)
local RIG = ReplicatedStorage.ShadowDuelist.Rig

local MOTIONS = {
	{ 23, "Basic dagger attack 1" },
	{ 24, "Basic dagger attack 2" },
	{ 25, "Basic dagger attack 3" },
	{ 35, "Cast release 1" },
	{ 36, "Cast release 2" },
	{ 37, "Cast release 3" },
	{ 38, "Cast release 4" },
}
for n = 1, 10 do
	table.insert(MOTIONS, { 38 + n, "Dagger technique " .. n })
end
for n = 1, 16 do
	table.insert(MOTIONS, { 48 + n, "Dagger ability " .. n })
end
for _, motion in
	{
		{ 65, "Casting gesture 1" },
		{ 66, "Dagger technique 11" },
		{ 67, "Dagger technique 12" },
		{ 68, "Dagger technique 13" },
		{ 69, "Casting gesture 2" },
		{ 70, "Casting gesture 3" },
		{ 71, "Signature motion 1" },
		{ 77, "Cinematic motion 1" },
		{ 78, "Cinematic motion 3" },
		{ 79, "Cinematic motion 4" },
	}
do
	table.insert(MOTIONS, motion)
end
for n = 1, 10 do
	table.insert(MOTIONS, { 79 + n, "Additional technique " .. n })
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

local rows = math.ceil(#MOTIONS / COLUMNS)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(COLUMNS * SPACING + 16, 1, rows * SPACING + 24)
floor.CFrame = CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, -0.5, (rows - 1) * SPACING / 2 + 6))
floor.Color = Color3.fromRGB(200, 186, 160)
floor.Material = Enum.Material.Sandstone
floor.Parent = room

for index, motion in MOTIONS do
	local column = (index - 1) % COLUMNS
	local row = (index - 1) // COLUMNS
	local rig = RIG:Clone()
	rig.Name = string.format("RA-SHD-%03d", motion[1])
	local root = rig.HumanoidRootPart
	root.Anchored = true
	-- The rigs face the player's start at the platform's front edge (towards -Z).
	local target = CFrame.new(ORIGIN + Vector3.new(column * SPACING, 2.35, row * SPACING))
	rig:PivotTo(target * root.CFrame:ToObjectSpace(rig:GetPivot()))
	rig.Parent = room

	-- Sized in studs, so the labels shrink with distance and never cover each other.
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(7, 2.4)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	board.LightInfluence = 0
	board.Adornee = rig.Head
	board.Parent = rig
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(28, 24, 22)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = string.format("%d\n%s", motion[1], motion[2])
	label.Parent = board

	local id = string.format("RA-SHD-%03d", motion[1])
	task.spawn(function()
		local player = ComponentPlayer.new(rig)
		while rig.Parent do
			player:Play(id)
			local started = os.clock()
			while player.id and os.clock() - started < LONGEST do
				task.wait(0.1)
			end
			player:Stop()
			task.wait(PAUSE)
		end
	end)
end

local character = Players.LocalPlayer.Character
if character then
	character:PivotTo(CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, 4, -6)))
end
return #MOTIONS .. " motions in the showroom"
