local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local module = {}
local vfxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("vfx")

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

local function createAttachmentIfNotExists(parent: BasePart, name: string, position: Vector3): Attachment
	local attachment = parent:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = name
	newAttachment.Position = position
	newAttachment.Parent = parent
	return newAttachment
end

module.TweenForward = function(params)
	local character = params.Char
	local humrp: Part = character:WaitForChild("HumanoidRootPart")

	for _, v in pairs(humrp:GetChildren()) do
		if v:IsA("LinearVelocity") then
			v:Destroy()
		end
	end

	local bv = Instance.new("LinearVelocity")
	bv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	bv.RelativeTo = Enum.ActuatorRelativeTo.World
	if params.Type == "Up" then
		bv.MaxAxesForce = Vector3.new(1, 1, 1) * math.huge
	else
		bv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	end
	bv.Attachment0 = humrp:FindFirstChild("RootAttachment")
	bv.Parent = humrp

	local velocityTween = Instance.new("NumberValue")
	velocityTween.Value = params.velocity

	if params.duration then
		if not params.Destroy then
			TweenService:Create(velocityTween, TweenInfo.new(params.duration), { Value = 0 }):Play()
		end
		destroyAfter(bv, params.duration)
	end

	local renderConn: RBXScriptConnection? = nil
	renderConn = game:GetService("RunService").RenderStepped:Connect(function()
		if not humrp or not character.Parent then
			if renderConn then
				renderConn:Disconnect()
			end
			return
		end

		if bv.Parent then
			if params.Type == "Up" then
				bv.VectorVelocity = humrp.CFrame.UpVector * velocityTween.Value
			else
				bv.VectorVelocity = humrp.CFrame.LookVector * velocityTween.Value
			end
		else
			if renderConn then
				renderConn:Disconnect()
			end
		end
	end)
end

module.MomentumSpeed = function(params)
	if typeof(params) ~= "table" then
		return
	end

	local char = params[1] or params.Char
	local enabled = params[2]
	if enabled == nil then
		enabled = params.Enabled
	end
	if typeof(enabled) ~= "boolean" then
		enabled = false
	end
	if not char or not char.Parent then
		return
	end

	local function fadeOutTrail(trail: Trail)
		local step = 0.1
		local transparencyIncrement = step / 0.3
		local currentTransparency = 0

		while currentTransparency < 1 do
			trail.Transparency = NumberSequence.new(currentTransparency)
			currentTransparency += transparencyIncrement
			task.wait(step)
		end

		trail.Enabled = false
	end

	local function toggleTrail(trail: Trail, isEnabled: boolean)
		if isEnabled then
			trail.Transparency = vfxFolder:WaitForChild("BodyTrail").BodyTrail2.Transparency
			trail.Enabled = true
		else
			fadeOutTrail(trail)
		end
	end

	local leftArm = char:FindFirstChild("Left Arm")
	local rightArm = char:FindFirstChild("Right Arm")
	local leftLeg = char:FindFirstChild("Left Leg")
	local rightLeg = char:FindFirstChild("Right Leg")

	if leftArm and rightArm and leftLeg and rightLeg then
		local trailTemplate = vfxFolder:WaitForChild("BodyTrail").BodyTrail2

		local function getOrCreateTrail(limb: BasePart): Trail
			local existingTrail = limb:FindFirstChild("BodyTrail")
			if existingTrail and existingTrail:IsA("Trail") then
				return existingTrail
			end
			local newTrail = trailTemplate:Clone()
			newTrail.Name = "BodyTrail"
			return newTrail
		end

		local leftArmTrail = getOrCreateTrail(leftArm)
		local rightArmTrail = getOrCreateTrail(rightArm)
		local leftLegTrail = getOrCreateTrail(leftLeg)
		local rightLegTrail = getOrCreateTrail(rightLeg)

		local leftArmAttachment0 =
			createAttachmentIfNotExists(leftArm, "TrailAttachment0", Vector3.new(0, -leftArm.Size.Y / 2, 0))
		local leftArmAttachment1 =
			createAttachmentIfNotExists(leftArm, "TrailAttachment1", Vector3.new(0, -leftArm.Size.Y / 3, 0))
		local rightArmAttachment0 =
			createAttachmentIfNotExists(rightArm, "TrailAttachment0", Vector3.new(0, -rightArm.Size.Y / 2, 0))
		local rightArmAttachment1 =
			createAttachmentIfNotExists(rightArm, "TrailAttachment1", Vector3.new(0, -rightArm.Size.Y / 3, 0))
		local leftLegAttachment0 =
			createAttachmentIfNotExists(leftLeg, "TrailAttachment0", Vector3.new(0, -leftLeg.Size.Y / 2, 0))
		local leftLegAttachment1 =
			createAttachmentIfNotExists(leftLeg, "TrailAttachment1", Vector3.new(0, -leftLeg.Size.Y / 3, 0))
		local rightLegAttachment0 =
			createAttachmentIfNotExists(rightLeg, "TrailAttachment0", Vector3.new(0, -rightLeg.Size.Y / 2, 0))
		local rightLegAttachment1 =
			createAttachmentIfNotExists(rightLeg, "TrailAttachment1", Vector3.new(0, -rightLeg.Size.Y / 3, 0))

		leftArmTrail.Attachment0 = leftArmAttachment0
		leftArmTrail.Attachment1 = leftArmAttachment1
		leftArmTrail.Parent = leftArm

		rightArmTrail.Attachment0 = rightArmAttachment0
		rightArmTrail.Attachment1 = rightArmAttachment1
		rightArmTrail.Parent = rightArm

		leftLegTrail.Attachment0 = leftLegAttachment0
		leftLegTrail.Attachment1 = leftLegAttachment1
		leftLegTrail.Parent = leftLeg

		rightLegTrail.Attachment0 = rightLegAttachment0
		rightLegTrail.Attachment1 = rightLegAttachment1
		rightLegTrail.Parent = rightLeg

		toggleTrail(leftArmTrail, enabled)
		toggleTrail(rightArmTrail, enabled)
		toggleTrail(leftLegTrail, enabled)
		toggleTrail(rightLegTrail, enabled)
	end
