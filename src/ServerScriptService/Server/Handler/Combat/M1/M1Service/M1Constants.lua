local RS = game:GetService("ReplicatedStorage")
local CombatStateRules = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))

local M1Constants = {
	Attributes = {
		Combo = "Combo",
		Swing = "Swing",
		Attacking = "Attacking",
		CombatTag = "Combats",
	},

	BlockedSelfAttrs = CombatStateRules.M1BlockedAttrs,

	BlockedTargetAttrs = {
		"IsRagdoll",
		"Downed",
		"Carried",
		"Gripped",
	},
}

return table.freeze(M1Constants)
