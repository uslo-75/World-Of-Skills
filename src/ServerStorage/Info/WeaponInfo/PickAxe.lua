local module = {}

module.Name = "PickAxe"
module.Data = {
	-- Blade
	Damage = 1,
	SwingSpeed = 1,
	WaitBetweenHits = 0.18,
	SwordSwingPause = 0.15,
	HitboxSize = Vector3.new(4.25, 6, 4.25),
	HitboxOffset = CFrame.new(0, 0, -3.65),
	--
	Description = "A reliable pickaxe, ideal for mining rocks and ores.",
}

return module
