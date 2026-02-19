local module = {}

module.ActionName = "AnchoringStrike"

module.Keyframes = table.freeze({
	Emit = table.freeze({
		emit = true,
	}),
	Enable = table.freeze({
		enable = true,
	}),
	Hit = table.freeze({
		hit = true,
		hitbox = true,
	}),
	Stop = table.freeze({
		stop = true,
		["end"] = true,
	}),
})

module.VfxOffsets = table.freeze({
	Emit = CFrame.new(0.391, 0.526, 2.956),
	EnableOne = CFrame.new(0.391, 0.526, 2.956),
	EnableTwo = CFrame.new(2.391, 0.526, 2.956),
})

module.Defaults = table.freeze({
	Cooldown = 9.5,
	IndicatorColor = "yellow",
	AttackWalkSpeed = 0,
	SwingSpeed = 1.2,
	HitSwingSpeed = 1.4,
	StateReleasePadding = 0.06,
	HitboxFallbackDelay = 0.12,
	Damage = 8,
	Knockback = 12,
	Stun = 0.45,
	ComboForReaction = 4,
	HitboxSize = Vector3.new(6, 8, 18),
	HitboxOffset = CFrame.new(0, 0, -8),
	PullDistance = 3,
	PullDuration = 0.3,
	PullForce = 250000,
	PullMaxSpeed = 48,
	PullStopDistance = 0.9,
	PullVerticalVelocityMax = 0,
	RecoilSpeed = 32,
	RecoilDuration = 0.1,
	HyperArmorDuration = 0.95,
	HyperArmorDamageMultiplier = 0.6,
	HitboxActiveTime = 0.1,
	FailsafeRelease = 4,
})

return table.freeze(module)
