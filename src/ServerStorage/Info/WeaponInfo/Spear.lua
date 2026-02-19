local module = {}

module.Name = "Spear"
module.Data = {
	-- Blade
	Damage = 6.5,
	SwingSpeed = 0.70,
	WaitBetweenHits = 0.15,
	SwordSwingPause = 0.1,
	HitboxSize = Vector3.new(4.25, 6, 4.25),
	HitboxOffset = CFrame.new(0, 0, -5.65),
	-- Handle
	HeavyDamage = 10,
	HeavyKB = 14,
	HeavyRagDoll = false,
	HeavyRagDuration = 0,
	HeavyHitboxSize = Vector3.new(8.5, 8, 8.5),
	HeavyHitboxOffset = CFrame.new(0, 0, -4),
	HeavyForwardTime = 0.10,
	HeavyCooldown = 6,
	--
	AerialCooldown = 5,
	AerialKB = 12,
	AerialHitboxSize = Vector3.new(6.25, 6, 6),
	AerialHitboxOffset = CFrame.new(0, 0, -5.5),
	--
	RunningCooldown = 3.6,
	RunningKB = 15,
	RunningHitboxSize = Vector3.new(5.5, 6, 6.5),
	RunningHitboxOffset = CFrame.new(0, 0, -6.5),
	--
	Z = "None",
	X = "None",
	C = "None",
	--
	Description = "A polearm with extended range and precision. Excellent for poking enemies from a safe distance.",
}

return module
