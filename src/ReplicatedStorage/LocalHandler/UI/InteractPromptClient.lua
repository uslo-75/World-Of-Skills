local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PromptUIManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("PromptUIManager"))

local module = {}

function module.Init(context)
	if context == nil then
		return
	end

	local scriptRef = context and context.script or script
	local root = context and context.root or scriptRef.Parent
	local player = Players.LocalPlayer
	if not player or not root then
		return
	end

	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Main")
	local promptUI = gui:WaitForChild("InteractPrompt")
	local template = promptUI:WaitForChild("PromptHandler"):WaitForChild("Prompt")

	PromptUIManager.Init({
		player = player,
		root = promptUI,
		template = template,
	})
end

return module
