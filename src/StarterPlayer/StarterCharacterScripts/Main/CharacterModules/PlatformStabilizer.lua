local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlatformStabilizer = {}

local player = Players.LocalPlayer
local heartbeatConn: RBXScriptConnection? = nil

local RAY_DISTANCE = 50
local PLATFORM_NAME = "RaftTop"

local lastRootCFrame: CFrame? = nil
local lastRootModel: Model? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function getRootFromHitPart(hit: BasePart): (Model?, BasePart?)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end

	local root = model.PrimaryPart
	if root and root:IsA("BasePart") then
		return model, root
	end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return model, hrp
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	return model, anyPart
end

function PlatformStabilizer.Init()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char then
			return
		end

		local humanoidRoot = char:FindFirstChild("HumanoidRootPart")
		if not humanoidRoot then
			return
		end

		rayParams.FilterDescendantsInstances = { char }

		local origin = humanoidRoot.Position
		local direction = Vector3.new(0, -RAY_DISTANCE, 0)
		local result = workspace:Raycast(origin, direction, rayParams)

		if result and result.Instance and result.Instance:IsA("BasePart") then
			local hitPart = result.Instance
			if PLATFORM_NAME and hitPart.Name ~= PLATFORM_NAME then
				-- Keep legacy permissive behavior: still allow model root delta even if name differs.
			end

			local model, rootPart = getRootFromHitPart(hitPart)
			if model and rootPart then
				local rootCF = rootPart.CFrame

				if lastRootCFrame == nil or lastRootModel ~= model then
					lastRootModel = model
					lastRootCFrame = rootCF
					return
				end

				local delta = rootCF * lastRootCFrame:Inverse()
				lastRootCFrame = rootCF
				humanoidRoot.CFrame = delta * humanoidRoot.CFrame
				return
			end
		end

		lastRootCFrame = nil
		lastRootModel = nil
	end)
end

return PlatformStabilizer
