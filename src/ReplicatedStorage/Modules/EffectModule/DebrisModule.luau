--!nocheck
local module = {}

local faces = {
	"Top",
	"Bottom",
	"Front",
	"Back",
	"Left",
	"Right",
}

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

module.Rocks = function(Origin, rockNumber, Color, Material, CanCollide, Trail, Size, Texture)
	for i = 1, rockNumber do
		local Part = Instance.new("Part")
		Part.Anchored = false
		Part.Name = "Part"
		Part.Shape = "Block"
		Part.Size = Size or Vector3.new(2.5, 2.5, 2.5)
		Part.Material = Material
		Part.CanCollide = CanCollide
		Part.Position = Origin
		Part.BrickColor = BrickColor.new(Color)

		Part.Velocity = Vector3.new(math.random(-100, 100), math.random(0, 100), math.random(-100, 100))
		Part.CFrame = Part.CFrame
			* CFrame.Angles(math.rad(math.random(30, 50)), math.rad(math.random(30, 50)), math.rad(math.random(30, 50)))

		if Trail == true then
			local a1 = Instance.new("Attachment", Part)
			a1.Name = "a1"
			a1.WorldCFrame = Part.CFrame * CFrame.new(0.2, 0, 0)

			local a2 = Instance.new("Attachment", Part)
			a2.Name = "a2"
			a2.WorldCFrame = Part.CFrame * CFrame.new(-0.2, 0, 0)

			local Trail = script.Trail:Clone()
			Trail.Parent = Part
			Trail.Attachment0 = a1
			Trail.Attachment1 = a2
		end

		if Texture and Texture ~= nil and Texture:IsA("Texture") then
			for i = 1, #faces do
				local clone = Texture:Clone()
				clone.Parent = Part
				clone.Face = faces[i]
			end
		end

		Part.Parent = workspace.Effects
	end
end

module.fireDebris = function(Origin, rockNumber, Color, Material, CanCollide, Trail, Size)
	for i = 1, rockNumber do
		local Part = Instance.new("Part")
		Part.Anchored = false
		Part.Name = "Part"
		Part.Shape = "Block"
		Part.Size = Size or Vector3.new(2.5, 2.5, 2.5)
		Part.Material = Material
		Part.CanCollide = false
		Part.Position = Origin
		Part.BrickColor = BrickColor.new(Color)

		Part.Velocity = Vector3.new(math.random(-100, 100), math.random(0, 100), math.random(-100, 100))
		Part.CFrame = Part.CFrame
			* CFrame.Angles(math.rad(math.random(30, 50)), math.rad(math.random(30, 50)), math.rad(math.random(30, 50)))

		local pointLight = Instance.new("PointLight", Part)
		pointLight.Color = Color3.new(1, 0.333333, 0)
		pointLight.Range = 10
		pointLight.Brightness = 1

		spawn(function()
			Part.Touched:Connect(function(hitPart)
				if
					not hitPart.Parent:FindFirstChildWhichIsA("Humanoid")
					and hitPart:IsA("BasePart")
					and not hitPart:IsDescendantOf(workspace.Effects)
					and not hitPart:IsDescendantOf(workspace.Instances)
				then
					local littleSplash =
						game.ReplicatedStorage.Services.OutputService["Mera Mera"]["Fire Hiken"].LittleSplash:Clone()
					littleSplash.Parent = workspace.Effects
					littleSplash.CFrame = Part.CFrame
					for i, v in pairs(littleSplash:GetDescendants()) do
						if v:IsA("ParticleEmitter") then
							v:Emit()
						end
					end
					destroyAfter(littleSplash, 2)
					Part:Destroy()
				end
			end)
		end)

		if Trail == true then
			local a1 = Instance.new("Attachment", Part)
			a1.Name = "a1"
			a1.CFrame = Part.CFrame * CFrame.new(0.2, 0, 0)

			local a2 = Instance.new("Attachment", Part)
			a2.Name = "a2"
			a2.CFrame = Part.CFrame * CFrame.new(-0.2, 0, 0)

			local Trail = script.Trail:Clone()
			Trail.Parent = Part
			Trail.Attachment0 = a1
			Trail.Attachment1 = a2
		end
		Part.Parent = workspace.Effects
	end
end

module.empDebris = function(Origin, rockNumber, Color, Material, CanCollide, Trail, Size)
	for i = 1, rockNumber do
		local Part = Instance.new("Part")
		Part.Anchored = false
		Part.Name = "Part"
		Part.Shape = "Ball"
		Part.Size = Size or Vector3.new(2.5, 2.5, 2.5)
		Part.Material = Material
		Part.CanCollide = false
		Part.Position = Origin
		Part.BrickColor = BrickColor.new(Color)

		Part.Velocity = Vector3.new(math.random(-100, 100), math.random(0, 100), math.random(-100, 100))
		Part.CFrame = Part.CFrame
			* CFrame.Angles(
				math.rad(math.random(30, 50)),
				math.rad(math.random(50, 100)),
				math.rad(math.random(30, 50))
			)

		local pointLight = Instance.new("PointLight", Part)
		pointLight.Color = Color3.new(1, 0.333333, 0)
		pointLight.Range = 10
		pointLight.Brightness = 1

		spawn(function()
			--[[
			Part.Touched:Connect(function(hitPart)
				if hitPart:IsA("BasePart") and not hitPart:IsDescendantOf(workspace.Effects) and not hitPart:IsDescendantOf(workspace.Instances) then
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = {workspace.Effects, workspace.Instances, workspace.Livings}
					local ray = workspace:Raycast(Part.Position,Vector3.new(0,-100,0), params)
					if ray then
						local part = Instance.new("Part", workspace.Effects)
						part.Position = ray.Position
						part.Material = Enum.Material.Neon
						part.Size = Vector3.new(0,0.01,0)
						part.Anchored = true
						part.CanCollide = false
						part.CFrame = part.CFrame * CFrame.Angles(0,math.rad(math.random(-720,720)),0)
						part.Color = Color3.new(1, 0.333333, 0)
						game.TweenService:Create(part,TweenInfo.new(1),{Size = Vector3.new(2,0.01,2)}):Play()
						delay(2,function()
							game.TweenService:Create(part,TweenInfo.new(2),{Transparency = 1}):Play()
							destroyAfter(part, 2)
						end)
					end
					
					Part:Destroy()
				end
			end)
			]]
		end)

		if Trail == true then
			local a1 = Instance.new("Attachment", Part)
			a1.Name = "a1"
			a1.CFrame = Part.CFrame * CFrame.new(0.2, 0, 0)

			local a2 = Instance.new("Attachment", Part)
			a2.Name = "a2"
			a2.CFrame = Part.CFrame * CFrame.new(-0.2, 0, 0)

			local Trail = script.Trail:Clone()
			Trail.Parent = Part
			Trail.Attachment0 = a1
			Trail.Attachment1 = a2
		end
		Part.Parent = workspace.Effects
	end
end

return module
