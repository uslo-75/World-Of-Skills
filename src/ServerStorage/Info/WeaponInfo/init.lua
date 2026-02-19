local module = {}
local info = {}

local function register(name: any, data: any)
	if typeof(name) ~= "string" or name == "" then
		return
	end
	if typeof(data) ~= "table" then
		return
	end
	if info[name] ~= nil then
		warn(("[WeaponInfo] Duplicate entry '%s'"):format(name))
		return
	end

	info[name] = data
end

local function loadEntry(moduleScript: ModuleScript)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(("[WeaponInfo] Failed to load '%s': %s"):format(moduleScript:GetFullName(), tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		warn(("[WeaponInfo] Invalid module '%s': expected table"):format(moduleScript:GetFullName()))
		return
	end

	if typeof(result.Name) == "string" and typeof(result.Data) == "table" then
		register(result.Name, result.Data)
		return
	end

	-- Fallback: module returns raw data table; use module name as key.
	register(moduleScript.Name, result)
end

local loaded = {}

local function loadFromContainer(container: Instance?, exclude: Instance?)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("ModuleScript") then
			continue
		end
		if child == exclude then
			continue
		end
		if loaded[child] then
			continue
		end

		loaded[child] = true
		loadEntry(child)
	end
end

-- Support both mappings:
-- 1) script is a ModuleScript with child weapon modules.
-- 2) script is an "init" ModuleScript with sibling weapon modules.
loadFromContainer(script, script)
if next(info) == nil and script.Name == "init" then
	loadFromContainer(script.Parent, script)
end

function module:getWeapon(weaponName: string)
	return info[weaponName]
end

return module
