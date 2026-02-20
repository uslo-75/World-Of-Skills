local module = {}

local function cleanupInstance(inst: Instance?)
	if inst and inst.Parent then
		inst:Destroy()
	end
end

local function resolveRootPart(character: Model): BasePart?
	if not character or not character.Parent then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart
end

local function toPlanar(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function normalize(vector: Vector3): Vector3?
	if vector.Magnitude <= 1e-5 then
		return nil
	end

	return vector.Unit
end

local function resolveDirectionVector(rootPart: BasePart, config: { [string]: any }): Vector3?
	local direction = config.direction
	local resolved = nil

	if typeof(direction) == "Vector3" then
		resolved = direction
	elseif typeof(direction) == "string" then
		local key = string.lower(direction)
		if key == "forward" or key == "look" then
			resolved = rootPart.CFrame.LookVector
		elseif key == "backward" or key == "back" then
			resolved = -rootPart.CFrame.LookVector
		elseif key == "right" then
			resolved = rootPart.CFrame.RightVector
		elseif key == "left" then
			resolved = -rootPart.CFrame.RightVector
		elseif key == "up" then
			resolved = rootPart.CFrame.UpVector
		elseif key == "down" then
			resolved = -rootPart.CFrame.UpVector
		end
	end

	if not resolved then
		resolved = rootPart.CFrame.LookVector
	end

	if config.planar == true then
		resolved = toPlanar(resolved)
	end

	if config.normalizeDirection == false then
		return resolved
	end

	return normalize(resolved)
end

local function resolveWorldVelocity(rootPart: BasePart, config: { [string]: any }, M1Calc: any): Vector3?
	local configuredVelocity = config.velocity
	if typeof(configuredVelocity) == "Vector3" then
		return configuredVelocity
	end

	local direction = resolveDirectionVector(rootPart, config)
	if not direction then
		return nil
	end

	local speed = M1Calc.ToNumber(config.speed, 0)
	local resolved = direction * speed

	local additive = config.additiveVelocity
	if typeof(additive) == "Vector3" then
		resolved += additive
	end

	return resolved
end

local function resolveRelativeTo(config: { [string]: any }): Enum.ActuatorRelativeTo
	local relativeTo = config.relativeTo
	if typeof(relativeTo) == "EnumItem" and relativeTo.EnumType == Enum.ActuatorRelativeTo then
		return relativeTo
	end
	return Enum.ActuatorRelativeTo.World
end

function module.StopForwardVelocity(stateByCharacter: { [Model]: any }, character: Model)
	local state = stateByCharacter[character]
	if not state then
		return
	end

	cleanupInstance(state.velocity)
	cleanupInstance(state.attachment)
	stateByCharacter[character] = nil
end

function module.ApplyPush(
	stateByCharacter: { [Model]: any },
	character: Model,
	config: { [string]: any }?,
	M1Calc: any
)
	if typeof(config) ~= "table" then
		return
	end

	local duration = tonumber(config.duration)
	if not duration or duration <= 0 then
		return
	end

	module.StopForwardVelocity(stateByCharacter, character)

	local rootPart = resolveRootPart(character)
	if not rootPart then
		return
	end

	local worldVelocity = resolveWorldVelocity(rootPart, config, M1Calc)
	if not worldVelocity then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "__CriticalForwardAttachment"
	attachment.Parent = rootPart

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "__CriticalForwardVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = resolveRelativeTo(config)
	velocity.MaxForce = math.max(1200, M1Calc.ToNumber(config.maxForce, worldVelocity.Magnitude * 1500))

	if typeof(config.maxAxesForce) == "Vector3" then
		velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		velocity.MaxAxesForce = config.maxAxesForce
	end

	velocity.VectorVelocity = worldVelocity
	velocity.Parent = rootPart

	stateByCharacter[character] = {
		attachment = attachment,
		velocity = velocity,
	}

	task.delay(duration, function()
		local latest = stateByCharacter[character]
		if latest and latest.velocity == velocity then
			module.StopForwardVelocity(stateByCharacter, character)
		end
	end)
end

return table.freeze(module)
