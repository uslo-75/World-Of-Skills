local RunService = game:GetService("RunService")

return {
	ServerListName = "serverlist_v1",
	ServerListTTL = 60 * 60 * 24 * 4, -- 4 days
	UpdateInterval = 60,

	RemotesFolderName = "Remotes",
	RemoteName = "ServerInfo",

	EnableMemoryStore = not RunService:IsStudio(),

	GeoLookup = {
		Url = "https://ipwho.is/",
		MaxAttempts = 5,
		RetrySeconds = 5,
	},

	RequestCooldown = 0.5,

	DefaultGameVersion = "Beta-test",
	DefaultRegionName = "Unknown Region",
}
