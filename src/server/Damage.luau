-- What items do to damage (Config.Items): a hero's Armor and Resist take the physical and magic damage he takes down to
-- 100 / (100 + them), his Lifesteal heals him by a share of what he deals, and the legendary effects that change a
-- hit: Kingsbane on the enemy Master, Stormcrown on magic, Void Scepter through Resist, Crown Bulwark near the hero's
-- own Master and Bloodthorn while he is low; and the Sun Crown's extra damage for its carrier and his team
-- (CrownService).
-- Attackers and victims are players or bots (Actors).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HeroKit = require(ReplicatedStorage.Shared.HeroKit)
local Items = require(ReplicatedStorage.Shared.Items)
local Actors = require(script.Parent.Actors)

local Damage = {}

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

-- `attacker`'s hit of `amount` on `target` with his items' effects, before the target's defence.
function Damage.outgoing(attacker: Instance, amount: number, magic: boolean, target: Instance): number
	if target:IsA("Model") and target:GetAttribute("Master") then
		amount *= 1 + (Items.effect(attacker, "Kingsbane") or 0)
	end
	if magic then
		amount *= 1 + (Items.effect(attacker, "Stormcrown") or 0)
	end
	local character = Actors.character(attacker)
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

-- What is left of `amount` of physical or magic damage on the hero `victim` after his Armor or Resist; `attacker`,
-- if a hero, may pierce Resist.
function Damage.mitigated(victim: Model, amount: number, magic: boolean, attacker: Instance?): number
	local owner = Actors.owner(victim)
	if not owner then
		return amount
	end
	local stats = Items.stats(owner)
	local defence = if magic then stats.Resist else stats.Armor
	local guard = Items.effect(owner, "CrownBulwark")
	if guard and nearOwnMaster(victim) then
		defence += guard
	end
	if magic and attacker then
		defence *= 1 - (Items.effect(attacker, "VoidScepter") or 0)
	end
	return amount * 100 / (100 + defence)
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
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + dealt * share)
end

return Damage
