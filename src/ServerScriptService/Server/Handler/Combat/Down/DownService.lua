local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local DownService = {}

function DownService.new(deps)
	return setmetatable({
		Config = deps.Config,
		StateManager =
			deps.StateManager or require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("StateManager")),
		PromptManager = deps.PromptManager,
		Collision = deps.Collision,
		RigUtil = deps.RigUtil,
		DownPrompts = deps.DownPrompts,
		_bound = {},
	}, { __index = DownService })
end

function DownService:_syncPlayer(character, isDown)
	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		self.StateManager.SetState(plr, "Downed", isDown)
		self.StateManager.SetState(plr, "IsRagdoll", isDown)
	end
end

function DownService:_apply(character, humanoid, isDown)
	if not character.Parent then
		return
	end

	character:SetAttribute(self.Config.DownAttribute, isDown)
	character:SetAttribute(self.Config.RagdollAttribute, isDown)
	self:_syncPlayer(character, isDown)
	character:SetAttribute("NoFall", isDown or nil)

	if humanoid and humanoid.Parent then
		if isDown then
			if character:GetAttribute("PrevAutoRotate") == nil then
				character:SetAttribute("PrevAutoRotate", humanoid.AutoRotate)
			end
			humanoid.AutoRotate = false
		else
			local prev = character:GetAttribute("PrevAutoRotate")
			humanoid.AutoRotate = (prev == nil) and true or (prev == true)
			character:SetAttribute("PrevAutoRotate", nil)
		end
	end

	if isDown then
		self.DownPrompts.Ensure(self.PromptManager, self.RigUtil, self.Config, character)
		self.Collision.SetNoPlayerCollision(character)
	else
		self.DownPrompts.Clear(self.RigUtil, character)
		self.Collision.SetPlayerCollision(character)
	end
end

function DownService:_evaluate(character, humanoid)
	if not humanoid or not humanoid.Parent then
		return
	end

	local hp = humanoid.Health
	local isDown = character:GetAttribute(self.Config.DownAttribute) == true

	if isDown then
		local exitHp = humanoid.MaxHealth * self.Config.ExitHealthRatio
		if hp >= exitHp then
			self:_apply(character, humanoid, false)
		end
		return
	end

	if hp > 0 and hp <= self.Config.DownHealth then
		self:_apply(character, humanoid, true)
	end
end

function DownService:BindCharacter(character)
	if self._bound[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	self._bound[character] = true

	if character:GetAttribute(self.Config.DownAttribute) == nil then
		character:SetAttribute(self.Config.DownAttribute, false)
	end
	if character:GetAttribute(self.Config.RagdollAttribute) == nil then
		character:SetAttribute(self.Config.RagdollAttribute, false)
	end

	self:_evaluate(character, humanoid)

	humanoid.HealthChanged:Connect(function()
		self:_evaluate(character, humanoid)
	end)

	humanoid.Died:Connect(function()
		self.DownPrompts.Clear(self.RigUtil, character)
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self._bound[character] = nil
			self.DownPrompts.Clear(self.RigUtil, character)
		end
	end)
end

function DownService:Init()
	local function bindPlayer(player)
		player.CharacterAdded:Connect(function(char)
			self:BindCharacter(char)
		end)
		if player.Character then
			self:BindCharacter(player.Character)
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		bindPlayer(p)
	end
	Players.PlayerAdded:Connect(bindPlayer)
end

return DownService
