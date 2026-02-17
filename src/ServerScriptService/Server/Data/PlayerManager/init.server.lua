local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Server.Data.PlayerManager.ProfileStore)
local Template = require(ServerScriptService.Server.Data.PlayerManager.Template)
local DataManager = require(ServerScriptService.Server.Data.PlayerManager.DataManager)
local SessionUtils = require(ServerScriptService.Server.Data.PlayerManager.SessionUtils)
local CharacterLifecycle = require(ServerScriptService.Server.Data.PlayerManager.CharacterLifecycle)

local Inventory = require(ServerScriptService.Server.Handler.Inventory)
local InventoryService = (Inventory and Inventory.Service) or Inventory
local PlayerCustomization = require(ServerScriptService.Server.Data.PlayerManager.PlayerCustomization)

local STORE_NAME = "Beta_V0.5"
local RECENT_DEATH_CAPTURE_WINDOW = 8

local PlayerStore = ProfileStore.New(STORE_NAME, Template)
local deathCapturedAt: { [Player]: number } = {}

local session = SessionUtils.new({
	Profiles = DataManager.Profiles,
	InventoryService = InventoryService,
})

local characterLifecycle = CharacterLifecycle.new({
	DataManager = DataManager,
	PlayerCustomization = PlayerCustomization,
	InventoryService = InventoryService,
	SessionUtils = session,
	RunService = RunService,
	deathCapturedAt = deathCapturedAt,
	RecentDeathCaptureWindow = RECENT_DEATH_CAPTURE_WINDOW,
})

local function PlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
		cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		if RunService:IsStudio() then
			warn("[DATA] Failed to start profile session for player:", player)
			return
		end
		player:Kick("Data error occured. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		DataManager.Profiles[player] = nil

		if player.Parent == Players then
			if RunService:IsStudio() then
				warn("[DATA] Session ended for player (OnSessionEnd):", player)
				return
			end
			player:Kick("Data error occured. Please rejoin.")
		end
	end)

	if player.Parent == Players then
		DataManager.Profiles[player] = profile
		characterLifecycle:Initialize(player, profile)
	else
		profile:EndSession()
	end

	player.CharacterRemoving:Connect(function(character)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, tool in ipairs(character:GetChildren()) do
				if tool:IsA("Tool") then
					tool.Parent = backpack
				end
			end
		end

		local lastDeathAt = deathCapturedAt[player]
		local isRecentDeath = lastDeathAt ~= nil and (os.clock() - lastDeathAt) <= RECENT_DEATH_CAPTURE_WINDOW
		if isRecentDeath then
			return
		end

		session:captureToolsToProfile(player, profile, character, { allowEmptySnapshot = false })
	end)

	player.CharacterAdded:Connect(function(character)
		characterLifecycle:OnCharacterAdded(player, profile, character)
	end)

	player.AncestryChanged:Connect(function(_, parent)
		if not parent and DataManager.Profiles[player] then
			session:endSessionWithCapture(player, profile)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local profile = DataManager.Profiles[player]
	if profile then
		session:endSessionWithCapture(player, profile)
	end
	deathCapturedAt[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(PlayerAdded, player)
end

Players.PlayerAdded:Connect(PlayerAdded)
