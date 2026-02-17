local Players = game:GetService("Players")

local DeathShutdown = {}

local player = Players.LocalPlayer
local characterAddedConn: RBXScriptConnection? = nil
local currentDiedConn: RBXScriptConnection? = nil

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local function disableMainScripts(character: Model, controllerScript: BaseScript?)
	local mainFolder = character:FindFirstChild("Main")
	if not mainFolder then
		return
	end

	for _, inst in ipairs(mainFolder:GetDescendants()) do
		if inst:IsA("BaseScript") and inst ~= controllerScript then
			inst.Enabled = false
		end
	end
end

local function disableMainGuiScripts()
	local mainGui = player:WaitForChild("PlayerGui"):FindFirstChild("Main")
	if not mainGui then
		return
	end

	for _, child in ipairs(mainGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			child.Enabled = false
		end
	end

	for _, inst in ipairs(mainGui:GetDescendants()) do
		if inst:IsA("BaseScript") then
			inst.Enabled = false
		end
	end
end

local function bindCharacter(character: Model, controllerScript: BaseScript?)
	disconnect(currentDiedConn)
	currentDiedConn = nil

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local didShutdown = false
	currentDiedConn = humanoid.Died:Connect(function()
		if didShutdown then
			return
		end
		didShutdown = true

		disableMainScripts(character, controllerScript)
		disableMainGuiScripts()
	end)
end

function DeathShutdown.Init(config)
	disconnect(characterAddedConn)
	characterAddedConn = nil

	local controllerScript = config and config.controllerScript

	if player.Character then
		bindCharacter(player.Character, controllerScript)
	end

	characterAddedConn = player.CharacterAdded:Connect(function(character)
		bindCharacter(character, controllerScript)
	end)
end

return DeathShutdown
