local SnowEffect = require(script:WaitForChild("Snow"))
local RainEffect = require(script:WaitForChild("Rain"))

local DynamicAmbience = {}

local EFFECT_MODULES = {
	Snow = SnowEffect,
	Rain = RainEffect,
	-- Fog = ...
	-- Sand = ...
	-- Wind = ...
	-- Wind_Snow = ...
}

local activeEffects: { [string]: any } = {}

local function getOrCreateEffect(effectName)
	local active = activeEffects[effectName]
	if active then
		return active
	end

	local module = EFFECT_MODULES[effectName]
	if not module then
		return nil
	end

	local created = nil
	if type(module.new) == "function" then
		created = module.new()
	else
		created = module
	end

	activeEffects[effectName] = created
	return created
end

local function startEffect(effectName, options)
	local effect = getOrCreateEffect(effectName)
	if not effect then
		return
	end

	if type(effect.Start) == "function" then
		effect:Start(options)
	end
end

local function stopEffect(effectName, options)
	local effect = activeEffects[effectName]
	if not effect then
		return
	end

	if type(effect.Stop) == "function" then
		effect:Stop(options)
	end
end

function DynamicAmbience.Apply(config, options)
	config = config or {}
	if type(options) ~= "table" then
		options = nil
	end

	for effectName, _ in pairs(EFFECT_MODULES) do
		if config[effectName] == true then
			startEffect(effectName, options)
		else
			stopEffect(effectName, options)
		end
	end
end

function DynamicAmbience.Reset()
	DynamicAmbience.Apply({})
end

return DynamicAmbience
