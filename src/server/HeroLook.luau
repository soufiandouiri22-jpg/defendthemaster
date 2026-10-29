-- How a hero looks (Config.Heroes[hero].Look): his avatar from catalog items in the proportions of his animation pack's
-- rig, his head hidden under a mask, and the pack's weapons bound to his root part as on the pack's rig. For the
-- heroes in a match (HeroService, BotService) and on the lobby's podium (Lobby.ShowcaseService).

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
	local components = ReplicatedStorage[settings.Pack].Rig.Components
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
		head.Transparency = 1
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
	arm(character, hero)
end

return HeroLook
