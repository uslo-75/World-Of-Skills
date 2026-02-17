local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationHandler =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))
local StateManager =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local StateKeys = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateKeys"))

local Config = require(script:WaitForChild("Config"))
local ToolEquipAnim = require(script:WaitForChild("Anim"))
local ToolEquipObserve = require(script:WaitForChild("Observe"))

local ToolEquipHandler = {}

local LOCAL_PLAYER = Players.LocalPlayer

local anim = ToolEquipAnim.new({
	Config = Config,
	AnimationHandler = AnimationHandler,
})

local observer = ToolEquipObserve.new()

local equippedTool: Tool? = nil
local refreshQueued = false
local runningConn: RBXScriptConnection? = nil
local characterAddedConn: RBXScriptConnection? = nil

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local function isRunning(): boolean
	return StateManager.GetState(LOCAL_PLAYER, StateKeys.Running) == true
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true

	task.defer(function()
		refreshQueued = false

		local char = LOCAL_PLAYER.Character
		if not char then
			return
		end

		local shouldPlay = equippedTool ~= nil and equippedTool.Parent ~= nil
		if Config.StopWhileRunning and isRunning() then
			shouldPlay = false
		end

		if not shouldPlay then
			if anim:isPlaying() then
				anim:stop(char)
			end
			return
		end

		if not anim:isPlaying() then
			anim:play(char)
		end
	end)
end

local function bindRunningSignal()
	disconnect(runningConn)
	runningConn = nil

	local char = LOCAL_PLAYER.Character
	if not char then
		return
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	runningConn = hum.Running:Connect(function()
		queueRefresh()
	end)
end

local function shutdown()
	disconnect(characterAddedConn)
	characterAddedConn = nil

	disconnect(runningConn)
	runningConn = nil

	observer:Stop()

	equippedTool = nil
	refreshQueued = false

	local char = LOCAL_PLAYER.Character
	if char then
		anim:stop(char)
	else
		anim:stop(nil)
	end
end

function ToolEquipHandler.Init()
	shutdown()
	ToolEquipHandler._initialized = true

	observer:Start({
		onEquipped = function(tool)
			equippedTool = tool
			queueRefresh()
		end,
		onUnequipped = function(tool)
			if equippedTool == tool then
				equippedTool = nil
			end
			queueRefresh()
		end,
		onCharacter = function()
			bindRunningSignal()
			queueRefresh()
		end,
	})

	characterAddedConn = LOCAL_PLAYER.CharacterAdded:Connect(function()
		bindRunningSignal()
		queueRefresh()
	end)

	if LOCAL_PLAYER.Character then
		bindRunningSignal()
	end

	queueRefresh()
end

function ToolEquipHandler.Shutdown()
	shutdown()
	ToolEquipHandler._initialized = false
end

return ToolEquipHandler
