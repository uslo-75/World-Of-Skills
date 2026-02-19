local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SnapshotUtil = require(script.Parent:WaitForChild("SnapshotUtil"))

local InventoryNet = {}
InventoryNet.__index = InventoryNet

function InventoryNet.new(deps)
	local self = setmetatable({}, InventoryNet)

	self.Config = deps.Config
	self.Service = deps.InventoryService

	self._remote = nil
	self._lastReqAt = {} -- [player] = os.clock()
	self._lastSyncAt = {} -- [player] = os.clock()
	self._lastHash = {} -- [player] = hash string
	self._pendingSync = {} -- [player] = {reason, requestId}
	self._flushScheduled = {} -- [player] = true

	return self
end

function InventoryNet:_getRemote()
	if self._remote and self._remote.Parent then
		return self._remote
	end

	local remotes = ReplicatedStorage:FindFirstChild(self.Config.RemotesFolderName)
	if not remotes or not remotes:IsA("Folder") then
		return nil
	end

	local r = remotes:FindFirstChild(self.Config.MainRemoteName)
	if r and r:IsA("RemoteEvent") then
		self._remote = r
		return r
	end

	return nil
end

function InventoryNet:CanRequest(player: Player)
	local now = os.clock()
	local last = self._lastReqAt[player]
	if last and (now - last) < self.Config.RequestCooldown then
		return false
	end
	self._lastReqAt[player] = now
	return true
end

function InventoryNet:_dispatchSnapshot(player: Player, reason: string?, requestId: any?)
	local remote = self:_getRemote()
	if not remote then
		return
	end
	if player.Parent == nil then
		return
	end

	local normalizedReason = SnapshotUtil.NormalizeReason(reason)
	local includeItems = SnapshotUtil.ShouldIncludeItems(normalizedReason, self.Config)

	local snapshot = self.Service:BuildSnapshot(player, {
		includeItems = includeItems,
	})
	if not snapshot then
		return
	end

	local hash = SnapshotUtil.ComputeHash(snapshot)
	if normalizedReason ~= "request" and self._lastHash[player] == hash then
		return
	end

	self._lastHash[player] = hash
	self._lastSyncAt[player] = os.clock()

	local payload = SnapshotUtil.BuildPayload(normalizedReason, requestId, snapshot)
	remote:FireClient(player, self.Config.SyncEventName, payload)
end

function InventoryNet:_queuePendingSnapshot(player: Player, reason: string?, requestId: any?, delaySeconds: number)
	if self.Config.EnableSnapshotCoalescing == false then
		return
	end

	local queued = self._pendingSync[player]
	if queued then
		queued.reason = SnapshotUtil.MergeReason(queued.reason, reason)
		if SnapshotUtil.NormalizeReason(reason) == "request" then
			queued.requestId = requestId
		end
	else
		self._pendingSync[player] = {
			reason = reason,
			requestId = requestId,
		}
	end

	if self._flushScheduled[player] then
		return
	end
	self._flushScheduled[player] = true

	local delayTime = math.max(0, tonumber(delaySeconds) or self.Config.MinSyncInterval or 0)
	task.delay(delayTime, function()
		self._flushScheduled[player] = nil
		if player.Parent == nil then
			self._pendingSync[player] = nil
			return
		end

		local pending = self._pendingSync[player]
		self._pendingSync[player] = nil
		if not pending then
			return
		end

		self:PushSnapshot(player, pending.reason, pending.requestId)
	end)
end

function InventoryNet:PushSnapshot(player: Player, reason: string?, requestId: any?)
	local minInterval = math.max(0, tonumber(self.Config.MinSyncInterval) or 0)
	local now = os.clock()
	local last = self._lastSyncAt[player]

	if last and (now - last) < minInterval then
		local remaining = minInterval - (now - last)
		self:_queuePendingSnapshot(player, reason, requestId, remaining)
		return
	end

	self:_dispatchSnapshot(player, reason, requestId)
end

function InventoryNet:Bind()
	if self.Config.UseStandaloneRequestListener ~= true then
		return
	end

	local remote = self:_getRemote()
	if not remote then
		return
	end

	remote.OnServerEvent:Connect(function(player: Player, actionOrEvent, payload)
		if actionOrEvent ~= "inventory" then
			return
		end

		if typeof(payload) ~= "table" then
			return
		end

		if not self:CanRequest(player) then
			return
		end

		self.Service:HandleRemoteRequest(player, payload)
	end)
end

function InventoryNet:CleanupPlayer(player: Player)
	self._lastReqAt[player] = nil
	self._lastSyncAt[player] = nil
	self._lastHash[player] = nil
	self._pendingSync[player] = nil
	self._flushScheduled[player] = nil
end

return InventoryNet
