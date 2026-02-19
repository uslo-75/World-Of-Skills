local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Server.Data.PlayerManager.DataManager)
local SessionUtils = require(ServerScriptService.Server.Data.PlayerManager.SessionUtils)
local PlayerCustomization = require(ServerScriptService.Server.Data.PlayerManager.PlayerCustomization)

local CmdrAdminUtil = {}

local CURRENCY_KEYS = {
	Rubi = true,
	ChronoCrystal = true,
}

local RACE_MAP = {
	solarians = "Solarians",
	lunarians = "Lunarians",
	sangivores = "Sangivores",
	pharaosiens = "Pharaosiens",
	varans = "Varans",
}

local VARANS_PATH_MAP = {
	bat = "Bat",
	cat = "Cat",
	fish = "Fish",
	bird = "Bird",
}

local CUSTOM_NUMBER_FIELDS = {
	variant = "RaceVariant",
	racevariant = "RaceVariant",
	ornament = "Ornament",
	facialmark = "FacialMark",
	mark = "FacialMark",
	face = "Face",
	skin = "Skin",
}

local function trim(value)
	if typeof(value) ~= "string" then
		return ""
	end
	return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function toWholeNumber(value)
	local n = tonumber(value)
	if n == nil then
		return nil
	end
	return math.floor(n)
end

local function isMissingClothing(value): boolean
	if typeof(value) ~= "string" then
		return true
	end

	local normalized = trim(value)
	if normalized == "" then
		return true
	end

	return string.lower(normalized) == "none"
end

local function isMissingHair(value): boolean
	if typeof(value) ~= "string" then
		return true
	end
	return trim(value) == ""
end

local function getCustomizationAssetRoot(charData)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local customCharacter = assets and assets:FindFirstChild("customcharacter")
	if not customCharacter then
		return nil
	end

	if charData.Civilizations == "Varans" and typeof(charData.VaransPath) == "string" and charData.VaransPath ~= "" then
		local varans = customCharacter:FindFirstChild("Varans")
		local subRace = varans and varans:FindFirstChild("SubRace")
		return subRace and subRace:FindFirstChild(charData.VaransPath)
	end

	if typeof(charData.Civilizations) ~= "string" or charData.Civilizations == "" then
		return nil
	end

	return customCharacter:FindFirstChild(charData.Civilizations)
end

local function ensureDefaultClothing(charData)
	local root = getCustomizationAssetRoot(charData)
	if not root then
		return
	end

	local shirt = root:FindFirstChild("Shirt")
	local pant = root:FindFirstChild("Pant")

	if isMissingClothing(charData.Shirt) and shirt and shirt:IsA("StringValue") and shirt.Value ~= "" then
		charData.Shirt = shirt.Value
	end

	if isMissingClothing(charData.Pant) and pant and pant:IsA("StringValue") and pant.Value ~= "" then
		charData.Pant = pant.Value
	end
end

local function ensureDefaultHair(player: Player, charData)
	if isMissingHair(charData.Hair) then
		local okDesc, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
		end)

		if okDesc and desc and typeof(desc.HairAccessory) == "string" and desc.HairAccessory ~= "" then
			charData.Hair = desc.HairAccessory
		else
			charData.Hair = "None"
		end
	end

	local hairValue = typeof(charData.Hair) == "string" and string.lower(trim(charData.Hair)) or "none"
	if hairValue == "none" then
		return
	end

	if type(charData.HairColor) == "table" and next(charData.HairColor) ~= nil then
		return
	end

	local variantIndex = tonumber(charData.RaceVariant) or 1
	variantIndex = math.max(1, math.floor(variantIndex))

	local root = getCustomizationAssetRoot(charData)
	local variantFolder = root and root:FindFirstChild("Variant")
	local variantEntry = variantFolder and variantFolder:FindFirstChild("Variant" .. tostring(variantIndex))
	local colorValue = variantEntry and variantEntry:FindFirstChild("Color")

	if colorValue and colorValue:IsA("Color3Value") then
		local c = colorValue.Value
		charData.HairColor = { r = c.R, g = c.G, b = c.B }
	else
		charData.HairColor = { r = 1, g = 1, b = 1 }
	end
end

local function getProfile(player: Player)
	local profile = DataManager.Profiles[player]
	if not profile or typeof(profile.Data) ~= "table" then
		return nil, "ProfileMissing"
	end
	return profile, nil
end

local function getSelectedSlotData(profile)
	local selected = tonumber(profile.Data.SelectedSlot) or 1
	selected = math.max(1, math.floor(selected))
	profile.Data.SelectedSlot = selected

	local slotData = profile.Data[selected]
	if typeof(slotData) ~= "table" then
		return nil, "SlotMissing"
	end

	if typeof(slotData.CharData) ~= "table" then
		slotData.CharData = {}
	end

	return slotData, nil
end

function CmdrAdminUtil.GetPlayers(arg): { Player }
	if typeof(arg) == "Instance" and arg:IsA("Player") then
		return { arg }
	end
	if typeof(arg) == "table" then
		local out = {}
		for _, value in ipairs(arg) do
			if typeof(value) == "Instance" and value:IsA("Player") then
				table.insert(out, value)
			end
		end
		return out
	end
	return {}
end

function CmdrAdminUtil.FormatSummary(actionLabel: string, changed: number, total: number, failed: { string }): string
	local message = ("%s: %d/%d joueur(s)."):format(actionLabel, changed, total)
	if #failed > 0 then
		message = message .. " Erreurs: " .. table.concat(failed, " | ")
	end
	return message
end

