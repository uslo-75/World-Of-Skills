return {
	Name = "set-shirt",
	Aliases = { "shirt-set" },
	Description = "Definit le shirt par AssetId (nombre ou rbxassetid://ID).",
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
			Description = "ID du shirt (ou 'None' pour retirer)",
		},
	},
}
