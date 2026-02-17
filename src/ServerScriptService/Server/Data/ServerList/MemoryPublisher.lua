local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Utils = require(script.Parent.Utils)

local MemoryPublisher = {}
MemoryPublisher.__index = MemoryPublisher

function MemoryPublisher.new(config)
	local self = setmetatable({}, MemoryPublisher)
	self._config = config
	self._map = MemoryStoreService:GetSortedMap(config.ServerListName)
	self._key = HttpService:GenerateGUID(false)
	return self
end

function MemoryPublisher:key()
	return self._key
end

function MemoryPublisher:publish(snapshot)
	if not self._config.EnableMemoryStore then
		return
	end
	Utils.safePCall("[ServerList] MemoryStore update failed:", function()
		self._map:SetAsync(self._key, snapshot, self._config.ServerListTTL)
	end)
end

function MemoryPublisher:remove()
	if not self._config.EnableMemoryStore then
		return
	end
	Utils.safePCall("[ServerList] Failed to remove MemoryStore entry:", function()
		self._map:RemoveAsync(self._key)
	end)
end

return MemoryPublisher
