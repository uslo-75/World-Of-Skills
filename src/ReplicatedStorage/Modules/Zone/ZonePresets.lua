local ZonePresets = {}

ZonePresets.Default = {
	TransitionTime = 1.55,
	MusicVolume = 0.25,
	Lighting = {},
	Atmosphere = {},
	ColorCorrection = {},
	DynamicVFX = {
		Snow = false,
		Rain = false,
		Fog = false,
		Sand = false,
		Wind = false,
		Wind_Snow = false,
	},
}

ZonePresets.ByName = {
	-- Example:
	Frostfalls = {
		TransitionTime = 1.55,
		MusicVolume = 0.2,
		Lighting = {
			Ambient = Color3.fromRGB(98, 109, 138),
			OutdoorAmbient = Color3.fromRGB(120, 130, 160),
			Brightness = 1.6,
			ColorShift_Top = Color3.fromRGB(170, 198, 255),
			ColorShift_Bottom = Color3.fromRGB(131, 161, 210),
		},
		Atmosphere = {
			Density = 0.34,
			Haze = 2.1,
			Color = Color3.fromRGB(187, 220, 255),
			Decay = Color3.fromRGB(113, 126, 156),
		},
		ColorCorrection = {
			TintColor = Color3.fromRGB(214, 228, 255),
			Saturation = -0.2,
			Contrast = 0.08,
			Brightness = -0.03,
		},
		DynamicVFX = {
			Snow = true,
		},
	},
}

function ZonePresets.Get(presetName)
	if typeof(presetName) == "string" and ZonePresets.ByName[presetName] then
		return ZonePresets.ByName[presetName]
	end

	return ZonePresets.Default
end

return ZonePresets
