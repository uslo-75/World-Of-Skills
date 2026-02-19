return {
	Name = "add-money",
	Aliases = { "add-rubi", "addrubi" },
	Description = "Ajoute des Rubi aux joueurs cibles.",
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
