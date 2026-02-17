local HttpService = game:GetService("HttpService")
local Utils = require(script.Parent.Utils)

local GeoResolver = {}

function GeoResolver.applyOverride(state, overrideRegion: any)
	local v = Utils.trimString(overrideRegion)
	if not v then
		return
	end

	local overrideCountry = Utils.normalizeCountryCode(v)
	if overrideCountry then
		state.serverCountry = overrideCountry
		state.serverRegionName = overrideCountry
	else
		state.serverRegionName = v
	end
	state.serverRegionResolved = true
end

function GeoResolver.tryResolve(state, geoConfig)
	if state.serverRegionResolved then
		return true
	end

	local okHttp, responseOrErr = pcall(HttpService.GetAsync, HttpService, geoConfig.Url)
	if not okHttp then
		warn("[ServerList] geolookup request failed:", responseOrErr)
		return false
	end

	local okDecode, payloadOrErr = pcall(HttpService.JSONDecode, HttpService, responseOrErr)
	if not okDecode then
		warn("[ServerList] geolookup decode failed:", payloadOrErr)
		return false
	end

	if typeof(payloadOrErr) ~= "table" then
		return false
	end

	local payload = payloadOrErr
	if payload.status ~= "success" then
		return false
	end

	local resolvedRegion = Utils.trimString(payload.regionName)
		or Utils.trimString(payload.region)
		or Utils.trimString(payload.city)

	local resolvedCountry = Utils.normalizeCountryCode(payload.countryCode)
		or Utils.normalizeCountryCode(payload.country_code)

	if resolvedCountry then
		state.serverCountry = resolvedCountry
	end
	if resolvedRegion then
		state.serverRegionName = resolvedRegion
	elseif resolvedCountry then
		state.serverRegionName = resolvedCountry
	end

	state.serverRegionResolved = resolvedRegion ~= nil or resolvedCountry ~= nil
	return state.serverRegionResolved
end

return GeoResolver
