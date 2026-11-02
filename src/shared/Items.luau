-- What a hero carries (Config.Shop, Config.Items), the same on the server and the client. A player's or bot's bag is
-- in the server's attributes on it (Actors): "Item" .. n the item in slot n ("" when empty) and "Count" .. n how many
-- (potions stack), for n from 1 to Config.Shop.Slots; "PotionUntil" is when the potions he drank stop healing (server
-- time).

local Workspace = game:GetService("Workspace")

local Boosts = require(script.Parent.Boosts)
local Config = require(script.Parent.Config)

local Items = {}

local SLOTS = Config.Shop.Slots
local TIERS = { Basic = 1, Epic = 2, Legendary = 3 }

export type Slot = { id: string, count: number }

export type Stats = {
	Attack: number,
	Magic: number,
	Health: number,
	Armor: number,
	Resist: number,
	AttackSpeed: number,
	Haste: number,
	Lifesteal: number,
	MoveSpeed: number,
}

-- How the armory names each stat, and whether it shows as a share.
Items.StatNames = {
	{ key = "Attack", name = "Attack" },
	{ key = "Magic", name = "Magic" },
	{ key = "Health", name = "Health" },
	{ key = "Armor", name = "Armor" },
	{ key = "Resist", name = "Resist" },
	{ key = "AttackSpeed", name = "Attack Speed", share = true },
	{ key = "Haste", name = "Haste" },
	{ key = "Lifesteal", name = "Lifesteal", share = true },
	{ key = "MoveSpeed", name = "Move Speed" },
}

function Items.get(id: string?): any
	return id and Config.Items[id]
end

-- Whether `id` is made for `class` (Config.Items' `Classes`); with no class, every item is.
function Items.fits(id: string, class: string?): boolean
	local classes = Config.Items[id].Classes
	return class == nil or classes == nil or table.find(classes, class) ~= nil
end

-- The build the armory recommends to `hero` (his own, else his class's), or `class`'s build when it is given and not
-- his class.
function Items.build(hero: string?, class: string?): { string }
	local settings = hero and Config.Heroes[hero]
	local own = settings and settings.Role
	if class and class ~= own then
		return table.clone(Config.ClassBuilds[class] or {})
	end
	if settings and settings.Build then
		return table.clone(settings.Build)
	end
	return table.clone(own and Config.ClassBuilds[own] or {})
end

-- The items of `category` made for `class` (all when nil), cheapest first within each tier; "Recommended" is the build
-- of Items.build.
function Items.list(category: string, hero: string?, class: string?): { string }
	if category == "Recommended" then
		return Items.build(hero, class)
	end
	local list = {}
	for id, item in Config.Items do
		if item.Category == category and Items.fits(id, class) then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b)
		local x, y = Config.Items[a], Config.Items[b]
		if TIERS[x.Tier] ~= TIERS[y.Tier] then
			return TIERS[x.Tier] < TIERS[y.Tier]
		end
		if x.Cost ~= y.Cost then
			return x.Cost < y.Cost
		end
		return x.Name < y.Name
	end)
	return list
end

-- The bag of `actor`, slot by slot (nil where empty).
function Items.bag(actor: Instance): { [number]: Slot }
	local bag = {}
	for i = 1, SLOTS do
		local id = actor:GetAttribute("Item" .. i)
		if typeof(id) == "string" and Config.Items[id] then
			bag[i] = { id = id, count = actor:GetAttribute("Count" .. i) or 1 }
		end
	end
	return bag
end

-- How many of `id` `actor` carries.
function Items.count(actor: Instance, id: string): number
	local n = 0
	for _, slot in Items.bag(actor) do
		if slot.id == id then
			n += slot.count
		end
	end
	return n
end

-- What `actor`'s items add up to.
function Items.stats(actor: Instance): Stats
	local total = {
		Attack = 0,
		Magic = 0,
		Health = 0,
		Armor = 0,
		Resist = 0,
		AttackSpeed = 0,
		Haste = 0,
		Lifesteal = 0,
		MoveSpeed = 0,
	}
	for _, slot in Items.bag(actor) do
		for key, value in Config.Items[slot.id].Stats do
			total[key] += value
		end
	end
	return total :: any
end

