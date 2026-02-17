local Utils = require(script.Parent.Utils)

local Solarians = {}

local function getArm(char, clone)
	if clone.Name == "OrnamentL" then
		return char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand")
	end

	return char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
end

local function getPart0ForVariant(context, clone)
	local index = context.ornamentIndex

	if index == 1 then
		return context.head, true
	end

	if index == 2 then
		return getArm(context.char, clone) or context.head, true
	end

	if index == 3 then
		return context.char:FindFirstChild("Torso") or context.char:FindFirstChild("UpperTorso") or context.head, false
	end

	return context.head, false
end

function Solarians.Apply(context)
	local root = context.assetsRoot:FindFirstChild("Solarians")
	local asset = Utils.GetOrnamentAsset(root, "Ornament", context.ornamentIndex, "Solarians")
	if not asset then
		return
	end

	for _, item in ipairs(asset:GetChildren()) do
		local clone = item:Clone()
		clone.Parent = context.char
		Utils.ApplyOrnamentColors(clone, context.ornamentColors)

		local part0, shouldSpin = getPart0ForVariant(context, clone)
		local weld = Utils.CreateWeld(clone, part0)
		if not weld then
			warn(("Ornament '%s' sans BasePart attachable pour Solarians."):format(clone.Name))
			clone:Destroy()
		elseif shouldSpin then
			Utils.StartSpin(clone, weld)
		end
	end
end

return Solarians
