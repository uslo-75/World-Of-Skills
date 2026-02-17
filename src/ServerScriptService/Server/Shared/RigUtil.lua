local RigUtil = {}

function RigUtil.GetRigFromPlayer(player)
	local character = player and player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	return character, humanoid, root
end

function RigUtil.GetRigFromPrompt(prompt)
	if not prompt or not prompt.Parent then
		return
	end
	local character = prompt.Parent.Parent
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	return character, humanoid, root
end

function RigUtil.GetPromptParent(character)
	if not character then
		return
	end
	return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart")
end

return RigUtil
