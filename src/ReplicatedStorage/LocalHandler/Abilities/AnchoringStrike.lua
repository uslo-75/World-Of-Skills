local VfxUtil = require(script.Parent:WaitForChild("VfxUtil"))

local module = {}

local TEMPLATES = {
	[1] = { template = "aca", weld = "AnchoringWeldTp", effect = "AnchoringEmit" },
	[2] = { template = "windbeam", weld = "AnchoringWeldWind1", effect = "AnchoringWind1" },
	[3] = { template = "windonde", weld = "AnchoringWeldWind2", effect = "AnchoringWind2" },
}

function module.AnchoringStrike(params: any)
	VfxUtil.PlaySkillTemplateVfx("AnchoringStrike", params, TEMPLATES, {
		defaultAction = "Emit",
		lifeTime = 5,
	})
end

return table.freeze(module)
