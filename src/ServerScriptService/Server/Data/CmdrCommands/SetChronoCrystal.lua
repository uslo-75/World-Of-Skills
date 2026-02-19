return {
	Name = "set-chronocrystal",
	Aliases = { "set-chrono", "setcc" },
	Description = "Definit exactement la valeur des ChronoCrystal.",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a modifier",
		},
		{
			Type = "nonNegativeInteger",
			Name = "Amount",
			Description = "Nouvelle valeur",
		},
	},
}
