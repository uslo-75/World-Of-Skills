local SnapshotUtil = {}

local DEFAULT_REASON = "sync"
local REQUEST_REASON = "request"

function SnapshotUtil.NormalizeReason(reason: any): string
	if typeof(reason) ~= "string" or reason == "" then
		return DEFAULT_REASON
	end
	return reason
end

function SnapshotUtil.ShouldIncludeItems(reason: string, config): boolean
	local normalizedReason = SnapshotUtil.NormalizeReason(reason)

	if normalizedReason == REQUEST_REASON then
		return config.SyncIncludeItemsOnRequest == true
	end

	local byReason = config.SyncIncludeItemsByReason
	if typeof(byReason) == "table" and byReason[normalizedReason] == true then
		return true
	end

	return config.SyncIncludeItemsDefault == true
end

function SnapshotUtil.ComputeHash(snapshot): string
	if typeof(snapshot) ~= "table" then
		return "invalid"
	end

	local count = tonumber(snapshot.count) or -1
	local maxCapacity = tonumber(snapshot.maxCapacity) or -1
	local selectedSlot = tonumber(snapshot.selectedSlot) or -1
	local itemsCount = (typeof(snapshot.items) == "table") and #snapshot.items or 0

	return string.format("%d|%d|%d|%d", count, maxCapacity, selectedSlot, itemsCount)
end

function SnapshotUtil.BuildPayload(reason: string, requestId: any, snapshot)
	local payload = {
		reason = SnapshotUtil.NormalizeReason(reason),
		snapshot = {
			count = snapshot.count,
			maxCapacity = snapshot.maxCapacity,
			selectedSlot = snapshot.selectedSlot,
		},
	}

	if requestId ~= nil then
		payload.requestId = requestId
	end

	if typeof(snapshot.items) == "table" then
		payload.snapshot.items = snapshot.items
	end

	return payload
end

function SnapshotUtil.MergeReason(currentReason: string?, incomingReason: string?): string
	local current = SnapshotUtil.NormalizeReason(currentReason)
	local incoming = SnapshotUtil.NormalizeReason(incomingReason)

	if current == REQUEST_REASON or incoming == REQUEST_REASON then
		return REQUEST_REASON
	end

	if current == DEFAULT_REASON then
		return incoming
	end

	return current
end

return SnapshotUtil
