local DataManager = {}
local HttpService = game:GetService("HttpService")

-- Store profiles from ProfileStore
DataManager.Profiles = {}

local RACES = { "Solarians", "Lunarians", "Sangivores", "Pharaosiens", "Varans" }
local VARANS_PATHS = { "Bat", "Cat", "Fish", "Bird" }

local BASE_STATS_DEFAULTS = {
	MaxHP = 80,
	MaxEther = 50,
	MaxPosture = 100,
	MaxCapacity = 100,
	Strength = 0,
	Agility = 0,
	Intelligence = 0,
	Vitality = 0,
	Fortitude = 0,
	WeaponMastery = 0,
	HPBuff = 0,
	EtherBuff = 0,
	LuckBuff = 0,
}

local ATTRIBUTE_KEYS = {
	"Strength",
	"Agility",
	"Intelligence",
	"Vitality",
	"Fortitude",
	"WeaponMastery",
	"MaxHP",
	"MaxEther",
	"MaxPosture",
	"MaxCapacity",
	"HPBuff",
	"EtherBuff",
	"LuckBuff",
}

local STAT_ALIASES = {
	maxstamina = "MaxEther",
	maxstam = "MaxEther",
	staminabuff = "EtherBuff",
}

local DEFAULT_MAX_CAPACITY = 100

---------------------------------------------------

local function normalizeStatName(statName)
	if typeof(statName) ~= "string" then
		return nil
	end

	local normalized = string.lower((statName:gsub("[%s_%-%.,]", "")))
	if STAT_ALIASES[normalized] ~= nil then
		return STAT_ALIASES[normalized]
	end

	for canonical in pairs(BASE_STATS_DEFAULTS) do
		if string.lower(canonical) == normalized then
			return canonical
		end
	end

	return statName
end

function DataManager.parseStatsString(statsString)
	if typeof(statsString) ~= "string" or statsString == "" then
		return {}
	end

	local parsed = {}
	for rawStatName, rawValue in statsString:gmatch("([%a_][%w_%-%s]*)%s*[:=]?%s*([%+%-]?%d+%.?%d*)") do
		local key = normalizeStatName(rawStatName)
		local numeric = tonumber(rawValue)
		if key ~= nil and numeric ~= nil then
			parsed[key] = (parsed[key] or 0) + numeric
		end
	end

	return parsed
end

---------------------------------------------------

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, child in pairs(value) do
		cloned[key] = deepCopy(child)
	end
	return cloned
end

local function resolveSelectedSlot(profileData): number
	local selectedSlot = tonumber(profileData and profileData.SelectedSlot) or 1
	selectedSlot = math.floor(selectedSlot)
	if selectedSlot < 1 then
		selectedSlot = 1
	end
	return selectedSlot
end

local function getOrCreateSlotData(profileData, slotIndex: number)
	local slotData = profileData[slotIndex]
	if typeof(slotData) ~= "table" then
		slotData = {}
		profileData[slotIndex] = slotData
	end
	return slotData
end

local function sanitizeStatsMap(rawStats): { [string]: number }
	if typeof(rawStats) == "string" then
		return DataManager.parseStatsString(rawStats)
	end

	if typeof(rawStats) ~= "table" then
		return {}
	end

	local parsed = {}
	for rawName, rawValue in pairs(rawStats) do
		local statName = normalizeStatName(rawName)
		local numeric = tonumber(rawValue)
		if statName ~= nil and numeric ~= nil then
			parsed[statName] = numeric
		end
	end
	return parsed
end

local function normalizeItemName(rawName): string?
	if typeof(rawName) ~= "string" then
		return nil
	end
	local trimmed = rawName:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

