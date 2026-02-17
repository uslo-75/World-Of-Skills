local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CharacterLifecycle = {}

function CharacterLifecycle.new(deps)
	local DataManager = deps.DataManager
	local PlayerCustomization = deps.PlayerCustomization
	local InventoryService = deps.InventoryService
	local SessionUtils = deps.SessionUtils
	local RunService = deps.RunService
	local deathCapturedAt = deps.deathCapturedAt
	local recentDeathCaptureWindow = deps.RecentDeathCaptureWindow

	local self = {}
	local handledCharacters = setmetatable({}, { __mode = "k" })
	local spawnNonceByPlayer: { [Player]: number } = {}

	local function cleanupLiveDuplicates(player: Player, keepCharacter: Model)
		local liveFolder = workspace:FindFirstChild("Live")
		if not liveFolder then
			return
		end

		for _, child in ipairs(liveFolder:GetChildren()) do
			if child ~= keepCharacter and child:IsA("Model") and child.Name == player.Name then
				if child:FindFirstChildOfClass("Humanoid") then
					child:Destroy()
				end
			end
		end
	end

	local function getCustomizationAssetRoot(charData)
		if charData and charData.VaransPath ~= nil then
			return ReplicatedStorage.Assets.customcharacter.Varans.SubRace[charData.VaransPath]
		end
		return ReplicatedStorage.Assets.customcharacter[charData.Civilizations]
	end

	function self:OnCharacterAdded(player: Player, profile, characterOverride: Model?)
		if not profile then
			if RunService:IsStudio() then
				warn("[DATA] No profile for player:", player)
				return
			end
			player:Kick("Data profile missing. Please rejoin.")
			return
		end

		local character = characterOverride or player.Character
		if not character then
			return
		end
		if handledCharacters[character] then
			return
		end
		handledCharacters[character] = true
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				handledCharacters[character] = nil
			end
		end)

		local spawnNonce = (spawnNonceByPlayer[player] or 0) + 1
		spawnNonceByPlayer[player] = spawnNonce

		local currentSlot = profile.Data.SelectedSlot
		if not currentSlot then
			if RunService:IsStudio() then
				warn("[DATA] No CurrentSlot for player:", player)
				return
			end
			player:Kick("Character data corrupted. Please rejoin.")
			return
		end

		local charData = profile.Data[currentSlot] and profile.Data[currentSlot].CharData
		if not charData then
			if RunService:IsStudio() then
				warn("[DATA] CharData is nil for player:", player)
				return
			end
			player:Kick("Character data missing. Please rejoin.")
			return
		end

		local humanoid = character:WaitForChild("Humanoid", 10)
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)

		if not humanoid or not rootPart then
			if RunService:IsStudio() then
				warn("[DATA] Humanoid or RootPart missing for player:", player)
				return
			end
			player:Kick("Character failed to initialize correctly. Please rejoin.")
			return
		end

		humanoid.Died:Connect(function()
			deathCapturedAt[player] = os.clock()
			SessionUtils:captureToolsToProfile(player, profile, character, { allowEmptySnapshot = false })
			task.defer(function()
				deathCapturedAt[player] = os.clock()
				SessionUtils:captureToolsToProfile(player, profile, character, { allowEmptySnapshot = false })
			end)
		end)

		local liveFolder = workspace:FindFirstChild("Live")
		if liveFolder then
			cleanupLiveDuplicates(player, character)
			character.Parent = liveFolder
		end

		if not SessionUtils.waitForCACData(player, 5) then
			if RunService:IsStudio() then
				warn("[DATA] CACData did not load for player:", player)
				return
			end
			player:Kick("Failed to load player data. Please rejoin.")
			return
		end

		if CollectionService:HasTag(player, "Loaded") and SessionUtils:backpackToolCount(player) > 0 then
			local lastDeathAt = deathCapturedAt[player]
			local isRecentDeath = lastDeathAt ~= nil and (os.clock() - lastDeathAt) <= recentDeathCaptureWindow
			if not isRecentDeath then
				SessionUtils:captureToolsToProfile(player, profile, nil, { allowEmptySnapshot = false })
			end
		end

		InventoryService:LoadPlayerInventory(player)
		rootPart.Anchored = true

		local success = false
		for _ = 1, 5 do
			task.wait()

			local ok, result = pcall(DataManager.InitializeInfo, player)
			if not ok then
				warn("[DATA] InitializeInfo threw an error for player:", player, "Error:", result)
				success = false
			else
				success = result ~= false
			end

			if success then
				break
			end

			task.wait()
		end

		if not success then
			if RunService:IsStudio() then
				warn("[DATA] InitializeInfo failed after 5 attempts for player:", player)
				rootPart.Anchored = false
				return
			end

			player:Kick("Unable to initialize your data. Please rejoin.")
			return
		end

		character:SetAttribute("CustomizationLoaded", false)
		PlayerCustomization.ApplyCustomization(player, profile, character)

		local customizationLoaded = false
		local customizationDeadline = os.clock() + 20
		while character.Parent and spawnNonceByPlayer[player] == spawnNonce and os.clock() < customizationDeadline do
			if character:GetAttribute("CustomizationLoaded") == true then
				customizationLoaded = true
				break
			end
			task.wait()
		end
		if spawnNonceByPlayer[player] ~= spawnNonce then
			return
		end

		if not customizationLoaded then
			warn(("[DATA] Customization timeout for %s, continuing spawn"):format(player.Name))
		end

		if not rootPart.Parent then
			return
		end

		local spawnPart = workspace:FindFirstChild("World")
			and workspace.World:FindFirstChild("SpawnPoint")
			and workspace.World.SpawnPoint:FindFirstChild("WorldSpawn")

		if spawnPart and spawnPart:IsA("BasePart") then
			rootPart.CFrame = spawnPart.CFrame
		end

		rootPart.Anchored = false
		if not CollectionService:HasTag(player, "Loaded") then
			SessionUtils.setValue(player, "Loaded", true, "Tag")
		end

	end

	function self:Initialize(player: Player, profile)
		if not profile then
			player:Kick("Data error occurred. Please rejoin.")
			return
		end

		SessionUtils.createCACData(player)

		local currentSlot = profile.Data.SelectedSlot
		if not currentSlot then
			player:Kick("Character data corrupted. Please rejoin.")
			return
		end

		local slotData = profile.Data[currentSlot]
		local charData = slotData and slotData.CharData
		if not charData then
			player:Kick("Character data corrupted. Please rejoin.")
			return
		end

		local desc
		local ok, result = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, player.UserId)
		if ok then
			desc = result
		else
			warn("[DATA] GetHumanoidDescriptionFromUserIdAsync failed for", player, "error:", result)
		end

		local hairId = (desc and desc.HairAccessory ~= "" and desc.HairAccessory) or "None"

		DataManager.ChangeRace(player, "Varans", "Cat", true)

		if not charData.Hair then
			charData.Hair = hairId
		end

		if not charData.HairColor then
			local variant = charData.RaceVariant
			local assetsRoot = getCustomizationAssetRoot(charData)
			local color3 = assetsRoot.Variant["Variant" .. variant].Color.Value
			charData.HairColor = { r = color3.R, g = color3.G, b = color3.B }
		end

		if not charData.Shirt or charData.Shirt == "None" then
			charData.Shirt = getCustomizationAssetRoot(charData).Shirt.Value
		end
		if not charData.Pant or charData.Pant == "None" then
			charData.Pant = getCustomizationAssetRoot(charData).Pant.Value
		end

		SessionUtils.setValue(player, "Civilizations", charData.Civilizations, "Instance")
		SessionUtils.setValue(player, "Power", charData.Power, "Instance")
		SessionUtils.setValue(player, "Rubi", charData.Rubi, "Instance")
		SessionUtils.setValue(player, "ChronoCrystal", charData.ChronoCrystal, "Instance")
		SessionUtils.setValue(player, "XP", charData.XP, "Instance")

		self:OnCharacterAdded(player, profile, player.Character)
	end

	return self
end

return CharacterLifecycle
