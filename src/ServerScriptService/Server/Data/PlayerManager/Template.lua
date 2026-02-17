return {

	SelectedSlot = 1, -- Default slot is 1

	[1] = {

		CharData = {
			Civilizations = nil, -- Random at spawn
			VaransPath = nil, -- Only for varans
			--
			Hair = nil,
			RaceVariant = 1,
			FacialMark = 1,
			Face = 1,
			Skin = 1,
			Ornament = 1,
			OrnamentColors = nil,
			HairColor = nil, --{ r = 1, g = 1, b = 1 },   -- couleur par défaut blanche
			Shirt = "None",
			Pant = "None",
			--
			Power = 1,
			XP = 1,
			Rubi = 0,
			ChronoCrystal = 0,
			--
		},

		CharStats = {
			-- Ressources
			MaxHP = 80, -- Points de vie de base
			MaxEther = 50, -- Mana de base
			MaxPosture = 100, -- Posture de base
			MaxCapacity = 100, -- Inventory capacity

			-- Caractéristiques principales
			Strength = 0, -- Force (augmente les dégâts physiques de base (M1's))
			Agility = 0, -- Agilité (vitesse de déplacement)
			Intelligence = 0, -- Intelligence (puissance des artefacts, Ether bonus)
			Vitality = 0, -- Vitalité (points de vie bonus & régénération)
			Fortitude = 0, -- Réduction de dégâts
			WeaponMastery = 0, -- Bonus de dégâts d’arme (Skill's)

			-- Buffs / modificateurs
			HPBuff = 0, -- PV supplémentaires apportés par équipements
			EtherBuff = 0, -- Mana supplémentaires
		},

		CharInfo = {
			Equipments = {
				Top = nil,
				Upper = nil,
				Back = nil,
				Lower = nil,
				Rings = { nil, nil, nil, nil },
				Backpack = nil,
			},
			Weapon = nil,
			Artefact = nil,
		},

		Inventory = {
			-- { name = "NomDeLObjet", stats = { attaque = 0, vitesse = 0, … } }
		},
	},

	[2] = {},

	[3] = {},
}
