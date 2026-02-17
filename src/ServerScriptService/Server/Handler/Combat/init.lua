local RS = game:GetService("ReplicatedStorage")

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

local Replication = RS:WaitForChild("Remotes"):WaitForChild("Replication")
local StateManager = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))

local api = {}

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
})

api.Down:Init()
api.Grip:Init()
api.Carry:Init()

return api
