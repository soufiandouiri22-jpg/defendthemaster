-- The ability indicators on the ground (design 06), shown while a key is held to aim: a skillshot arrow, a zone (a
-- pale circle of the range round the hero and a gold circle where he lands) and a cone. Each is a flat, invisible part
-- just above the ground with its image on top, semi-transparent with soft gradients (Tools/ui_textures.py).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Indicators = {}

local GOLD = Color3.fromRGB(255, 196, 92)
local PALE = Color3.fromRGB(235, 240, 250)
-- Pixels per stud of the images on the ground.
local DETAIL = 24
-- How far above the ground they lie, so they do not flicker in it.
local LIFT = 0.15
-- The cone image: its reach is this share of its height, its apex this share above its bottom, and it is this much
-- wider than high (Tools/ui_textures.py).
local CONE_REACH, CONE_APEX, CONE_ASPECT = 498 / 512, 4 / 512, 604 / 512
-- The arrow: its shaft is this share of the head's width, the head this much longer than wide.
local ARROW_SHAFT, ARROW_HEAD = 0.5, 224 / 256

export type Indicator = {
	parts: { BasePart },
	kind: string,
}

local folder: Folder

local function effects(): Folder
	if not folder or not folder.Parent then
		folder = Workspace:FindFirstChild("Effects") :: Folder or Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

local function plate(image: string, colour: Color3, transparency: number): BasePart
	local part = Instance.new("Part")
	part.Name = "Indicator"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 0.05, 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = DETAIL
	gui.Adornee = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageColor3 = colour
	label.ImageTransparency = transparency
	label.Parent = gui
	gui.Parent = part
	part.Parent = effects()
	return part
end

-- A flat part of `width` by `length` studs centred on `centre`, its image's top towards `direction`.
local function lay(part: BasePart, centre: Vector3, direction: Vector3, width: number, length: number)
	part.Size = Vector3.new(width, 0.05, length)
	part.CFrame = CFrame.lookAt(centre, centre + direction)
end

function Indicators.arrow(): Indicator
	return {
		kind = "Arrow",
		parts = { plate(Assets.IndicatorArrowShaft, GOLD, 0), plate(Assets.IndicatorArrowHead, GOLD, 0) },
	}
end

function Indicators.zone(): Indicator
	return {
		kind = "Zone",
		parts = { plate(Assets.IndicatorDisc, PALE, 0.15), plate(Assets.IndicatorDisc, GOLD, 0) },
	}
end

function Indicators.cone(): Indicator
	return { kind = "Cone", parts = { plate(Assets.IndicatorCone, PALE, 0) } }
end

-- An arrow from `from` (on the ground) `length` studs along `direction`, `width` studs wide.
function Indicators.placeArrow(indicator: Indicator, from: Vector3, direction: Vector3, length: number, width: number)
	local head = width / ARROW_SHAFT
	local headLength = head * ARROW_HEAD
	local shaft = math.max(0.1, length - headLength)
	local lift = Vector3.new(0, LIFT, 0)
	lay(indicator.parts[1], from + direction * (shaft / 2) + lift, direction, width, shaft)
	lay(indicator.parts[2], from + direction * (shaft + headLength / 2) + lift, direction, head, headLength)
end

-- A circle of `range` studs round `centre` and one of `radius` studs round `target`, both on the ground.
function Indicators.placeZone(indicator: Indicator, centre: Vector3, range: number, target: Vector3, radius: number)
	local lift = Vector3.new(0, LIFT, 0)
	lay(indicator.parts[1], centre + lift, Vector3.zAxis, range * 2, range * 2)
	lay(indicator.parts[2], target + lift * 2, Vector3.zAxis, radius * 2, radius * 2)
end

-- A cone from `apex` on the ground along `direction`, reaching `range` studs (the image's angle is the R's 70°).
function Indicators.placeCone(indicator: Indicator, apex: Vector3, direction: Vector3, range: number)
	local height = range / CONE_REACH
	local centre = apex + direction * (height / 2 - height * CONE_APEX) + Vector3.new(0, LIFT, 0)
	lay(indicator.parts[1], centre, direction, height * CONE_ASPECT, height)
end

function Indicators.destroy(indicator: Indicator)
	for _, part in indicator.parts do
		part:Destroy()
	end
end

return Indicators
