-- A showroom of a hero's motions, to choose his attacks and poses from (owner, 2026-10-31): on Studio's test ground
-- (TestGround) with the Workspace attribute "TestShowroom" set, Play puts the player, as his own hero (TestHero), on a
-- platform high above the sand among one clone of that hero per motion of his pack, each repeating its motion under a
-- label with its number, length and name. "TestShowroom" lists the clips by number ("23-25, 35-68, 76-85"), or is
-- "all" for every clip of the pack. Built again on every spawn; nothing of it reaches the server. A live server never
-- reads it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Motion = require(ReplicatedStorage.Shared.Motion)

local Showroom = {}

local COLUMNS = 10
local SPACING = 20
local ORIGIN = Vector3.new(0, 400, 0)
local PAUSE = 0.8
local LONGEST = 8
-- Past this many missing numbers in a row, "all" has found every clip of the pack.
local GAP = 5

local function exists(pack: string, id: string): boolean
	local ok, meta = pcall(Motion.meta, pack, id)
	return ok and meta ~= nil
end

-- The clip ids the attribute `list` names, as "<prefix><number>" with the number in three digits.
local function clips(pack: string, prefix: string, list: string): { string }
	local ids = {}
	if list:lower() == "all" then
		local missing, n = 0, 0
		while missing < GAP do
			n += 1
			local id = string.format("%s%03d", prefix, n)
			if exists(pack, id) then
				table.insert(ids, id)
				missing = 0
			else
				missing += 1
			end
		end
		return ids
	end
	for part in list:gmatch("[^,]+") do
		local from, to = part:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
		from = from or part:match("^%s*(%d+)%s*$")
		for n = tonumber(from) or 1, tonumber(to or from) or 0 do
			local id = string.format("%s%03d", prefix, n)
			if exists(pack, id) then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function build(character: Model, hero: string, list: string)
	local settings = Config.Heroes[hero]
	local pack, idle = settings.Pack, settings.Motions.Idle
	local prefix = idle:match("^(.*%-)%d+$") or ""
	local ids = clips(pack, prefix, list)

	local old = Workspace:FindFirstChild("Showroom")
	if old then
		old:Destroy()
	end
	local room = Instance.new("Folder")
	room.Name = "Showroom"
	room.Parent = Workspace

	character.Archivable = true
	local template = character:Clone()
	character.Archivable = false
	for _, d in template:GetDescendants() do
		-- A Highlight would be the white flash of his spawn or a hit, caught at the moment of cloning.
		if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	-- Without the hero's tags and attributes the game's HeroAnimator leaves the clones alone, instead of standing them
	-- in their idle every frame.
	for _, tag in template:GetTags() do
		template:RemoveTag(tag)
	end
	for name in template:GetAttributes() do
		template:SetAttribute(name, nil)
	end
	local humanoid = template:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.EvaluateStateMachine = false

	local rows = math.ceil(#ids / COLUMNS)
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(COLUMNS * SPACING + 16, 1, rows * SPACING + 24)
	floor.CFrame = CFrame.new(ORIGIN + Vector3.new((COLUMNS - 1) * SPACING / 2, -0.5, (rows - 1) * SPACING / 2 + 6))
	floor.Color = Color3.fromRGB(70, 64, 60)
	floor.Material = Enum.Material.Slate
	floor.Parent = room

	local motions = {}
	for index, id in ids do
		local column = (index - 1) % COLUMNS
		local row = (index - 1) // COLUMNS
		local meta = Motion.meta(pack, id)
		local rig = template:Clone()
		rig.Name = id
		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
		root.Anchored = true
		-- The clones face the player's start at the platform's front edge (towards -Z), standing on the floor.
		local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		local height = hum.HipHeight + root.Size.Y / 2
		local spot = ORIGIN + Vector3.new(column * SPACING, height, row * SPACING)
		rig:PivotTo(CFrame.lookAt(spot, spot - Vector3.zAxis) * root.CFrame:ToObjectSpace(rig:GetPivot()))
		-- The game's health bar (HeroBar) finds every hero model; here it would cover the labels.
		rig.ChildAdded:Connect(function(child)
			if child.Name == "HeroBar" then
				task.defer(child.Destroy, child)
			end
		end)
		rig.Parent = room

		-- Sized in studs, so the labels shrink with distance and never cover each other.
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromScale(8, 2.6)
		board.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		board.LightInfluence = 0
		board.Adornee = rig:FindFirstChild("Head") :: BasePart
		board.Parent = rig
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(28, 24, 22)
		label.BackgroundTransparency = 0.2
		label.TextColor3 = Color3.fromRGB(255, 240, 210)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = string.format("%s  %.1fs\n%s", id:sub(#prefix + 1), meta.duration, (meta :: any).name or "")
		label.Parent = board

		local m = Motion.new(rig, pack)
		m:setBase(idle, 1)
		table.insert(motions, { motion = m, id = id, next = 0 })
	end
	template:Destroy()

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
end

function Showroom.start()
	local list = Workspace:GetAttribute("TestShowroom")
	if not RunService:IsStudio() or Workspace:GetAttribute("TestGround") ~= true then
		return
	end
	if type(list) ~= "string" or list == "" then
		return
	end
	local function spawned(character: Model)
		local hero = character:GetAttribute("Hero")
		while not hero and character.Parent do
			character:GetAttributeChangedSignal("Hero"):Wait()
			hero = character:GetAttribute("Hero")
		end
		local settings = hero and Config.Heroes[hero]
		if not settings or not settings.Pack then
			return
		end
		if settings.Weapons and not character:WaitForChild("Weapons", 10) then
			return
		end
		-- Every piece of him in, his clothing and weapons, before he is copied.
		task.wait(1)
		if character.Parent then
			build(character, hero, list)
		end
	end
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

return Showroom
