local module = {}

module.Name = "MSword"
module.Data = {
	-- Blade
	Damage = 8,
	SwingSpeed = 0.70,
	WaitBetweenHits = 0.15,
	SwordSwingPause = 0.1,
	HitboxSize = Vector3.new(5.5, 6, 5.5),
	HitboxOffset = CFrame.new(0, 0, -4),
	-- Handle
	HeavyDamage = 12,
	HeavyKB = 15,
	HeavyRagDoll = false,
	HeavyRagDuration = 0,
	HeavyHitboxSize = Vector3.new(8, 8, 8),
	HeavyHitboxOffset = CFrame.new(0, 0, 0),
	HeavyForwardTime = 0.10,
	HeavyCooldown = 6,
	--
	AerialCooldown = 5,
	AerialKB = 12,
	AerialHitboxSize = Vector3.new(6.25, 6, 6),
	AerialHitboxOffset = CFrame.new(0, 0, -4),
	--
	RunningCooldown = 3.6,
	RunningKB = 15,
	RunningHitboxSize = Vector3.new(5.5, 6, 6.5),
	RunningHitboxOffset = CFrame.new(0, 0, -4),
	--
	Z = "WhirlwindFlourish",
	X = "FlashStrike",
	C = "StaticFlourish",
	--
	Description = "A versatile medium sword for balanced offense and defense. Ideal for quick slashes and moderate reach.",
}

return module
