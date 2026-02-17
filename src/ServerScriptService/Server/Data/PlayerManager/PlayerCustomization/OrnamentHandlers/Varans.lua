local Utils = require(script.Parent.Utils)

local Varans = {}

local WELD_RULES_BY_SUBRACE = {
	Bat = {
		[1] = {
			OrnamentL = "head",
			OrnamentR = "head",
		},
	},
	Cat = {
		[1] = {
			OrnamentL = "head",
			OrnamentR = "head",
			OrnamentB = "back",
		},
	},
}

local function getVaransRoot(assetsRoot, charData)
	local varans = assetsRoot:FindFirstChild("Varans")
	local subRace = varans and varans:FindFirstChild("SubRace")
	if not subRace or not charData.VaransPath then
		return nil
	end

	return subRace:FindFirstChild(charData.VaransPath)
end

local function getPartFromTarget(char, head, target)
	if target == "head" then
		return head
	end
	if target == "left_arm" then
		return char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand") or char:FindFirstChild("LeftLowerArm")
	end

	if target == "right_arm" then
		return char:FindFirstChild("Right Arm")
			or char:FindFirstChild("RightHand")
			or char:FindFirstChild("RightLowerArm")
	end

	if target == "back" then
		return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	end

	return head
end

local function getTargetFromRule(rule, ornamentName)
	if not rule then
		return nil
	end

	if rule[ornamentName] then
		return rule[ornamentName]
	end

	local suffix = ornamentName:sub(-1)
	if suffix == "L" and rule.OrnamentL then
		return rule.OrnamentL
	end
	if suffix == "R" and rule.OrnamentR then
		return rule.OrnamentR
	end
	if suffix == "B" and rule.OrnamentB then
		return rule.OrnamentB
	end

	return rule.default
end

function Varans.Apply(context)
	local root = getVaransRoot(context.assetsRoot, context.charData)
	local debugRace = ("Varans/%s"):format(tostring(context.charData.VaransPath))
	local asset = Utils.GetOrnamentAsset(root, "Ornament", context.ornamentIndex, debugRace)
	if not asset then
		return
	end

	local subRaceRules = WELD_RULES_BY_SUBRACE[context.charData.VaransPath]
	local indexRule = subRaceRules and subRaceRules[context.ornamentIndex]

	for _, item in ipairs(asset:GetChildren()) do
		local clone = item:Clone()
		clone.Parent = context.char
		Utils.ApplyOrnamentColors(clone, context.ornamentColors)

		local target = getTargetFromRule(indexRule, clone.Name)
		local part0 = getPartFromTarget(context.char, context.head, target)
		local weld = Utils.CreateWeld(clone, part0)
		if not weld then
			warn(("Ornament '%s' sans BasePart attachable pour %s."):format(clone.Name, debugRace))
			clone:Destroy()
		end
	end
end

return Varans
