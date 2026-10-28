-- The lobby's hall behind the menu (design 10): a dark throne room of the colosseum's own kit (ColosseumBuilder.Kit),
-- lit only by its fires. A round stone podium in the middle carries the player's hero (Lobby.ShowcaseService), before
-- a stone wall with red banners; behind it the Master's throne on its dais against the wall, braziers mirrored on both
-- sides. The menu's camera looks at the podium from the front (the Workspace attribute "MenuCamera", and "MenuFocus"
-- where it looks); the hero stands on "ShowcaseAt".

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ColosseumBuilder = require(script.Parent.Parent.ColosseumBuilder)

local K = ColosseumBuilder.Kit

local LobbyBuilder = {}

-- The hall's walls stand this far behind the podium, this high, and reach this far to each side.
local WALL_BACK, WALL_HEIGHT, WALL_REACH = 30, 30, 75
local STONE = Color3.fromRGB(92, 78, 66)
local PLINTH = Color3.fromRGB(70, 60, 52)
local FLOOR = Color3.fromRGB(88, 74, 62)
local CARPET = Color3.fromRGB(122, 26, 30)
-- Where the camera stands and looks, from the podium's foot.
local CAMERA, FOCUS = Vector3.new(0, 4.6, 15), Vector3.new(0, 3.7, 0)

export type Hall = { map: Folder, showcase: CFrame }

local function block(parent: Instance, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function light()
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(40, 28, 22)
	Lighting.OutdoorAmbient = Color3.fromRGB(40, 28, 22)
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogColor = Color3.fromRGB(24, 16, 12)
	Lighting.FogStart = 60
	Lighting.FogEnd = 160
	local sky = Instance.new("Sky")
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "LobbyGrade"
	grade.Saturation = 0.08
	grade.Contrast = 0.12
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 236, 214)
	grade.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "LobbyBloom"
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end

-- A warm lamp that is not seen, only its light.
local function lamp(parent: Instance, at: Vector3, colour: Color3, brightness: number, range: number, face: Vector3?)
	local holder = block(parent, Vector3.one, CFrame.new(at), colour, Enum.Material.SmoothPlastic)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	if face then
		holder.CFrame = CFrame.lookAt(at, face)
		local spot = Instance.new("SpotLight")
		spot.Color = colour
		spot.Brightness = brightness
		spot.Range = range
		spot.Angle = 50
		spot.Shadows = true
		spot.Parent = holder
	else
		local point = Instance.new("PointLight")
		point.Color = colour
		point.Brightness = brightness
		point.Range = range
		point.Shadows = false
		point.Parent = holder
	end
end

