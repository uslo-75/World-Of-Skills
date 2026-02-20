local combatRoot = script:FindFirstAncestor("Combat")
if not combatRoot then
	error(("[CriticalPrewarm] Combat root not found from %s"):format(script:GetFullName()))
end

local SkillAnimUtil = require(
	combatRoot:WaitForChild("WeaponSpecials"):WaitForChild("Shared"):WaitForChild("SkillAnimUtil")
)

local SKILL_PREWARM_ANIMATION_CANDIDATES = table.freeze({
	table.freeze({ "MeleCharge" }),
	table.freeze({ "Strikefall" }),
	table.freeze({ "MeleHit" }),
	table.freeze({ "StrikefallCombo" }),
	table.freeze({ "MeleStartUp" }),
	table.freeze({ "RendStep" }),
	table.freeze({ "MeleStartUpMiss" }),
	table.freeze({ "RendStepMiss" }),
	table.freeze({ "MeleStartUpHit" }),
	table.freeze({ "RendStepHit" }),
	table.freeze({ "AnchoringStrike" }),
})

local module = {}
local skillAnimationCacheByAssetsRoot = setmetatable({}, { __mode = "k" }) -- [AssetsRoot] = { [string]: Animation | false }

local function addAnimationUnique(target: { Animation }, seen: { [Animation]: boolean }, animation: Animation?)
	if not animation then
		return
	end
	if seen[animation] then
		return
	end
	seen[animation] = true
	table.insert(target, animation)
end

local function resolveCachedSkillAnimation(service: any, candidates: { string }): Animation?
	local candidateKey = candidates[1]
	if typeof(candidateKey) ~= "string" or candidateKey == "" then
		return SkillAnimUtil.ResolveSkillAnimation(service, candidates)
	end

	local assetsRoot = service and service.AssetsRoot
	if not assetsRoot then
		return SkillAnimUtil.ResolveSkillAnimation(service, candidates)
	end

	local cache = skillAnimationCacheByAssetsRoot[assetsRoot]
	if not cache then
		cache = {}
		skillAnimationCacheByAssetsRoot[assetsRoot] = cache
	end

	local cached = cache[candidateKey]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		if cached and cached.Parent then
			return cached
		end
		cache[candidateKey] = nil
	end

	local resolved = SkillAnimUtil.ResolveSkillAnimation(service, candidates)
	cache[candidateKey] = resolved or false
	return resolved
end

function module.CollectAnimations(
	service: any,
	character: Model,
	equippedTool: Tool,
	actionDefsList: { [number]: { name: string } }
): { Animation }
	local animations = {}
	local seen: { [Animation]: boolean } = {}
	local comboForFallback = 4

	for _, actionDef in ipairs(actionDefsList) do
		local animation = service:ResolveActionAnimation(character, equippedTool.Name, actionDef.name, comboForFallback)
		addAnimationUnique(animations, seen, animation)
	end

	for _, candidates in ipairs(SKILL_PREWARM_ANIMATION_CANDIDATES) do
		addAnimationUnique(animations, seen, resolveCachedSkillAnimation(service, candidates))
	end

	return animations
end

function module.PrewarmTracks(animUtil: any, humanoid: Humanoid, animations: { Animation }, trackName: string)
	if not animUtil or typeof(animUtil.LoadTrack) ~= "function" then
		return
	end

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	for _, animation in ipairs(animations) do
		local ok, track = pcall(animUtil.LoadTrack, humanoid, animation, trackName)
		if ok and track then
			pcall(function()
				track:Stop(0)
			end)
			pcall(function()
				track:Destroy()
			end)
		end
	end
end

return table.freeze(module)
