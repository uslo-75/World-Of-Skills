local PromptManager = {}
local PromptConfig = require(script:WaitForChild("Config"))
local ATTR = PromptConfig.Attributes
local TARGET_LOCK_TYPE_ATTR = PromptConfig.TargetLockTypeAttribute
local TARGET_LOCK_USER_ATTR = PromptConfig.TargetLockUserAttribute

local function getBoolAttr(prompt: ProximityPrompt, name: string): boolean
	return prompt:GetAttribute(name) == true
end

local function getStringAttr(prompt: ProximityPrompt, name: string): string?
	local value = prompt:GetAttribute(name)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function findSiblingPrompt(prompt: ProximityPrompt, name: string?): ProximityPrompt?
	if not name or name == "" then
		return nil
	end
	local parent = prompt.Parent
	if not parent then
		return nil
	end
	local target = parent:FindFirstChild(name)
	if target and target:IsA("ProximityPrompt") then
		return target
	end
	return nil
end

local function setTextOverride(prompt: ProximityPrompt, value: string?)
	if value and value ~= "" then
		prompt:SetAttribute(ATTR.PromptTextOverride, value)
	else
		prompt:SetAttribute(ATTR.PromptTextOverride, nil)
	end
end

local function shouldToggle(prompt: ProximityPrompt): boolean
	return getBoolAttr(prompt, ATTR.OnePlayerUse)
		or getStringAttr(prompt, ATTR.HideOtherPrompt) ~= nil
		or getStringAttr(prompt, ATTR.ChangePromptText) ~= nil
end

local function normalizeKeyCode(value: any): Enum.KeyCode?
	if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
		return value
	end
	if typeof(value) == "string" then
		local item = Enum.KeyCode[value]
		if item then
			return item
		end
	end
	return nil
end

local function applyAttributes(prompt: ProximityPrompt, attrs: { [string]: any }?)
	if not attrs then
		return
	end
	for k, v in pairs(attrs) do
		prompt:SetAttribute(k, v)
	end
end

local function applyConfig(prompt: ProximityPrompt, config: { [string]: any }?)
	if not config then
		return
	end

	if config.Name ~= nil then
		prompt.Name = tostring(config.Name)
	end
	if config.ActionText ~= nil then
		prompt.ActionText = tostring(config.ActionText)
	end
	if config.ObjectText ~= nil then
		prompt.ObjectText = tostring(config.ObjectText)
	end

	if config.KeyboardKeyCode ~= nil then
		local key = normalizeKeyCode(config.KeyboardKeyCode)
		if key then
			prompt.KeyboardKeyCode = key
		end
	end
	if config.GamepadKeyCode ~= nil then
		local key = normalizeKeyCode(config.GamepadKeyCode)
		if key then
			prompt.GamepadKeyCode = key
		end
	end

	if config.MaxActivationDistance ~= nil then
		prompt.MaxActivationDistance = tonumber(config.MaxActivationDistance) or prompt.MaxActivationDistance
	end
	if config.HoldDuration ~= nil then
		prompt.HoldDuration = tonumber(config.HoldDuration) or prompt.HoldDuration
	end
	if config.Enabled ~= nil then
		prompt.Enabled = config.Enabled == true
	end
	if config.RequiresLineOfSight ~= nil then
		prompt.RequiresLineOfSight = config.RequiresLineOfSight == true
	end
	if config.Exclusivity ~= nil then
		if typeof(config.Exclusivity) == "EnumItem" then
			prompt.Exclusivity = config.Exclusivity
		end
	end
	if config.Style ~= nil then
		if typeof(config.Style) == "EnumItem" then
			prompt.Style = config.Style
		end
	else
		-- Default to custom so the Roblox UI does not appear
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end

	applyAttributes(prompt, config.Attributes)
end

function PromptManager.Create(parent: Instance, config: { [string]: any }?): ProximityPrompt
	assert(parent ~= nil, "PromptManager.Create requires a parent Instance")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Parent = parent
	applyConfig(prompt, config)
	return prompt
end

function PromptManager.Update(prompt: ProximityPrompt, config: { [string]: any }?)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	applyConfig(prompt, config)
end

function PromptManager.SetEnabled(prompt: ProximityPrompt, enabled: boolean)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt.Enabled = enabled == true
end

function PromptManager.SetAttributes(prompt: ProximityPrompt, attrs: { [string]: any })
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	applyAttributes(prompt, attrs)
end

