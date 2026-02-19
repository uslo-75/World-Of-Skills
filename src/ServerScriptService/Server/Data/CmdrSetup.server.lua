local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local dataFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Data")
local cmdrModule = dataFolder:WaitForChild("Cmdr")

local okCmdr, Cmdr = pcall(require, cmdrModule)
if not okCmdr then
	warn("[CmdrSetup] Failed to require Cmdr:", Cmdr)
	return
end

Cmdr:RegisterDefaultCommands()

local commandRoots = {
	dataFolder:FindFirstChild("CmdrCommands"),
	script:FindFirstChild("Commands"),
}
for _, root in ipairs(commandRoots) do
	if root then
		Cmdr:RegisterCommandsIn(root)
	end
end

local typeRoots = {
	dataFolder:FindFirstChild("CmdrTypes"),
	script:FindFirstChild("Types"),
}
for _, root in ipairs(typeRoots) do
	if root then
		Cmdr:RegisterTypesIn(root)
	end
end

local hookRoots = {
	dataFolder:FindFirstChild("CmdrHooks"),
	script:FindFirstChild("Hooks"),
}
for _, root in ipairs(hookRoots) do
	if root then
		Cmdr:RegisterHooksIn(root)
	end
end

local ADMIN_USER_IDS = {
	-- Add extra admin UserIds here.
	953516966,
}

local ADMIN_SET = {}
for _, userId in ipairs(ADMIN_USER_IDS) do
	ADMIN_SET[userId] = true
end

local PUBLIC_GROUPS = {
	DefaultUtil = true,
	Help = true,
	UserAlias = true,
}

local MIN_GROUP_RANK = 254

local function canUseAdminCommands(player)
	if RunService:IsStudio() then
		return true
	end

	if ADMIN_SET[player.UserId] == true then
		return true
	end

	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local okRank, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if okRank and rank >= MIN_GROUP_RANK then
			return true
		end
	end

	return false
end

Cmdr:RegisterHook("BeforeRun", function(context)
	local executor = context.Executor
	if not executor then
		return
	end

	if PUBLIC_GROUPS[context.Group] == true then
		return
	end

	if canUseAdminCommands(executor) then
		return
	end

	return "Tu n'as pas la permission d'utiliser cette commande."
end)
