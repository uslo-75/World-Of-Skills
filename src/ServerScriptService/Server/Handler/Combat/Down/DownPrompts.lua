local Players = game:GetService("Players")

local DownPrompts = {}

function DownPrompts.Ensure(promptManager, rigUtil, config, character)
	local parent = rigUtil.GetPromptParent(character)
	if not parent then
		return
	end

	local owner = Players:GetPlayerFromCharacter(character)
	local objectText = owner and (owner.DisplayName or owner.Name) or ""
	local ownerUserId = owner and owner.UserId or nil

	local grip = parent:FindFirstChild("GripPrompt")
	local carry = parent:FindFirstChild("CarryPrompt")

	if not (grip and grip:IsA("ProximityPrompt")) then
		grip = promptManager.Create(parent, {
			Name = "GripPrompt",
			ActionText = "Grip",
			ObjectText = objectText,
			KeyboardKeyCode = config.GripKey,
			MaxActivationDistance = config.PromptMaxActivationDistance,
			RequiresLineOfSight = false,
			Style = Enum.ProximityPromptStyle.Custom,
			Attributes = {
				PromptOwnerUserId = ownerUserId,
				OnePlayerUse = true,
				DontHidePromptForPlayer = true,
				HideOtherPrompt = "CarryPrompt",
				ChangePromptText = "Stop Grip",
			},
		})
	end

	if not (carry and carry:IsA("ProximityPrompt")) then
		carry = promptManager.Create(parent, {
			Name = "CarryPrompt",
			ActionText = "Carry",
			ObjectText = objectText,
			KeyboardKeyCode = config.CarryKey,
			MaxActivationDistance = config.PromptMaxActivationDistance,
			RequiresLineOfSight = false,
			Style = Enum.ProximityPromptStyle.Custom,
			Attributes = {
				PromptOwnerUserId = ownerUserId,
				OnePlayerUse = true,
				DontHidePromptForPlayer = true,
				HideOtherPrompt = "GripPrompt",
				ChangePromptText = "Drop",
			},
		})
	end

	return grip, carry
end

function DownPrompts.Clear(rigUtil, character)
	local parent = rigUtil.GetPromptParent(character)
	if not parent then
		return
	end

	local grip = parent:FindFirstChild("GripPrompt")
	if grip and grip:IsA("ProximityPrompt") then
		grip:Destroy()
	end

	local carry = parent:FindFirstChild("CarryPrompt")
	if carry and carry:IsA("ProximityPrompt") then
		carry:Destroy()
	end

	character:SetAttribute("GripOwnerUserId", nil)
	character:SetAttribute("CarryOwnerUserId", nil)
end

return DownPrompts
