local M1Anims = {}

local function getSwingAnimCandidates(combo: number): { string }
	return {
		("swing%d"):format(combo),
		("Swing%d"):format(combo),
		("m1_%d"):format(combo),
		("M1_%d"):format(combo),
	}
end

local function getHitAnimCandidates(index: number): { string }
	return {
		("hit%d"):format(index),
		("Hit%d"):format(index),
	}
end

local function getParryAnimCandidates(): { string }
	if math.random(1, 2) == 1 then
		return {
			"trueparry1",
			"TrueParry1",
			"trueparry2",
			"TrueParry2",
			"parry",
			"Parry",
			"perfectparry",
			"PerfectParry",
		}
	end

	return {
		"trueparry2",
		"TrueParry2",
		"trueparry1",
		"TrueParry1",
		"parry",
		"Parry",
		"perfectparry",
		"PerfectParry",
	}
end

local function getGuardBreakAnimCandidates(): { string }
	return {
		"guardbreak",
		"Guardbreak",
		"GuardBreak",
		"guardBreak",
	}
end

local function getCriticalAnimCandidates(): { string }
	return {
		"critical",
		"Critical",
		"heavy",
		"Heavy",
		"heavyattack",
		"HeavyAttack",
		"heavy_attack",
	}
end

local function getAerialAnimCandidates(): { string }
	return {
		"aerial",
		"Aerial",
		"air",
		"Air",
	}
end

local function getRunningAnimCandidates(): { string }
	return {
		"running",
		"Running",
		"runattack",
		"RunAttack",
	}
end

local function getActionAnimCandidates(actionName: string): { string }
	local key = string.lower(actionName)
	if key == "critical" then
		return getCriticalAnimCandidates()
	end
	if key == "aerial" then
		return getAerialAnimCandidates()
	end
	if key == "running" then
		return getRunningAnimCandidates()
	end

	return {}
end

local function getActionContainerCandidates(actionName: string): { string }
	local key = string.lower(actionName)
	if key == "critical" then
		return { "Attacking", "attacking", "Critical", "critical", "Heavy", "heavy" }
	end
	if key == "aerial" then
		return { "Attacking", "attacking", "Aerial", "aerial", "Air", "air" }
	end
	if key == "running" then
		return { "Attacking", "attacking", "Running", "running" }
	end

	return { "Attacking", "attacking" }
end

local function findAnimationIn(parent: Instance?, names: { string }): Animation?
	if not parent then
		return nil
	end

	for _, name in ipairs(names) do
		local anim = parent:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			return anim
		end
	end

	return nil
end

local function appendUnique(list: { string }, value: any)
	if typeof(value) ~= "string" or value == "" then
		return
	end

	for _, existing in ipairs(list) do
		if existing == value then
			return
		end
	end

	table.insert(list, value)
end

local function resolveCombatRoot(assetsRoot: Instance): Instance?
	local assets = assetsRoot:FindFirstChild("Assets")
	local animationRoot = assets and assets:FindFirstChild("animation")
	return animationRoot and animationRoot:FindFirstChild("combat")
end

local function collectWeaponFolderNames(character: Model, fallbackToolName: string?): { string }
	local names = {}
	appendUnique(names, fallbackToolName)
	appendUnique(names, character:GetAttribute("Weapon"))

	local selectedAttackTool: Tool? = nil
	local fallbackTool: Tool? = nil
	for _, child in ipairs(character:GetChildren()) do
		if not child:IsA("Tool") then
			continue
		end

		if not fallbackTool then
			fallbackTool = child
		end

		if child:GetAttribute("Type") == "Attack" and child:FindFirstChild("EquipedWeapon") ~= nil then
			selectedAttackTool = child
			break
		end
	end

	local tool = selectedAttackTool or fallbackTool
	if tool then
		appendUnique(names, tool.Name)
		appendUnique(names, tool:GetAttribute("Name"))
		appendUnique(names, tool:GetAttribute("Weapon"))
	end

	return names
end

