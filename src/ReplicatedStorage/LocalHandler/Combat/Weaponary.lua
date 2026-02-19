local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localHandler = ReplicatedStorage:WaitForChild("LocalHandler")
local libsRoot = localHandler:WaitForChild("libs")
local CharacterUtil = require(libsRoot:WaitForChild("Combat"):WaitForChild("CharacterUtil"))
local ModuleRunner = require(libsRoot:WaitForChild("Combat"):WaitForChild("ModuleRunner"))
local CombatFx = require(libsRoot:WaitForChild("Vfx"):WaitForChild("CombatFx"))

local module = {}
local activeHyperArmorByCharacter = setmetatable({}, { __mode = "k" })

local weaponsRoot: Folder? = nil
do
	local direct = script:FindFirstChild("Weapons")
	if direct and direct:IsA("Folder") then
		weaponsRoot = direct
	end

	if not weaponsRoot and script.Parent then
		local sibling = script.Parent:FindFirstChild("Weapons")
		if sibling and sibling:IsA("Folder") then
			weaponsRoot = sibling
		end
	end

	if not weaponsRoot then
		warn(("[Weaponary] Weapons folder missing near %s"):format(script:GetFullName()))
	end
end

local abilitiesRoot: Folder? = nil
do
	local abilities = localHandler:FindFirstChild("Abilities")
	if abilities and abilities:IsA("Folder") then
		abilitiesRoot = abilities
	end
end

local function resolveWeaponActionModule(character: Model, actionName: string): ModuleScript?
	if not weaponsRoot then
		return nil
	end

	for _, weaponName in ipairs(CharacterUtil.CollectWeaponNames(character)) do
		local folder = weaponsRoot:FindFirstChild(weaponName)
		if folder and folder:IsA("Folder") then
			local moduleScript = folder:FindFirstChild(actionName)
			if moduleScript and moduleScript:IsA("ModuleScript") then
				return moduleScript
			end
		end
	end

	local defaultFolder = weaponsRoot:FindFirstChild("Default")
	if not defaultFolder or not defaultFolder:IsA("Folder") then
		return nil
	end

	local defaultScript = defaultFolder:FindFirstChild(actionName)
	if not defaultScript or not defaultScript:IsA("ModuleScript") then
		return nil
	end

	return defaultScript
end

local function playWeaponAction(actionName: string, params: any)
	local character = CharacterUtil.ResolveCharacter(params)
	if not character then
		return
	end

	local moduleScript = resolveWeaponActionModule(character, actionName)
	if not moduleScript then
		return
	end

	ModuleRunner.RunModule(moduleScript, actionName, params, "Weaponary")
end

local function playAbilityAction(abilityName: string, params: any)
	if not abilitiesRoot then
		return
	end

	local moduleScript = abilitiesRoot:FindFirstChild(abilityName)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return
	end

	ModuleRunner.RunModule(moduleScript, abilityName, params, "Weaponary")
end

module.Hit = function(params)
	local character = CharacterUtil.ResolveCharacter(params)
	if not character then
		return
	end

	local combo = 1
	local targetType = nil

	if typeof(params) == "table" then
		combo = tonumber(params.combo or params.Combo) or combo
		targetType = params.targetType or params.TargetType

		local data = params[2]
		if typeof(data) == "table" then
			combo = tonumber(data[1]) or combo
			targetType = data[2] or targetType
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and combo ~= 4 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	if targetType == "Human" then
		CombatFx.PlayHumanHit(ReplicatedStorage, character, 5)
	end
end

module.ParryHit = function(params)
	CombatFx.PlayWeaponSpark(ReplicatedStorage, params, "PARRYPART")
end

module.BlockingHit = function(params)
	CombatFx.PlayWeaponSpark(ReplicatedStorage, params, "BLOCKPART")
end

module.iFramesSuccess = function(params)
	CombatFx.PlayDodge(ReplicatedStorage, params)
end

module.Indication = function(params)
	CombatFx.PlayIndication(ReplicatedStorage, params, nil)
end

module.RedIndication = function(params)
	CombatFx.PlayIndication(ReplicatedStorage, params, "red")
