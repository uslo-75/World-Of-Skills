return {
	Name = "set-pant",
	Aliases = { "set-pants", "pant-set", "pants-set" },
	Description = "Definit le pant par AssetId (nombre ou rbxassetid://ID).",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",
			Name = "Players",
			Description = "Joueurs a modifier",
		},
		{
			Type = "string",
			Name = "AssetId",
			Description = "ID du pant (ou 'None' pour retirer)",
		},
	},
}
