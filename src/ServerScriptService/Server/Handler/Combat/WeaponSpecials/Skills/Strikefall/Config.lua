local module = {}

module.ActionName = "Strikefall"

module.Keyframes = table.freeze({
	OpeningHit = table.freeze({
		hit = true,
		hitbox = true,
		strike = true,
	}),
	ComboHitOne = table.freeze({
		hit = true,
	}),
	ComboHitTwo = table.freeze({
		hit2 = true,
		finisher = true,
	}),
})

module.VfxOffsets = table.freeze({
	OpeningBams = CFrame.new(-0.194, -0.5, 1.608),
	ComboHitOneBams = CFrame.new(1.206, -0.5, 1.608),
	ComboHitTwoBams = CFrame.new(-0.194, -0.5, 1.608),
	Cacas = CFrame.new(-0.594, -0.1, 4.408),
})

module.Defaults = table.freeze({
	Cooldown = 8.5,
	IndicatorColor = "red",
	AttackWalkSpeed = 4,
	OpeningSwingSpeed = 0.95,
	ComboSwingSpeed = 0.98,
	ComboFirstSwingSpeed = 0.85,
	StateReleasePadding = 0.06,
	HitboxFallbackDelay = 0.12,
	OpeningHitboxActiveTime = 0.1,
	ComboHitboxActiveTime = 0.1,
	ComboForReaction = 4,
	Damage = 6,
	OpeningHitboxSize = Vector3.new(5, 8, 10),
	OpeningHitboxOffset = CFrame.new(0, 0, -5.5),
	ComboHitboxSize = Vector3.new(5, 7, 12),
	ComboHitboxOffset = CFrame.new(0, 0, -5.5),
	OpeningKnockback = 15,
	ComboHitOneKnockback = 18,
	ComboHitTwoKnockback = 12,
	Stun = 0.4,
	ForwardSpeed = 10,
	ForwardDuration = 0.2,
	FailsafeRelease = 4,
})

return table.freeze(module)