function PromptManager.Destroy(prompt: ProximityPrompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt:Destroy()
end

function PromptManager.ApplyUseProperties(prompt: ProximityPrompt, player: Player)
	if not prompt or not player or not prompt:IsA("ProximityPrompt") then
		return
	end
	if not shouldToggle(prompt) then
		return
	end

	local isActive = prompt:GetAttribute(ATTR.PromptUseState) == true
	local newActive = not isActive
	prompt:SetAttribute(ATTR.PromptUseState, newActive)

	-- OnePlayerUse
	if getBoolAttr(prompt, ATTR.OnePlayerUse) then
		if newActive then
			prompt:SetAttribute(ATTR.PromptLockedByUserId, player.UserId)
			if
				getBoolAttr(prompt, ATTR.DontHidePromptForPlayer)
				or getStringAttr(prompt, ATTR.DontHidePromptForPlayer) == prompt.Name
			then
				prompt:SetAttribute(ATTR.HidePromptText, false)
			else
				prompt:SetAttribute(ATTR.HidePromptText, true)
			end
		else
			prompt:SetAttribute(ATTR.PromptLockedByUserId, nil)
			prompt:SetAttribute(ATTR.HidePromptText, false)
		end
	end

	-- HideOtherPrompt
	local otherName = getStringAttr(prompt, ATTR.HideOtherPrompt)
	if otherName then
		local otherPrompt = findSiblingPrompt(prompt, otherName)
		if otherPrompt then
			if newActive then
				otherPrompt.Enabled = false
				otherPrompt:SetAttribute(ATTR.HidePromptText, true)
				otherPrompt:SetAttribute(ATTR.PromptLockedByUserId, nil)
				otherPrompt:SetAttribute(ATTR.PromptUseState, false)
				setTextOverride(otherPrompt, nil)
			else
				otherPrompt.Enabled = true
				otherPrompt:SetAttribute(ATTR.HidePromptText, false)
			end
		end
	end

	-- ChangePromptText (client-only)
	local newText = getStringAttr(prompt, ATTR.ChangePromptText)
	if newText then
		if newActive then
			setTextOverride(prompt, newText)
		else
			setTextOverride(prompt, nil)
		end
	end
end

function PromptManager.ShouldResetPrompt(prompt: ProximityPrompt?, player: Player?): boolean
	if not prompt or not player or not prompt:IsA("ProximityPrompt") then
		return false
	end
	if prompt:GetAttribute(ATTR.PromptUseState) ~= true then
		return false
	end
	local lockedId = prompt:GetAttribute(ATTR.PromptLockedByUserId)
	return lockedId == nil or lockedId == player.UserId
end

function PromptManager.ResetPromptState(prompt: ProximityPrompt?, player: Player?): boolean
	if not PromptManager.ShouldResetPrompt(prompt, player) then
		return false
	end
	PromptManager.ApplyUseProperties(prompt, player :: Player)
	return true
end

function PromptManager.TryAcquireTargetLock(target: Instance?, actionType: string, player: Player?): boolean
	if not target or not target.Parent then
		return false
	end
	if typeof(actionType) ~= "string" or actionType == "" then
		return false
	end
	if not player then
		return false
	end

	local currentType = target:GetAttribute(TARGET_LOCK_TYPE_ATTR)
	local currentUserId = target:GetAttribute(TARGET_LOCK_USER_ATTR)

	if currentType ~= nil then
		return currentType == actionType and currentUserId == player.UserId
	end

	target:SetAttribute(TARGET_LOCK_TYPE_ATTR, actionType)
	target:SetAttribute(TARGET_LOCK_USER_ATTR, player.UserId)
	return true
end

function PromptManager.ReleaseTargetLock(target: Instance?, actionType: string?, player: Player?): boolean
	if not target then
		return false
	end

	local currentType = target:GetAttribute(TARGET_LOCK_TYPE_ATTR)
	local currentUserId = target:GetAttribute(TARGET_LOCK_USER_ATTR)
	if currentType == nil then
		return false
	end
	if actionType and actionType ~= currentType then
		return false
	end
	if player and currentUserId ~= nil and currentUserId ~= player.UserId then
		return false
	end

	target:SetAttribute(TARGET_LOCK_TYPE_ATTR, nil)
	target:SetAttribute(TARGET_LOCK_USER_ATTR, nil)
	return true
end

return PromptManager
