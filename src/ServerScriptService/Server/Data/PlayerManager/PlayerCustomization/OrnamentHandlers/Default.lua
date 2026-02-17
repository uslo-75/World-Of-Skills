local Utils = require(script.Parent.Utils)

local Default = {}

local function getRoot(assetsRoot, charData)
	return assetsRoot:FindFirstChild(charData.Civilizations or "")
end

function Default.Apply(context)
	local root = getRoot(context.assetsRoot, context.charData)
	local debugRace = tostring(context.charData.Civilizations)
	local asset = Utils.GetOrnamentAsset(root, "Ornament", context.ornamentIndex, debugRace)
	if not asset then
		return
	end

	for _, item in ipairs(asset:GetChildren()) do
		local clone = item:Clone()
		clone.Parent = context.char
		Utils.ApplyOrnamentColors(clone, context.ornamentColors)

		local weld = Utils.CreateWeld(clone, context.head)
		if not weld then
			warn(("Ornament '%s' sans BasePart attachable pour %s."):format(clone.Name, debugRace))
			clone:Destroy()
		end
	end
end

return Default
