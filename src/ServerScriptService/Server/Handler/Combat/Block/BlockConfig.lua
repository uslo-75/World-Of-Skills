local RS = game:GetService("ReplicatedStorage")
local CombatStateRules = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))

return {
	BlockWalkSpeed = 6,
	RestoreWalkSpeed = 9,

	ParryFrame = 0.145,
	ParryHitCooldown = 0.2,
	ParryMissCooldown = 1.1,
	PostureDecayStartDelay = 1.2,
	PostureDecayInterval = 0.25,
	PostureDecayPerSecond = 7,

	BlockedStartAttrs = CombatStateRules.DefenseStartBlockedAttrs,

	BlockedStartStates = CombatStateRules.DefenseStartBlockedStates,

	InterruptAttrs = CombatStateRules.DefenseInterruptAttrs,

	RestoreBlockedAttrs = CombatStateRules.DefenseRestoreBlockedAttrs,
}
