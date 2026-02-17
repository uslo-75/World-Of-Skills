local Utils = require(script.Parent.Utils)

local Sangivores = {}

function Sangivores.Apply(context)
	local root = context.assetsRoot:FindFirstChild("Sangivores")
	local asset = Utils.GetOrnamentAsset(root, "Ornament", context.ornamentIndex, "Sangivores")
	if not asset then
		return
	end

	for _, item in ipairs(asset:GetChildren()) do
		local clone = item:Clone()
		clone.Parent = context.char
		Utils.ApplyOrnamentColors(clone, context.ornamentColors)

		local weld = Utils.CreateWeld(clone, context.head)
		if not weld then
			warn(("Ornament '%s' sans BasePart attachable pour Sangivores."):format(clone.Name))
			clone:Destroy()
		end
	end
end

return Sangivores
