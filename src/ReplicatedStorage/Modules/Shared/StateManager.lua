local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}

local states = {}
local stateTokens = {}

local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("State")
local CLIENT_REPLICATED = {
	Sliding = true,
	Crouching = true,
	WallRunning = true,
	Climbing = true,
}

local charConns = {} -- [Player] = RBXScriptConnection

local function clearPlayerStates(plr: Player)
	states[plr] = nil
	stateTokens[plr] = nil
end

local function hookCharacterRemoving(plr: Player)
	-- cleanup old conn if any
	local c = charConns[plr]
	if c then
		c:Disconnect()
		charConns[plr] = nil
	end

	-- If already has a character, hook its AncestryChanged (fires when removed)
	local char = plr.Character
	if not char then
		return
	end

	charConns[plr] = char.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearPlayerStates(plr)
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterAdded:Connect(function()
		-- Re-hook on each respawn
		hookCharacterRemoving(plr)
	end)
	hookCharacterRemoving(plr)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		hookCharacterRemoving(plr)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	local c = charConns[plr]
	if c then
		c:Disconnect()
		charConns[plr] = nil
	end
	clearPlayerStates(plr)
end)

function module.ReturnStates(plr: Player)
	return states[plr]
end

function module.GetState(plr: Player, stateKey: string)
	local plrStates = states[plr]
	return plrStates and plrStates[stateKey] or nil
end

function module.SetState(plr: Player, stateKey: string, value: any, duration: number?, replicate: boolean?)
	local plrStates = states[plr]
	if plrStates == nil then
		if value == nil then
			return
		end
		plrStates = {}
		states[plr] = plrStates
	end

	local plrTokens = stateTokens[plr]
	if plrTokens == nil then
		plrTokens = {}
		stateTokens[plr] = plrTokens
	end

	local hasTimedDuration = type(duration) == "number" and duration > 0
	local previousValue = plrStates[stateKey]
	if previousValue == value and not hasTimedDuration then
		return
	end

	local nextToken = (plrTokens[stateKey] or 0) + 1
	plrTokens[stateKey] = nextToken

	plrStates[stateKey] = value
	if value == nil then
		plrTokens[stateKey] = nil
	end
	if value == nil and next(plrStates) == nil then
		states[plr] = nil
	end
	if value == nil and next(plrTokens) == nil then
		stateTokens[plr] = nil
	end

	if hasTimedDuration then
		local tokenAtSchedule = nextToken
		task.delay(duration, function()
			local currentStates = states[plr]
			if not currentStates then
				return
			end
			local tokens = stateTokens[plr]
			if not tokens or tokens[stateKey] ~= tokenAtSchedule then
				return
			end

			currentStates[stateKey] = nil
			tokens[stateKey] = nil
			if next(currentStates) == nil then
				states[plr] = nil
			end
			if next(tokens) == nil then
				stateTokens[plr] = nil
			end
		end)
	end

	if replicate and RunService:IsClient() then
		if CLIENT_REPLICATED[stateKey] then
			Remote:FireServer(stateKey, value, duration)
		end
	end
end

function module.RemoveStates(plr: Player, stateKey: string?)
	local plrStates = states[plr]
	if not plrStates then
		return
	end
	local plrTokens = stateTokens[plr]

	if stateKey ~= nil then
		plrStates[stateKey] = nil
		if plrTokens then
			plrTokens[stateKey] = nil
		end
		if next(plrStates) == nil then
			states[plr] = nil
		end
		if plrTokens and next(plrTokens) == nil then
			stateTokens[plr] = nil
		end
	else
		states[plr] = nil
		stateTokens[plr] = nil
	end
end

function module.ClearAllStates()
	table.clear(states)
	table.clear(stateTokens)
end

return module
