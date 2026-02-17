local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryNet = {}
InventoryNet.__index = InventoryNet

function InventoryNet.new(deps)
	local self = setmetatable({}, InventoryNet)

	self.Config = deps.Config
	self.Service = deps.InventoryService

	self._remote = nil
	self._lastReqAt = {} -- [player] = os.clock()
	self._lastSyncAt = {} -- [player] = os.clock()
	self._lastHash = {} -- [player] = string

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

local function hashSnapshot(snapshot)
	return tostring(snapshot.count) .. "|" .. tostring(snapshot.maxCapacity) .. "|" .. tostring(#snapshot.items)
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

function InventoryNet:PushSnapshot(player: Player, reason: string?, requestId: any?)
	local remote = self:_getRemote()
	if not remote then
		return
	end

	local now = os.clock()
	local last = self._lastSyncAt[player]
	if last and (now - last) < self.Config.MinSyncInterval then
		return
	end
	self._lastSyncAt[player] = now

	local snapshot = self.Service:BuildSnapshot(player)
	if not snapshot then
		return
	end

	local h = hashSnapshot(snapshot)
	if reason ~= "request" and self._lastHash[player] == h then
		return
	end
	self._lastHash[player] = h

	remote:FireClient(player, self.Config.SyncEventName, {
		reason = reason or "sync",
		requestId = requestId,
		snapshot = snapshot,
	})
end

function InventoryNet:Bind()
	local remote = self:_getRemote()
	if not remote then
		return
	end

	remote.OnServerEvent:Connect(function(player: Player, actionOrEvent, payload)
		local payloadTable = payload
		if typeof(actionOrEvent) == "string" and actionOrEvent ~= self.Config.SyncEventName then
		end

		if typeof(payloadTable) ~= "table" then
			return
		end

		if not self:CanRequest(player) then
			return
		end

		self.Service:HandleRemoteRequest(player, payloadTable)
	end)
end

function InventoryNet:CleanupPlayer(player: Player)
	self._lastReqAt[player] = nil
	self._lastSyncAt[player] = nil
	self._lastHash[player] = nil
end

return InventoryNet
