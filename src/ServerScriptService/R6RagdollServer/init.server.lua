--[[ System By @Liam

Contact: @liam3124 on Discord.
Thanks for using this.
Subscribe: https://www.youtube.com/@Liam223?sub_confirmation=1
Do not resell this or claim ownership.

--]]

--||Services||--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--||Ragdoll CFrames (can be changed)||--
local attachmentCFrames = {
	["Neck"] = { CFrame.new(0, 1, 0, 0, -1, 0, 1, 0, -0, 0, 0, 1), CFrame.new(0, -0.5, 0, 0, -1, 0, 1, 0, -0, 0, 0, 1) },
	["Left Shoulder"] = {
		CFrame.new(-1.3, 0.75, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1),
		CFrame.new(0.2, 0.75, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1),
	},
	["Right Shoulder"] = {
		CFrame.new(1.3, 0.75, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
		CFrame.new(-0.2, 0.75, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	},
	["Left Hip"] = {
		CFrame.new(-0.5, -1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
		CFrame.new(0, 1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
	},
	["Right Hip"] = {
		CFrame.new(0.5, -1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
		CFrame.new(0, 1, 0, 0, 1, -0, -1, 0, 0, 0, 0, 1),
	},
}

--||Don't change this||--
local ragdollInstanceNames = {
	["RagdollAttachment"] = true,
	["RagdollConstraint"] = true,
	["ColliderPart"] = true,
}

--||Settings||--
local RagdollSounds = true --if you wanna have ragdoll sounds when the body hits something set this to true
local fixNpcFling = true --fixes the npc flinging away when they get up
local fixVoidBug = true --fixes the bug that the player doesnt respawn when he falls into the void (may causes error)

------------------------------------------------------------------------------------------------------------------

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

--//
--local function PlayRagdollSounds(char) --playing a sound when those body parts hit something
--	if RagdollSounds then
--		local impactH = script.ImpactSound:Clone()
--		impactH.Parent = char:WaitForChild("Head")
--		impactH.Disabled = false
--		local impactLA = script.ImpactSound:Clone()
--		impactLA.Parent = char:WaitForChild("Left Arm")
--		impactLA.Disabled = false
--		local impactRA = script.ImpactSound:Clone()
--		impactRA.Parent = char:WaitForChild("Right Arm")
--		impactRA.Disabled = false
--	end
--end

--//
local function createColliderPart(part) --creating the parts that are gonna be colliding with the world
	if not part then
		return
	end
	local rp = Instance.new("Part")
	rp.Name = "ColliderPart"
	rp.Size = part.Size / 1.7
	rp.Massless = true
	rp.CFrame = part.CFrame
	rp.Transparency = 1

	local wc = Instance.new("WeldConstraint")
	wc.Part0 = rp
	wc.Part1 = part
	wc.Parent = rp
	rp.Parent = part
end

--//
local function replaceJoints(char, hum) --replacing the joints and other stuff
	hum.PlatformStand = true
	hum.AutoRotate = false
	char.HumanoidRootPart.Massless = true
	char.HumanoidRootPart.CanCollide = false

	for _, motor in ipairs(char:GetDescendants()) do
		if motor:IsA("Motor6D") and attachmentCFrames[motor.Name] then
			motor.Enabled = false

			--PlayRagdollSounds(char)

			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.CFrame = attachmentCFrames[motor.Name][1]
			a1.CFrame = attachmentCFrames[motor.Name][2]

			a0.Name = "RagdollAttachment"
			a1.Name = "RagdollAttachment"

			createColliderPart(motor.Part1)

			local b = Instance.new("BallSocketConstraint")
			b.Attachment0 = a0
			b.Attachment1 = a1
			b.Name = "RagdollConstraint"

			b.Radius = 0.15
			b.LimitsEnabled = true
			b.TwistLimitsEnabled = motor.Name == "Neck"
			b.MaxFrictionTorque = 0
			b.Restitution = 0
			b.UpperAngle = motor.Name == "Neck" and 45 or 90
			b.TwistLowerAngle = motor.Name == "Neck" and -70 or -45
			b.TwistUpperAngle = motor.Name == "Neck" and 70 or 45

			a0.Parent = motor.Part0
			a1.Parent = motor.Part1
			b.Parent = motor.Parent
		end
	end
end

--//
local function resetJoints(hum) --resetting the joints and all the other properties
	local char = hum.Parent
	local hrp = char.HumanoidRootPart

	char:SetAttribute("IsRagdoll", false)
	hum.PlatformStand = false
	hum.AutoRotate = true
	char.HumanoidRootPart.Massless = false
	char.HumanoidRootPart.CanCollide = true

	if RagdollSounds then
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("Script") and v.Name == "ImpactSound" and v.Enabled == true then
				v:Destroy()
			end
		end
	end

	if hum.Health <= 0 then
		return
	end --we don't want the player to stand up again if he is dead

	for _, instance in ipairs(char:GetDescendants()) do
		if ragdollInstanceNames[instance.Name] then
			instance:Destroy()
		end
		if instance:IsA("Motor6D") then
			instance.Enabled = true
		end
	end

	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)

	local isPlayer = Players:GetPlayerFromCharacter(hum.Parent)
	if not isPlayer and fixNpcFling then --the body position and body gyro thing was something I found on the devforum so not my idea
		local FloatThing = Instance.new("BodyPosition")
		do
			FloatThing.Position = hrp.Position + Vector3.new(0, 2, 0)
			FloatThing.Parent = hrp
			destroyAfter(FloatThing, 0.25)
		end

		local Stabilizer = Instance.new("BodyGyro")
		do
			Stabilizer.P = 1000000
			Stabilizer.D = 500
			Stabilizer.MaxTorque = Vector3.new(10000, 0, 10000)
			Stabilizer.Parent = hrp
			destroyAfter(Stabilizer, 0.25)
		end
	end
end

--//
local function applyRagdollToCharacter(char) --applying the ragdoll
	if char:GetAttribute("RagdollServerBound") == true then
		return
	end
	char:SetAttribute("RagdollServerBound", true)

	local hum = char:FindFirstChild("Humanoid")
	if hum then
		local torso = char:FindFirstChild("Torso")
		if torso then
			hum.BreakJointsOnDeath = false
			hum.RequiresNeck = false

			char:SetAttribute("IsRagdoll", false) --setting ragdoll to false from the beginning on

			char:GetAttributeChangedSignal("IsRagdoll"):Connect(function()
				if char:GetAttribute("IsRagdoll") then
					replaceJoints(char, hum)
				else
					resetJoints(hum)
				end
			end)

			hum.Died:Once(function()
				char:SetAttribute("IsRagdoll", true)
				char:SetAttribute("Stunned", true)
				torso:ApplyImpulse(torso.CFrame.LookVector * 100)
			end)
		end
	end
end

--//
local function applyRagdollToCharacters()
	for _, char in ipairs(workspace:GetDescendants()) do
		applyRagdollToCharacter(char)
	end
end

-- Example if workspace includes an NPC folder:
--[[

workspace.Map.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child:FindFirstChild("Humanoid") then
		applyRagdollToCharacter(child)
	end
end)

]]

--//
applyRagdollToCharacters()

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		applyRagdollToCharacter(char)

		if fixVoidBug then
			local queued = false
			local hbConn

			local function queueRespawnFromVoid()
				if queued then
					return
				end
				if plr.Character ~= char then
					return
				end

				queued = true
				task.delay(Players.RespawnTime, function()
					if plr.Parent ~= Players then
						return
					end
					if plr.Character ~= char then
						return
					end

					pcall(function()
						plr:LoadCharacter()
					end)
				end)
			end

			hbConn = RunService.Heartbeat:Connect(function()
				if plr.Character ~= char then
					if hbConn then
						hbConn:Disconnect()
					end
					return
				end

				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then
					return
				end

				if hrp.Position.Y <= workspace.FallenPartsDestroyHeight then
					queueRespawnFromVoid()
				end
			end)

			char.AncestryChanged:Connect(function(_, parent)
				if parent == nil and hbConn then
					hbConn:Disconnect()
					hbConn = nil
				end
			end)
		end
	end)
end)
