local module = {}

local handlersRoot = script.Parent:WaitForChild("GlobalHandlers")
local handlerModules = {
	require(handlersRoot:WaitForChild("Core")),
	require(handlersRoot:WaitForChild("Movement")),
	require(handlersRoot:WaitForChild("Combat")),
}

for _, handlers in ipairs(handlerModules) do
	for name, fn in pairs(handlers) do
		if module[name] ~= nil then
			warn(("[GlobalVisuals] Duplicate handler '%s'"):format(tostring(name)))
		end
		module[name] = fn
	end
end

return module
