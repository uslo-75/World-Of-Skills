local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local PromptManager = require(script.Parent:WaitForChild("PromptManager"))
local Collision = require(script.Parent:WaitForChild("CollisionGroupHandler"))

local Maid = require(script.Parent.Parent.Shared:WaitForChild("Maid"))
local RigUtil = require(script.Parent.Parent.Shared:WaitForChild("RigUtil"))
local AnimUtil = require(script.Parent.Parent.Shared:WaitForChild("AnimUtil"))
local SoundUtil = require(script.Parent.Parent.Shared:WaitForChild("SoundUtil"))
local TargetLock = require(script.Parent.Parent.Shared:WaitForChild("TargetLock"))

local DownConfig = require(script.Down:WaitForChild("DownConfig"))
local DownPrompts = require(script.Down:WaitForChild("DownPrompts"))
local DownService = require(script.Down:WaitForChild("DownService"))

local GripConfig = require(script.Grip:WaitForChild("GripConfig"))
local GripService = require(script.Grip:WaitForChild("GripService"))

local CarryConfig = require(script.Carry:WaitForChild("CarryConfig"))
local CarryService = require(script.Carry:WaitForChild("CarryService"))
local M1Config = require(script.M1:WaitForChild("M1Config"))
local M1Service = require(script.M1:WaitForChild("M1Service"))
local BlockConfig = require(script.Block:WaitForChild("BlockConfig"))
local BlockService = require(script.Block:WaitForChild("BlockService"))
local HyperArmorService = require(script:WaitForChild("Shared"):WaitForChild("HyperArmorService"))
local criticalServiceRoot = script.WeaponSpecials:WaitForChild("CriticalService")
local criticalServiceModule = criticalServiceRoot
local nestedInit = criticalServiceRoot:FindFirstChild("init")
if nestedInit and nestedInit:IsA("ModuleScript") then
	criticalServiceModule = nestedInit
end
local CriticalService = require(criticalServiceModule)
local CombatReplication = require(script:WaitForChild("Shared"):WaitForChild("CombatReplication"))

local Replication = RS:WaitForChild("Remotes"):WaitForChild("Replication")
local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
local weaponInfoRoot = SS:WaitForChild("Info"):WaitForChild("WeaponInfo")
local weaponInfoModule = weaponInfoRoot
local weaponInfoInit = weaponInfoRoot:FindFirstChild("init")
if weaponInfoInit and weaponInfoInit:IsA("ModuleScript") then
	weaponInfoModule = weaponInfoInit
end
local WeaponInfo = require(weaponInfoModule)

local hyperArmorService = HyperArmorService.new({
	Replication = Replication,
	CombatReplication = CombatReplication,
	Settings = {
		VfxReplicationRadius = M1Config.VfxReplicationRadius,
		DefaultResilientMultiplier = 0.45,
		DefaultInvulnerableDuration = 1.1,
		DefaultResilientDuration = 0.7,
	},
})

local api = {}
api.HyperArmor = hyperArmorService

api.Down = DownService.new({
	Config = DownConfig,
	PromptManager = PromptManager,
	Collision = Collision,
	StateManager = StateManager,
	RigUtil = RigUtil,
	DownPrompts = DownPrompts,
})

api.Grip = GripService.new({
	Config = GripConfig,
	PromptManager = PromptManager,
	Collision = Collision,
	StateManager = StateManager,
	Replication = Replication,
	RigUtil = RigUtil,
	AnimUtil = AnimUtil,
	SoundUtil = SoundUtil,
	TargetLock = TargetLock,
	Maid = Maid,
	AssetsRoot = RS,
	CombatReplication = CombatReplication,
})

api.Carry = CarryService.new({
	Config = CarryConfig,
	PromptManager = PromptManager,
	Collision = Collision,
	StateManager = StateManager,
	Replication = Replication,
	RigUtil = RigUtil,
	AnimUtil = AnimUtil,
	TargetLock = TargetLock,
	Maid = Maid,
	AssetsRoot = RS,
	CombatReplication = CombatReplication,
})

api.Block = BlockService.new({
	Config = BlockConfig,
	StateManager = StateManager,
})

api.M1 = M1Service.new({
	Config = M1Config,
	StateManager = StateManager,
	AnimUtil = AnimUtil,
	SoundUtil = SoundUtil,
	Replication = Replication,
	AssetsRoot = RS,
	WeaponInfo = WeaponInfo,
	HitboxModule = require(SS:WaitForChild("Module"):WaitForChild("RenderedHitboxs")),
	CombatReplication = CombatReplication,
	DefenseService = api.Block,
	HyperArmorService = hyperArmorService,
})

api.Critical = CriticalService.new({
	StateManager = StateManager,
	AnimUtil = AnimUtil,
	SoundUtil = SoundUtil,
	AssetsRoot = RS,
	WeaponsRoot = script.WeaponSpecials:FindFirstChild("Weapons"),
	SkillsRoot = script.WeaponSpecials:FindFirstChild("Skills"),
	WeaponInfo = WeaponInfo,
	HitboxModule = require(SS:WaitForChild("Module"):WaitForChild("RenderedHitboxs")),
	CombatHandler = api.M1:GetCombatHandler(),
	HyperArmorService = hyperArmorService,
})

if typeof(api.M1.SetWeaponSpecialService) == "function" then
	api.M1:SetWeaponSpecialService(api.Critical)
end

api.Down:Init()
api.Grip:Init()
api.Carry:Init()
api.Block:Init()
api.M1:Init()
api.Critical:Init()

return api
