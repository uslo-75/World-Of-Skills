local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CarryService = {}
CarryService.__index = CarryService

local function setRagdoll(stateManager, targetCharacter, targetPlayer, enabled)
	if targetCharacter and targetCharacter.Parent then
		targetCharacter:SetAttribute("IsRagdoll", enabled)
	end
	if targetPlayer then
		stateManager.SetState(targetPlayer, "IsRagdoll", enabled)
	end
end

local function zeroVelocity(character)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.AssemblyLinearVelocity = Vector3.zero
			inst.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function clearExternalMotion(rootPart)
	for _, child in ipairs(rootPart:GetChildren()) do
		if
			child:IsA("LinearVelocity")
			or child:IsA("VectorForce")
			or child:IsA("AngularVelocity")
			or child:IsA("BodyVelocity")
			or child:IsA("BodyForce")
			or child:IsA("BodyGyro")
			or child:IsA("BodyPosition")
		then
			child:Destroy()
		end
	end
end

local function disableStates(config, humanoid)
	local prev = {}
	for _, st in ipairs(config.DisabledStates) do
		prev[st] = humanoid:GetStateEnabled(st)
		humanoid:SetStateEnabled(st, false)
	end
	return prev
end

local function restoreStates(humanoid, prev)
	for st, was in pairs(prev) do
		if typeof(was) == "boolean" then
			humanoid:SetStateEnabled(st, was)
		end
	end
end

local function setMasslessAndOwner(targetChar, ownerPlayer)
	local prevMassless = {}
	local owned = {}

	for _, inst in ipairs(targetChar:GetDescendants()) do
		if inst:IsA("BasePart") then
			prevMassless[inst] = inst.Massless
			inst.Massless = true
			owned[inst] = true
			pcall(function()
				inst:SetNetworkOwnershipAuto(false)
				inst:SetNetworkOwner(ownerPlayer)
			end)
		end
	end

	return prevMassless, owned
end

local function restoreMasslessAndOwner(prevMassless, owned)
	for part, was in pairs(prevMassless) do
		if part and part.Parent then
			part.Massless = was
		end
	end
	for part in pairs(owned) do
		if part and part.Parent then
			pcall(function()
				part:SetNetworkOwnershipAuto(true)
			end)
		end
	end
end

function CarryService.new(deps)
	local self = setmetatable({}, CarryService)

	self.Config = deps.Config
	self.PromptManager = deps.PromptManager
	self.Collision = deps.Collision
	self.StateManager =
		deps.StateManager or require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
	self.Replication = deps.Replication
	self.RigUtil = deps.RigUtil
	self.AnimUtil = deps.AnimUtil
	self.TargetLock = deps.TargetLock
	self.Maid = deps.Maid
	self.AssetsRoot = deps.AssetsRoot or RS

	self._active = {} -- [player] = { cancel=fn, carrierRoot=..., targetRoot=..., carriedAnimId=... }
	self._syncing = {} -- [player] = true

	return self
end

function CarryService:_carryAnim(name)
	return self.AnimUtil.FindCombatAnimation(self.AssetsRoot, self.Config.AnimFolder, name)
end

function CarryService:_sendVisualStart(carrierRoot, targetRoot, carriedAnimId)
	self.Replication:FireAllClients(
		"CarryVisual",
		"Start",
		carrierRoot,
		targetRoot,
		self.Config.CarryOffset,
		carriedAnimId
	)
end

function CarryService:_sendVisualStop(targetRoot)
	self.Replication:FireAllClients("CarryVisual", "Stop", targetRoot)
end

function CarryService:_waitReady(player)
	while player.Parent == Players do
		local loaded = CollectionService:HasTag(player, "Loaded")
		local char = player.Character
		local customizationLoaded = char and char:GetAttribute("CustomizationLoaded") == true
		if loaded and customizationLoaded then
			return true
		end
		task.wait(0.25)
	end
	return false
end

function CarryService:_syncVisualFor(player)
	for _, entry in pairs(self._active) do
		if entry and entry.carrierRoot and entry.targetRoot then
			self.Replication:FireClient(
				player,
				"CarryVisual",
				"Start",
				entry.carrierRoot,
				entry.targetRoot,
				self.Config.CarryOffset,
				entry.carriedAnimId
			)
		end
	end
end

function CarryService:_syncWhenReady(player)
	if self._syncing[player] then
		return
	end
	self._syncing[player] = true

	task.spawn(function()
		if self:_waitReady(player) then
			self:_syncVisualFor(player)
		end
		self._syncing[player] = nil
	end)
end

