-- The armory (design 08, Config.Shop, Config.Items). A client asks through ReplicatedStorage.Net.Shop (action,
-- argument): "Buy" an item, "Sell" the item in a slot, "Undo" the last purchase or sale, "Drink" a potion. The server
-- checks each (Shared.Items) and keeps every bag in its actor's attributes (Items), with "AtShop" whether he can shop
-- where he stands: at one of his team's armory stalls, or while dead. Each stall has an invisible part in
-- Workspace.Armories, with its "Team", where the clients hang the prompt that opens the armory (Shop). What he bought
-- and sold there can be undone until he leaves or drinks. A potion heals over Potion.Time seconds; one drunk while
-- another still heals starts after it. Bots (BotService) shop through the same functions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Actors = require(script.Parent.Actors)
local ProgressService = require(script.Parent.ProgressService)

local ShopService = {}

local SETTINGS = Config.Shop
local SLOTS = SETTINGS.Slots
-- How often "AtShop" is brought up to date, and potions heal.
local LOOK = 0.25
local POTION_TICK = 0.5

-- A purchase or sale that can be undone: the bag before it, and what it did to the coins.
type Change = { bag: { [number]: Items.Slot }, coins: number }

local history: { [Instance]: { Change } } = {}
local shops: { [string]: { Vector3 } } = {}

local function living(actor: Instance): (Model?, Humanoid?, BasePart?)
	local character = Actors.character(actor)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- Whether `actor` can shop where he is now.
function ShopService.atShop(actor: Instance): boolean
	local character, _, root = living(actor)
	if not character or not root then
		return true
	end
	local team = character:GetAttribute("Team") or "Blue"
	for _, spot in shops[team] or {} do
		if HeroKit.flat(root.Position - spot).Magnitude <= SETTINGS.Reach then
			return true
		end
	end
	return false
end

local function copy(bag: { [number]: Items.Slot }): { [number]: Items.Slot }
	local out = {}
	for i, slot in bag do
		out[i] = { id = slot.id, count = slot.count }
	end
	return out
end

-- Puts `bag` in `actor`'s attributes, and what his items do on his hero: health, walk and attack speed.
local function put(actor: Instance, bag: { [number]: Items.Slot })
	for i = 1, SLOTS do
		local slot = bag[i]
		actor:SetAttribute("Item" .. i, if slot then slot.id else "")
		actor:SetAttribute("Count" .. i, if slot then slot.count else 0)
	end
	local character = Actors.character(actor)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	character:SetAttribute("AttackSpeed", Items.attackSpeed(actor))
	ProgressService.refresh(actor)
	-- A hero slowed by his own motion gets his speed back from CombatService and HeroControls.
	if humanoid.WalkSpeed >= Config.Combat.WalkSpeed then
		humanoid.WalkSpeed = Items.walkSpeed(actor)
	end
end

local function remember(actor: Instance, bag: { [number]: Items.Slot }, coins: number)
	local list = history[actor] or {}
	table.insert(list, { bag = copy(bag), coins = coins })
	history[actor] = list
end

local function coinsOf(actor: Instance): number
	return actor:GetAttribute("Coins") or 0
end

-- `actor` buys `id`; whether he did, else why not.
function ShopService.buy(actor: Instance, id: string): (boolean, string?)
	if not ShopService.atShop(actor) then
		return false, "Go to your armory"
	end
	local ok, why, price, used = Items.check(actor, id)
	if not ok then
		return false, why
	end
	local bag = Items.bag(actor)
	remember(actor, bag, -price)
	for _, i in used do
		bag[i] = nil
	end
	local placed = false
	if Config.Items[id].Potion then
		for _, slot in bag do
			if slot.id == id then
				slot.count += 1
				placed = true
				break
			end
		end
	end
	if not placed then
		for i = 1, SLOTS do
			if not bag[i] then
				bag[i] = { id = id, count = 1 }
				break
			end
		end
	end
	actor:SetAttribute("Coins", coinsOf(actor) - price)
	put(actor, bag)
	return true, nil
