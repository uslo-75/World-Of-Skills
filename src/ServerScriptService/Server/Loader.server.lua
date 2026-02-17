local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Loader = require(RS:WaitForChild("Modules"):WaitForChild("Loader"))

Loader.LoadAll({
	includeLocalHandler = false,
	serverRoots = {
		SSS:WaitForChild("Server"):WaitForChild("Handler"),
	},
	skipPaths = {
		"ReplicatedStorage.Modules.EffectModule",
		"ReplicatedStorage.Modules.Libs",
		"ServerScriptService.Server.Handler.HealthManager",
		"ServerScriptService.Server.Handler.Combat",
		"ServerScriptService.Server.Handler.Inventory",
		"ServerScriptService.Server.Handler.PromptManager",
	},
})
