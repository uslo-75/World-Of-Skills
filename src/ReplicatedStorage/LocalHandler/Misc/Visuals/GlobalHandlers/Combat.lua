local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

module.Hit = function(params)
	local char = params[1]
	local data = params[2]

	if data[1] ~= 4 then
		char.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	if data[2] == "Human" then
		local bloodEffect = vfxFolder:WaitForChild("Hitvfx"):WaitForChild("Hit"):WaitForChild("Human"):Clone()
		bloodEffect.Parent = char:FindFirstChild("Torso")
		destroyAfter(bloodEffect, 5)

		for _, v in pairs(bloodEffect:GetDescendants()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end
end

return module