local function normalizeInventoryEntry(rawEntry)
	if typeof(rawEntry) ~= "table" then
		return nil
	end

	local itemName = normalizeItemName(rawEntry.name or rawEntry.Name)
	if not itemName then
		return nil
	end

	local itemId = rawEntry.id or rawEntry.Id
	if typeof(itemId) ~= "string" or itemId == "" then
		itemId = HttpService:GenerateGUID(false)
	end

	local createdAt = tonumber(rawEntry.createdAt or rawEntry.CreatedAt or os.time()) or os.time()
	local stats = sanitizeStatsMap(rawEntry.stats or rawEntry.Stats)
	local statsRaw = rawEntry.statsRaw or rawEntry.StatsRaw
	if typeof(statsRaw) ~= "string" then
		statsRaw = nil
	end
	local enchant = rawEntry.enchant or rawEntry.Enchant
	local itemType = rawEntry.type or rawEntry.Type
	local rarity = rawEntry.rarity or rawEntry.Rarity
	local description = rawEntry.description or rawEntry.Description

	local normalized = {
		id = itemId,
		name = itemName,
		stats = stats,
		statsRaw = statsRaw,
		enchant = enchant,
		type = (typeof(itemType) == "string" and itemType) or nil,
		rarity = (typeof(rarity) == "string" and rarity) or nil,
		description = (typeof(description) == "string" and description) or nil,
		createdAt = createdAt,
	}

	return normalized
end

local function getCapacityFromPlayerValues(player: Player): number?
	local attributesFolder = player:FindFirstChild("Attributes")
	if attributesFolder and attributesFolder:IsA("Folder") then
		local maxCapacityValue = attributesFolder:FindFirstChild("MaxCapacity")
		if maxCapacityValue and maxCapacityValue:IsA("NumberValue") then
			return maxCapacityValue.Value
		end
	end

	local statsFolder = player:FindFirstChild("Stats")
	if statsFolder and statsFolder:IsA("Folder") then
		local maxCapacityValue = statsFolder:FindFirstChild("MaxCapacity")
		if maxCapacityValue and maxCapacityValue:IsA("NumberValue") then
			return maxCapacityValue.Value
		end
	end

	return nil
end

local function getSelectedSlotInventory(profileData, createIfMissing: boolean)
	local selectedSlot = resolveSelectedSlot(profileData)
	local slotData = getOrCreateSlotData(profileData, selectedSlot)

	-- Legacy migration: move old root inventory into selected slot
	if typeof(profileData.Inventory) == "table" then
		if typeof(slotData.Inventory) ~= "table" then
			slotData.Inventory = {}
		end
		if #slotData.Inventory == 0 and #profileData.Inventory > 0 then
			for _, legacyEntry in ipairs(profileData.Inventory) do
				local normalized = normalizeInventoryEntry(legacyEntry)
				if normalized then
					table.insert(slotData.Inventory, normalized)
				end
			end
		end
		profileData.Inventory = nil
	end

	if typeof(slotData.Inventory) ~= "table" and createIfMissing then
		slotData.Inventory = {}
	end

	if typeof(slotData.Inventory) ~= "table" then
		return nil
	end

	for index = #slotData.Inventory, 1, -1 do
		local normalized = normalizeInventoryEntry(slotData.Inventory[index])
		if normalized then
			slotData.Inventory[index] = normalized
		else
			table.remove(slotData.Inventory, index)
		end
	end

	return slotData.Inventory
end

function DataManager.GetInventoryCapacity(player: Player): number
	local profile = DataManager.Profiles[player]
	if not profile or not profile.Data then
		return DEFAULT_MAX_CAPACITY
	end

	local numericCapacity = getCapacityFromPlayerValues(player)

	if numericCapacity == nil then
		local selectedSlot = resolveSelectedSlot(profile.Data)
		local slotData = profile.Data[selectedSlot]
		local charStats = slotData and slotData.CharStats
		numericCapacity = tonumber(charStats and charStats.MaxCapacity)
	end

	numericCapacity = tonumber(numericCapacity) or DEFAULT_MAX_CAPACITY
	numericCapacity = math.max(0, math.floor(numericCapacity))
	return numericCapacity
end

function DataManager.GetInventory(player: Player, createIfMissing: boolean?): { [number]: any }?
	local profile = DataManager.Profiles[player]
	if not profile or not profile.Data then
		return nil
	end

	return getSelectedSlotInventory(profile.Data, createIfMissing == true)
end