function CarryService:_start(player, prompt)
	local carrierChar, carrierHum, carrierRoot = self.RigUtil.GetRigFromPlayer(player)
	if not carrierChar or not carrierHum or not carrierRoot then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	local targetChar, targetHum, targetRoot = self.RigUtil.GetRigFromPrompt(prompt)
	if not targetChar or not targetHum or not targetRoot then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if targetChar == carrierChar then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	if targetHum.Health <= 0 then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if targetChar:GetAttribute("Downed") ~= true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if targetChar:GetAttribute("Carried") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if targetChar:GetAttribute("Gripped") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	if carrierChar:GetAttribute("Gripping") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if carrierChar:GetAttribute("Carrying") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	if not self.TargetLock.Acquire(targetChar, "Carry", player) then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	local maid = self.Maid.new()
	local cleaned = false

	local function cleanup(resetPrompt)
		if cleaned then
			return
		end
		cleaned = true

		if resetPrompt then
			self.PromptManager.ResetPromptState(prompt, player)
		end

		maid:DoCleaning()
	end

	local function cancel()
		cleanup(true)
	end

	self._active[player] = { cancel = cancel }

	maid:Give(function()
		self._active[player] = nil
		self._syncing[player] = nil
		self.TargetLock.Release(targetChar, "Carry", player)

		if carrierChar.Parent then
			carrierChar:SetAttribute("Carrying", false)
		end
		if targetChar.Parent then
			targetChar:SetAttribute("Carried", false)
		end
	end)

	carrierChar:SetAttribute("Carrying", true)

	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)

	local prevRagdoll = targetChar:GetAttribute("IsRagdoll") == true
	local prevAutoRotate = targetHum.AutoRotate
	local prevPlatformStand = targetHum.PlatformStand
	local prevGroup = self.Collision.GetGroup(targetChar)

	local prevStates = disableStates(self.Config, targetHum)
	local prevMassless, ownedParts = setMasslessAndOwner(targetChar, player)

	maid:Give(targetHum.Died:Connect(function()
		cleanup(false)
	end))
	maid:Give(carrierHum.Died:Connect(function()
		cleanup(false)
	end))
	maid:Give(carrierChar.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanup(false)
		end
	end))
	maid:Give(targetChar.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanup(false)
		end
	end))
	maid:Give(targetHum:GetPropertyChangedSignal("AutoRotate"):Connect(function()
		if targetHum.Parent and targetHum.AutoRotate ~= false then
			targetHum.AutoRotate = false
		end
	end))

	targetHum.AutoRotate = false
	targetHum.PlatformStand = true
	targetHum.Jump = false
	targetHum:Move(Vector3.zero)

	clearExternalMotion(targetRoot)
	zeroVelocity(targetChar)
	pcall(function()
		targetHum:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	setRagdoll(self.StateManager, targetChar, targetPlayer, false)
	self.Collision.SetNoPlayerCollision(targetChar)
	targetChar:SetAttribute("Carried", true)

	local carryTrack = self.AnimUtil.LoadTrack(carrierHum, self:_carryAnim("Carry"), "Carry")
	local carriedAnim = self:_carryAnim("Carried")
	local carriedTrack = self.AnimUtil.LoadTrack(targetHum, carriedAnim, "Carried")
	local carriedAnimId = carriedAnim and carriedAnim.AnimationId or nil

	maid:Give(function()
		if carryTrack and carryTrack.IsPlaying then
			pcall(function()
				carryTrack:Stop(0.1)
			end)
		end
		if carriedTrack and carriedTrack.IsPlaying then
			pcall(function()
				carriedTrack:Stop(0.1)
			end)
		end
	end)

	maid:Give(function()
		restoreMasslessAndOwner(prevMassless, ownedParts)

		if targetHum.Parent then
			restoreStates(targetHum, prevStates)
			local isDown = targetChar.Parent and targetChar:GetAttribute("Downed") == true
			targetHum.AutoRotate = isDown and false or prevAutoRotate
			targetHum.PlatformStand = prevPlatformStand
		end

		local isDown = targetChar.Parent and targetChar:GetAttribute("Downed") == true
		setRagdoll(self.StateManager, targetChar, targetPlayer, isDown or prevRagdoll)

		if isDown then
			self.Collision.SetNoPlayerCollision(targetChar)
		else
			self.Collision.SetGroup(targetChar, prevGroup)
		end

		self:_sendVisualStop(targetRoot)
	end)

	local attachCarrier = Instance.new("Attachment")
	attachCarrier.Name = "CarryAttachCarrier"
	attachCarrier.CFrame = self.Config.CarryOffset
	attachCarrier.Parent = carrierRoot
	maid:Give(attachCarrier)

	local attachTarget = Instance.new("Attachment")
	attachTarget.Name = "CarryAttachTarget"
	attachTarget.CFrame = CFrame.new()
	attachTarget.Parent = targetRoot
	maid:Give(attachTarget)

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "CarryAlignPosition"
	alignPos.Attachment0 = attachTarget
	alignPos.Attachment1 = attachCarrier
	alignPos.Responsiveness = self.Config.Align.Responsiveness
	alignPos.MaxForce = self.Config.Align.MaxForce
	alignPos.MaxVelocity = self.Config.Align.MaxVelocity
	alignPos.ApplyAtCenterOfMass = true
	alignPos.ReactionForceEnabled = false
	alignPos.RigidityEnabled = true
	alignPos.Parent = targetRoot
	maid:Give(alignPos)

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "CarryAlignOrientation"
	alignOri.Attachment0 = attachTarget
	alignOri.Attachment1 = attachCarrier
	alignOri.Responsiveness = self.Config.Align.Responsiveness
	alignOri.MaxTorque = self.Config.Align.MaxTorque
	alignOri.MaxAngularVelocity = self.Config.Align.MaxAngularVelocity
	alignOri.RigidityEnabled = true
	alignOri.Parent = targetRoot
	maid:Give(alignOri)

	if carriedTrack then
		carriedTrack:Play()
	end
	if carryTrack then
		carryTrack:Play()
	end

	self:_sendVisualStart(carrierRoot, targetRoot, carriedAnimId)

	self._active[player] = {
		cancel = cancel,
		carrierRoot = carrierRoot,
		targetRoot = targetRoot,
		carriedAnimId = carriedAnimId,
	}
end

function CarryService:Toggle(player, prompt)
	if not player then
		return
	end

	local entry = self._active[player]
	if entry and entry.cancel then
		entry.cancel()
		return
	end

	self:_start(player, prompt)
end

function CarryService:ForceStop(player)
	local entry = self._active[player]
	if entry and entry.cancel then
		entry.cancel()
		return true
	end
	return false
end

function CarryService:Init()
	Players.PlayerAdded:Connect(function(player)
		self:_syncWhenReady(player)
		player.CharacterAdded:Connect(function()
			self:_syncWhenReady(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:ForceStop(player)
		self._syncing[player] = nil
	end)
end

return CarryService
