-- What items do to damage (Config.Items): a hero's Armor and Resist take the physical and magic damage he takes down to
-- 100 / (100 + them), his Lifesteal heals him by a share of what he deals, and the effects that change a hit: Kingsbane
-- on the enemy Master, Stormcrown on magic, Soulfire on low heroes, Farshot from afar, Tempest on every third M1,
-- Colossus by the hero's max health, Nightveil on a hero not hit for a while; Void Scepter through Resist, Rending Pick
-- and Sunderer through Armor, Crown Bulwark near the hero's own Master, Ironroot once he is low, Spellward's shield
-- against magic, and Bloodthorn's lifesteal while he is low. Wound and Thorns wound heroes, who then heal less from
-- lifesteal, potions (ShopService) and pads (PadService); Thornwall sends part of an M1 back (CombatService). And the
-- Sun Crown's extra damage for its carrier and his team (CrownService).
-- Attackers and victims are players or bots (Actors).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Actors = require(script.Parent.Actors)

local Damage = {}

-- Per attacker and target: his M1 hits on it in a row (Tempest), and when he last hit the hero (Nightveil).
local tempest: { [Instance]: { target: Instance, count: number } } = setmetatable({}, { __mode = "k" }) :: any
local lastHit: { [Instance]: { [Instance]: number } } = setmetatable({}, { __mode = "k" }) :: any
-- Per hero's owner: his wound (the share he heals less, until when), when his Ironroot last caught him and how long
-- it holds, and what is left of his Spellward shield since the last magic damage.
local wounds: { [Instance]: { share: number, ends: number } } = setmetatable({}, { __mode = "k" }) :: any
local ironroot: { [Instance]: { at: number, ends: number } } = setmetatable({}, { __mode = "k" }) :: any
local wards: { [Instance]: { left: number, at: number } } = setmetatable({}, { __mode = "k" }) :: any

local function nearOwnMaster(character: Model): boolean
	local team = character:GetAttribute("Team")
	local position = character:GetPivot().Position
	for _, model in CollectionService:GetTagged("Combatant") do
		if
			model:IsA("Model")
			and model:GetAttribute("Master")
			and model:GetAttribute("Team") == team
			and HeroKit.flat(model:GetPivot().Position - position).Magnitude <= Config.Shop.GuardReach
		then
			return true
		end
	end
	return false
end