-- The value of the effect `kind` if `actor` carries it, the strongest of his items that have it, and that effect.
function Items.effect(actor: Instance, kind: string): (number?, any)
	local best = nil
	for _, slot in Items.bag(actor) do
		local effect = Config.Items[slot.id].Effect
		if effect and effect.Kind == kind and (not best or effect.Value > best.Value) then
			best = effect
		end
	end
	return best and best.Value, best
end

-- With the Wind Gem's speed while his team carries it (Boosts), and slower while a net statue's net holds him (his
-- "Netted" attribute, until when in server time, HazardService).
function Items.walkSpeed(actor: Instance): number
	local speed = (Config.Combat.WalkSpeed + Items.stats(actor).MoveSpeed) * (1 + Boosts.bonus(actor, "Speed"))
	local netted = actor:GetAttribute("Netted")
	if netted and netted > Workspace:GetServerTimeNow() then
		speed *= Config.NetStatues.Slow
	end
	return speed
end

-- How much faster than the kit's `Speed` the M1 combo plays.
function Items.attackSpeed(actor: Instance): number
	return 1 + Items.stats(actor).AttackSpeed
end

-- What the parts of `id` that are in `pool` (slot to item, taken out as they are used) leave to pay; their slots go
-- into `used`. A part he lacks counts with its own parts he holds.
local function rest(id: string, pool: { [number]: string }, used: { number }): number
	local item = Config.Items[id]
	local cost = item.Cost
	for _, part in item.From or {} do
		local found: number? = nil
		for i, held in pool do
			if held == part then
				found = i
				break
			end
		end
		if found then
			pool[found] = nil
			table.insert(used, found)
			cost -= Config.Items[part].Cost
		else
			cost -= Config.Items[part].Cost - rest(part, pool, used)
		end
	end
	return cost
end

-- What `id` costs `actor` now, and the slots of the parts he holds that go into it.
function Items.price(actor: Instance, id: string): (number, { number })
	local pool = {}
	for i, slot in Items.bag(actor) do
		if not Config.Items[slot.id].Potion then
			pool[i] = slot.id
		end
	end
	local used = {}
	return rest(id, pool, used), used
end

-- Whether `actor` may buy `id` now (where he stands aside), else why not; what it costs him and the parts it uses.
function Items.check(actor: Instance, id: string): (boolean, string?, number, { number })
	local item = Config.Items[id]
	if not item then
		return false, "Unknown item", 0, {}
	end
	local price, used = Items.price(actor, id)
	local bag = Items.bag(actor)
	local free = #used
	for i = 1, SLOTS do
		if not bag[i] then
			free += 1
		end
	end
	if item.Potion then
		local stacked = false
		for _, slot in bag do
			if slot.id == id then
				if slot.count >= Config.Shop.Potion.Stack then
					return false, "You carry " .. Config.Shop.Potion.Stack .. " already", price, used
				end
				stacked = true
			end
		end
		if stacked then
			free = math.max(free, 1)
		end
	else
		for i, slot in bag do
			local held = Config.Items[slot.id]
			if item.Boots and held.Boots and not table.find(used, i) then
				return false, "Only one pair of boots", price, used
			end
			if item.Tier == "Legendary" and slot.id == id then
				return false, "You own it already", price, used
			end
		end
	end
	if free < 1 then
		return false, "Your bag is full", price, used
	end
	if (actor:GetAttribute("Coins") or 0) < price then
		return false, "Not enough coins", price, used
	end
	return true, nil, price, used
end

-- What selling one of `id` gives back.
function Items.refund(id: string): number
	return math.floor(Config.Items[id].Cost * Config.Shop.Sell)
end

-- The share `x` as "12%", a number as "10" or "1.5".
local function number(x: number, share: boolean?): string
	if share then
		return math.round(x * 100) .. "%"
	end
	return if x == math.floor(x) then tostring(x) else string.format("%.1f", x)
end

-- The armory's lines for `id`'s stats: "+10 Attack".
function Items.lines(id: string): { string }
	local item = Config.Items[id]
	local lines = {}
	for _, stat in Items.StatNames do
		local value = item.Stats[stat.key]
		if value then
			table.insert(lines, "+" .. number(value, stat.share) .. " " .. stat.name)
		end
	end
	return lines
end

return Items