end

module.YellowIndication = function(params)
	CombatFx.PlayIndication(ReplicatedStorage, params, "yellow")
end

module.BlueIndication = function(params)
	CombatFx.PlayIndication(ReplicatedStorage, params, "blue")
end

module.SlowStunned = function(params)
	CombatFx.PlaySlowStunned(ReplicatedStorage, params, 3)
end

local function resolveHyperArmorData(params: any): (string, string, number)
	local action = "start"
	local armorType = "Resilient"
	local duration = 0

	if typeof(params) ~= "table" then
		return action, armorType, duration
	end

	local data = params[2]
	if typeof(data) ~= "table" then
		data = params
	end

	local rawAction = data.Action or data.action
	if typeof(rawAction) == "string" and rawAction ~= "" then
		action = string.lower(rawAction)
	end

	local rawType = data.Type or data.type
	if typeof(rawType) == "string" and rawType ~= "" then
		armorType = rawType
	end

	duration = tonumber(data.Duration or data.duration) or 0
	return action, armorType, duration
end

local function resolveHyperArmorColor(rawType: string): Color3
	local key = string.lower(rawType)
	if key == "invulnerable" or key == "fulliframe" or key == "iframe" then
		return Color3.fromRGB(141, 141, 141)
	end

	return Color3.fromRGB(255, 142, 67)
end

local function stopHyperArmorVisual(character: Model)
	local state = activeHyperArmorByCharacter[character]
	if not state then
		return
	end

	local highlight = state.highlight
	if highlight and highlight.Parent then
		local tween =
			TweenService:Create(highlight, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
		tween:Play()
		task.delay(0.18, function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end)
	end

	activeHyperArmorByCharacter[character] = nil
end

local function ensureHyperArmorHighlight(character: Model)
	local state = activeHyperArmorByCharacter[character]
	if state and state.highlight and state.highlight.Parent then
		return state.highlight, state
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "__HyperArmorHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	state = {
		highlight = highlight,
		token = 0,
	}
	activeHyperArmorByCharacter[character] = state
	return highlight, state
end

module.HyperArmor = function(params)
	local character = CharacterUtil.ResolveCharacter(params)
	if not character then
		return
	end

	local action, armorType, duration = resolveHyperArmorData(params)
	if action == "stop" or action == "disable" or action == "end" then
		stopHyperArmorVisual(character)
		return
	end

	local highlight, state = ensureHyperArmorHighlight(character)
	local color = resolveHyperArmorColor(armorType)

	highlight.FillColor = color
	highlight.OutlineColor = color:Lerp(Color3.fromRGB(255, 255, 255), 0.35)

	if action == "impact" then
		local flashIn = TweenService:Create(
			highlight,
			TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FillTransparency = 0.82, OutlineTransparency = 0.03 }
		)
		local flashOut = TweenService:Create(
			highlight,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FillTransparency = 0.92, OutlineTransparency = 0.08 }
		)
		flashIn:Play()
		flashIn.Completed:Connect(function()
			if highlight and highlight.Parent then
				flashOut:Play()
			end
		end)
		return
	end

	local fadeIn = TweenService:Create(
		highlight,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 0.92, OutlineTransparency = 0.08 }
	)
	fadeIn:Play()

	state.token += 1
	local token = state.token
	if duration > 0 then
		task.delay(duration + 0.05, function()
			local liveState = activeHyperArmorByCharacter[character]
			if not liveState or liveState.token ~= token then
				return
			end
			stopHyperArmorVisual(character)
		end)
	end
end

module.Critical = function(params: any)
	playWeaponAction("Critical", params)
end

module.Aerial = function(params: any)
	playWeaponAction("Aerial", params)
end

module.Running = function(params: any)
	playWeaponAction("Running", params)
end

module.Strikefall = function(params: any)
	playAbilityAction("Strikefall", params)
end

module.RendStep = function(params: any)
	playAbilityAction("RendStep", params)
end

module.AnchoringStrike = function(params: any)
	playAbilityAction("AnchoringStrike", params)
end

return module
