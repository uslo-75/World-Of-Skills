return {
	Name = "add-chronocrystal",
	Aliases = { "add-chrono", "addcc" },
	Description = "Ajoute des ChronoCrystal aux joueurs cibles.",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a modifier",
		},
		{
			Type = "positiveInteger",
			Name = "Amount",
			Description = "Montant a ajouter",
		},
	},
}
