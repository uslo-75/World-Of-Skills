local module = {}

local function cloneFlags(flags: { [any]: any }?): { [any]: boolean }?
	if typeof(flags) ~= "table" then
		return nil
	end

	local copied = {}
	for key, value in pairs(flags) do
		copied[key] = (value == true)
	end
	return copied
end

function module.MakeData(flags: { [any]: any }?, offsetCFrame: CFrame?, action: string?): { [string]: any }
	local data = {}

	local copiedFlags = cloneFlags(flags)
	if copiedFlags then
		data.Flags = copiedFlags
	end

	if typeof(offsetCFrame) == "CFrame" then
		data.OffsetCFrame = offsetCFrame
	end

	if typeof(action) == "string" and action ~= "" then
		data.Action = action
	end

	return data
end

function module.Replicate(
	service,
	effectName: string,
	character: Model,
	player: Player,
	flags: { [any]: any }?,
	offsetCFrame: CFrame?,
	action: string?,
	contextCharacters: any?
)
	local payload = service.CombatNet.MakeCharacterPayload(character, module.MakeData(flags, offsetCFrame, action))
	service:ReplicateWeaponaryEffect(effectName, payload, contextCharacters or { character }, { player })
end

return table.freeze(module)