end

-- `actor` sells one of what is in slot `index`.
function ShopService.sell(actor: Instance, index: number): boolean
	local bag = Items.bag(actor)
	local slot = bag[index]
	if not slot or not ShopService.atShop(actor) then
		return false
	end
	local refund = Items.refund(slot.id)
	remember(actor, bag, refund)
	slot.count -= 1
	if slot.count <= 0 then
		bag[index] = nil
	end
	actor:SetAttribute("Coins", coinsOf(actor) + refund)
	put(actor, bag)
	return true
end

-- Takes back `actor`'s last purchase or sale at the armory.
function ShopService.undo(actor: Instance): boolean
	local list = history[actor]
	local last = list and table.remove(list)
	if not last or not ShopService.atShop(actor) then
		return false
	end
	actor:SetAttribute("Coins", coinsOf(actor) - last.coins)
	put(actor, last.bag)
	return true
end

-- `actor` drinks a potion, if he carries one and his hero lives.
function ShopService.drink(actor: Instance): boolean
	if not living(actor) then
		return false
	end
	local bag = Items.bag(actor)
	for i, slot in bag do
		if Config.Items[slot.id].Potion then
			slot.count -= 1
			if slot.count <= 0 then
				bag[i] = nil
			end
			local now = Workspace:GetServerTimeNow()
			local from = math.max(now, actor:GetAttribute("PotionUntil") or 0)
			actor:SetAttribute("PotionUntil", from + SETTINGS.Potion.Time)
			history[actor] = nil
			put(actor, bag)
			return true
		end
	end
	return false
end

local function heal()
	local now = Workspace:GetServerTimeNow()
	for _, actor in Actors.all() do
		local ends = actor:GetAttribute("PotionUntil")
		if not ends or ends <= now then
			continue
		end
		local _, humanoid = living(actor)
		if not humanoid then
			actor:SetAttribute("PotionUntil", nil)
			continue
		end
		local amount = SETTINGS.Potion.Heal / SETTINGS.Potion.Time * POTION_TICK
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

local function look()
	for actor in history do
		if not actor.Parent then
			history[actor] = nil
		end
	end
	for _, actor in Actors.all() do
		local here = ShopService.atShop(actor)
		if actor:GetAttribute("AtShop") ~= here then
			actor:SetAttribute("AtShop", here)
		end
		if not here then
			history[actor] = nil
		end
	end
end

export type Layout = {
	shops: { [string]: { CFrame } },
}

function ShopService.start(layout: Layout)
	local armories = Instance.new("Folder")
	armories.Name = "Armories"
	for team, list in layout.shops do
		shops[team] = {}
		for _, spot in list do
			table.insert(shops[team], spot.Position)
			local anchor = Instance.new("Part")
			anchor.Name = "Armory"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Transparency = 1
			anchor.Size = Vector3.one
			anchor.CFrame = CFrame.new(spot.Position + Vector3.new(0, 3, 0))
			anchor:SetAttribute("Team", team)
			anchor.Parent = armories
		end
	end
	armories.Parent = Workspace
	local net = ReplicatedStorage:WaitForChild("Net")
	local event = Instance.new("RemoteEvent")
	event.Name = "Shop"
	event.Parent = net
	event.OnServerEvent:Connect(function(player, action, argument)
		if action == "Buy" and typeof(argument) == "string" and Config.Items[argument] then
			ShopService.buy(player, argument)
		elseif action == "Sell" and typeof(argument) == "number" and argument == argument then
			ShopService.sell(player, math.floor(argument))
		elseif action == "Undo" then
			ShopService.undo(player)
		elseif action == "Drink" then
			ShopService.drink(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(LOOK)
			look()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(POTION_TICK)
			heal()
		end
	end)
end

return ShopService
