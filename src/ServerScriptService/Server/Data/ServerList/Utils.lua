local Utils = {}

function Utils.pickRandom(list, fallback)
	if typeof(list) == "table" and #list > 0 then
		return list[math.random(1, #list)]
	end
	return fallback
end

function Utils.trimString(v)
	if typeof(v) ~= "string" then
		return nil
	end
	local s = v:gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return nil
	end
	return s
end

function Utils.normalizeCountryCode(v)
	local code = Utils.trimString(v)
	if code and #code == 2 then
		return string.upper(code)
	end
	return nil
end

function Utils.formatServerAge(seconds)
	local total = math.max(0, math.floor(seconds))
	local days = math.floor(total / 86400)
	local hours = math.floor((total % 86400) / 3600)
	local minutes = math.floor((total % 3600) / 60)
	return string.format("%dd %dh %dm", days, hours, minutes)
end

function Utils.safePCall(tag, fn)
	local ok, res = pcall(fn)
	if not ok then
		warn(tag, res)
	end
	return ok, res
end

return Utils
