local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterPlayer = game:GetService("StarterPlayer")

local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local StateKeys = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateKeys"))
local AnimsHandler = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local GlobalRelay = require(script.Parent:WaitForChild("GlobalRelay"))
local ActionsHelpers = require(script.Parent:WaitForChild("ActionsHelpers"))
local ActionsSlide = require(script:WaitForChild("Slide"))
local ActionsRunning = require(script:WaitForChild("Running"))
local ActionsDash = require(script:WaitForChild("Dash"))
local ActionsVault = require(script:WaitForChild("Vault"))
local ActionsClimbWall = require(script:WaitForChild("ClimbWall"))
local ActionsFall = require(script:WaitForChild("Fall"))
local ConnectionManager = require(script.Parent:WaitForChild("ConnectionManager"))
local LocalGlobal =
	require(RS:WaitForChild("LocalHandler"):WaitForChild("Misc"):WaitForChild("Visuals"):WaitForChild("Global"))

local Main = RS.Remotes:WaitForChild("Main")
local Replication = RS.Remotes:WaitForChild("Replication")
local MoveFolder = RS:WaitForChild("Assets"):WaitForChild("animation"):WaitForChild("move")

local module = {}

local camera = workspace.CurrentCamera
local Gravity_Force = -10
local sounds = script.Parent.Parent.Sounds

local function destroyAfter(inst: Instance?, delaySeconds: number?)
	if not inst then
		return
	end

	local t = tonumber(delaySeconds) or 0
	if t <= 0 then
		if inst.Parent then
			inst:Destroy()
		end
		return
	end

	task.delay(t, function()
		if inst and inst.Parent then
			inst:Destroy()
		end
	end)
end

local Global = GlobalRelay.Create(LocalGlobal, Replication)

local momentumVfxState = setmetatable({}, { __mode = "k" }) -- [Character] = bool
local function setMomentumVfx(char: Model, enabled: boolean)
	if momentumVfxState[char] == enabled then
		return
	end
	momentumVfxState[char] = enabled
	Global.MomentumSpeed({ char, enabled })
end

local fallData = setmetatable({}, { __mode = "k" }) -- [char] = {oldY, fallMag}
local landingLock = setmetatable({}, { __mode = "k" }) -- [char] = true/false

local runConnManager = ConnectionManager.new()

local function getDashRenderStepKey(plr: Player): string
	return "DashStep_" .. tostring(plr.UserId)
end

local function unbindDashRenderStep(plr: Player)
	RunService:UnbindFromRenderStep(getDashRenderStepKey(plr))
end

local slideConnManager = ConnectionManager.new()
local slideVelocity = setmetatable({}, { __mode = "k" }) -- [Player] = LinearVelocity
local slideAlign = setmetatable({}, { __mode = "k" }) -- [Player] = AlignOrientation
local slidePushLock = setmetatable({}, { __mode = "k" }) -- [Player] = true
local crouchConnManager = ConnectionManager.new()

local climbConnManager = ConnectionManager.new()
local wallRunConnManager = ConnectionManager.new()

local fallParams = RaycastParams.new()
fallParams.RespectCanCollide = true
fallParams.IgnoreWater = false
fallParams.FilterType = Enum.RaycastFilterType.Exclude

local vaultParams = RaycastParams.new()
vaultParams.FilterType = Enum.RaycastFilterType.Exclude
vaultParams.IgnoreWater = true

local slideParams = RaycastParams.new()
slideParams.FilterType = Enum.RaycastFilterType.Exclude
slideParams.IgnoreWater = true

local Helpers = ActionsHelpers.Create({
	Settings = Settings,
	StateManager = StateManager,
	AnimsHandler = AnimsHandler,
	MoveFolder = MoveFolder,
	StarterPlayer = StarterPlayer,
	fallData = fallData,
	fallParams = fallParams,
	vaultParams = vaultParams,
	destroyAfter = destroyAfter,
})

local anyState = Helpers.anyState
local isCarryOrGripBlocked = Helpers.isCarryOrGripBlocked
local isGripBlocked = Helpers.isGripBlocked
local canUse = Helpers.canUse
local canUseVault = Helpers.canUseVault
local playMoveAnim = Helpers.playMoveAnim
local refreshParams = Helpers.refreshParams
local lerp = Helpers.lerp
local createLinearVelocity = Helpers.createLinearVelocity
local createAlignOrientation = Helpers.createAlignOrientation
local getDashAnimIdFromDir = Helpers.getDashAnimIdFromDir
local getFallBucket = Helpers.getFallBucket
local rockDebris = Helpers.rockDebris
local restoreMovement = Helpers.restoreMovement
local spawnVaultTargetCF = Helpers.spawnVaultTargetCF
local vaultRayCheckForClimb = Helpers.vaultRayCheckForClimb