function LobbyBuilder.build(): Hall
	for _, name in { "Baseplate", "SpawnLocation", "Map", "Hall" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "Hall"

	-- The floor, and the hall's walls on three sides with a dark roof over them, so only the fires light it.
	local floor = K.folder(map, "Floor")
	block(floor, Vector3.new(200, 2, 160), CFrame.new(0, -1, -20), FLOOR, Enum.Material.Slate)
	block(
		floor,
		Vector3.new(200, 2, 160),
		CFrame.new(0, WALL_HEIGHT + 6, -20),
		Color3.fromRGB(20, 14, 10),
		Enum.Material.Slate
	)
	local walls = K.folder(map, "Walls")
	-- Dark stone blocks, with a plinth along the foot.
	local height = WALL_HEIGHT + 6
	block(
		walls,
		Vector3.new(WALL_REACH * 2, height, 2),
		CFrame.new(0, height / 2, -WALL_BACK - 1),
		STONE,
		Enum.Material.Brick
	)
	block(
		walls,
		Vector3.new(WALL_REACH * 2, 2.4, 1.6),
		CFrame.new(0, 1.2, -WALL_BACK + 0.6),
		PLINTH,
		Enum.Material.Slate
	)
	for _, side in { -1, 1 } do
		local at = CFrame.new(side * (WALL_REACH - 1), height / 2, 20)
		block(walls, Vector3.new(2, height, 120), at, STONE, Enum.Material.Brick)
	end

	-- The red banners on the wall, two each side of the podium, and pillars between them.
	local deco = K.folder(map, "Decoration")
	local bannerScale = K.byHeight("banner_red", 16)
	for _, x in { -30, -13, 13, 30 } do
		K.kit(deco, "banner_red", CFrame.new(x, 8, -WALL_BACK + 1) * CFrame.Angles(0, math.pi, 0), bannerScale, false)
	end
	for _, x in { -21.5, 21.5, -40, 40 } do
		K.kit(
			deco,
			"pillar_whole",
			CFrame.new(x, 0, -WALL_BACK + 3) * CFrame.Angles(0, math.pi, 0),
			K.byHeight("pillar_whole", 26)
		)
	end

	-- The Master's throne on its dais at the back, against the wall behind the podium and facing the camera, with a red
	-- carpet from it to the podium's foot.
	local throneSpot = CFrame.new(0, 0, -WALL_BACK + 6.2) * CFrame.Angles(0, math.pi, 0)
	local dais = K.kit(deco, "dais", throneSpot, K.byWidth("dais", 10))
	local daisTop = if dais then K.topOf(dais).Y else 3
	K.kit(deco, "throne", throneSpot * CFrame.new(0, daisTop - 0.1, 1), K.byHeight("throne", 12))
	block(deco, Vector3.new(5, 0.12, 14), CFrame.new(0, 0.06, -12.5), CARPET, Enum.Material.Fabric)

	-- Fire: a brazier pillar on each side of the podium, braziers on columns further out, and wall braziers along the
	-- wall, mirrored left and right.
	local fires = K.folder(map, "Fires")
	for _, side in { -1, 1 } do
		K.brazier(fires, "brazier_pillar", CFrame.new(side * 11, 0, -6), 6)
		K.brazier(fires, "column_brazier", CFrame.new(side * 27, 0, -18), 7)
		K.brazier(fires, "wall_brazier", CFrame.new(side * 40, 0, -24) * CFrame.Angles(0, math.pi, 0), 8)
	end

	-- The podium: a broad round step of stone, and the rune pad on top.
	local podium = K.folder(map, "Podium")
	local base = K.disc(podium, Vector3.new(0, 0.8, 0), 5.3, 0.8, Color3.fromRGB(116, 102, 90), Enum.Material.Slate)
	base.Name = "Step"
	local pad = K.kit(podium, "pad", CFrame.new(0, 0.8, 0), K.byWidth("pad", 7.8))
	local top = if pad then K.topOf(pad).Y - 0.08 else 1.8
	local showcase = CFrame.new(0, top, 0)

	-- Light: the warm glow of the fires over the hall, a lamp from the front on the hero, and a dim fill from above.
	local lights = K.folder(map, "Lights")
	lamp(lights, Vector3.new(0, 14, 12), Color3.fromRGB(255, 220, 180), 2, 30, Vector3.new(0, 3, 0))
	lamp(lights, Vector3.new(-7, 6, 6), Color3.fromRGB(255, 170, 90), 0.8, 18)
	lamp(lights, Vector3.new(0, 20, -20), Color3.fromRGB(255, 160, 90), 0.7, 40)
	-- On the throne from the front, so it stands out of the dark behind the hero.
	lamp(lights, Vector3.new(0, 9, -16), Color3.fromRGB(255, 180, 110), 1.2, 16)
	-- Behind him, low: the golden rim of the design round his shoulders and hair.
	lamp(lights, Vector3.new(0, 6, -4), Color3.fromRGB(255, 178, 90), 2.2, 12)

	map.Parent = Workspace
	light()
	Workspace:SetAttribute("ShowcaseAt", showcase)
	Workspace:SetAttribute("MenuCamera", CFrame.lookAt(CAMERA, FOCUS))
	Workspace:SetAttribute("MenuFocus", FOCUS)
	return { map = map, showcase = showcase }
end

return LobbyBuilder
