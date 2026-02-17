local ZoneDetector = {}
ZoneDetector.__index = ZoneDetector

local EPSILON = 0.0001

local function isZoneContainer(instance)
	if instance:IsA("Folder") or instance:IsA("Model") then
		return true
	end

	if instance:IsA("BasePart") then
		return true
	end

	return false
end

local function getZoneParts(container)
	if container:IsA("BasePart") then
		return { container }
	end

	local parts = {}
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function isInsidePartXZ(part, worldPosition)
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5

	return math.abs(localPosition.X) <= halfSize.X and math.abs(localPosition.Z) <= halfSize.Z
end

local function getBoolAttribute(instance, attributeName)
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "boolean" then
		return value
	end

	return nil
end

local function buildZoneInfo(container, bestPart, deltaY)
	local zoneId = container:GetAttribute("ZoneId") or container.Name
	local displayName = container:GetAttribute("DisplayName") or zoneId
	local priority = container:GetAttribute("Priority") or 0
	local lightingPreset = container:GetAttribute("LightingPreset")
	local musicId = container:GetAttribute("MusicId")
	local musicVolume = container:GetAttribute("MusicVolume")
	local transitionTime = container:GetAttribute("TransitionTime")

	return {
		id = tostring(zoneId),
		displayName = tostring(displayName),
		priority = tonumber(priority) or 0,
		lightingPreset = (typeof(lightingPreset) == "string" and lightingPreset) or nil,
		musicId = musicId,
		musicVolume = tonumber(musicVolume),
		transitionTime = tonumber(transitionTime),
		dynamicVFX = {
			Snow = getBoolAttribute(container, "Snow"),
			Rain = getBoolAttribute(container, "Rain"),
			Fog = getBoolAttribute(container, "Fog"),
			Sand = getBoolAttribute(container, "Sand"),
			Wind = getBoolAttribute(container, "Wind"),
			Wind_Snow = getBoolAttribute(container, "Wind_Snow"),
		},
		deltaY = deltaY,
		container = container,
		part = bestPart,
	}
end

function ZoneDetector.new(zoneRoot)
	local self = setmetatable({}, ZoneDetector)
	self._zoneRoot = zoneRoot
	return self
end

function ZoneDetector:GetClosestZoneAbove(worldPosition)
	if not self._zoneRoot then
		return nil
	end

	local selectedZone = nil

	for _, child in ipairs(self._zoneRoot:GetChildren()) do
		if isZoneContainer(child) then
			local bestPart = nil
			local bestDeltaY = nil
			local parts = getZoneParts(child)

			for _, part in ipairs(parts) do
				if isInsidePartXZ(part, worldPosition) then
					local deltaY = part.Position.Y - worldPosition.Y
					if deltaY >= 0 and (not bestDeltaY or deltaY < bestDeltaY) then
						bestDeltaY = deltaY
						bestPart = part
					end
				end
			end

			if bestPart and bestDeltaY then
				local zoneInfo = buildZoneInfo(child, bestPart, bestDeltaY)

				if not selectedZone then
					selectedZone = zoneInfo
				else
					local yDiff = zoneInfo.deltaY - selectedZone.deltaY
					if yDiff < -EPSILON then
						selectedZone = zoneInfo
					elseif math.abs(yDiff) <= EPSILON and zoneInfo.priority > selectedZone.priority then
						selectedZone = zoneInfo
					end
				end
			end
		end
	end

	return selectedZone
end

return ZoneDetector