local function positionOf(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

local function isHero(target: Instance): boolean
	return target:IsA("Model") and target:GetAttribute("Hero") ~= nil
end

-- `attacker`'s hit of `amount` on `target` with his items' effects, before the target's defence; `basic` when it is
-- an M1 hit.
function Damage.outgoing(attacker: Instance, amount: number, magic: boolean, target: Instance, basic: boolean?): number
	local now = os.clock()
	local hero = isHero(target)
	local humanoid = if hero then (target :: Model):FindFirstChildOfClass("Humanoid") else nil
	if target:IsA("Model") and target:GetAttribute("Master") then
		amount *= 1 + (Items.effect(attacker, "Kingsbane") or 0)
	end
	if magic then
		amount *= 1 + (Items.effect(attacker, "Stormcrown") or 0)
		local soulfire, effect = Items.effect(attacker, "Soulfire")
		if soulfire and humanoid and humanoid.Health < humanoid.MaxHealth * effect.Below then
			amount *= 1 + soulfire
		end
	end
	local character = Actors.character(attacker)
	local farshot, far = Items.effect(attacker, "Farshot")
	local at = positionOf(target)
	if farshot and character and at then
		local distance = HeroKit.flat(at - character:GetPivot().Position).Magnitude
		amount *= 1 + farshot * math.clamp((distance - far.From) / (far.To - far.From), 0, 1)
	end
	local surge, storm = Items.effect(attacker, "Tempest")
	if surge and basic then
		local run = tempest[attacker]
		if not run or run.target ~= target then
			run = { target = target, count = 0 }
			tempest[attacker] = run
		end
		run.count += 1
		if run.count >= storm.Every then
			run.count = 0
			amount *= 1 + surge
		end
	end
	if hero then
		local colossus = Items.effect(attacker, "Colossus")
		if colossus and humanoid then
			amount += humanoid.MaxHealth * colossus
		end
		local hits = lastHit[attacker] or setmetatable({}, { __mode = "k" }) :: any
		lastHit[attacker] = hits
		local veil, effect = Items.effect(attacker, "Nightveil")
		if veil and (not hits[target] or now - hits[target] >= effect.After) then
			amount *= 1 + veil
		end
		hits[target] = now
	end
	if
		character
		and Workspace:GetAttribute("Crown") == "Carried"
		and Workspace:GetAttribute("CrownTeam") == character:GetAttribute("Team")
	then
		local carries = character:GetAttribute("Crown") == true
		amount *= 1 + (if carries then Config.Crown.Carrier else Config.Crown.Damage)
	end
	return amount
end

-- What is left of `amount` of physical or magic damage on the hero `victim` after his Armor or Resist, his Ironroot
-- and his Spellward; `attacker`, if a hero, may pierce Resist or Armor.
function Damage.mitigated(victim: Model, amount: number, magic: boolean, attacker: Instance?): number
	local owner = Actors.owner(victim)
	if not owner then
		return amount
	end
	local now = os.clock()
	local stats = Items.stats(owner)
	local defence = if magic then stats.Resist else stats.Armor
	local guard = Items.effect(owner, "CrownBulwark")
	if guard and nearOwnMaster(victim) then
		defence += guard
	end
	if attacker then
		defence *= 1 - (Items.effect(attacker, if magic then "VoidScepter" else "ArmorPierce") or 0)
	end
	amount *= 100 / (100 + defence)

	local ward, shield = Items.effect(owner, "Spellward")
	if ward and magic then
		local state = wards[owner]
		if not state or now - state.at >= shield.Refill then
			state = { left = ward, at = now }
			wards[owner] = state
		end
		local taken = math.min(state.left, amount)
		state.left -= taken
		state.at = now
		amount -= taken
	end

	local root, effect = Items.effect(owner, "Ironroot")
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		local state = ironroot[owner]
		if
			(not state or now - state.at >= effect.Cooldown)
			and humanoid.Health - amount < humanoid.MaxHealth * effect.Below
		then
			state = { at = now, ends = now + effect.Time }
			ironroot[owner] = state
		end
		if state and now < state.ends then
			amount *= 1 - root
		end
	end
	return amount
end

-- Wounds `owner`'s hero: he heals `share` less for Shop.WoundTime seconds (a stronger wound overrides a weaker one).
function Damage.wound(owner: Instance, share: number)
	local now = os.clock()
	local current = wounds[owner]
	if current and now < current.ends and current.share > share then
		return
	end
	wounds[owner] = { share = share, ends = now + Config.Shop.WoundTime }
end

-- The share of a heal that `owner`'s hero gets now: less while he is wounded.
function Damage.healing(owner: Instance): number
	local current = wounds[owner]
	if current and os.clock() < current.ends then
		return 1 - current.share
	end
	return 1
end

-- After `attacker`'s hit on the hero `victim` has landed: his hits wound (Wound), and the victim's Thorns wound him.
-- Returns how much of the hit (`raw`, before the victim's defence) Thornwall sends back when it was an M1.
function Damage.struck(attacker: Instance, victim: Model, raw: number, basic: boolean?): number
	local owner = Actors.owner(victim)
	if not owner then
		return 0
	end
	local wound = Items.effect(attacker, "Wound")
	if wound then
		Damage.wound(owner, wound)
	end
	local thorns, effect = Items.effect(owner, "Thorns")
	if thorns and Actors.character(attacker) then
		Damage.wound(attacker, thorns)
		if basic and effect.Reflect then
			return raw * effect.Reflect
		end
	end
	return 0
end

-- Heals `attacker`'s hero `character` by his Lifesteal of the `dealt` damage.
function Damage.leech(attacker: Instance, character: Model, dealt: number)
	local share = Items.stats(attacker).Lifesteal
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if share <= 0 or not humanoid or humanoid.Health <= 0 then
		return
	end
	local low = Items.effect(attacker, "Bloodthorn")
	if low and humanoid.Health < humanoid.MaxHealth * low then
		share *= 2
	end
	share *= Damage.healing(attacker)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + dealt * share)
end

return Damage
