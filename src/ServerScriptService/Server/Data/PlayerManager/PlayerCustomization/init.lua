local PlayerCustomization = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local OrnamentHandlers = require(script:WaitForChild("OrnamentHandlers"))

local MANAGED_ATTR = "CustomizationManaged"
local APPLY_NONCE_ATTR = "CustomizationApplyNonce"

local function hasOrnamentColors(value)
	return type(value) == "table" and next(value) ~= nil
end

local function toColorTable(color3)
	return {
		r = color3.R,
		g = color3.G,
		b = color3.B,
	}
end

local function getCustomizationRoot(assetsRoot, charData, civilization)
	if charData.Civilizations == "Varans" and charData.VaransPath ~= nil then
		local varans = assetsRoot:FindFirstChild("Varans")
		local subRace = varans and varans:FindFirstChild("SubRace")
		return subRace and subRace:FindFirstChild(charData.VaransPath)
	end

	return assetsRoot:FindFirstChild(civilization)
end

local function buildOrnamentColorsFromVariant(assetsRoot, charData, civilization)
	local root = getCustomizationRoot(assetsRoot, charData, civilization)
	if not root then
		return nil
	end

	local variantRoot = root:FindFirstChild("Variant")
	local variantIndex = charData.RaceVariant or 1
	local variant = variantRoot and variantRoot:FindFirstChild("Variant" .. tostring(variantIndex))
	if not variant then
		return nil
	end

	local colors = {}
	for _, item in ipairs(variant:GetChildren()) do
		if item:IsA("Color3Value") and string.match(item.Name, "^Order%d+$") then
			colors[item.Name] = toColorTable(item.Value)
		end
	end

	if next(colors) == nil then
		return nil
	end

	return colors
end

local function ensureOrnamentColors(assetsRoot, charData, civilization)
	if hasOrnamentColors(charData.OrnamentColors) then
		return
	end

	charData.OrnamentColors = buildOrnamentColorsFromVariant(assetsRoot, charData, civilization)
end

local function markManagedTree(instance)
	if not instance then
		return
	end

	instance:SetAttribute(MANAGED_ATTR, true)
	for _, descendant in ipairs(instance:GetDescendants()) do
		descendant:SetAttribute(MANAGED_ATTR, true)
	end
end

