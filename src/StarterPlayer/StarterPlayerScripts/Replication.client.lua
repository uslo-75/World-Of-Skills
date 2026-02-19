local player = game:GetService("Players").LocalPlayer
local camera = workspace.CurrentCamera
local rp = game:GetService("ReplicatedStorage")
local Remotes = rp:WaitForChild("Remotes")
local Replication = Remotes:WaitForChild("Replication")
local camShaker = require(rp:FindFirstChild("Modules"):FindFirstChild("EffectModule"):WaitForChild("CameraShaker"))
local loading_start = os.clock()

local character = player.Character
if not character then
	character = player.CharacterAdded:Wait()
end

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
end)

local LocalHandler = game.ReplicatedStorage:WaitForChild("LocalHandler")
local moduleScriptCache: { [string]: ModuleScript } = {}
local requiredModuleCache: { [string]: any } = {}
local ambiguousModuleNames: { [string]: boolean } = {}
local cacheBuilt = false

local function rebuildModuleIndex()
	table.clear(moduleScriptCache)
	table.clear(ambiguousModuleNames)

	for _, inst in ipairs(LocalHandler:GetDescendants()) do
		if not inst:IsA("ModuleScript") then
			continue
		end

		local moduleName = inst.Name
		if ambiguousModuleNames[moduleName] then
			continue
		end

		local existing = moduleScriptCache[moduleName]
		if existing and existing ~= inst then
			moduleScriptCache[moduleName] = nil
			ambiguousModuleNames[moduleName] = true
			continue
		end

		moduleScriptCache[moduleName] = inst
	end

	cacheBuilt = true
end

local function getIndexedModule(moduleName: string): (ModuleScript?, string?)
	if not cacheBuilt then
		rebuildModuleIndex()
	end

	if ambiguousModuleNames[moduleName] then
		return nil, ("[Replication] ModuleScript '%s' is ambiguous in LocalHandler (duplicate names)"):format(moduleName)
	end

	local moduleScript = moduleScriptCache[moduleName]
	if moduleScript and moduleScript.Parent then
		return moduleScript, nil
	end

	rebuildModuleIndex()
	if ambiguousModuleNames[moduleName] then
		return nil, ("[Replication] ModuleScript '%s' is ambiguous in LocalHandler (duplicate names)"):format(moduleName)
	end

	moduleScript = moduleScriptCache[moduleName]
	if not moduleScript then
		return nil, ("[Replication] ModuleScript '%s' not found under LocalHandler index"):format(moduleName)
	end

	return moduleScript, nil
end

LocalHandler.DescendantAdded:Connect(function(inst)
	if not inst:IsA("ModuleScript") then
		return
	end

	cacheBuilt = false
	requiredModuleCache[inst.Name] = nil
end)

LocalHandler.DescendantRemoving:Connect(function(inst)
	if not inst:IsA("ModuleScript") then
		return
	end

	cacheBuilt = false
	requiredModuleCache[inst.Name] = nil
end)

local function getRequiredModule(moduleName: string)
	local cached = requiredModuleCache[moduleName]
	if cached ~= nil then
		return cached
	end

	local moduleScript = moduleScriptCache[moduleName]
	if not moduleScript or not moduleScript.Parent or ambiguousModuleNames[moduleName] then
		local resolveErr = nil
		moduleScript, resolveErr = getIndexedModule(moduleName)
		if not moduleScript then
			return nil, resolveErr
		end
	end

	local ok, requiredmodule = pcall(require, moduleScript)
	if not ok then
		return nil, ("[Replication] require('%s') failed: %s"):format(moduleScript:GetFullName(), tostring(requiredmodule))
	end

	requiredModuleCache[moduleName] = requiredmodule
	return requiredmodule
end

local Shake = camShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCFrame)
	camera.CFrame = camera.CFrame * shakeCFrame
end)

function shared.Shake(Params)
	local Table = Params

	if typeof(Table.Pos) ~= "table" then
		Table.Pos = {}
	end
	if typeof(Table.magnitude) ~= "number" then
		Table.magnitude = 15
	end
	if typeof(Table.fadeIn) ~= "number" then
		Table.fadeIn = 0
	end
	if typeof(Table.fadeIn) ~= "number" then
		Table.fadeIn = 0
	end
	if typeof(Table.fadeOut) ~= "number" then
		Table.fadeOut = 0.4
	end
	if typeof(Table.fadeOut) ~= "number" then
		Table.fadeOut = 0.4
	end
	if typeof(Table.Pos.X) ~= "number" then
		Table.Pos.X = 0.4
	end
	if typeof(Table.Pos.Y) ~= "number" then
		Table.Pos.Y = 0.5
	end
	if typeof(Table.Pos.Z) ~= "number" then
		Table.Pos.Z = 0.25
	end

	if Shake._running == false then
		Shake:Start()
	end

	local ShakeCam = Shake:ShakeOnce(
		Params.magnitude,
		Params.magnitude,
		Params.fadeIn,
		Params.fadeOut,
		vector.create(Table.Pos.X, Table.Pos.Y, Table.Pos.Z),
		Vector3.zero
	)
	return ShakeCam
end

function shared.SFX(id: string, parent: Part, propierties: {}, tags: {})
	local CollectionService = game:GetService("CollectionService")

	local debris = nil

	local sound = Instance.new("Sound")
	sound.Parent = parent
	sound.SoundId = id
	CollectionService:AddTag(sound, "Client")

	if propierties then
		for i, v in pairs(propierties) do
			if i == "Debris" then
				debris = v
				continue
			end

			sound[i] = v
		end
	end

	sound:Play()

	task.spawn(function()
		if not debris then
			repeat
				task.wait()
			until sound.TimeLength ~= 0

			task.delay(((sound.TimeLength - sound.TimePosition) * sound.PlaybackSpeed) + 2, function()
				if sound.Parent then
					sound:Destroy()
				end
			end)
		else
			repeat
				task.wait()
			until sound.TimeLength ~= 0

			task.delay(debris, function()
				if sound.Parent then
					sound:Destroy()
				end
			end)
		end
	end)

	if tags then
		for i, v in pairs(tags) do
			CollectionService:AddTag(sound, v)
		end
	end

	return sound
end

Replication.OnClientEvent:Connect(function(Module, function_name, ...)
	if typeof(Module) ~= "string" then
		warn("[Replication] Module is not a string:", Module)
		return
	end

	if typeof(function_name) ~= "string" then
		warn("[Replication] function_name is not a string:", function_name, "for module", Module)
		return
	end

	local requiredmodule, moduleErr = getRequiredModule(Module)
	if not requiredmodule then
		warn("[Replication] module resolve failed:", tostring(moduleErr))
		return
	end

	local fn = requiredmodule[function_name]
	if typeof(fn) ~= "function" then
		warn(("[Replication] '%s.%s' is not a function"):format(Module, function_name))
		return
	end

	local ok2, err = pcall(fn, ...)
	if not ok2 then
		warn(("[Replication] Error while running %s.%s: %s"):format(Module, function_name, tostring(err)))
	end
end)

warn(`[REPLICATION] Replication loaded correctly in : {os.clock() - loading_start} seconds.`)
