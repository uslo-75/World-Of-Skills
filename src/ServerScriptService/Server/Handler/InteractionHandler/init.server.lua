local ProximityPromptService = game:GetService("ProximityPromptService")
local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Combat = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Handler"):WaitForChild("Combat"))
local PromptManager =
	require(
		ServerScriptService:WaitForChild("Server")
			:WaitForChild("Handler")
			:WaitForChild("PromptManager")
	)

local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local MovementBlockStates =
	require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("MovementBlockStates"))

local BLOCK_STATES = MovementBlockStates.InteractionPrompt

local PROMPT_ROUTES = {
	GripPrompt = function(player: Player, prompt: ProximityPrompt)
		Combat.Grip:Toggle(player, prompt)
	end,
	CarryPrompt = function(player: Player, prompt: ProximityPrompt)
		Combat.Carry:Toggle(player, prompt)
	end,
}

local function isPromptBlocked(player: Player): boolean
	local character = player.Character
	if character and character:GetAttribute("Dashing") == true then
		return true
	end
	for _, stateName in ipairs(BLOCK_STATES) do
		if StateManager.GetState(player, stateName) == true then
			return true
		end
	end
	return false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end

	local character = player.Character
	if character and character:GetAttribute("Downed") == true then
		return
	end

	if isPromptBlocked(player) then
		return
	end

	local ownerId = prompt:GetAttribute("PromptOwnerUserId")
	if ownerId and ownerId == player.UserId then
		return
	end

	local lockedId = prompt:GetAttribute("PromptLockedByUserId")
	if lockedId and lockedId ~= player.UserId then
		return
	end

	PromptManager.ApplyUseProperties(prompt, player)
	local route = PROMPT_ROUTES[prompt.Name]
	if route then
		route(player, prompt)
	end
end)
