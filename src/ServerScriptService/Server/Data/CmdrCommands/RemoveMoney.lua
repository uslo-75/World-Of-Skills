return {
	Name = "remove-money",
	Aliases = { "remove-rubi", "removerubi", "sub-money" },
	Description = "Retire des Rubi aux joueurs cibles.",
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
