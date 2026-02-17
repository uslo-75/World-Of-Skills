-- ReplicatedStorage/Modules/Loader.lua
local RunService = game:GetService("RunService")

local Loader = {}

local function hasNoAutoLoad(inst: Instance): boolean
	-- Si un parent folder a NoAutoLoad = true, on ignore aussi
	while inst do
		local v = inst:GetAttribute("NoAutoLoad")
		if v == true then
			return true
		end
		inst = inst.Parent
	end
	return false
end

local function shouldSkipByPath(ms: ModuleScript, skipPaths: { string }): boolean
	local full = ms:GetFullName()
	for _, p in ipairs(skipPaths) do
		if full:find(p, 1, true) then
			return true
		end
	end
	return false
end

local function collectModuleScripts(roots: { Instance }, opts)
	local out = {}
	local skipPaths = opts.skipPaths or {}

	for _, root in ipairs(roots) do
		if root and root.Parent and not hasNoAutoLoad(root) then
			for _, inst in ipairs(root:GetDescendants()) do
				if inst:IsA("ModuleScript") then
					if not hasNoAutoLoad(inst) and not shouldSkipByPath(inst, skipPaths) then
						table.insert(out, inst)
					end
				end
			end
		end
	end

	-- ordre stable + LoadOrder
	table.sort(out, function(a, b)
		local ao = a:GetAttribute("LoadOrder") or 0
		local bo = b:GetAttribute("LoadOrder") or 0
		if ao ~= bo then
			return ao < bo
		end
		return a:GetFullName() < b:GetFullName()
	end)

	return out
end

local function safeRequire(ms: ModuleScript)
	local ok, mod = pcall(require, ms)
	if not ok then
		warn(("[Loader] require failed: %s | %s"):format(ms:GetFullName(), tostring(mod)))
		return nil
	end
	return mod
end

local function callIfExists(mod, fnName: "Init" | "Start")
	local fn = mod and mod[fnName]
	if typeof(fn) == "function" then
		local ok, err = pcall(fn)
		if not ok then
			warn(("[Loader] %s() error: %s"):format(fnName, tostring(err)))
		end
	end
end

function Loader.LoadAll(opts)
	opts = opts or {}

	local RS = game:GetService("ReplicatedStorage")

	local roots = {}

	-- Shared
	if opts.includeModules ~= false then
		table.insert(roots, RS:WaitForChild("Modules"))
	end
	if opts.includeLocalHandler ~= false then
		table.insert(roots, RS:WaitForChild("LocalHandler"))
	end

	-- Server-only roots (extensible)
	if RunService:IsServer() and opts.serverRoots then
		for _, r in ipairs(opts.serverRoots) do
			table.insert(roots, r)
		end
	end

	-- Client-only roots (extensible)
	if RunService:IsClient() and opts.clientRoots then
		for _, r in ipairs(opts.clientRoots) do
			table.insert(roots, r)
		end
	end

	-- Par défaut on skip les libs (utils purs)
	local skipPaths = opts.skipPaths
		or {
			"ReplicatedStorage.Modules.EffectModule",
			"ReplicatedStorage.Modules.Libs",
			"ReplicatedStorage.LocalHandler.UI",
		}

	local moduleScripts = collectModuleScripts(roots, { skipPaths = skipPaths })

	-- require cache pour ne pas re-require 2 fois
	local required = {}

	for _, ms in ipairs(moduleScripts) do
		local mod = safeRequire(ms)
		if mod ~= nil then
			required[ms] = mod
		end
	end

	-- Init puis Start
	for _, ms in ipairs(moduleScripts) do
		callIfExists(required[ms], "Init")
	end
	for _, ms in ipairs(moduleScripts) do
		callIfExists(required[ms], "Start")
	end
end

return Loader
