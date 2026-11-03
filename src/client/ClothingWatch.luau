-- Logs (ReplicatedFirst.Trace, "clothing.jump") when the player's own hero, wearing layered clothing (a WrapLayer), is
-- carried farther than JUMP studs in one frame (a dash, a leap): Roblox wraps every layered piece round its body anew
-- each frame, and with many of them in the world (2026-11-03: 228, the test ground's Showroom and leftover try-on
-- models) it falls behind, so on such a jump the sleeves and trouser legs hang loose where the body just was. The
-- entry says how far, at what frame rate, during which clip, and how many layered pieces were about and on whom most.
-- In Studio it is printed as well.
-- And ("clothing.state") every CHECK seconds, for every hero wearing layered clothing, whether each piece is still on
-- him, attached, near his body and shown, and how many of his body parts are hidden, marked when it changes: a hero's
-- layered clothing that stops being drawn takes the body under it with it (Roblox hides what the clothing covers), so
-- heroes lost their bodies in a match (2026-11-03), all of them wearing layered clothing.
-- And ("clothing.churn") every CHURN seconds, what changed in those heroes: the properties set on their parts and the
-- parts and joints put in or taken out, counted by hero, part and property. Roblox fits a hero's layered clothing
-- anew on every such change, out of sight until it is done, so a hero changed every frame may never get his back.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Trace = require(ReplicatedFirst:WaitForChild("Trace"))

local ClothingWatch = {}

-- Studs in one frame beyond which the clothing may be left behind, the least seconds between two entries, and how
-- many entries a match gets at most.
local JUMP, QUIET, MOST = 4, 10, 20
-- How many models' counts the entry names.
local TOP = 3
-- Seconds between two looks at every hero's clothing, and the studs from his torso beyond which a piece hangs loose.
local CHECK, LOOSE = 2, 4
-- Seconds between two counts of the changes, and how many of the most changed the entry names.
local CHURN, CHURN_TOP = 30, 8
-- What moves a part without changing it, and what the physics works out of it.
local MOVING = {
	CFrame = true,
	Position = true,
	Orientation = true,
	Rotation = true,
	Velocity = true,
	RotVelocity = true,
	AssemblyLinearVelocity = true,
	AssemblyAngularVelocity = true,
	AssemblyCenterOfMass = true,
	AssemblyMass = true,
	Mass = true,
}

-- The model right under the Workspace (or a folder in it) that `item` belongs to.
local function holderOf(item: Instance): string
	local at: Instance = item
	while at.Parent and at.Parent ~= Workspace do
		at = at.Parent
	end
	return at.Name
end

-- What `model`'s layered clothing and body are like now, or nil when he wears none.
local function stateOf(model: Model): { [string]: any }?
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	local pieces, attached, near, shown = 0, 0, 0, 0
	local off = {}
	for _, item in model:GetDescendants() do
		if item:IsA("WrapLayer") then
			pieces += 1
			local handle = item.Parent
			local accessory = handle and handle.Parent
			if handle and handle:IsA("BasePart") then
				if
					accessory
					and accessory:IsA("Accessory")
					and accessory.Parent == model
					and (
						handle:FindFirstChildWhichIsA("JointInstance")
						or handle:FindFirstChildWhichIsA("RigidConstraint")
					)
				then
					attached += 1
				end
				if torso and (handle.Position - torso.Position).Magnitude <= LOOSE then
					near += 1
				end
				if item.Enabled and handle.Transparency < 1 and handle.LocalTransparencyModifier < 1 then
					shown += 1
				else
					table.insert(
						off,
						`{if accessory then accessory.Name else "?"} on={item.Enabled} t={handle.Transparency} ltm={handle.LocalTransparencyModifier}`
					)
				end
			end
		end
	end
	if pieces == 0 then
		return nil
	end
	local hidden = 0
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if part.Transparency >= 1 or part.LocalTransparencyModifier >= 1 then
				hidden += 1
			end
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return {
		who = model.Name,
		hero = model:GetAttribute("Hero"),
		pieces = pieces,
		attached = attached,
		near = near,
		shown = shown,
		hidden = hidden,
		dead = humanoid ~= nil and humanoid.Health <= 0,
		off = if #off > 0 then string.sub(table.concat(off, "; "), 1, 250) else nil,
	}
end

-- Marks "clothing.state" for every hero whose layered clothing is not as it was at the last look.
local function watchStates()
	local last: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
	while true do
		task.wait(CHECK)
		for _, model in CollectionService:GetTagged("Combatant") do
			if model:IsA("Model") and model:GetAttribute("Hero") then
				local state = stateOf(model)
				local key = if state
					then `{state.pieces}/{state.attached}/{state.near}/{state.shown}/{state.hidden}/{state.dead}`
					else "none"
				if state and last[model] ~= nil and last[model] ~= key then
					Trace.mark("clothing.state", state)
					if RunService:IsStudio() then
						print("[ClothingWatch]", state.who, state.hero, key, state.off or "")
					end
				end
				last[model] = key
			end
		end
	end
