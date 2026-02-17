local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventsBridge = {}

function EventsBridge.Init()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local mouse = player:GetMouse()

	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GetCF").OnClientInvoke = function(params)
		local fn = params and params.Fun
		if fn ~= "GetCF" then
			return nil
		end

		if params.Object == "Camera" then
			return camera.CFrame
		end
		if params.Object == "MousePos" then
			return mouse.Hit.Position
		end
		if params.Object and typeof(params.Object) == "Instance" and params.Object:IsA("BasePart") then
			return params.Object.CFrame
		end

		return nil
	end
end

return EventsBridge
