return {
	Name = "set-race",
	Aliases = { "race-set", "changer-race" },
	Description = "Change la race (et optionnellement la subrace pour Varans).",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a modifier",
		},
		{
			Type = "string",
			Name = "Race",
			Description = "Solarians/Lunarians/Sangivores/Pharaosiens/Varans",
		},
		{
			Type = "string",
			Name = "VaransPath",
			Description = "Bat/Cat/Fish/Bird (si race=Varans)",
			Optional = true,
		},
		{
			Type = "boolean",
			Name = "ResetCustomization",
			Description = "Reset les valeurs de custom au changement de race",
			Optional = true,
		},
	},
}
