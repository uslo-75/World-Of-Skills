local module = {}

module.Name = "Mele"
module.Data = {
	-- Blade
	Damage = 5.8,
	SwingSpeed = 0.85,
	WaitBetweenHits = 0.10,
	SwordSwingPause = 0.15,
	HitboxSize = Vector3.new(6, 6, 5.5),
	HitboxOffset = CFrame.new(0, 0, -3),
	-- Handle
	HeavyDamage = 8,
	HeavyKB = 25,
	HeavyRagDoll = true,
	HeavyRagDuration = 0.52,
	HeavyHitboxSize = Vector3.new(12, 8, 12),
	HeavyHitboxOffset = CFrame.new(0, 0, -1.6),
	HeavyForwardSpeed = 20,
	HeavyForwardTime = 0.10,
	HeavyCooldown = 6,
	--
	AerialCooldown = 8.2,
	AerialKB = 15,
	AerialHitboxSize = Vector3.new(7, 7, 7),
	AerialHitboxOffset = CFrame.new(0, -1.8, -7.5),
	--
	RunningCooldown = 6.8,
	RunningKB = 28,
	RunningHitboxSize = Vector3.new(5.5, 6, 6.5),
	RunningHitboxOffset = CFrame.new(0, 0, -4),
	--
	Z = "Strikefall",
	X = "RendStep",
	C = "AnchoringStrike",
	--
	Description = "A versatile medium sword for balanced offense and defense. Ideal for quick slashes and moderate reach.",
}

return module
