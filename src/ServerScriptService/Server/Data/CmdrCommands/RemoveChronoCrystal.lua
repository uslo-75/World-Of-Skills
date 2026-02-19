return {
	Name = "remove-chronocrystal",
	Aliases = { "remove-chrono", "removecc", "sub-chrono" },
	Description = "Retire des ChronoCrystal aux joueurs cibles.",
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
			Description = "Montant a retirer",
		},
	},
}
