local ReplicatedStorage = game:GetService("ReplicatedStorage")

local libsRoot = script.Parent.Parent:WaitForChild("libs")
local InstanceUtil = require(libsRoot:WaitForChild("Common"):WaitForChild("InstanceUtil"))
local SkillEffectPlayer = require(libsRoot:WaitForChild("Vfx"):WaitForChild("SkillEffectPlayer"))
local SkillTemplateVfx = require(libsRoot:WaitForChild("Vfx"):WaitForChild("SkillTemplateVfx"))

local module = {}

function module.PlaySkillVfx(skillName: string, params: any, options: { [string]: any }?): (boolean, string, Instance?, Model?)
	return SkillEffectPlayer.PlaySkillEffect(ReplicatedStorage, skillName, params, options)
end

function module.PlaySkillTemplateVfx(
	skillName: string,
	params: any,
	templates: { [any]: { [string]: any } },
	options: { [string]: any }?
): boolean
	return SkillTemplateVfx.PlaySkillTemplates(ReplicatedStorage, skillName, params, templates, options)
end

function module.DestroyAfter(inst: Instance?, delaySeconds: number?)
	InstanceUtil.DestroyAfter(inst, delaySeconds)
end

return table.freeze(module)