local function resolveWeaponFolderForCharacter(
	assetsRoot: Instance,
	character: Model?,
	fallbackToolName: string?
): Folder?
	if not character then
		return nil
	end

	local combatRoot = resolveCombatRoot(assetsRoot)
	if not combatRoot then
		return nil
	end

	for _, folderName in ipairs(collectWeaponFolderNames(character, fallbackToolName)) do
		local folder = combatRoot:FindFirstChild(folderName)
		if folder and folder:IsA("Folder") then
			return folder
		end
	end

	return nil
end

local function findAnimationInContainers(
	weaponFolder: Folder?,
	containerNames: { string },
	animationNames: { string }
): Animation?
	if not weaponFolder then
		return nil
	end

	local direct = findAnimationIn(weaponFolder, animationNames)
	if direct then
		return direct
	end

	for _, containerName in ipairs(containerNames) do
		local container = weaponFolder:FindFirstChild(containerName)
		if not container then
			continue
		end

		if container:IsA("Animation") then
			for _, name in ipairs(animationNames) do
				if container.Name == name then
					return container
				end
			end
			continue
		end

		if container:IsA("Folder") then
			local inContainer = findAnimationIn(container, animationNames)
			if inContainer then
				return inContainer
			end

			for _, child in ipairs(container:GetChildren()) do
				if not child:IsA("Folder") then
					continue
				end

				local inNested = findAnimationIn(child, animationNames)
				if inNested then
					return inNested
				end
			end
		end
	end

	for _, descendant in ipairs(weaponFolder:GetDescendants()) do
		if descendant:IsA("Animation") then
			for _, name in ipairs(animationNames) do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end

	return nil
end

function M1Anims.ResolveWeaponAttackAnimation(assetsRoot: Instance, toolName: string, actionName: string): Animation?
	local combatRoot = resolveCombatRoot(assetsRoot)
	local toolFolder = combatRoot and combatRoot:FindFirstChild(toolName)
	if not toolFolder or not toolFolder:IsA("Folder") then
		return nil
	end

	local names = getActionAnimCandidates(actionName)
	if #names == 0 then
		return nil
	end

	return findAnimationInContainers(toolFolder, getActionContainerCandidates(actionName), names)
end

function M1Anims.ResolveSwingAnimation(assetsRoot: Instance, toolName: string, combo: number): Animation?
	local combatRoot = resolveCombatRoot(assetsRoot)
	local toolFolder = combatRoot and combatRoot:FindFirstChild(toolName)
	if not toolFolder or not toolFolder:IsA("Folder") then
		return nil
	end

	local names = getSwingAnimCandidates(combo)

	local attackingFolder = toolFolder:FindFirstChild("Attacking")
	if attackingFolder and attackingFolder:IsA("Folder") then
		local found = findAnimationIn(attackingFolder, names)
		if found then
			return found
		end
	end

	local direct = findAnimationIn(toolFolder, names)
	if direct then
		return direct
	end

	local fallbackNames = { "swing1", "Swing1", "m1_1", "M1_1" }
	if attackingFolder and attackingFolder:IsA("Folder") then
		local fallback = findAnimationIn(attackingFolder, fallbackNames)
		if fallback then
			return fallback
		end
	end

	return findAnimationIn(toolFolder, fallbackNames)
end

function M1Anims.ResolveHitReactionAnimation(assetsRoot: Instance, combo: number): Animation?
	local combatRoot = resolveCombatRoot(assetsRoot)
	if not combatRoot then
		return nil
	end

	-- Same behaviour as the old system: combo 2 and combo 4 use hit2, others use hit1.
	local hitIndex = (combo == 2 or combo == 4) and 2 or 1
	local names = getHitAnimCandidates(hitIndex)

	local direct = findAnimationIn(combatRoot, names)
	if direct then
		return direct
	end

	local hitFolder = combatRoot:FindFirstChild("Hit")
	if hitFolder and hitFolder:IsA("Folder") then
		return findAnimationIn(hitFolder, names)
	end

	return nil
end

