local module = {}

function module.Init(context)
	if context == nil then
		return
	end

	local script = context and context.script or error("missing script context")
	local root = context and context.root or script.Parent
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	
	local zoneModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Zone")
	local ZoneDetector = require(zoneModules:WaitForChild("ZoneDetector"))
	local ZoneUIController = require(zoneModules:WaitForChild("ZoneUIController"))
	local ZoneEnvironmentController = require(zoneModules:WaitForChild("ZoneEnvironmentController"))
	
	local UPDATE_INTERVAL = 0.1
	local DEFAULT_ZONE_ID = "__DEFAULT__"
	
	local player = Players.LocalPlayer
	local uiController = ZoneUIController.new()
	local environmentController = ZoneEnvironmentController.new()
	
	local detector = nil
	local currentZoneId = nil
	local elapsed = 0
	
	local function resetZoneState()
		detector = nil
		currentZoneId = nil
		environmentController:ApplyZone(nil)
		uiController:Reset()
	end
	
	local function getZoneRoot()
		local world = Workspace:FindFirstChild("World")
		if world then
			local zoneVolumes = world:FindFirstChild("ZoneVolumes")
			if zoneVolumes then
				return zoneVolumes
			end
		end
	
		local legacyLocations = Workspace:FindFirstChild("Locations")
		if legacyLocations then
			return legacyLocations
		end
	
		return nil
	end
	
	local function updateZone()
		local zoneRoot = getZoneRoot()
		if zoneRoot then
			if not detector or detector._zoneRoot ~= zoneRoot then
				detector = ZoneDetector.new(zoneRoot)
			end
		else
			detector = nil
		end
	
		local zoneInfo = nil
		local character = player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if detector and humanoidRootPart then
			zoneInfo = detector:GetClosestZoneAbove(humanoidRootPart.Position)
		end
	
		local newZoneId = zoneInfo and zoneInfo.id or DEFAULT_ZONE_ID
		if newZoneId ~= currentZoneId then
			currentZoneId = newZoneId
			environmentController:ApplyZone(zoneInfo)
			if zoneInfo then
				uiController:ShowZoneName(zoneInfo.displayName)
			end
		end
	end
	
	resetZoneState()
	
	player.CharacterRemoving:Connect(function()
		resetZoneState()
	end)
	
	player.CharacterAdded:Connect(function()
		resetZoneState()
		task.defer(updateZone)
	end)
	
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		updateZone()
	end)
end

return module
