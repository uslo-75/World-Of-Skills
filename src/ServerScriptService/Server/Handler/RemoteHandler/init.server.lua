local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Events = ReplicatedStorage:WaitForChild("Remotes")
local Replication = Events:WaitForChild("Replication")
local State = Events:WaitForChild("State")

local AntiCheat = require(script.Parent:WaitForChild("AntiCheat"))

local Inventory = require(script.Parent:WaitForChild("Inventory"))
local InventoryService = (Inventory and Inventory.Service) or Inventory
local Combat = require(script.Parent:WaitForChild("Combat"))

local StateManager =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local CombatStateRules =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatStateRules"))
local CombatNet = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("CombatNet"))
local Utils = require(script:WaitForChild("Utils"))
local combatRoot = script.Parent:WaitForChild("Combat")
local CombatReplication = require(combatRoot:WaitForChild("Shared"):WaitForChild("CombatReplication"))
local M1Config = require(combatRoot:WaitForChild("M1"):WaitForChild("M1Config"))
local DASH_VFX_RADIUS = math.max(0, tonumber(M1Config.VfxReplicationRadius) or 180)

local remoteList = {}

local DASH = Utils.GetDashConfig()
local dashLast: { [Player]: number } = {}
local dashToken: { [Player]: number } = {}

----------------------------------------------

Players.PlayerRemoving:Connect(function(plr)
	dashLast[plr] = nil
	dashToken[plr] = nil
end)

----------------------------------------------

Events.Main.OnServerEvent:Connect(function(player, remoteName, remoteData)
	if not Utils.IsSafeName(remoteName, 32) then
		AntiCheat.Flag(player, "Main remoteName invalid", 1)
		return
	end
	if not AntiCheat.Allow(player, "Main", 25, 1) then
		AntiCheat.Flag(player, "Main rate-limit", 1)
		return
	end

	local fn = remoteList[remoteName]
	if not fn then
		AntiCheat.Flag(player, "Main unknown remote: " .. tostring(remoteName), 1)
		return
	end

	local ok, err = pcall(fn, player, remoteData)
	if not ok then
		AntiCheat.Flag(player, ("Main handler error (%s)"):format(remoteName), 1)
		warn(("[RemoteHandler] Main.%s failed for %s: %s"):format(remoteName, player.Name, tostring(err)))
	end
end)

State.OnServerEvent:Connect(function(player, stateKey, value, duration)
	if not AntiCheat.Allow(player, "State", 10, 1) then
		AntiCheat.Flag(player, "State rate-limit", 1)
		return
	end
	if not Utils.IsSafeName(stateKey, 48) then
		AntiCheat.Flag(player, "State invalid key", 1)
		return
	end
	if not Utils.IsAllowedClientState(stateKey) then
		AntiCheat.Flag(player, "State blocked: " .. stateKey, 1)
		return
	end
	if typeof(value) ~= "boolean" then
		AntiCheat.Flag(player, "State invalid value: " .. stateKey, 1)
		return
	end
	if duration ~= nil and typeof(duration) ~= "number" then
		duration = nil
	end

	StateManager.SetState(player, stateKey, value, duration)
end)

Replication.OnServerEvent:Connect(function(player, a, b, c, d, e)
	if typeof(a) == "string" and a == "RelayVFX" then
		Utils.HandleReplicationRelay(AntiCheat, Replication, player, b, c, d, e)
		return
	end

	Utils.HandleReplicationRelay(AntiCheat, Replication, player, a, b, c, d)
end)

----------------------------------------------

remoteList["destroyGui"] = function(player, guiName)
	if typeof(guiName) ~= "string" then
		AntiCheat.Flag(player, "destroyGui bad type", 1)
		return
	end

	local gui = player.PlayerGui:FindFirstChild(tostring(guiName))
	if gui and gui:IsA("ScreenGui") then
		gui:Destroy()
	end
end

remoteList["dash"] = function(player, bool)
	if typeof(bool) ~= "boolean" then
		AntiCheat.Flag(player, "dash bad type", 1)
		return
	end

	local character = player.Character
	if not character then
		return
	end

	-- Always allow explicit dash stop so client cleanup cannot trigger anti-cheat
	-- when the character has entered another state (block/parry/stun) mid-dash.
	if bool == false then
		character:SetAttribute("Dashing", nil)
		character:SetAttribute("iFrames", false)
		return
	end

	if CollectionService:HasTag(character, "Dead") or player:GetAttribute("Wiped") then
		AntiCheat.Flag(player, "dash while dead/wiped", 1)
		return
	end
	if character:GetAttribute("Stunned") or character:GetAttribute("SlowStunned") then
		AntiCheat.Flag(player, "dash while stunned", 1)
		return
	end
	if character:GetAttribute("IsRagdoll") or character:GetAttribute("UsingMove") then
		AntiCheat.Flag(player, "dash while ragdoll/using move", 1)
		return
	end
	if character:GetAttribute("Gripping") == true then
		AntiCheat.Flag(player, "dash while gripping", 1)
		return
	end
	if CombatStateRules.IsDefenseActive(character) then
		AntiCheat.Flag(player, "dash while blocking/parrying/auto-parry", 1)
		return
	end

	if not AntiCheat.Allow(player, "Dash", 4, 1) then
		AntiCheat.Flag(player, "dash rate-limit", 1)
		return
	end

	local now = os.clock()
	local last = dashLast[player]
	if last and (now - last) < DASH.cooldown then
		AntiCheat.Flag(player, "dash cooldown", 1)
		return
	end
	dashLast[player] = now

	character:SetAttribute("Dashing", true)
	character:SetAttribute("iFrames", true)
	if CombatReplication and typeof(CombatReplication.FireClientsNear) == "function" then
		CombatReplication.FireClientsNear(
			Replication,
			"Global",
			"BodyTrail",
			{ character, 0.55, "BodyTrail1" },
			{ character },
			DASH_VFX_RADIUS,
			{ player }
		)
	else
		Replication:FireAllClients("Global", "BodyTrail", { character, 0.55, "BodyTrail1" })
	end

	local token = (dashToken[player] or 0) + 1
	dashToken[player] = token
	task.delay(DASH.duration, function()
		if dashToken[player] ~= token then
			return
		end
		if character and character.Parent then
			character:SetAttribute("Dashing", nil)
			character:SetAttribute("iFrames", false)
		end
	end)
