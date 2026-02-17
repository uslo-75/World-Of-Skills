local module = {}

local info = {
	["Blocking"] = {
		ParryFrame = 0.145,
		VentCooldown = 5,
	},

	["Delver Pickaxe"] = {
		--Blade
		Damage = 6.8,
		SwingSpeed = 0.62,
		WaitBetweenHits = 0.2,
		SwordSwingPause = 0.165,
		HitboxSize = Vector3.new(6, 6, 5.5),
		HitboxOffset = CFrame.new(0, 0, -4),
		--Handle
		HeavyDamage = 8,
		HeavyKB = 14,
		HeavyRagDoll = false,
		HeavyRagDuration = 0,
		HeavyHitboxSize = Vector3.new(12, 8, 12),
		HeavyHitboxOffset = CFrame.new(0, 0, -1.6),
		HeavyForwardTime = 0.10,
		HeavyCooldown = 6,
		--
		AerialCooldown = 5.2,
		AerialKB = 18,
		AerialHitboxSize = Vector3.new(7, 7, 7),
		AerialHitboxOffset = CFrame.new(0, -1.5, -5),
		--
		RunningCooldown = 3.8,
		RunningKB = 28,
		RunningHitboxSize = Vector3.new(5.5, 6, 6.5),
		RunningHitboxOffset = CFrame.new(0, 0, -4),
		--
		Z = "None",
		X = "None",
		C = "None",
		--
		Description = "A reliable pickaxe, ideal for mining rocks and ores.",
	},
}

function module:getWeapon(WeaponName: string)
	return info[WeaponName]
end

return module
