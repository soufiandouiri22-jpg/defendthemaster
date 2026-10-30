-- How a hero looks (Config.Heroes[hero].Look): his avatar from catalog items in the proportions of his animation pack's
-- rig, his head hidden under a mask, and the pack's weapons bound to his root part or his hand as on the pack's rig. For the
-- heroes in a match (HeroService, BotService) and on the lobby's podium (Lobby.ShowcaseService).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Motion = require(ReplicatedStorage.Shared.Motion)

local HeroLook = {}

local BODY_COLOURS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

-- The avatar of the hero `name`.
function HeroLook.description(name: string): HumanoidDescription
	local look = Config.Heroes[name].Look
	local description = Instance.new("HumanoidDescription")
	description.Shirt = look.Shirt
	description.Pants = look.Pants
	description.HairAccessory = look.HairAccessory or ""
	description.FaceAccessory = look.FaceAccessory or ""
	description.HatAccessory = look.HatAccessory or ""
	description.BackAccessory = look.BackAccessory or ""
	-- A dynamic head from the catalog with its own animated face, and the mood it plays.
	description.Head = look.Head or 0
	description.MoodAnimation = look.Mood or 0
	for _, part in BODY_COLOURS do
		(description :: any)[part] = look.Skin
	end
	-- The proportions of the animation packs' rigs.
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	return description
end

local function arm(character: Model, hero: string)
	local settings = Config.Heroes[hero]
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not settings.Pack or not root then
		return
	end
	-- A keyframe pack (Tools/keyframe_pack.py) has its components beside its rig, and its weapon held in a hand.
	local pack = ReplicatedStorage[settings.Pack]
	local components = pack.Rig:FindFirstChild("Components") or pack.Components
	local held = if pack.Rig:FindFirstChild("Components")
		then nil
		else HttpService:JSONDecode(pack.ComponentPlayer.Configuration.Value).weapon
	local shift = Motion.rootShift(character)
	local folder = Instance.new("Folder")
	folder.Name = "Weapons"
	for _, name in settings.Weapons or {} do
		local weapon = components[name]:Clone()
		for _, d in weapon:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				d.CastShadow = true
			elseif d:IsA("Motor6D") and d.Name == "ComponentBinding" and held and weapon.Name == held.name then
				-- Held in his own hand as on the pack's rig, so it never drifts from it.
				d.Part0 = character:FindFirstChild(held.parent) :: BasePart
				d.C0 = CFrame.new(table.unpack(held.c0))
				d.C1 = CFrame.new(table.unpack(held.c1))
			elseif (d:IsA("Weld") or d:IsA("Motor6D")) and d.Name == "ComponentBinding" then
				-- A skinned component hangs from a Weld, a rigid one (the Ranger's quiver) from a Motor6D the clips
				-- turn; both bind to the pack rig's root part, which becomes the hero's.
				d.Part0 = root
				d.C0 = shift * d.C0
			end
		end
		weapon.Parent = folder
	end
	folder.Parent = character
	for _, d in folder:GetDescendants() do
		if d:IsA("JointInstance") and not (d.Part0 and d.Part0:IsDescendantOf(character)) then
			warn("[HeroLook] a weapon of", hero, "is not bound to the hero:", d:GetFullName())
		end
	end
end

-- Gives the hero body `character` the look of `hero` beyond his avatar: his head hidden under a mask, or its painted
-- face taken off and his own face painted on, and his weapons.
function HeroLook.dress(character: Model, hero: string)
	character:SetAttribute("Hero", hero)
	local look = Config.Heroes[hero].Look
	local head = character:FindFirstChild("Head")
	if look.HideHead and head and head:IsA("BasePart") then
		-- Nothing of his face is drawn on a hidden head.
		head.Transparency = 1
		head = nil
	end
	if look.BlankFace and head and head:IsA("MeshPart") then
		head.TextureID = ""
	end
	local mouth = look.Mouth
	if mouth and head and head:IsA("BasePart") then
		-- A strip in the middle of the face, `Height` studs from the head's centre, sunk halfway into its front.
		local strip = Instance.new("Part")
		strip.Name = "Mouth"
		strip.Size = Vector3.new(mouth.Length, mouth.Thickness, 0.012)
		strip.Color = mouth.Colour
		strip.Material = Enum.Material.SmoothPlastic
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.Massless = true
		strip.CastShadow = false
		strip.CFrame = head.CFrame * CFrame.new(0, mouth.Height, -head.Size.Z / 2)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = strip
		weld.Parent = strip
		strip.Parent = head
	end
	local eyes = look.Eyes
	if eyes and head and head:IsA("BasePart") then
		-- Each eye a picture (Tools/face_eyes.py) on a thin plate, `Apart` studs to the side and `Height` from the head's
		-- centre, sunk halfway into the face and turned with its curve; his left eye is on the head's -X.
		local radius = head.Size.X / 2
		for side, image in { [-1] = eyes.Left, [1] = eyes.Right } do
			local x = side * eyes.Apart
			local plate = Instance.new("Part")
			plate.Name = if side < 0 then "LeftEye" else "RightEye"
			plate.Size = Vector3.new(eyes.Width, eyes.Width * eyes.Aspect, 0.012)
			plate.Transparency = 1
			plate.CanCollide = false
			plate.CanQuery = false
			plate.CanTouch = false
			plate.Massless = true
			plate.CastShadow = false
			local depth = math.sqrt(math.max(radius * radius - x * x, 0)) * head.Size.Z / head.Size.X
			plate.CFrame = head.CFrame
				* CFrame.new(x, eyes.Height, -depth)
				* CFrame.Angles(0, -math.asin(math.clamp(x / radius, -1, 1)), 0)
			local decal = Instance.new("Decal")
			decal.Texture = image
			decal.Face = Enum.NormalId.Front
			decal.Parent = plate
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = plate
			weld.Parent = plate
			plate.Parent = head
		end
	end
	local brows = look.Brows
	if brows and head and head:IsA("BasePart") then
		-- A strip above each eye, `Apart` studs to the side and `Height` from the head's centre, sunk into the face
		-- and turned with its curve, its inner end `Tilt` degrees lower than its outer end.
		local radius = head.Size.X / 2
		for _, side in { -1, 1 } do
			local x = side * brows.Apart
			local strip = Instance.new("Part")
			strip.Name = if side < 0 then "LeftBrow" else "RightBrow"
			strip.Size = Vector3.new(brows.Length, brows.Thickness, 0.012)
			strip.Color = brows.Colour
			strip.Material = Enum.Material.SmoothPlastic
			strip.CanCollide = false
			strip.CanQuery = false
			strip.CanTouch = false
			strip.Massless = true
			strip.CastShadow = false
			local depth = math.sqrt(math.max(radius * radius - x * x, 0)) * head.Size.Z / head.Size.X
			strip.CFrame = head.CFrame
				* CFrame.new(x, brows.Height, -depth)
				* CFrame.Angles(0, -math.asin(math.clamp(x / radius, -1, 1)), side * math.rad(brows.Tilt))
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = strip
			weld.Parent = strip
			strip.Parent = head
		end
	end
	arm(character, hero)
end

return HeroLook
