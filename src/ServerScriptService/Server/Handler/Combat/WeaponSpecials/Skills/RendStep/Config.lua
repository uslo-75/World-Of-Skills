local module = {}

module.ActionName = "RendStep"

module.Keyframes = table.freeze({
	Teleport = table.freeze({
		tp = true,
		teleport = true,
	}),
	Hit = table.freeze({
		hit = true,
		hitbox = true,
	}),
})

module.VfxOffsets = table.freeze({
	TeleportOne = CFrame.new(0.9, 0.071, 0.456) * CFrame.Angles(0, 0, math.rad(-90)),
	TeleportTwo = CFrame.new(-0.071, -2.926, 1.144) * CFrame.Angles(0, math.rad(180), math.rad(180)),
	Hit = CFrame.new(-0.209, -1.78, 2.556),
})

module.Defaults = table.freeze({
	Cooldown = 9.5,
	IndicatorColor = "red",
	AttackWalkSpeed = 0,
	StartupSwingSpeed = 2,
	HitSwingSpeed = 1,
	MissSwingSpeed = 1.25,
	StateReleasePadding = 0.06,
	HitboxFallbackDelay = 0.12,
	Damage = 10,
	Knockback = 12,
	Stun = 0.4,
	ComboForReaction = 4,
	HitboxSize = Vector3.new(7, 8, 8),
	HitboxOffset = CFrame.new(0, 0, 1.5),
	TargetDistance = 25,
	TargetConeAngle = 100,
	MissDashSpeed = 38,
	MissDashDuration = 0.2,
	HitStepDistance = 8,
	TeleportBehindDistance = 2.5,
	InvulnerableDuration = 1.35,
	HitboxActiveTime = 0.1,
	FailsafeRelease = 4,
})

return table.freeze(module)
