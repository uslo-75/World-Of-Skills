local module = {}

local rp = game:GetService("ReplicatedStorage")
local RNS = game:GetService("RunService")

local LiveOParams = OverlapParams.new()
LiveOParams.FilterType = Enum.RaycastFilterType.Include
LiveOParams.FilterDescendantsInstances = { workspace }

local function destroyAfter(inst: Instance?, delaySeconds: number)
	if not inst then
		return
	end
	task.delay(delaySeconds, function()
		if inst and inst.Parent then
			inst:Destroy()
		end
	end)
end

local function resolveCFrame(obj)
	if typeof(obj) == "CFrame" then
		return obj
	end
	if typeof(obj) == "Vector3" then
		return CFrame.new(obj)
	end
	if typeof(obj) ~= "Instance" then
		return nil
	end
	if obj:IsA("BasePart") then
		return obj.CFrame
	end
	if obj:IsA("Attachment") then
		return obj.WorldCFrame
	end
	if obj:IsA("Model") then
		return obj:GetPivot()
	end
	return nil
end

local function Hitbox(Params)
	if typeof(Params) ~= "table" then
		return
	end
	if typeof(Params.Player) ~= "Instance" or not Params.Player:IsA("Player") then
		return
	end
	if not Params.Player.Parent then
		return
	end
	if not Params.Player.Character or not Params.Player.Character.Parent then
		return
	end
	if typeof(Params.Size) ~= "Vector3" then
		return
	end
	if typeof(Params.Offset) ~= "CFrame" then
		Params.Offset = CFrame.new()
	end
	if typeof(Params.Ignore) ~= "table" then
		Params.Ignore = {}
	end

	local player = Params.Player
	local touchedCharacters = {}
	local closestCharacter = nil

	local function resolveForPlayer(obj)
		local base = resolveCFrame(obj)
		if not base then
			return nil
		end
		if typeof(obj) == "Instance" then
			local char = player.Character
			if char and (obj:IsDescendantOf(char)) then
				return base
			end
			local tool = char and char:FindFirstChildWhichIsA("Tool")
			if tool and obj:IsDescendantOf(tool) then
				return base
			end
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				return hrp.CFrame
			end
		end
		return base
	end

	task.spawn(function()
		pcall(function()
			if RNS:IsStudio() then
				local baseCFrame = resolveForPlayer(Params.Instance)
				if not baseCFrame then
					return
				end
				local HitboxVisualizer = rp.HitboxVisulizer:Clone()
				HitboxVisualizer.Size = Params.Size
				HitboxVisualizer.CFrame = baseCFrame * Params.Offset
				HitboxVisualizer.Name = "Hitbox" .. player.UserId
				HitboxVisualizer.Parent = workspace.Thrown
				destroyAfter(HitboxVisualizer, 0.1)
			end
		end)
	end)

	pcall(function()
		local baseCFrame = resolveForPlayer(Params.Instance)
		if not baseCFrame then
			return
		end
		local HitboxCFrame = baseCFrame * Params.Offset
		local touchingParts = workspace:GetPartBoundsInBox(HitboxCFrame, Params.Size, LiveOParams)
		for _, Part in touchingParts do
			if Part and Part.Parent then
				local EnemyCharacter: Model = Part.Parent

				local Player = game.Players:GetPlayerFromCharacter(EnemyCharacter)
				if Player and not Player:FindFirstChild("LoadedData") then
					continue
				end

				local Humanoid: Humanoid = EnemyCharacter:FindFirstChild("Humanoid")
				if
					Humanoid
					and not table.find(touchedCharacters, EnemyCharacter)
					and not table.find(Params.Ignore, EnemyCharacter)
				then
					table.insert(touchedCharacters, EnemyCharacter)

					if closestCharacter ~= nil then
						closestCharacter = EnemyCharacter
					else
						closestCharacter = EnemyCharacter
					end
				end
			end
		end
	end)
	if #touchedCharacters > 0 and closestCharacter ~= nil then
		local FirstIndex = touchedCharacters[1]
		if FirstIndex ~= closestCharacter then
			local tempTable = table.clone(touchedCharacters)

			touchedCharacters[1] = closestCharacter
			for i = 2, #touchedCharacters do
				touchedCharacters[i] = tempTable[i - 1]
			end
		end

		return touchedCharacters
	else
		return nil
	end
end

module.__index = module

function module.new(Player: Player)
	local MetaTable = setmetatable({
		Size = Vector3.new(1, 1, 1) * 7,
		Ignore = {},
		Instance = nil,
		Offset = CFrame.new(0, 0, 0),
		Characters = {},
		onTouch = function(EnemyCharacter: Model) end,
		functionAfterDestroy = function() end,
		ResetCharactersList = false,
		Player = Player,
		Connection = nil,
		StopConnection = false,
		destroyAfterOnce = false,
	}, module)

	return MetaTable
end

function module:Once()
	local TouchedEnemies = Hitbox({
		Player = self.Player,
		Instance = self.Instance,
		Size = self.Size,
		Offset = self.Offset,
		Ignore = self.Ignore,
	})

	if TouchedEnemies ~= nil and #TouchedEnemies > 0 then
		if TouchedEnemies ~= nil and #TouchedEnemies > 0 then
			for _, EnemyCharacter: Model in TouchedEnemies do
				if self.ResetCharactersList == false then
					if table.find(self.Characters, EnemyCharacter) then
						continue
					end
					table.insert(self.Characters, EnemyCharacter)
				else
					self.Characters = {}
				end

				self.onTouch(EnemyCharacter)
			end
		end

		if self.destroyAfterOnce == true then
			self:Destroy()
		end
	end
end

function module:Start(HitboxTime, Destroy)
	self.Connection = RNS.Heartbeat:Connect(function()
		local TouchedEnemies = Hitbox({
			Player = self.Player,
			Instance = self.Instance,
			Size = self.Size,
			Offset = self.Offset,
			Ignore = self.Ignore,
		})

		if TouchedEnemies ~= nil and #TouchedEnemies > 0 then
			if TouchedEnemies ~= nil and #TouchedEnemies > 0 then
				for _, EnemyCharacter: Model in TouchedEnemies do
					if self.StopConnection == true then
						return
					end
					if self.Player.Character:GetAttribute("Stunned") == true then
						return
					end
					if self.Player.Character:GetAttribute("Attacked") == true then
						return
					end

					if self.ResetCharactersList == false then
						if table.find(self.Characters, EnemyCharacter) then
							continue
						end

						table.insert(self.Characters, EnemyCharacter)
					else
						self.Characters = {}
					end

					self.onTouch(EnemyCharacter)
				end
			end

			if self.destroyAfterOnce == true then
				self:Destroy()
			end
		end
	end)

	if HitboxTime then
		task.delay(HitboxTime, function()
			if self ~= nil and self.Stop ~= nil and self.Destroy ~= nil then
				if Destroy == true then
					self:Destroy()
				else
					self:Stop()
				end
			end
		end)
	end
end

function module:Stop()
	self.StopConnection = true
end

function module:Destroy()
	local Connection: RBXScriptConnection = self.Connection

	if Connection then
		Connection:Disconnect()
	end

	task.spawn(self.functionAfterDestroy)

	setmetatable(self, nil)
end

return table.freeze(module)
