local module = {}

module.Name = "Axe"
module.Data = {
	-- Blade
	Damage = 1,
	SwingSpeed = 1,
	WaitBetweenHits = 0.18,
	SwordSwingPause = 0.15,
	HitboxSize = Vector3.new(4.25, 6, 4.25),
	HitboxOffset = CFrame.new(0, 0, -3.65),
	--
	Description = "A sturdy axe, perfect for chopping down trees.",
}

return module
