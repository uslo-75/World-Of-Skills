return {
	Name = "set-money",
	Aliases = { "set-rubi", "money-set" },
	Description = "Definit exactement la valeur des Rubi.",
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