ActionsSlide.Bind(module, {
	script = script,
	StateManager = StateManager,
	Settings = Settings,
	RunService = RunService,
	StarterPlayer = StarterPlayer,
	AnimsHandler = AnimsHandler,
	Global = Global,
	destroyAfter = destroyAfter,
	isCarryOrGripBlocked = isCarryOrGripBlocked,
	createLinearVelocity = createLinearVelocity,
	createAlignOrientation = createAlignOrientation,
	playMoveAnim = playMoveAnim,
	slideParams = slideParams,
	slideConnManager = slideConnManager,
	slideVelocity = slideVelocity,
	slideAlign = slideAlign,
	slidePushLock = slidePushLock,
	crouchConnManager = crouchConnManager,
})

ActionsRunning.Bind(module, {
	StateManager = StateManager,
	Settings = Settings,
	RunService = RunService,
	Global = Global,
	camera = camera,
	runConnManager = runConnManager,
	landingLock = landingLock,
	isGripBlocked = isGripBlocked,
	setMomentumVfx = setMomentumVfx,
})

ActionsDash.Bind(module, {
	Settings = Settings,
	RunService = RunService,
	Main = Main,
	Global = Global,
	canUse = canUse,
	isCarryOrGripBlocked = isCarryOrGripBlocked,
	AnimsHandler = AnimsHandler,
	getDashAnimIdFromDir = getDashAnimIdFromDir,
	getDashRenderStepKey = getDashRenderStepKey,
	unbindDashRenderStep = unbindDashRenderStep,
	sounds = sounds,
	Gravity_Force = Gravity_Force,
})

ActionsVault.Bind(module, {
	StateManager = StateManager,
	MoveFolder = MoveFolder,
	TweenService = TweenService,
	canUseVault = canUseVault,
	isGripBlocked = isGripBlocked,
	anyState = anyState,
	refreshParams = refreshParams,
	spawnVaultTargetCF = spawnVaultTargetCF,
	AnimsHandler = AnimsHandler,
	vaultParams = vaultParams,
	sounds = sounds,
})

ActionsClimbWall.Bind(module, {
	StateManager = StateManager,
	Settings = Settings,
	RunService = RunService,
	Global = Global,
	sounds = sounds,
	AnimsHandler = AnimsHandler,
	createLinearVelocity = createLinearVelocity,
	createAlignOrientation = createAlignOrientation,
	playMoveAnim = playMoveAnim,
	refreshParams = refreshParams,
	vaultParams = vaultParams,
	vaultRayCheckForClimb = vaultRayCheckForClimb,
	lerp = lerp,
	isCarryOrGripBlocked = isCarryOrGripBlocked,
	isGripBlocked = isGripBlocked,
	climbConnManager = climbConnManager,
	wallRunConnManager = wallRunConnManager,
	destroyAfter = destroyAfter,
})

ActionsFall.Bind(module, {
	StateManager = StateManager,
	MoveFolder = MoveFolder,
	StarterPlayer = StarterPlayer,
	AnimsHandler = AnimsHandler,
	Global = Global,
	rockDebris = rockDebris,
	restoreMovement = restoreMovement,
	getFallBucket = getFallBucket,
	refreshParams = refreshParams,
	fallParams = fallParams,
	landingLock = landingLock,
})

local TRANSIENT_STATE_RESET = {
	StateKeys.Running,
	StateKeys.Dashing,
	StateKeys.Sliding,
	StateKeys.SlidePush,
	StateKeys.Crouching,
	StateKeys.Climbing,
	StateKeys.ClimbUp,
	StateKeys.ClimbDisengage,
	StateKeys.WallRunning,
	StateKeys.WallHopping,
	StateKeys.Vaulting,
	"Falling",
	"PlayClimb",
}

local function resetTransientStates(plr: Player)
	for _, key in ipairs(TRANSIENT_STATE_RESET) do
		StateManager.SetState(plr, key, false, 0, true)
	end
end

local function cleanupMovementRuntime(plr: Player, characterOverride: Model?)
	runConnManager:DisconnectAll()
	climbConnManager:DisconnectAll()
	wallRunConnManager:DisconnectAll()
	slideConnManager:DisconnectAll()
	crouchConnManager:DisconnectAll()

	module.CleanupSlideState(plr)
	unbindDashRenderStep(plr)
	resetTransientStates(plr)

	local char = characterOverride or plr.Character
	if char then
		AnimsHandler.StopAnims(char, "Slide")
		AnimsHandler.StopAnims(char, "Crouch")
		AnimsHandler.StopAnims(char, "WallRun")
		AnimsHandler.StopAnims(char, "Climb")
		AnimsHandler.StopAnims(char, "ClimbUp")
		AnimsHandler.StopAnims(char, "ClimbJumpOff")
		AnimsHandler.StopAnims(char, "Dashing")
		momentumVfxState[char] = false
	end

	Global.FOV({ nil, { 0.15, 70 } })
end

function module.SetPlayClimb(plr: Player, enabled: boolean, replicate: boolean?)
	StateManager.SetState(plr, "PlayClimb", enabled, 0, replicate == true)
end

function module.OnCharacterAdded(plr: Player)
	cleanupMovementRuntime(plr, plr.Character)
end

function module.OnCharacterRemoving(plr: Player, character: Model?)
	cleanupMovementRuntime(plr, character)
end

return module
