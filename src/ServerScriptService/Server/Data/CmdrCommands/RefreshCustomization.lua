return {
	Name = "refresh-customization",
	Aliases = { "refresh-custom", "refresh-cac" },
	Description = "Reapplique la custom du profil sur le character actuel.",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a refresh",
		},
	},
}
