-- The emote wheel (Config.Emotes): the emotes in the player's wheel (Profile.wheel) in a ring round the middle of the
-- screen, each its icon on a brown disc like the middle's with a gold edge; the one pointed at lights up and its name
-- shows in the middle. In the lobby it opens on the Play page's EMOTE button and a click picks (the middle stops the
-- dance); in a match it opens while G is held and letting go picks the one pointed at (EmoteWheel.hold and release).
-- The lobby's has a + at its foot that turns it to changing its slots, as Fortnite's locker does: he clicks a slot,
-- his whole collection opens beside the wheel for it, and the emote he clicks there takes the slot (Editor); the +,
-- now DONE, ends it. Emotes he has not seen yet carry a NEW tag.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)
local Widgets = require(script.Parent.Widgets)

local EmoteWheel = {}

local C = UiStyle.Colors
local W = Widgets.Colors
-- The ring's radius to the middle of each disc, the discs' and the middle's sizes, in pixels on a 1920 by 1080 screen.
local RADIUS = 230
local SLOT = 150
local MIDDLE = 170
-- How far the lobby's + is lifted, as the font's + sits below the middle of its line.
local PLUS_LIFT = 8
-- How far from the middle the mouse must be before it points at a disc.
local DEAD = 40
-- The collection beside the wheel: its size, its discs' and their names' sizes, and how many discs a row holds.
local PANEL = Vector2.new(480, 600)
local CELL = 96
local CELL_NAME = 26
local COLUMNS = 4

-- What the lobby's wheel needs to let the player choose what fills its slots.
export type Editor = {
	-- Every emote he has, in the collection's order.
	owned: () -> { string },
	isNew: (id: string) -> boolean,
	-- Asks for `id` in slot `slot`; the wheel's emotes after, or nil when it could not be.
	place: (slot: number, id: string) -> { string }?,
	-- After the wheel closed, having shown what was new.
	closed: () -> (),
}

export type Wheel = {
	open: (ids: { string }, onPick: (id: string?) -> (), editor: Editor?) -> (),
	hold: (ids: { string }) -> (),
	release: () -> string?,
	close: () -> (),
	isOpen: () -> boolean,
}

-- A small gold NEW tag at the top right of `parent`, `height` high.
function EmoteWheel.newTag(parent: Instance, height: number): Frame
	local tag = UiStyle.frame(parent, UDim2.fromOffset(height * 2, height), UDim2.new(1, 4, 0, -4), Vector2.new(1, 0))
	tag.Name = "New"
	tag.ZIndex = 3
	UiStyle.corner(tag, UDim.new(0.5, 0))
	UiStyle.gradient(tag, C.Xp, C.XpDark)
	UiStyle.stroke(tag, C.Edge, 2)
	local text = Widgets.label(tag, "NEW", math.floor(height * 0.72), C.Cream, nil, C.Edge)
	text.ZIndex = 4
	return tag
end

-- A round brown button `size` across, like the wheel's middle, named `name`.
local function disc(parent: Instance, name: string, size: number): (TextButton, UIStroke)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(size, size)
	button.Parent = parent
	UiStyle.corner(button, UDim.new(0.5, 0))
	UiStyle.gradient(button, W.Brown, W.BrownDark)
	return button, UiStyle.stroke(button, C.GoldDark, 3)
end

-- Emote `id`'s icon filling `parent`.
local function icon(parent: Instance, id: string): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = Config.Emotes.List[id].Icon
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromScale(0.86, 0.86)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Parent = parent
	return image
end