local function clearManagedAppearance(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") then
			child:Destroy()
		elseif child:IsA("BodyColors") then
			child:Destroy()
		elseif child:IsA("CharacterMesh") then
			child:Destroy()
		elseif child:GetAttribute(MANAGED_ATTR) == true then
			child:Destroy()
		elseif string.match(child.Name, "^Ornament") then
			child:Destroy()
		end
	end
end

-- Apply customization with profile passed directly
function PlayerCustomization.ApplyCustomization(player, profile, characterOverride)
	local char = characterOverride or player.Character
	if not char then
		return
	end

	local CurrentSlot = profile.Data.SelectedSlot
	local charData = profile.Data[CurrentSlot].CharData
	local hairId = charData.Hair or "None"
	local hairColors = charData.HairColor or { r = 1, g = 1, b = 1 }
	local shirtId = charData.Shirt or ""
	local pantId = charData.Pant or ""
	local civilization = charData.Civilizations or "Default"
	local head = char:FindFirstChild("Head")
	local OverHead = char:FindFirstChild("OverHead")
	local applyNonce = (tonumber(char:GetAttribute(APPLY_NONCE_ATTR)) or 0) + 1

	char:SetAttribute(APPLY_NONCE_ATTR, applyNonce)
	char:SetAttribute("CustomizationLoaded", false)
	clearManagedAppearance(char)

	local function isApplyCurrent()
		return char.Parent ~= nil and char:GetAttribute(APPLY_NONCE_ATTR) == applyNonce
	end

	-- Cleanup old mesh/decals
	if head and OverHead then
		if head:FindFirstChild("Mesh") then
			head.Mesh:Destroy()
		end
		if OverHead:FindFirstChild("Mesh") then
			OverHead.Mesh:Destroy()
		end
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		for _, d in ipairs(OverHead:GetChildren()) do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		local headMesh = script.Mesh:Clone()
		headMesh.Parent = head
		markManagedTree(headMesh)

		local overHeadMesh = script.Mesh:Clone()
		overHeadMesh.Parent = OverHead
		markManagedTree(overHeadMesh)
	end

	task.spawn(function()
		local ok, err = xpcall(function()
			if not isApplyCurrent() then
				return
			end

			-- Hair
			if hairId ~= "None" then
				for _, idStr in ipairs(string.split(hairId, ",")) do
					if not isApplyCurrent() then
						return
					end

					local loaded, model = pcall(InsertService.LoadAsset, InsertService, tonumber(idStr))
					if loaded and model then
						local acc = model:FindFirstChildOfClass("Accessory")
						if acc and acc.Handle then
							local mesh = acc.Handle:FindFirstChildWhichIsA("SpecialMesh")
								or acc.Handle:FindFirstChildWhichIsA("Mesh")
							if mesh then
								mesh.VertexColor = Vector3.new(hairColors.r, hairColors.g, hairColors.b)
								mesh.TextureId = "rbxassetid://2599831937"
							end
							acc.Parent = char
							markManagedTree(acc)
						end
						model:Destroy()
					end
					task.wait(0.1)
				end
			end

			-- Clothing
			if shirtId ~= "" then
				local shirt = char:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", char)
				shirt.ShirtTemplate = "rbxassetid://" .. shirtId
				shirt:SetAttribute(MANAGED_ATTR, true)
			end
			if pantId ~= "" then
				local pants = char:FindFirstChildOfClass("Pants") or Instance.new("Pants", char)
				pants.PantsTemplate = "rbxassetid://" .. pantId
				pants:SetAttribute(MANAGED_ATTR, true)
			end

			-- Face/Mark/Skin assets
			local function applyAssets(assetType, index, parent)
				if not isApplyCurrent() then
					return
				end

				local root = getCustomizationRoot(ReplicatedStorage.Assets.customcharacter, charData, civilization)
				if not root then
					return
				end

				local folder = root:FindFirstChild(assetType)
				local variantRoot = root:FindFirstChild("Variant")
				if not folder then
					return
				end

				local asset = folder:FindFirstChild(assetType .. index)
				local variant = variantRoot and variantRoot:FindFirstChild("Variant" .. index)
				if not asset then
					return
				end

				for _, item in ipairs(asset:GetChildren()) do
					local clone = item:Clone()
					clone.Parent = parent
					markManagedTree(clone)

					if assetType == "Eye" then
						local c = variant and variant:FindFirstChild("EyeColor")
						if c then
							clone.Color3 = c.Value
						end
					elseif assetType == "Mouth" then
						local m = variant and variant:FindFirstChild("MouthColor")
						if m then
							clone.Color3 = m.Value
						end
					elseif assetType == "Face" then
						local f = variant and variant:FindFirstChild("FaceColor")
						if f then
							clone.Color3 = f.Value
						end
					end
				end
			end

			if head and OverHead then
				applyAssets("Mark", charData.FacialMark, OverHead)
				applyAssets("Face", charData.Face, OverHead)
			end
			applyAssets("Skin", charData.Skin, char)

			if head and OverHead then
				OverHead.Color = head.Color
			end

			-- Ornament
			if isApplyCurrent() then
				PlayerCustomization.ApplyOrnament(player, profile, char)
			end
		end, debug.traceback)

		if not ok then
			warn(("[PlayerCustomization] ApplyCustomization failed for %s: %s"):format(player.Name, tostring(err)))
		end

		if isApplyCurrent() then
			char:SetAttribute("CustomizationLoaded", true)
		end
	end)
end

function PlayerCustomization.ApplyOrnament(player, profile, characterOverride)
	local char = characterOverride or player.Character
	if not char then
		return
	end

	for _, child in ipairs(char:GetChildren()) do
		if string.match(child.Name, "^Ornament") then
			child:Destroy()
		end
	end

	local head = char:WaitForChild("Head", 2)
	if not head then
		return
	end

	local CurrentSlot = profile.Data.SelectedSlot
	if not CurrentSlot then
		return
	end

	local charData = profile.Data[CurrentSlot].CharData
	local ornamentValue = charData.Ornament or 1
	local civilization = charData.Civilizations or "Default"
	local assetsRoot = ReplicatedStorage.Assets.customcharacter

	ensureOrnamentColors(assetsRoot, charData, civilization)

	local handler = OrnamentHandlers.GetForRace(civilization)
	if not handler or type(handler.Apply) ~= "function" then
		warn(("Handler ornament invalide pour la race '%s'."):format(tostring(civilization)))
		return
	end

	handler.Apply({
		char = char,
		head = head,
		charData = charData,
		ornamentIndex = ornamentValue,
		ornamentColors = charData.OrnamentColors,
		assetsRoot = assetsRoot,
	})

	for _, child in ipairs(char:GetChildren()) do
		if string.match(child.Name, "^Ornament") then
			markManagedTree(child)
		end
	end
end

return PlayerCustomization