end

-- Counts what changes in every hero wearing layered clothing, and marks "clothing.churn" every CHURN seconds.
local function watchChurn()
	local counts: { [string]: number } = {}
	local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function count(key: string)
		counts[key] = (counts[key] or 0) + 1
	end
	local function label(model: Model): string
		return `{model:GetAttribute("Hero") or model.Name}`
	end
	local function watchPart(model: Model, part: BasePart)
		part.Changed:Connect(function(property)
			if not MOVING[property] then
				count(`{label(model)}.{part.Name}.{property}`)
			end
		end)
	end
	local function watch(model: Model)
		if watched[model] or not model:FindFirstChildWhichIsA("WrapLayer", true) then
			return
		end
		watched[model] = true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				watchPart(model, d)
			end
		end
		model.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") or d:IsA("JointInstance") or d:IsA("Highlight") then
				count(`{label(model)}.added.{d.ClassName}`)
			end
			if d:IsA("BasePart") then
				watchPart(model, d)
			end
		end)
		model.DescendantRemoving:Connect(function(d)
			if d:IsA("BasePart") or d:IsA("JointInstance") or d:IsA("Highlight") then
				count(`{label(model)}.removed.{d.ClassName}`)
			end
		end)
	end
	local since = os.clock()
	while true do
		task.wait(CHECK)
		for _, model in CollectionService:GetTagged("Combatant") do
			if model:IsA("Model") and model:GetAttribute("Hero") then
				watch(model)
			end
		end
		if os.clock() - since >= CHURN then
			local seconds = os.clock() - since
			since = os.clock()
			local keys = {}
			for key in counts do
				table.insert(keys, key)
			end
			table.sort(keys, function(a, b)
				return counts[a] > counts[b]
			end)
			if #keys > 0 then
				local top = {}
				for i = 1, math.min(CHURN_TOP, #keys) do
					table.insert(top, `{keys[i]}={math.floor(counts[keys[i]] / seconds * 10) / 10}/s`)
				end
				local data = { kinds = #keys, top = string.sub(table.concat(top, " "), 1, 290) }
				Trace.mark("clothing.churn", data)
				if RunService:IsStudio() then
					print("[ClothingWatch] churn", data.top)
				end
			end
			counts = {}
		end
	end
end

function ClothingWatch.start(playing: (character: Model) -> string?)
	task.spawn(watchStates)
	task.spawn(watchChurn)
	local player = Players.LocalPlayer
	local layered: { [Instance]: string } = {}
	local total = 0
	local function added(item: Instance)
		if item:IsA("WrapLayer") and not layered[item] then
			layered[item] = holderOf(item)
			total += 1
		end
	end
	Workspace.DescendantAdded:Connect(added)
	Workspace.DescendantRemoving:Connect(function(item)
		if layered[item] then
			layered[item] = nil
			total -= 1
		end
	end)
	for _, item in Workspace:GetDescendants() do
		added(item)
	end

	local frames: { number } = {}
	local last: Vector3? = nil
	local lastCharacter: Model? = nil
	local quietUntil, marked = 0, 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		table.insert(frames, now)
		while frames[1] and frames[1] < now - 1 do
			table.remove(frames, 1)
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			last = nil
			return
		end
		local position = root.Position
		local step = if last and character == lastCharacter then (position - last).Magnitude else 0
		last, lastCharacter = position, character
		if step < JUMP or now < quietUntil or marked >= MOST then
			return
		end
		local own = 0
		for _, item in character:GetDescendants() do
			if item:IsA("WrapLayer") then
				own += 1
			end
		end
		if own == 0 then
			return
		end
		quietUntil = now + QUIET
		marked += 1
		local counts: { [string]: number } = {}
		for _, holder in layered do
			counts[holder] = (counts[holder] or 0) + 1
		end
		local names = {}
		for name in counts do
			table.insert(names, name)
		end
		table.sort(names, function(a, b)
			return counts[a] > counts[b]
		end)
		local most = {}
		for i = 1, math.min(TOP, #names) do
			table.insert(most, `{names[i]}={counts[names[i]]}`)
		end
		local data = {
			hero = character:GetAttribute("Hero"),
			step = math.floor(step * 10) / 10,
			fps = #frames,
			clip = playing(character),
			own = own,
			layered = total,
			most = table.concat(most, " "),
		}
		Trace.mark("clothing.jump", data)
		if RunService:IsStudio() then
			print(
				`[ClothingWatch] {data.hero} jumped {data.step} studs in one frame at {data.fps} fps ({data.clip or "no clip"}); {total} layered pieces about, most: {data.most}`
			)
		end
	end)
end

return ClothingWatch
