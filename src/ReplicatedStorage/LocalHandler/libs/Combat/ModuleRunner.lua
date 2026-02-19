local module = {}

local requiredCache: { [ModuleScript]: any } = setmetatable({}, { __mode = "k" })
local failedCache: { [ModuleScript]: boolean } = setmetatable({}, { __mode = "k" })

local function resolveRunFunction(requiredModule: any, actionName: string): ((any) -> ())?
	if typeof(requiredModule) == "function" then
		return requiredModule
	end

	if typeof(requiredModule) ~= "table" then
		return nil
	end

	local direct = requiredModule[actionName]
	if typeof(direct) == "function" then
		return direct
	end

	local play = requiredModule.Play
	if typeof(play) == "function" then
		return play
	end

	local execute = requiredModule.Execute
	if typeof(execute) == "function" then
		return execute
	end

	return nil
end

function module.Require(moduleScript: ModuleScript, warnPrefix: string?): any
	local cached = requiredCache[moduleScript]
	if cached ~= nil then
		return cached
	end
	if failedCache[moduleScript] then
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		failedCache[moduleScript] = true
		warn(("[%s] Failed to require '%s': %s"):format(warnPrefix or "ModuleRunner", moduleScript:GetFullName(), tostring(result)))
		return nil
	end

	requiredCache[moduleScript] = result
	return result
end

function module.RunModule(moduleScript: ModuleScript, actionName: string, payload: any, warnPrefix: string?): boolean
	local loaded = module.Require(moduleScript, warnPrefix)
	if loaded == nil then
		return false
	end

	local runFn = resolveRunFunction(loaded, actionName)
	if not runFn then
		return false
	end

	local ok, err = pcall(runFn, payload)
	if not ok then
		warn(("[%s] %s execution failed: %s"):format(warnPrefix or "ModuleRunner", tostring(actionName), tostring(err)))
		return false
	end

	return true
end

return table.freeze(module)