function DataManager.GetInventoryCount(player: Player): number
	local inventory = DataManager.GetInventory(player, false)
	if typeof(inventory) ~= "table" then
		return 0
	end
	return #inventory
end

function DataManager.GetInventorySnapshot(player: Player): { [number]: any }
	local inventory = DataManager.GetInventory(player, false)
	if typeof(inventory) ~= "table" then
		return {}
	end

	local snapshot = table.create(#inventory)
	for i, item in ipairs(inventory) do
		snapshot[i] = deepCopy(item)
	end

	return snapshot
end

function DataManager.ReplaceInventory(player: Player, entries): (boolean, string?, number)
	local inventory = DataManager.GetInventory(player, true)
	if typeof(inventory) ~= "table" then
		return false, "ProfileMissing", 0
	end

	table.clear(inventory)

	local capacity = DataManager.GetInventoryCapacity(player)
	local inserted = 0

	if typeof(entries) == "table" then
		for _, rawEntry in ipairs(entries) do
			local normalized = normalizeInventoryEntry(rawEntry)
			if normalized then
				if inserted >= capacity then
					break
				end
				inserted += 1
				inventory[inserted] = normalized
			end
		end
	end

	return true, nil, inserted
end

local function getCharData(player)
	local profile = DataManager.Profiles[player]
	if not profile then
		return nil
	end

	local currentSlot = profile.Data.SelectedSlot
	if not currentSlot then
		return nil
	end

	local slotData = profile.Data[currentSlot]
	if not slotData or not slotData.CharData then
		return nil
	end

	return slotData.CharData
end

local function listHasValue(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function resetCustomizationToTemplateDefaults(charData)
	charData.Hair = nil
	charData.RaceVariant = 1
	charData.FacialMark = 1
	charData.Face = 1
	charData.Skin = 1
	charData.Ornament = 1
	charData.OrnamentColors = nil
	charData.HairColor = nil
	charData.Shirt = "None"
	charData.Pant = "None"
end

function DataManager.ChangeRace(player, raceName, subRace, resetCustomization)
	local charData = getCharData(player)
	if not charData then
		return false
	end

	if not raceName or not listHasValue(RACES, raceName) then
		warn(("[DataManager] Race invalide: %s"):format(tostring(raceName)))
		return false
	end

	charData.Civilizations = raceName

	if raceName == "Varans" then
		if subRace ~= nil and not listHasValue(VARANS_PATHS, subRace) then
			warn(("[DataManager] SubRace varans invalide: %s"):format(tostring(subRace)))
			subRace = nil
		end

		charData.VaransPath = subRace or VARANS_PATHS[math.random(1, #VARANS_PATHS)]
	else
		charData.VaransPath = nil
	end

	if resetCustomization == true then
		resetCustomizationToTemplateDefaults(charData)
	end

	return true
end

function DataManager.SetRandomRace(player)
	local chosenRace = RACES[math.random(1, #RACES)]
	return DataManager.ChangeRace(player, chosenRace)
end

---------------------------------------------------

function DataManager.AddItemToInventory(player, ItemName, Itemstats, Enchant, extraData)
	local inventory = DataManager.GetInventory(player, true)
	if typeof(inventory) ~= "table" then
		return false, "ProfileMissing"
	end

	local itemName = normalizeItemName(ItemName)
	if not itemName then
		return false, "InvalidName"
	end

	local maxCapacity = DataManager.GetInventoryCapacity(player)
	if #inventory >= maxCapacity then
		return false, "CapacityReached"
	end

	local base = {
		id = HttpService:GenerateGUID(false),
		name = itemName,
		stats = sanitizeStatsMap(Itemstats),
		statsRaw = (typeof(Itemstats) == "string" and Itemstats) or nil,
		enchant = Enchant,
		createdAt = os.time(),
	}

	if typeof(extraData) == "table" then
		if typeof(extraData.type) == "string" then
			base.type = extraData.type
		elseif typeof(extraData.Type) == "string" then
			base.type = extraData.Type
		end

		if typeof(extraData.rarity) == "string" then
			base.rarity = extraData.rarity
		elseif typeof(extraData.Rarity) == "string" then
			base.rarity = extraData.Rarity
		end

		if typeof(extraData.description) == "string" then
			base.description = extraData.description
		elseif typeof(extraData.Description) == "string" then
			base.description = extraData.Description
		end

		if typeof(extraData.statsRaw) == "string" then
			base.statsRaw = extraData.statsRaw
		elseif typeof(extraData.StatsRaw) == "string" then
			base.statsRaw = extraData.StatsRaw
		end
	end

	local normalized = normalizeInventoryEntry(base)
	if not normalized then
		return false, "InvalidEntry"
	end

	table.insert(inventory, normalized)
	return true, deepCopy(normalized)
end

function DataManager.RemoveItemFromInventory(player: Player, itemIdOrName: string, amount: number?): (boolean, { [number]: any })
	local inventory = DataManager.GetInventory(player, false)
	if typeof(inventory) ~= "table" then
		return false, {}
	end

	local query = tostring(itemIdOrName or "")
	if query == "" then
		return false, {}
	end

	local toRemove = math.max(1, math.floor(tonumber(amount) or 1))
	local removed = {}

	for index = #inventory, 1, -1 do
		if toRemove <= 0 then
			break
		end

		local entry = inventory[index]
		if entry then
			local id = entry.id
			local name = entry.name
			if id == query or name == query then
				table.insert(removed, deepCopy(entry))
				table.remove(inventory, index)
				toRemove -= 1
			end
		end
	end

	return #removed > 0, removed
end

---------------------------------------------------

function DataManager.RecalculateStats(player)
	local profile = DataManager.Profiles[player]
	if not profile then
		return nil
	end

	local currentSlot = profile.Data and profile.Data.SelectedSlot
	if not currentSlot then
		return nil
	end

	local slotData = profile.Data[currentSlot]
	if not slotData then
		return nil
	end

	local charStats = slotData.CharStats or {}
	local charInfo = slotData.CharInfo or {}

	local totalStats = table.clone(BASE_STATS_DEFAULTS)
	for statName in pairs(totalStats) do
		local numeric = tonumber(charStats[statName])
		if numeric ~= nil then
			totalStats[statName] = numeric
		end
	end

	local legacyMaxStam = tonumber(charStats.MaxStam or charStats.MaxStamina)
	if legacyMaxStam ~= nil then
		totalStats.MaxEther = legacyMaxStam
	end

	local legacyStaminaBuff = tonumber(charStats.StaminaBuff)
	if legacyStaminaBuff ~= nil then
		totalStats.EtherBuff = legacyStaminaBuff
	end

	local function applyStatMap(statMap)
		if typeof(statMap) == "string" then
			statMap = DataManager.parseStatsString(statMap)
		end
		if typeof(statMap) ~= "table" then
			return
		end

		for rawName, rawBonus in pairs(statMap) do
			local statName = normalizeStatName(rawName)
			local numericBonus = tonumber(rawBonus)
			if statName ~= nil and numericBonus ~= nil then
				totalStats[statName] = (totalStats[statName] or 0) + numericBonus
			end
		end
	end

	local seen = {}
	local function collectEquipmentStats(node)
		if typeof(node) ~= "table" then
			return
		end
		if seen[node] then
			return
		end
		seen[node] = true

		if node.stats ~= nil then
			applyStatMap(node.stats)
		end

		for _, child in pairs(node) do
			if typeof(child) == "table" then
				collectEquipmentStats(child)
			end
		end
	end

	collectEquipmentStats(charInfo.Equipments)
	collectEquipmentStats(charInfo.Weapon)
	collectEquipmentStats(charInfo.Artefact)

	local derivedStats = {
		DamageReduction = math.clamp((totalStats.Fortitude or 0) * 0.01, 0, 0.5),
		StrengthMul = 1 + (totalStats.Strength or 0) / 100,
		SpeedMul = 1 + (totalStats.Agility or 0) / 100,
		IntelMul = 1 + (totalStats.Intelligence or 0) / 100,
		VitalityMul = 1 + (totalStats.Vitality or 0) / 100,
		WeaponMasteryMul = 1 + (totalStats.WeaponMastery or 0) / 100,
		LuckMul = 1 + ((totalStats.LuckBuff or 0) / 100),
	}

	local basePosture = tonumber(totalStats.MaxPosture) or BASE_STATS_DEFAULTS.MaxPosture
	local fortitude = tonumber(totalStats.Fortitude) or 0
	local weaponMastery = tonumber(totalStats.WeaponMastery) or 0
	local postureBonus = (fortitude * 0.35) + (weaponMastery * 0.2)
	totalStats.MaxPosture = math.max(1, math.floor(basePosture + postureBonus + 0.5))

	local attributesValues = {}
	for _, key in ipairs(ATTRIBUTE_KEYS) do
		attributesValues[key] = tonumber(totalStats[key]) or 0
	end
	local function ensureFolder(folderName: string): Folder
		local folder = player:FindFirstChild(folderName)
		if folder == nil or not folder:IsA("Folder") then
			if folder ~= nil then
				folder:Destroy()
			end
			folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = player
		end
		return folder
	end

	local function syncNumberValues(folder: Folder, values)
		for statName, value in pairs(values) do
			local numeric = tonumber(value)
			if numeric ~= nil then
				local stat = folder:FindFirstChild(statName)
				if not stat or not stat:IsA("NumberValue") then
					if stat then
						stat:Destroy()
					end
					stat = Instance.new("NumberValue")
					stat.Name = statName
					stat.Parent = folder
				end

				stat.Value = numeric
			end
		end
	end

	local function syncCurrentResource(
		folder: Folder,
		currentName: string,
		maxValue: number,
		defaultOnCreate: number?
	): number
		maxValue = math.max(0, tonumber(maxValue) or 0)

		local currentValue = folder:FindFirstChild(currentName)
		if currentValue ~= nil and not currentValue:IsA("NumberValue") then
			currentValue:Destroy()
			currentValue = nil
		end

		if currentValue == nil then
			local initialValue = tonumber(defaultOnCreate)
			if initialValue == nil then
				initialValue = maxValue
			end
			local created = Instance.new("NumberValue")
			created.Name = currentName
			created.Value = math.clamp(initialValue, 0, maxValue)
			created.Parent = folder
			return created.Value
		end

		currentValue.Value = math.clamp(currentValue.Value, 0, maxValue)
		return currentValue.Value
	end

	local attributesFolder = ensureFolder("Attributes")
	local statsFolder = ensureFolder("Stats")

	syncNumberValues(attributesFolder, attributesValues)
	syncNumberValues(statsFolder, derivedStats)
	attributesValues.Ether = syncCurrentResource(attributesFolder, "Ether", attributesValues.MaxEther, attributesValues.MaxEther)
	attributesValues.Posture = syncCurrentResource(attributesFolder, "Posture", attributesValues.MaxPosture, 0)

	local result = table.clone(attributesValues)
	for key, value in pairs(derivedStats) do
		result[key] = value
	end

	-- Keep MaxCapacity mirrored in Stats to remain compatible with existing UI scripts.
	local maxCapacityStat = statsFolder:FindFirstChild("MaxCapacity")
	if maxCapacityStat == nil or not maxCapacityStat:IsA("NumberValue") then
		if maxCapacityStat ~= nil then
			maxCapacityStat:Destroy()
		end
		maxCapacityStat = Instance.new("NumberValue")
		maxCapacityStat.Name = "MaxCapacity"
		maxCapacityStat.Parent = statsFolder
	end
	maxCapacityStat.Value = attributesValues.MaxCapacity

	return result
end

function DataManager.InitializeInfo(player: Player)
	local profile = DataManager.Profiles[player]
	if not profile then
		return
	end

	local CurrentSlot = profile.Data.SelectedSlot
	if not CurrentSlot then
		return
	end

	local EquipData = profile.Data[CurrentSlot].CharInfo
	if not EquipData then
		return
	end

	DataManager.RecalculateStats(player)
	--UpdateEquipmentUI:FireClient(player, slotsData)

	return true
end

---------------------------------------------------

---------------------------------------------------

return DataManager