end

remoteList["fallDamage"] = function(_player, _damage)
	return
end

remoteList["inventory"] = function(player, remoteData)
	if not AntiCheat.Allow(player, "InventoryRemote", 18, 1) then
		AntiCheat.Flag(player, "inventory rate-limit", 1)
		return
	end

	if not InventoryService or not InventoryService.HandleRemoteRequest then
		AntiCheat.Flag(player, "inventory service missing", 1)
		return
	end

	local ok, err = InventoryService:HandleRemoteRequest(player, remoteData)
	if not ok and err then
		AntiCheat.Flag(player, ("inventory invalid request: %s"):format(tostring(err)), 1)
	end
end

remoteList["combatM1"] = function(player, remoteData)
	local normalizedPayload, payloadErr = CombatNet.NormalizeM1Payload(remoteData)
	if not normalizedPayload then
		AntiCheat.Flag(player, ("combatM1 invalid payload: %s"):format(tostring(payloadErr)), 1)
		return
	end

	if not AntiCheat.Allow(player, "CombatM1Remote", 16, 1) then
		AntiCheat.Flag(player, "combatM1 rate-limit", 1)
		return
	end

	if not Combat or not Combat.M1 or typeof(Combat.M1.HandleRequest) ~= "function" then
		AntiCheat.Flag(player, "combatM1 service missing", 1)
		return
	end

	local ok, reason = Combat.M1:HandleRequest(player, normalizedPayload)
	if not ok then
		if reason == "InvalidPayload" or reason == "InvalidToolName" or reason == "ToolMismatch" then
			AntiCheat.Flag(player, ("combatM1 invalid request: %s"):format(tostring(reason)), 1)
		end
	end
end

remoteList["combatBlock"] = function(player, remoteData)
	local normalizedPayload, payloadErr = CombatNet.NormalizeBlockPayload(remoteData)
	if not normalizedPayload then
		AntiCheat.Flag(player, ("combatBlock invalid payload: %s"):format(tostring(payloadErr)), 1)
		return
	end

	if not AntiCheat.Allow(player, "CombatBlockRemote", 18, 1) then
		AntiCheat.Flag(player, "combatBlock rate-limit", 1)
		return
	end

	if not Combat or not Combat.Block or typeof(Combat.Block.HandleRequest) ~= "function" then
		AntiCheat.Flag(player, "combatBlock service missing", 1)
		return
	end

	local ok, reason = Combat.Block:HandleRequest(player, normalizedPayload)
	if not ok and (reason == "InvalidPayload" or reason == "InvalidAction") then
		AntiCheat.Flag(player, ("combatBlock invalid request: %s"):format(tostring(reason)), 1)
	end
end

remoteList["combatCritical"] = function(player, remoteData)
	local normalizedPayload, payloadErr = CombatNet.NormalizeCriticalPayload(remoteData)
	if not normalizedPayload then
		AntiCheat.Flag(player, ("combatCritical invalid payload: %s"):format(tostring(payloadErr)), 1)
		return
	end

	if not AntiCheat.Allow(player, "CombatCriticalRemote", 12, 1) then
		AntiCheat.Flag(player, "combatCritical rate-limit", 1)
		return
	end

	if not Combat or not Combat.Critical or typeof(Combat.Critical.HandleRequest) ~= "function" then
		AntiCheat.Flag(player, "combatCritical service missing", 1)
		return
	end

	local ok, reason = Combat.Critical:HandleRequest(player, normalizedPayload)
	if not ok and (reason == "InvalidPayload" or reason == "InvalidAction" or reason == "InvalidToolName" or reason == "ToolMismatch") then
		AntiCheat.Flag(player, ("combatCritical invalid request: %s"):format(tostring(reason)), 1)
	end
end

remoteList["combatSkill"] = function(player, remoteData)
	local normalizedPayload, payloadErr = CombatNet.NormalizeSkillPayload(remoteData)
	if not normalizedPayload then
		AntiCheat.Flag(player, ("combatSkill invalid payload: %s"):format(tostring(payloadErr)), 1)
		return
	end

	if not AntiCheat.Allow(player, "CombatSkillRemote", 12, 1) then
		AntiCheat.Flag(player, "combatSkill rate-limit", 1)
		return
	end

	if not Combat or not Combat.Critical or typeof(Combat.Critical.HandleSkillRequest) ~= "function" then
		AntiCheat.Flag(player, "combatSkill service missing", 1)
		return
	end

	local ok, reason = Combat.Critical:HandleSkillRequest(player, normalizedPayload)
	if not ok and (
		reason == "InvalidPayload"
		or reason == "InvalidAction"
		or reason == "InvalidToolName"
		or reason == "ToolMismatch"
		or reason == "InvalidSkillKey"
	) then
		AntiCheat.Flag(player, ("combatSkill invalid request: %s"):format(tostring(reason)), 1)
	end
end

----------------------------------------------
