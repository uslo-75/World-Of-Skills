local Players = game:GetService("Players")

local module = {}

local function addRecipient(recipients: { Player }, seen: { [Player]: boolean }, player: Player?)
	if not player or seen[player] then
		return
	end
	if player.Parent ~= Players then
		return
	end

	seen[player] = true
	table.insert(recipients, player)
end

local function getRootPosition(character: Model?): Vector3?
	if not character or not character.Parent then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

local function appendContextCenters(centers: { Vector3 }, value: any)
	if typeof(value) == "Instance" and value:IsA("Model") then
		local pos = getRootPosition(value)
		if pos then
			table.insert(centers, pos)
		end
		return
	end

	if typeof(value) ~= "table" then
		return
	end

	for _, nested in ipairs(value) do
		appendContextCenters(centers, nested)
	end
end

function module.ResolveNearbyPlayers(
	contextCharacters: any,
	radius: number?,
	includePlayers: { Player }?
): { Player }
	local recipients = {}
	local seen: { [Player]: boolean } = {}
	local centers = {}

	appendContextCenters(centers, contextCharacters)

	local maxDistance = math.max(0, tonumber(radius) or 0)
	local maxDistanceSq = maxDistance * maxDistance

	if #centers > 0 and maxDistanceSq > 0 then
		for _, player in ipairs(Players:GetPlayers()) do
			local pos = getRootPosition(player.Character)
			if not pos then
				continue
			end

			for _, center in ipairs(centers) do
				local delta = pos - center
				if delta:Dot(delta) <= maxDistanceSq then
					addRecipient(recipients, seen, player)
					break
				end
			end
		end
	end

	if includePlayers then
		for _, player in ipairs(includePlayers) do
			addRecipient(recipients, seen, player)
		end
	end

	return recipients
end

function module.FireClientsNear(
	replicationRemote: RemoteEvent,
	moduleName: string,
	functionName: string,
	payload: any,
	contextCharacters: any,
	radius: number?,
	includePlayers: { Player }?
): number
	if not replicationRemote then
		return 0
	end

	local recipients = module.ResolveNearbyPlayers(contextCharacters, radius, includePlayers)
	for _, player in ipairs(recipients) do
		replicationRemote:FireClient(player, moduleName, functionName, payload)
	end

	return #recipients
end

function module.FireClientsNearArgs(
	replicationRemote: RemoteEvent,
	moduleName: string,
	functionName: string,
	args: { any }?,
	contextCharacters: any,
	radius: number?,
	includePlayers: { Player }?
): number
	if not replicationRemote then
		return 0
	end

	local payloadArgs = args
	if typeof(payloadArgs) ~= "table" then
		payloadArgs = {}
	end

	local recipients = module.ResolveNearbyPlayers(contextCharacters, radius, includePlayers)
	for _, player in ipairs(recipients) do
		replicationRemote:FireClient(player, moduleName, functionName, table.unpack(payloadArgs))
	end

	return #recipients
end

return table.freeze(module)
