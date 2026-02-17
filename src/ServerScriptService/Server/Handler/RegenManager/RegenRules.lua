local module = {}

function module.new(deps)
	local config = deps.Config
	local CollectionService = deps.CollectionService
	local StateManager = deps.StateManager

	local rules = {}

	function rules.IsDowned(player: Player, character: Model): boolean
		if character:GetAttribute("Downed") == true then
			return true
		end
		return StateManager.GetState(player, "Downed") == true
	end

	function rules.IsInCombat(player: Player, character: Model): boolean
		local combatTag = config.CombatTag
		if CollectionService:HasTag(player, combatTag) then
			return true
		end
		if CollectionService:HasTag(character, combatTag) then
			return true
		end
		if player:GetAttribute(combatTag) == true then
			return true
		end
		if character:GetAttribute(combatTag) == true then
			return true
		end
		return StateManager.GetState(player, combatTag) == true
	end

	function rules.IsRegenBlockedCommon(player: Player, character: Model, humanoid: Humanoid): boolean
		if humanoid.Health <= 0 then
			return true
		end
		if player:GetAttribute("Wiped") == true then
			return true
		end
		if character:GetAttribute("NoRegen") == true then
			return true
		end
		if character:GetAttribute("Carried") == true then
			return true
		end
		if character:GetAttribute("Gripping") == true then
			return true
		end
		return false
	end

	return rules
end

return module
