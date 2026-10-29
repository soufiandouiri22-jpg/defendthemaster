-- A showroom of the Ranger pack's fighting motions, to choose Rowan's attacks from (as Shadowren's,
-- shadow_duelist_showroom.luau). Run it in Play on the client (Studio command bar on the Client, or the Studio MCP):
-- it builds a platform high above the arena with one of the pack's rigs per motion, bow, arrow and quiver played by
-- the pack's own player, each repeating its motion under a label with its number and name, and puts the player's
-- character on the platform. Nothing of it reaches the server. Run it again to rebuild it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComponentPlayer = require(ReplicatedStorage.Ranger.ComponentPlayer)
local RIG = ReplicatedStorage.Ranger.Rig

local MOTIONS = {
	{ "024", "Weapon guard" },
	{ "032", "Song casting start" },
	{ "033", "Song casting hold" },
}
for n = 1, 15 do
	table.insert(MOTIONS, { string.format("%03d", 33 + n), "Bow technique " .. n })
	if n == 6 then
		table.insert(MOTIONS, { "039-WV01", "Bow technique 6 (early bow)" })
	end
end
for n = 1, 11 do
	table.insert(MOTIONS, { string.format("%03d", 48 + n), "Bow ability " .. n })
end
for _, motion in
	{
		{ "060", "Bow technique 16" },
		{ "061", "Bow technique 17" },
		{ "062", "Signature motion 1" },
		{ "063", "Battle flourish 2" },
		{ "064", "Battle flourish 3" },
		{ "065", "Weapon pose enter" },
		{ "066", "Weapon pose hold" },
		{ "067", "Cinematic motion 1" },
		{ "068", "Cinematic motion 2" },
		{ "069", "Cinematic motion 3" },
	}
do
	table.insert(MOTIONS, motion)
end
for n = 1, 3 do
	table.insert(MOTIONS, { string.format("%03d", 70 + n), "Additional battle motion " .. n })
end
for n = 1, 8 do
	table.insert(MOTIONS, { string.format("%03d", 73 + n), "Additional bow technique " .. n })
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
	local id = "RA-RNG-" .. motion[1]
	local rig = RIG:Clone()
	rig.Name = id
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
	label.Text = string.format("%s\n%s", motion[1], motion[2])
	label.Parent = board

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
