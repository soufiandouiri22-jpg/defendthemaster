-- The beast's key on screen (Config.Beast.Key, BeastService's "SerpentKey" attributes): its model
-- (ReplicatedStorage[Key.Model], from Meshy) turns and bobs where it floats, with the boosts' warm light and glow from
-- the floor (BoostView); while a hero carries it, a smaller one turns over his head, over his boost if he carries one
-- too. Its carrier sees what lets the beast loose ("Press H to release Serpent", owner 2026-11-26) while no other
-- beast is about, and that key lets it loose (Net.SerpentRelease). Without its model yet it floats as a gold ball.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local BoostView = require(script.Parent.BoostView)
local Prompts = require(script.Parent.Tips.Prompts)
local UiStyle = require(script.Parent.UiStyle)

local KeyView = {}

local KEY = Config.Beast.Key
local C = UiStyle.Colors
local GOLD = Color3.fromRGB(255, 196, 64)
-- It turns this many degrees a second and bobs this many studs; over a carrier's head its foot is `OVER` studs over
-- the top of his head (or of his boost).
local TURN, BOB, OVER = 70, 0.35, 1.2
local BALL = 2.2
-- The model, as imported, lies flat with its ring towards its mesh's +X (however the import turned the mesh): it
-- stands up, ring on top, this many studs long.
local LENGTH = 4.5
local STAND = CFrame.Angles(0, 0, math.rad(-90))
-- The prompt: its height in the HUD's 1080-high pixels, its key's, and how far over the screen's bottom it sits
-- (over the ability bar).
local PLATE, KEYCAP, BOTTOM = 58, 44, 210

local function source(): Model
	local model = ReplicatedStorage:FindFirstChild(KEY.Model)
	if model and model:IsA("Model") then
		local key = model:Clone()
		local size = key:GetExtentsSize()
		key:ScaleTo(key:GetScale() * LENGTH / math.max(size.X, size.Y, size.Z))
		local mesh = key:FindFirstChildWhichIsA("BasePart", true)
		local axes = if mesh then mesh.CFrame.Rotation else CFrame.identity
		key.WorldPivot = CFrame.new((key:GetBoundingBox()).Position) * axes * STAND
		return key
	end
	local ball = Instance.new("Model")
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(BALL, BALL, BALL)
	part.Material = Enum.Material.Neon
	part.Color = GOLD
	part.Parent = ball
	ball.PrimaryPart = part
	return ball
end

local wornHeight: number? = nil

-- How high the worn key stands over its carrier's head, from the top of his head (or boost) to its own top.
function KeyView.wornTop(): number
	if not wornHeight then
		local model = source()
		local size = model:GetExtentsSize()
		wornHeight = math.max(size.X, size.Y, size.Z) * KEY.Worn
		model:Destroy()
	end
	return OVER + wornHeight :: number
end

local function carrier(): Model?
	for _, model in CollectionService:GetTagged("Combatant") do
		if model:IsA("Model") and model:GetAttribute("SerpentKey") == true and model:FindFirstChild("Head") then
			return model
		end
	end
	return nil
end

-- Whether a beast is about (coming, fighting or let loose), which the key cannot be used against.
local function beastAbout(): boolean
	local beast = Workspace:FindFirstChild("Beast")
	return beast ~= nil and beast:GetAttribute("Phase") ~= "Dead"
end

local function prompt(): ScreenGui
	local gui = UiStyle.screen("SerpentKey", Players.LocalPlayer:WaitForChild("PlayerGui"), 5)
	gui.Enabled = false
	local plate = UiStyle.frame(gui, UDim2.fromOffset(0, PLATE), UDim2.new(0.5, 0, 1, -BOTTOM), Vector2.new(0.5, 1))
	plate.AutomaticSize = Enum.AutomaticSize.X
	UiStyle.corner(plate, PLATE // 2)
	UiStyle.gradient(plate, Color3.fromRGB(96, 62, 36), Color3.fromRGB(52, 32, 18))
	UiStyle.stroke(plate, C.Gold, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 26)
	padding.PaddingRight = UDim.new(0, 26)
	padding.Parent = plate
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = plate
	local function words(text: string, order: number)
		local label = UiStyle.text(plate, text, 28, C.Cream, C.Edge)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, PLATE)
		label.LayoutOrder = order
	end
	words("PRESS", 1)
	local key = Prompts.key(plate, KEY.Press.Name, KEYCAP)
	key.frame.LayoutOrder = 2
	words("TO RELEASE " .. string.upper(Config.Beast.Name), 3)
	return gui
end

function KeyView.start()
	local release = ReplicatedStorage:WaitForChild("Net"):WaitForChild("SerpentRelease") :: RemoteEvent
	local base, top = BoostView.glow()
	local folder = Instance.new("Folder")
	folder.Name = "KeyEffects"
	folder.Parent = Workspace
	local floating = source()
	BoostView.prepare(floating, 16, 2)
	local worn = source()
	worn:ScaleTo(worn:GetScale() * KEY.Worn)
	BoostView.prepare(worn, 8, 1)
	local function half(model: Model): number
		local size = model:GetExtentsSize()
		return math.max(size.X, size.Y, size.Z) / 2
	end
	local floatingHalf = half(floating)
	local wornHalf = half(worn)
	local gui = prompt()
	local angle = 0

	local function mine(): boolean
		local character = Players.LocalPlayer.Character
		return character ~= nil and character:GetAttribute("SerpentKey") == true
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == KEY.Press and mine() and not beastAbout() then
			release:FireServer()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		angle = (angle + TURN * dt) % 360
		local turn = CFrame.Angles(0, math.rad(angle), 0)
		local bob = math.sin(os.clock() * 2)
		local state = Workspace:GetAttribute("SerpentKey")
		local at = Workspace:GetAttribute("SerpentKeySpot")
		local shown = state == "Dropped" and typeof(at) == "Vector3"
		base.Parent = if shown then folder else nil
		floating.Parent = if shown then folder else nil
		if shown then
			local middle = at + Vector3.new(0, floatingHalf * 0.2 + bob * BOB, 0)
			floating:PivotTo(CFrame.new(middle) * turn)
			base.CFrame = CFrame.new(at - Vector3.new(0, KEY.Float - 0.1, 0))
			top.WorldPosition = at + Vector3.new(0, 2, 0)
		end
		local wearer = if state == "Carried" then carrier() else nil
		worn.Parent = if wearer then folder else nil
		if wearer then
			local head = wearer:FindFirstChild("Head") :: BasePart
			local boost = if wearer:GetAttribute("Boost") == true then Boosts.current() else nil
			local under = if boost then BoostView.wornTop(boost) else 0
			local over = head.Position
				+ Vector3.new(0, head.Size.Y / 2 + under + OVER + wornHalf + bob * BOB * KEY.Worn, 0)
			worn:PivotTo(CFrame.new(over) * turn)
		end
		gui.Enabled = mine() and not beastAbout()
	end)
end

return KeyView