-- A wheel `size` times as large as on the menu (smaller in a match, where the fight stays in sight round it).
function EmoteWheel.new(size: number?): Wheel
	local drawn = size or 1
	local gui = UiStyle.screen("EmoteWheel", Players.LocalPlayer:WaitForChild("PlayerGui"), 30)
	gui.Enabled = false
	local catcher = Instance.new("TextButton")
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Parent = gui
	local ring =
		UiStyle.frame(gui, UDim2.fromOffset((RADIUS + SLOT) * 2, (RADIUS + SLOT) * 2), UDim2.fromScale(0.5, 0.5))
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	local sized = Instance.new("UIScale")
	sized.Scale = drawn
	sized.Parent = ring
	local back = UiStyle.frame(ring, UDim2.fromOffset(RADIUS * 2 + SLOT + 30, RADIUS * 2 + SLOT + 30))
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.BackgroundColor3 = W.BrownDark
	back.BackgroundTransparency = 0.45
	UiStyle.corner(back, UDim.new(0.5, 0))
	UiStyle.stroke(back, C.GoldDark, 2).Transparency = 0.3

	local middle = Instance.new("TextButton")
	middle.Text = ""
	middle.AutoButtonColor = false
	middle.Size = UDim2.fromOffset(MIDDLE, MIDDLE)
	middle.Position = UDim2.fromScale(0.5, 0.5)
	middle.AnchorPoint = Vector2.new(0.5, 0.5)
	middle.Parent = ring
	UiStyle.corner(middle, UDim.new(0.5, 0))
	UiStyle.gradient(middle, W.Brown, W.BrownDark)
	UiStyle.stroke(middle, C.Gold, 3)
	local title = Widgets.label(middle, "EMOTES", 26, C.Cream, nil, C.Edge)
	title.Size = UDim2.new(1, -20, 1, -20)
	title.Position = UDim2.fromOffset(10, 10)
	title.TextWrapped = true

	-- The collection beside the ring, on a back like the ring's but nearly solid, as it may lie over the menu's cards.
	local reach = (RADIUS + SLOT / 2 + 15) * drawn
	local panel = UiStyle.frame(gui, UDim2.fromOffset(PANEL.X, PANEL.Y), UDim2.new(0.5, reach + 24, 0.5, 0))
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Name = "Collection"
	panel.Visible = false
	panel.BackgroundColor3 = W.BrownDark
	panel.BackgroundTransparency = 0.08
	UiStyle.corner(panel, 40)
	UiStyle.stroke(panel, C.GoldDark, 2).Transparency = 0.3
	local heading = Widgets.label(panel, "", 28, C.Cream, nil, C.Edge)
	heading.Size = UDim2.new(1, -40, 0, 52)
	heading.Position = UDim2.fromOffset(20, 6)
	local grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.new(1, -40, 1, -90)
	grid.Position = UDim2.fromOffset(20, 64)
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = C.GoldDark
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / COLUMNS, -10, 0, CELL + CELL_NAME + 6)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 6)
	gridPadding.Parent = grid

	type Slot = { frame: TextButton, id: string, edge: UIStroke, scale: UIScale }
	local slots: { Slot } = {}
	local plus: { frame: TextButton, edge: UIStroke, scale: UIScale, cross: TextLabel, mark: TextLabel, tag: Frame }? =
		nil
	local pointed: number? = nil
	local picking: ((id: string?) -> ())? = nil
	local holding = false
	local editor: Editor? = nil
	local editing = false
	local chosen: number? = nil
	local busy = false
	local wheel = {} :: Wheel
	local show: (ids: { string }) -> ()

	local function paint()
		for i, slot in slots do
			local on = i == pointed or i == chosen
			slot.edge.Color = if on then C.Xp else C.GoldDark
			slot.edge.Thickness = if on then 5 else 3
			Widgets.tween(slot.scale, 0.1, { Scale = if on then 1.12 else 1 })
		end
		if plus then
			plus.edge.Color = if editing then C.Xp else C.Gold
			plus.edge.Thickness = if editing then 5 else 3
			plus.mark.Visible = editing
			plus.cross.Visible = not editing
		end
		if busy then
			title.Text = "..."
		elseif pointed then
			title.Text = string.upper(Config.Emotes.List[slots[pointed].id].Name)
		elseif editing then
			title.Text = if chosen then "PICK AN EMOTE" else "PICK A SLOT"
		else
			title.Text = if picking then "STOP" else "EMOTES"
		end
	end

	local function light(index: number?)
		if index == pointed then
			return
		end
		pointed = index
		if index then
			UiSound.play("Hover", 0.6)
		end
		paint()
	end

	-- The collection for slot `chosen`: every emote he has, those in the wheel already faded.
	local function fill()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local index = chosen
		if not editor or not index then
			panel.Visible = false
			return
		end
		heading.Text = "REPLACE " .. string.upper(Config.Emotes.List[slots[index].id].Name)
		local changer = editor
		local inWheel: { [string]: boolean } = {}
		for _, slot in slots do
			inWheel[slot.id] = true
		end
		for order, id in changer.owned() do
			local cell = Instance.new("Frame")
			cell.Name = id
			cell.BackgroundTransparency = 1
			cell.LayoutOrder = order
			cell.Parent = grid
			local button = disc(cell, id, CELL)
			button.AnchorPoint = Vector2.new(0.5, 0)
			button.Position = UDim2.fromScale(0.5, 0)
			local image = icon(button, id)
			local name = Widgets.label(cell, string.upper(Config.Emotes.List[id].Name), 18, C.Cream, nil, C.Edge)
			name.Size = UDim2.new(1, 4, 0, CELL_NAME)
			name.Position = UDim2.fromOffset(-2, CELL + 4)
			name.TextScaled = true
			if inWheel[id] then
				image.ImageTransparency = 0.55
				name.TextTransparency = 0.45
			end
			if changer.isNew(id) then
				EmoteWheel.newTag(button, 28)
			end
			Widgets.feel(button, true)
			button.Activated:Connect(function()
				local slot = chosen
				if busy or not slot then
					return
				end
				busy = true
				paint()
				local ids = changer.place(slot, id)
				busy = false
				if not gui.Enabled then
					return
				end
				if ids then
					UiSound.play("Pick", 0.8)
					chosen = nil
					show(ids)
				else
					UiSound.play("Denied", 0.8)
					paint()
				end
			end)
		end
		grid.CanvasPosition = Vector2.zero
		panel.Visible = true
	end

	local function setEditing(on: boolean)
		editing = on
		chosen = nil
		fill()
		paint()
	end

	-- Lays `ids` round the ring: from the top clockwise, with the lobby's + at the foot.
	function show(ids: { string })
		for _, slot in slots do
			slot.frame:Destroy()
		end
		if plus then
			plus.frame:Destroy()
			plus = nil
		end
		slots = {}
		pointed = nil
		local count = math.min(#ids, Config.Emotes.Slots)
		local places = if editor then count + 1 else count
		local foot = if editor then math.floor(places / 2) else -1
		local function place(frame: GuiObject, at: number)
			local angle = -math.pi / 2 + at * 2 * math.pi / places
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS)
		end
		local at = 0
		for i = 1, count do
			if at == foot then
				at += 1
			end
			local id = ids[i]
			local frame, edge = disc(ring, id, SLOT)
			icon(frame, id)
			place(frame, at)
			at += 1
			local scale = Instance.new("UIScale")
			scale.Parent = frame
			if editor and editor.isNew(id) then
				EmoteWheel.newTag(frame, 40)
			end
			frame.MouseEnter:Connect(function()
				if picking then
					light(i)
				end
			end)
			frame.MouseLeave:Connect(function()
				if picking and pointed == i then
					light(nil)
				end
			end)
			frame.Activated:Connect(function()
				if busy then
					return
				elseif editing then
					UiSound.play("Tab", 0.7)
					chosen = if chosen == i then nil else i
					fill()
					paint()
				elseif picking then
					local pick = picking
					wheel.close()
					UiSound.play("Pick", 0.8)
					pick(id)
				end
			end)
			table.insert(slots, { frame = frame, id = id, edge = edge, scale = scale })
		end
		if editor then
			local frame, edge = disc(ring, "Plus", SLOT)
			place(frame, foot)
			local scale = Instance.new("UIScale")
			scale.Parent = frame
			local cross = Widgets.label(frame, "+", 90, C.Gold, nil, C.Edge)
			cross.Position = UDim2.fromOffset(0, -PLUS_LIFT)
			local mark = Widgets.label(frame, "DONE", 34, C.Gold, nil, C.Edge)
			local waiting = false
			for _, id in editor.owned() do
				if editor.isNew(id) and not table.find(ids, id) then
					waiting = true
				end
			end
			local tag = EmoteWheel.newTag(frame, 40)
			tag.Visible = waiting
			frame.MouseEnter:Connect(function()
				light(nil)
				Widgets.tween(scale, 0.1, { Scale = 1.08 })
			end)
			frame.MouseLeave:Connect(function()
				Widgets.tween(scale, 0.1, { Scale = 1 })
			end)
			frame.Activated:Connect(function()
				if not busy then
					UiSound.play("Tab", 0.8)
					setEditing(not editing)
				end
			end)
			plus = { frame = frame, edge = edge, scale = scale, cross = cross, mark = mark, tag = tag }
		end
		if editing then
			fill()
		end
		paint()
	end

	function wheel.close()
		local shown = if gui.Enabled then editor else nil
		picking = nil
		holding = false
		editor = nil
		editing = false
		chosen = nil
		panel.Visible = false
		gui.Enabled = false
		if shown then
			task.spawn(shown.closed)
		end
	end

	function wheel.isOpen(): boolean
		return gui.Enabled
	end

	function wheel.open(ids: { string }, onPick: (id: string?) -> (), changer: Editor?)
		editor = changer
		picking = onPick
		holding = false
		editing = false
		chosen = nil
		panel.Visible = false
		show(ids)
		catcher.Visible = true
		gui.Enabled = true
	end

	function wheel.hold(ids: { string })
		editor = nil
		picking = nil
		holding = true
		editing = false
		chosen = nil
		panel.Visible = false
		show(ids)
		catcher.Visible = false
		gui.Enabled = true
	end

	function wheel.release(): string?
		local id = if holding and pointed then slots[pointed].id else nil
		wheel.close()
		return id
	end

	catcher.Activated:Connect(function()
		if not busy then
			wheel.close()
		end
	end)
	middle.Activated:Connect(function()
		if picking and not editing and not busy then
			local pick = picking
			wheel.close()
			pick(nil)
		end
	end)
	middle.MouseEnter:Connect(function()
		if picking then
			light(nil)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not holding or not gui.Enabled or #slots == 0 then
			return
		end
		local centre = ring.AbsolutePosition + ring.AbsoluteSize / 2
		local offset = UserInputService:GetMouseLocation() - centre
		local scale = ring.AbsoluteSize.X / ring.Size.X.Offset
		if offset.Magnitude < DEAD * scale then
			light(nil)
			return
		end
		local angle = math.atan2(offset.Y, offset.X)
		local best, closest = nil, math.huge
		for i = 1, #slots do
			local at = -math.pi / 2 + (i - 1) * 2 * math.pi / #slots
			local apart = math.abs((angle - at + math.pi) % (2 * math.pi) - math.pi)
			if apart < closest then
				best, closest = i, apart
			end
		end
		light(best)
	end)
	return wheel
end

return EmoteWheel
