local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

local function disconnectConnection(connection)
	if connection == nil then
		return
	end

	if typeof(connection) == "RBXScriptConnection" then
		if connection.Connected then
			connection:Disconnect()
		end
		return
	end

	if type(connection) == "table" and type(connection.Disconnect) == "function" then
		connection:Disconnect()
	end
end

function ConnectionManager.new()
	return setmetatable({
		_connections = setmetatable({}, { __mode = "k" }),
	}, ConnectionManager)
end

function ConnectionManager:Set(key, connection)
	self:Disconnect(key)
	if connection ~= nil then
		self._connections[key] = connection
	end
	return connection
end

function ConnectionManager:Disconnect(key)
	local existing = self._connections[key]
	if existing == nil then
		return
	end

	self._connections[key] = nil
	disconnectConnection(existing)
end

function ConnectionManager:DisconnectAll()
	for key in pairs(self._connections) do
		self:Disconnect(key)
	end
end

return ConnectionManager
