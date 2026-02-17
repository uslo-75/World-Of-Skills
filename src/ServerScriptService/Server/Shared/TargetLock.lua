local TargetLock = {}

local LOCK_TYPE_ATTR = "PromptActionLockType"
local LOCK_USER_ATTR = "PromptActionLockUserId"

function TargetLock.Acquire(targetCharacter, kind, player)
	if not targetCharacter or not targetCharacter.Parent then
		return false
	end
	if typeof(kind) ~= "string" or kind == "" then
		return false
	end
	if not player then
		return false
	end

	local currentType = targetCharacter:GetAttribute(LOCK_TYPE_ATTR)
	local currentUserId = targetCharacter:GetAttribute(LOCK_USER_ATTR)
	if currentType ~= nil then
		return currentType == kind and currentUserId == player.UserId
	end

	targetCharacter:SetAttribute(LOCK_TYPE_ATTR, kind)
	targetCharacter:SetAttribute(LOCK_USER_ATTR, player.UserId)
	return true
end

function TargetLock.Release(targetCharacter, kind, player)
	if not targetCharacter then
		return
	end

	local currentType = targetCharacter:GetAttribute(LOCK_TYPE_ATTR)
	local currentUserId = targetCharacter:GetAttribute(LOCK_USER_ATTR)
	if currentType == nil then
		return
	end
	if kind and currentType ~= kind then
		return
	end
	if player and currentUserId ~= nil and currentUserId ~= player.UserId then
		return
	end

	targetCharacter:SetAttribute(LOCK_TYPE_ATTR, nil)
	targetCharacter:SetAttribute(LOCK_USER_ATTR, nil)
end

return TargetLock
