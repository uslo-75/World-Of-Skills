local VfxUtil = require(script.Parent:WaitForChild("VfxUtil"))

local module = {}

local TEMPLATES = {
	[1] = { template = "bams", weld = "StrikeWeldBams", effect = "StrikeBams" },
	[2] = { template = "cacas", weld = "StrikeWeldCacas", effect = "StrikeCacas" },
}

function module.Strikefall(params: any)
	VfxUtil.PlaySkillTemplateVfx("Strikefall", params, TEMPLATES, {
		defaultAction = "Emit",
		lifeTime = 5,
	})
end

return table.freeze(module)
