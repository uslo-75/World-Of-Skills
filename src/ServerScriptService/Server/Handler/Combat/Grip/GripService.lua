local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GripService = {}
GripService.__index = GripService

local function getWeaponName(character)
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local weaponAttr = tool:GetAttribute("Weapon")
	if typeof(weaponAttr) == "string" and weaponAttr ~= "" then
		return weaponAttr
	end

	return tool.Name
end

local function removeDownPrompts(rigUtil, config, targetCharacter)
	local parent = rigUtil.GetPromptParent(targetCharacter)
	if not parent then
		return
	end

	for _, name in ipairs(config.PromptNamesToRemove) do
		local p = parent:FindFirstChild(name)
		if p and p:IsA("ProximityPrompt") then
			p:Destroy()
		end
	end
end

local function setRagdoll(stateManager, targetCharacter, targetPlayer, enabled)
	if targetCharacter and targetCharacter.Parent then
		targetCharacter:SetAttribute("IsRagdoll", enabled)
	end
	if targetPlayer then
		stateManager.SetState(targetPlayer, "IsRagdoll", enabled)
	end
end

function GripService.new(deps)
	local self = setmetatable({}, GripService)

	self.Config = deps.Config
	self.PromptManager = deps.PromptManager
	self.Collision = deps.Collision
	self.StateManager = deps.StateManager
		or require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager"))
	self.Replication = deps.Replication
	self.RigUtil = deps.RigUtil
	self.AnimUtil = deps.AnimUtil
	self.SoundUtil = deps.SoundUtil
	self.TargetLock = deps.TargetLock
	self.Maid = deps.Maid
	self.AssetsRoot = deps.AssetsRoot or RS

	self._active = {} -- [player] = { cancel = fn }
	return self
end

function GripService:_start(player, prompt)
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

	if carrierChar:GetAttribute("Carrying") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end
	if carrierChar:GetAttribute("Gripping") == true then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	if not self.TargetLock.Acquire(targetChar, "Grip", player) then
		self.PromptManager.ResetPromptState(prompt, player)
		return
	end

	carrierChar:SetAttribute("Gripping", true)
	targetChar:SetAttribute("Gripped", true)

	local maid = self.Maid.new()
	local cancelled = false

	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
	local prevCarrierAutoRotate = carrierHum.AutoRotate
	local prevCarrierGroup = self.Collision.GetGroup(carrierChar)

	local prevTargetRagdoll = targetChar:GetAttribute("IsRagdoll") == true
	local prevTargetAnchored = targetRoot.Anchored

	local function cancel()
		if cancelled then
			return
		end
		cancelled = true
		self.PromptManager.ResetPromptState(prompt, player)
		maid:DoCleaning()
	end

	self._active[player] = { cancel = cancel }

	maid:Give(function()
		self._active[player] = nil
		if carrierChar.Parent then
			carrierChar:SetAttribute("Gripping", false)
		end
		if targetChar.Parent then
			targetChar:SetAttribute("Gripped", false)
		end
		self.TargetLock.Release(targetChar, "Grip", player)
	end)

	maid:Give(carrierHum.Died:Connect(function()
		maid:DoCleaning()
	end))
	maid:Give(targetHum.Died:Connect(function()
		maid:DoCleaning()
		removeDownPrompts(self.RigUtil, self.Config, targetChar)
	end))
	maid:Give(carrierChar.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			maid:DoCleaning()
		end
	end))
	maid:Give(targetChar.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			maid:DoCleaning()
		end
	end))

	carrierHum.AutoRotate = false
	self.Collision.SetNoPlayerCollision(carrierChar)
	setRagdoll(self.StateManager, targetChar, targetPlayer, false)

	maid:Give(function()
		if targetRoot.Parent then
			targetRoot.Anchored = prevTargetAnchored
		end
		if carrierHum.Parent then
			carrierHum.AutoRotate = prevCarrierAutoRotate
		end
		self.Collision.SetGroup(carrierChar, prevCarrierGroup)

		local isDown = targetChar.Parent and targetChar:GetAttribute("Downed") == true
		setRagdoll(self.StateManager, targetChar, targetPlayer, isDown or prevTargetRagdoll)
	end)

	targetRoot.Anchored = true

	local folderName = getWeaponName(carrierChar) or self.Config.DefaultAnimFolder
	local gripAnim = self.AnimUtil.FindCombatAnimation(self.AssetsRoot, folderName, "Grip")
	local groundAnim = self.AnimUtil.FindCombatAnimation(self.AssetsRoot, folderName, "Ground")

	local gripTrack = self.AnimUtil.LoadTrack(carrierHum, gripAnim, "Grip")
	local groundTrack = self.AnimUtil.LoadTrack(targetHum, groundAnim, "Ground")

	maid:Give(function()
		cancelled = true
		if gripTrack and gripTrack.IsPlaying then
			pcall(function()
				gripTrack:Stop(0.1)
			end)
		end
		if groundTrack and groundTrack.IsPlaying then
			pcall(function()
				groundTrack:Stop(0.1)
			end)
		end
	end)

	local desiredOffset = self.Config.Offset - self.Config.LowerOffset
	local desiredCFrame = CFrame.new(desiredOffset) * self.Config.Rotation
	targetRoot.CFrame = carrierRoot.CFrame * desiredCFrame

	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = targetRoot
	weld.Part1 = carrierRoot
	weld.C0 = CFrame.new()
	weld.C1 = desiredCFrame
	weld.Parent = targetRoot
	maid:Give(weld)

	if groundTrack then
		groundTrack:Play()
	end

	if gripTrack then
		gripTrack:Play()
		gripTrack.Stopped:Wait()
		if cancelled then
			return
		end
	end

	if cancelled or not carrierChar.Parent or not targetChar.Parent then
		return
	end

	self.SoundUtil.PlayNatural(self.AssetsRoot, "Execute", carrierRoot)
	self.Replication:FireAllClients("Global", "Hit", { targetChar, { 4, "Human" } })

	targetHum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	if targetHum.Health > 0 then
		targetHum.Health = 0
	end

	self.SoundUtil.PlayNatural(self.AssetsRoot, "Loss", targetRoot)
	removeDownPrompts(self.RigUtil, self.Config, targetChar)

	self.PromptManager.ResetPromptState(prompt, player)
	maid:DoCleaning()
end

function GripService:Toggle(player, prompt)
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

function GripService:ForceStop(player)
	local entry = self._active[player]
	if entry and entry.cancel then
		entry.cancel()
		return true
	end
	return false
end

function GripService:Init()
	Players.PlayerRemoving:Connect(function(player)
		self:ForceStop(player)
	end)
end

return GripService