function M1Anims.ResolveParryAnimation(assetsRoot: Instance, character: Model, fallbackToolName: string?): Animation?
	local toolFolder = resolveWeaponFolderForCharacter(assetsRoot, character, fallbackToolName)
	if not toolFolder then
		return nil
	end

	return findAnimationInContainers(
		toolFolder,
		{ "Blocking", "blocking", "Parrying", "parrying", "Parry", "parry", "Block", "block" },
		getParryAnimCandidates()
	)
end

function M1Anims.ResolveGuardBreakAnimation(assetsRoot: Instance, character: Model, fallbackToolName: string?): Animation?
	local toolFolder = resolveWeaponFolderForCharacter(assetsRoot, character, fallbackToolName)
	if not toolFolder then
		return nil
	end

	return findAnimationInContainers(
		toolFolder,
		{ "Blocking", "blocking", "Parrying", "parrying", "Parry", "parry", "Block", "block" },
		getGuardBreakAnimCandidates()
	)
end

function M1Anims.ResolveCriticalAnimation(assetsRoot: Instance, toolName: string): Animation?
	return M1Anims.ResolveWeaponAttackAnimation(assetsRoot, toolName, "Critical")
end

function M1Anims.StopTargetAnims(targetHumanoid: Humanoid, preserveLocomotion: boolean?)
	local animator = targetHumanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local keepLocomotion = preserveLocomotion ~= false

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local lowerName = string.lower(tostring(track.Name))
		if keepLocomotion and (string.find(lowerName, "idle", 1, true) or string.find(lowerName, "walk", 1, true)) then
			continue
		end

		pcall(function()
			track:Stop(0.03)
		end)
	end
end

function M1Anims.PlayHitReaction(animUtil: any, assetsRoot: Instance, targetHumanoid: Humanoid, combo: number)
	local animation = M1Anims.ResolveHitReactionAnimation(assetsRoot, combo)
	if not animation then
		return
	end

	M1Anims.StopTargetAnims(targetHumanoid)

	local track = animUtil.LoadTrack(targetHumanoid, animation, "M1HitReaction")
	if not track then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.03)
end

local function playOneShot(
	animUtil: any,
	humanoid: Humanoid?,
	animation: Animation?,
	trackName: string,
	priority: Enum.AnimationPriority?
)
	if not humanoid or not animation then
		return nil
	end

	local track = animUtil.LoadTrack(humanoid, animation, trackName)
	if not track then
		return nil
	end

	track.Priority = priority or Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.04)

	return track
end

function M1Anims.PlayParryExchange(
	animUtil: any,
	assetsRoot: Instance,
	attackerCharacter: Model,
	defenderCharacter: Model,
	attackerToolName: string?
)
	local attackerHumanoid = attackerCharacter:FindFirstChildOfClass("Humanoid")
	local defenderHumanoid = defenderCharacter:FindFirstChildOfClass("Humanoid")

	local attackerParryAnim = M1Anims.ResolveParryAnimation(assetsRoot, attackerCharacter, attackerToolName)
	local defenderParryAnim = M1Anims.ResolveParryAnimation(assetsRoot, defenderCharacter)

	if attackerHumanoid and attackerParryAnim then
		M1Anims.StopTargetAnims(attackerHumanoid, false)
		playOneShot(animUtil, attackerHumanoid, attackerParryAnim, "M1ParryAttacker", Enum.AnimationPriority.Action4)
	end

	if defenderHumanoid and defenderParryAnim then
		M1Anims.StopTargetAnims(defenderHumanoid, false)
		playOneShot(animUtil, defenderHumanoid, defenderParryAnim, "M1ParryDefender", Enum.AnimationPriority.Action4)
	end
end

function M1Anims.PlayGuardBreak(
	animUtil: any,
	assetsRoot: Instance,
	targetCharacter: Model,
	targetHumanoid: Humanoid,
	fallbackToolName: string?
)
	local guardBreakAnimation = M1Anims.ResolveGuardBreakAnimation(assetsRoot, targetCharacter, fallbackToolName)
	if not guardBreakAnimation then
		return
	end

	M1Anims.StopTargetAnims(targetHumanoid, false)
	playOneShot(animUtil, targetHumanoid, guardBreakAnimation, "M1GuardBreak", Enum.AnimationPriority.Action4)
end

return table.freeze(M1Anims)
