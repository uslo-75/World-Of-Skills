return {
	Name = "set-custom-number",
	Aliases = { "set-custom", "set-variant-number", "set-ornament-number" },
	Description = "Set un index de custom numerique (variant/ornament/facialmark/face/skin).",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a modifier",
		},
		{
			Type = "string",
			Name = "Field",
			Description = "variant / ornament / facialmark / face / skin",
		},
		{
			Type = "positiveInteger",
			Name = "Value",
			Description = "Nouvelle valeur",
		},
		{
			Type = "boolean",
			Name = "Refresh",
			Description = "Reapplique la custom apres changement",
			Optional = true,
		},
	},
}
