local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local SessionUtils = {}

local StorageMode = {
	Tag = "Tag",
	Attribute = "Attribute",
	Instance = "Instance",
}

function SessionUtils.createCACData(player: Player)
	local folder = player:FindFirstChild("CACData") or Instance.new("Folder")
	folder.Name = "CACData"
	folder.Parent = player
	return folder
end

function SessionUtils.setValue(player: Player, name: string, value: any, mode: string?)
	mode = mode or StorageMode.Attribute

	if mode == StorageMode.Tag then
		if type(value) ~= "boolean" then
			warn("[setValue] Tag mode expects boolean for", name, "got", typeof(value))
			return
		end

		if value then
			if not CollectionService:HasTag(player, name) then
				CollectionService:AddTag(player, name)
			end
		else
			if CollectionService:HasTag(player, name) then
				CollectionService:RemoveTag(player, name)
			end
		end

		return
	end

	if mode == StorageMode.Attribute then
		player:SetAttribute(name, value)
		return
	end

	if mode == StorageMode.Instance then
		local folder = SessionUtils.createCACData(player)
		local obj = folder:FindFirstChild(name)

		if not obj then
			local valueType = typeof(value)
			if valueType == "number" then
				obj = Instance.new("NumberValue")
			elseif valueType == "boolean" then
				obj = Instance.new("BoolValue")
			elseif valueType == "string" then
				obj = Instance.new("StringValue")
			else
				obj = Instance.new("ObjectValue")
			end

			obj.Name = name
			obj.Parent = folder
		end

		obj.Value = value
		return
	end

	warn("[setValue] Unknown storage mode for", name, "mode =", mode)
end

function SessionUtils.waitForCACData(player: Player, timeout: number?): Folder?
	local maxWait = timeout or 5
	local elapsed = 0
	local step = 0.1

	while elapsed < maxWait do
		if player.Parent ~= Players then
			return nil
		end

		local folder = player:FindFirstChild("CACData")
		if folder then
			return folder
		end

		task.wait(step)
		elapsed += step
	end

	return player:FindFirstChild("CACData")
end

function SessionUtils.new(deps)
	local profiles = deps.Profiles
	local inventoryService = deps.InventoryService

	local self = setmetatable({}, { __index = SessionUtils })

	local function isProfileActive(profile): boolean
		if not profile then
			return false
		end

		local isActiveFn = profile.IsActive
		if typeof(isActiveFn) ~= "function" then
			return false
		end

		local ok, result = pcall(isActiveFn, profile)
		return ok and result == true
	end

	function self:isProfileActive(profile): boolean
		return isProfileActive(profile)
	end

	function self:canUseProfile(player: Player, profile): boolean
		if not profile then
			return false
		end
		if profiles[player] ~= profile then
			return false
		end
		return isProfileActive(profile)
	end

	function self:captureToolsToProfile(player: Player, profile, characterOverride: Model?, captureOptions): boolean
		if not self:canUseProfile(player, profile) then
			return false
		end

		local ok, resultOrBool, err = pcall(function()
			return inventoryService:CapturePlayerInventory(player, characterOverride, captureOptions)
		end)

		if not ok then
			warn("[DATA] CapturePlayerInventory failed for", player, "error:", resultOrBool)
			return false
		end

		if resultOrBool == false then
			warn("[DATA] CapturePlayerInventory returned false for", player, "reason:", err)
			return false
		end

		return true
	end

	function self:backpackToolCount(player: Player): number
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then
			return 0
		end

		local count = 0
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				count += 1
			end
		end
		return count
	end

	function self:endSessionWithCapture(player: Player, profile): boolean
		self:captureToolsToProfile(player, profile, player.Character, { allowEmptySnapshot = false })

		if isProfileActive(profile) then
			profile:EndSession()
		end

		profiles[player] = nil
		return true
	end

	return self
end

return SessionUtils
