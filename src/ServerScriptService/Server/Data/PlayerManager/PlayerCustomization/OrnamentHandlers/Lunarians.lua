local Utils = require(script.Parent.Utils)

local Lunarians = {}

function Lunarians.Apply(context)
	local root = context.assetsRoot:FindFirstChild("Lunarians")
	local asset = Utils.GetOrnamentAsset(root, "Ornament", context.ornamentIndex, "Lunarians")
	if not asset then
		return
	end

	for _, item in ipairs(asset:GetChildren()) do
		local clone = item:Clone()
		clone.Parent = context.char
		Utils.ApplyOrnamentColors(clone, context.ornamentColors)

		local weld = Utils.CreateWeld(clone, context.head)
		if not weld then
			warn(("Ornament '%s' sans BasePart attachable pour Lunarians."):format(clone.Name))
			clone:Destroy()
		end
	end
end

return Lunarians