end

module.BodyTrail = function(params)
	if typeof(params) ~= "table" then
		return
	end

	local char = params[1] or params.Char
	local time = params[2] or params.Time or 0.3
	local location = params[3] or params.Location or "BodyTrail1"
	if typeof(time) ~= "number" or time <= 0 then
		time = 0.3
	end
	if typeof(location) ~= "string" then
		location = "BodyTrail1"
	end
	if not char or not char.Parent then
		return
	end

	local function fadeOutAndDestroy(trail: Trail, duration: number)
		task.spawn(function()
			local step = 0.1
			local currentTime = 0

			while currentTime < duration do
				trail.Transparency = NumberSequence.new(currentTime / duration)
				currentTime += step
				task.wait(step)
			end

			trail.Transparency = NumberSequence.new(1)
			if trail.Parent then
				trail:Destroy()
			end
		end)
	end

	local leftArm = char:FindFirstChild("Left Arm")
	local rightArm = char:FindFirstChild("Right Arm")
	local leftLeg = char:FindFirstChild("Left Leg")
	local rightLeg = char:FindFirstChild("Right Leg")

	if leftArm and rightArm and leftLeg and rightLeg then
		local bodyTrailFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("vfx"):WaitForChild("BodyTrail")
		local trailTemplate = bodyTrailFolder:FindFirstChild(location) or bodyTrailFolder:FindFirstChild("BodyTrail1")
		if not trailTemplate then
			return
		end

		local leftArmTrail = trailTemplate:Clone()
		local leftArmAttachment0 =
			createAttachmentIfNotExists(leftArm, "TrailAttachment0", Vector3.new(0, -leftArm.Size.Y / 2, 0))
		local leftArmAttachment1 =
			createAttachmentIfNotExists(leftArm, "TrailAttachment1", Vector3.new(0, -leftArm.Size.Y / 3, 0))

		local rightArmTrail = trailTemplate:Clone()
		local rightArmAttachment0 =
			createAttachmentIfNotExists(rightArm, "TrailAttachment0", Vector3.new(0, -rightArm.Size.Y / 2, 0))
		local rightArmAttachment1 =
			createAttachmentIfNotExists(rightArm, "TrailAttachment1", Vector3.new(0, -rightArm.Size.Y / 3, 0))

		local leftLegTrail = trailTemplate:Clone()
		local leftLegAttachment0 =
			createAttachmentIfNotExists(leftLeg, "TrailAttachment0", Vector3.new(0, -leftLeg.Size.Y / 2, 0))
		local leftLegAttachment1 =
			createAttachmentIfNotExists(leftLeg, "TrailAttachment1", Vector3.new(0, -leftLeg.Size.Y / 3, 0))

		local rightLegTrail = trailTemplate:Clone()
		local rightLegAttachment0 =
			createAttachmentIfNotExists(rightLeg, "TrailAttachment0", Vector3.new(0, -rightLeg.Size.Y / 2, 0))
		local rightLegAttachment1 =
			createAttachmentIfNotExists(rightLeg, "TrailAttachment1", Vector3.new(0, -rightLeg.Size.Y / 3, 0))

		leftArmTrail.Attachment0 = leftArmAttachment0
		leftArmTrail.Attachment1 = leftArmAttachment1
		leftArmTrail.Parent = leftArm
		rightArmTrail.Attachment0 = rightArmAttachment0
		rightArmTrail.Attachment1 = rightArmAttachment1
		rightArmTrail.Parent = rightArm
		leftLegTrail.Attachment0 = leftLegAttachment0
		leftLegTrail.Attachment1 = leftLegAttachment1
		leftLegTrail.Parent = leftLeg
		rightLegTrail.Attachment0 = rightLegAttachment0
		rightLegTrail.Attachment1 = rightLegAttachment1
		rightLegTrail.Parent = rightLeg

		fadeOutAndDestroy(leftArmTrail, time)
		fadeOutAndDestroy(rightArmTrail, time)
		fadeOutAndDestroy(leftLegTrail, time)
		fadeOutAndDestroy(rightLegTrail, time)
	end
end

module.BodyColour = function(params)
	local char = params[1]
	local data = params[2]

	local highlight = Instance.new("Highlight")
	highlight.FillColor = data[2]
	highlight.FillTransparency = 0.1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = char

	local tweenInfo = TweenInfo.new(data[1], Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	local fadeTween = TweenService:Create(highlight, tweenInfo, { FillTransparency = 1, OutlineTransparency = 1 })
	fadeTween:Play()

	destroyAfter(highlight, data[1])
end

module.FOV = function(params)
	local data = params[2]
	local tweenInfo = TweenInfo.new(data[1], Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	local fovTween =
		TweenService:Create(game.Workspace.CurrentCamera, tweenInfo, { FieldOfView = data[2] })
	fovTween:Play()
end

return module