function CmdrAdminUtil.GetContext(player: Player)
	local profile, profileErr = getProfile(player)
	if not profile then
		return nil, profileErr
	end

	local slotData, slotErr = getSelectedSlotData(profile)
	if not slotData then
		return nil, slotErr
	end

	return {
		profile = profile,
		slotData = slotData,
		charData = slotData.CharData,
	}, nil
end

function CmdrAdminUtil.AdjustCurrency(player: Player, currencyKey: string, mode: string, amount)
	if CURRENCY_KEYS[currencyKey] ~= true then
		return false, "InvalidCurrency"
	end

	local whole = toWholeNumber(amount)
	if whole == nil then
		return false, "AmountInvalid"
	end
	if mode ~= "set" and whole < 0 then
		return false, "AmountMustBePositive"
	end

	local context, err = CmdrAdminUtil.GetContext(player)
	if not context then
		return false, err
	end

	local current = tonumber(context.charData[currencyKey]) or 0
	local newValue = current

	if mode == "add" then
		newValue = current + whole
	elseif mode == "remove" then
		newValue = current - whole
	elseif mode == "set" then
		newValue = whole
	else
		return false, "InvalidMode"
	end

	newValue = math.max(0, math.floor(newValue))
	context.charData[currencyKey] = newValue
	SessionUtils.setValue(player, currencyKey, newValue, "Instance")

	return true, newValue
end

function CmdrAdminUtil.NormalizeRaceName(rawRace: string): string?
	local key = string.lower(trim(rawRace))
	return RACE_MAP[key]
end

function CmdrAdminUtil.NormalizeVaransPath(rawPath: string?): string?
	if rawPath == nil then
		return nil
	end
	local key = string.lower(trim(rawPath))
	if key == "" then
		return nil
	end
	return VARANS_PATH_MAP[key]
end

function CmdrAdminUtil.SetRace(player: Player, rawRace: string, rawSubRace: string?, resetCustomization: boolean)
	local raceName = CmdrAdminUtil.NormalizeRaceName(rawRace)
	if not raceName then
		return false, "RaceInvalid (Solarians/Lunarians/Sangivores/Pharaosiens/Varans)"
	end

	local subRace = nil
	if raceName == "Varans" then
		if rawSubRace ~= nil and trim(rawSubRace) ~= "" then
			subRace = CmdrAdminUtil.NormalizeVaransPath(rawSubRace)
			if not subRace then
				return false, "VaransPathInvalid (Bat/Cat/Fish/Bird)"
			end
		end
	end

	local ok = DataManager.ChangeRace(player, raceName, subRace, resetCustomization == true)
	if not ok then
		return false, "ChangeRaceFailed"
	end

	local context, err = CmdrAdminUtil.GetContext(player)
	if not context then
		return false, err
	end

	ensureDefaultClothing(context.charData)
	ensureDefaultHair(player, context.charData)
	SessionUtils.setValue(player, "Civilizations", context.charData.Civilizations, "Instance")
	return true, context.charData.Civilizations
end

function CmdrAdminUtil.NormalizeAssetId(rawValue): (string?, string?)
	local text = trim(tostring(rawValue or ""))
	if text == "" then
		return nil, "AssetIdMissing"
	end

	local lower = string.lower(text)
	if lower == "none" then
		return "None", nil
	end

	local fromUrl = text:match("^rbxassetid://(%d+)$")
	if fromUrl then
		return fromUrl, nil
	end

	local digits = text:match("^(%d+)$")
	if digits then
		return digits, nil
	end

	return nil, "AssetIdInvalid"
end

function CmdrAdminUtil.SetClothing(player: Player, fieldName: string, rawAssetId)
	if fieldName ~= "Shirt" and fieldName ~= "Pant" then
		return false, "InvalidField"
	end

	local assetId, parseErr = CmdrAdminUtil.NormalizeAssetId(rawAssetId)
	if not assetId then
		return false, parseErr
	end

	local context, err = CmdrAdminUtil.GetContext(player)
	if not context then
		return false, err
	end

	context.charData[fieldName] = assetId
	return true, assetId
end

function CmdrAdminUtil.ResolveCustomNumberField(rawField: string): string?
	local key = string.lower(trim(rawField))
	return CUSTOM_NUMBER_FIELDS[key]
end

function CmdrAdminUtil.SetCustomNumber(player: Player, rawField: string, rawValue)
	local fieldName = CmdrAdminUtil.ResolveCustomNumberField(rawField)
	if not fieldName then
		return false, "FieldInvalid (variant/ornament/facialmark/face/skin)"
	end

	local value = toWholeNumber(rawValue)
	if value == nil or value < 1 then
		return false, "ValueMustBePositiveInteger"
	end

	local context, err = CmdrAdminUtil.GetContext(player)
	if not context then
		return false, err
	end

	context.charData[fieldName] = value
	if fieldName == "RaceVariant" then
		-- Ornament colors are variant-dependent; rebuild them on next apply.
		context.charData.OrnamentColors = nil
	end

	return true, fieldName, value
end

function CmdrAdminUtil.RefreshCustomization(player: Player)
	local context, err = CmdrAdminUtil.GetContext(player)
	if not context then
		return false, err
	end

	local character = player.Character
	if not character or character.Parent == nil then
		return false, "CharacterMissing"
	end

	PlayerCustomization.ApplyCustomization(player, context.profile, character)
	return true
end

function CmdrAdminUtil.GetPlayerLabel(player: Player): string
	return ("%s(%d)"):format(player.Name, player.UserId)
end

function CmdrAdminUtil.IsValidPlayerInstance(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
end

return CmdrAdminUtil
