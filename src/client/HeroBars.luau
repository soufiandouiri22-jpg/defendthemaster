-- The bar over every other hero's head (design 05): his health in his team's colour, the only thing that tells the
-- teams apart, with his level in the round knob at its left end. A hero's bar goes when he dies (the "Combatant" tag
-- goes with his life).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UiStyle = require(script.Parent.UiStyle)

local HeroBars = {}

local C = UiStyle.Colors
local WIDTH, HEIGHT, KNOB = 132, 16, 28

local bars: { [Model]: BillboardGui } = {}

local function levelOf(model: Model): number
	local owner = Players:GetPlayerFromCharacter(model)
	return (if owner then owner:GetAttribute("Level") else model:GetAttribute("Level")) or 1
end

local function build(model: Model)
	-- While the game loads, a hero's tag can arrive before its parts.
	local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if
		bars[model]
		or not humanoid
		or not root
		or not CollectionService:HasTag(model, "Combatant")
		or model == Players.LocalPlayer.Character
	then
		return
	end
	local team = model:GetAttribute("Team") or "Blue"
	local colour = C[team]

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroBar"
	gui.Size = UDim2.fromOffset(WIDTH + KNOB / 2, KNOB)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	gui.LightInfluence = 0
	-- Only the heroes near enough to matter, measured from the camera: further bars would crowd the screen.
	gui.MaxDistance = 75
	gui.Adornee = root

	local bar = UiStyle.bar(
		gui,
		UDim2.fromOffset(WIDTH, HEIGHT),
		UDim2.new(0, KNOB / 2, 0.5, 0),
		colour:Lerp(Color3.new(1, 1, 1), 0.2),
		colour:Lerp(C[team .. "Dark"], 0.4),
		Vector2.new(0, 0.5)
	);
	(bar.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 2
	local knob = UiStyle.frame(gui, UDim2.fromOffset(KNOB, KNOB))
	knob.BackgroundColor3 = colour
	knob.ZIndex = 2
	UiStyle.corner(knob, UDim.new(0.5, 0))
	UiStyle.gradient(knob, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	UiStyle.stroke(knob, C.Edge, 2)
	local level = UiStyle.text(knob, "1", 17, C.Cream, C.Edge)
	level.Size = UDim2.fromScale(1, 1)
	level.ZIndex = 3

	local function update()
		bar:set(if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0)
		level.Text = tostring(levelOf(model))
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	local owner = Players:GetPlayerFromCharacter(model)
	if owner then
		owner:GetAttributeChangedSignal("Level"):Connect(update)
	else
		model:GetAttributeChangedSignal("Level"):Connect(update)
	end
	update()
	gui.Parent = model
	bars[model] = gui
end

local function add(instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Hero") and instance ~= Players.LocalPlayer.Character then
		task.spawn(build, instance)
	end
end

local function remove(instance: Instance)
	local gui = bars[instance :: Model]
	if gui then
		gui:Destroy()
		bars[instance :: Model] = nil
	end
end

function HeroBars.start()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(remove)
	for _, instance in CollectionService:GetTagged("Combatant") do
		add(instance)
	end
end

return HeroBars
