local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstanceUtil = require(
	ReplicatedStorage:WaitForChild("LocalHandler"):WaitForChild("libs"):WaitForChild("Common"):WaitForChild("InstanceUtil")
)

local module = {}
local vfxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("vfx")

module.Slide = function(params)
	local char = params[1]
	local extra = params[2]
	local emitPart = vfxFolder:WaitForChild("Slide"):WaitForChild("EmitPart")

	if not char[extra[1]]:FindFirstChild("Slide") then
		local effect = emitPart.Attachment:Clone()
		effect.Parent = char[extra[1]]
		effect.CFrame = CFrame.new(0, -1.5, 0)
		effect.Name = "Slide"
	end

	if extra[3] == true then
		char[extra[1]]:FindFirstChild("Slide").dust.Enabled = true
		if extra[2] then
			char[extra[1]]:FindFirstChild("Slide").dust.Color = ColorSequence.new(extra[2])
			char[extra[1]]:FindFirstChild("Slide").dust.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.399002, 0.45625),
				NumberSequenceKeypoint.new(1, 1),
			})
		else
			char[extra[1]]:FindFirstChild("Slide").dust.Transparency = NumberSequence.new(1)
		end
	else
		char[extra[1]]:FindFirstChild("Slide").dust.Enabled = false
		InstanceUtil.DestroyAfter(char[extra[1]]:WaitForChild("Slide"), 0)
	end
end

module.SlideJump = function(params)
	local char = params[1]
	local extra = params[2] or {}

	local groundColor: Color3? = extra[2]
	local groundNormal: Vector3? = extra[4]

	local emitPart = vfxFolder:WaitForChild("Slide"):WaitForChild("SlideJump"):Clone()
	local hrp = char:WaitForChild("HumanoidRootPart")
	local pos = hrp.Position + Vector3.new(0, -0.5, 0)

	if groundNormal then
		local up = groundNormal.Unit
		local fwd = hrp.CFrame.LookVector
		fwd = (fwd - up * fwd:Dot(up))

		if fwd.Magnitude < 0.01 then
			fwd = hrp.CFrame.RightVector:Cross(up)
		end
		fwd = fwd.Unit

		local right = up:Cross(fwd).Unit
		fwd = right:Cross(up).Unit

		emitPart.CFrame = CFrame.fromMatrix(pos, right, up, -fwd)
	else
		emitPart.CFrame = CFrame.new(pos)
	end

	emitPart.Parent = workspace:FindFirstChild("Debris") or workspace

	for _, obj in ipairs(emitPart:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			if obj.Name == "Dust" and groundColor then
				obj.Color = ColorSequence.new(groundColor)
			end
			obj:Emit(obj:GetAttribute("EmitCount") or 1)
		end
	end

	InstanceUtil.DestroyAfter(emitPart, 3)
end

module.SlideJump2 = function(params)
	local char = params[1]
	local extra = params[2] or {}

	local groundColor: Color3? = extra[1]

	local emitPart = vfxFolder:WaitForChild("Fall"):WaitForChild("EmitPart")
	local effect = emitPart.Attachment:Clone()
	effect.Parent = char:WaitForChild("HumanoidRootPart")
	effect.CFrame = CFrame.new(0, -3, 0)
	InstanceUtil.DestroyAfter(effect, 5)

	for _, particle in pairs(effect:GetDescendants()) do
		if particle:IsA("ParticleEmitter") then
			if particle.Name == "Dust" and groundColor then
				particle.Color = ColorSequence.new(groundColor)
			end
			particle:Emit(particle:GetAttribute("EmitCount"))
		end
	end
end

module.WallRun = function(params)
	local char = params[1]
	local extra = params[2]
	local emitPart = vfxFolder:WaitForChild("WallRun"):WaitForChild("EmitPart")

	if not char[extra[1]]:FindFirstChild("WallRun") then
		local effect = emitPart.Attachment:Clone()
		effect.Parent = char[extra[1]]
		effect.CFrame = CFrame.new(0, -0.4, 0)
		effect.Name = "WallRun"
	end

	if extra[2] == true then
		char[extra[1]]:FindFirstChild("WallRun").dust.Enabled = true
	else
		char[extra[1]]:FindFirstChild("WallRun").dust.Enabled = false
		InstanceUtil.DestroyAfter(char[extra[1]]:WaitForChild("WallRun"), 0)
	end
end

module.Fall = function(params)
	local char = params[1]
	local emitPart = vfxFolder:WaitForChild("Fall"):WaitForChild("EmitPart")

	local effect = emitPart.Attachment:Clone()
	effect.Parent = char:WaitForChild("HumanoidRootPart")
	effect.CFrame = CFrame.new(0, -3, 0)
	InstanceUtil.DestroyAfter(effect, 5)

	for _, particle in pairs(effect:GetDescendants()) do
		particle:Emit(particle:GetAttribute("EmitCount"))
	end
end

return module
