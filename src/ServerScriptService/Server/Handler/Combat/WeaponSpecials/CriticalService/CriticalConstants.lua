local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatStateRules =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))

local CriticalConstants = {
	Attributes = {
		Swing = "Swing",
		Attacking = "Attacking",
		Cooldown = "HeavyCooldown",
		CooldownTime = "HeavyCooldownTime",
	},

	BlockedSelfAttrs = CombatStateRules.M1BlockedAttrs,
}

return table.freeze(CriticalConstants)
