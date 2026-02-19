local VfxUtil = require(script.Parent:WaitForChild("VfxUtil"))

local module = {}

local TEMPLATES = {
	[1] = { template = "tp", weld = "StrikeWeldTp", effect = "StrikeTP" },
	[2] = { template = "tp2", weld = "StrikeWeldCaTp2", effect = "StrikeTP2" },
	[3] = { template = "HitTP", weld = "StrikeWeldHitTP", effect = "StrikeHitTP" },
}

function module.RendStep(params: any)
	VfxUtil.PlaySkillTemplateVfx("RendStep", params, TEMPLATES, {
		defaultAction = "Emit",
		lifeTime = 5,
	})
end

return table.freeze(module)
