local Players = game:GetService("Players")

local RagdollClient = {}

local player = Players.LocalPlayer
local characterAddedConn: RBXScriptConnection? = nil
local ragdollAttrConn: RBXScriptConnection? = nil
local diedConn: RBXScriptConnection? = nil

local function disconnect(conn: RBXScriptConnection?)
	if conn then
		conn:Disconnect()
	end
end

local function getTorso(character: Model): BasePart?
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso and upperTorso:IsA("BasePart") then
		return upperTorso
	end

	return nil
end

local function bindCharacter(character: Model)
	disconnect(ragdollAttrConn)
	ragdollAttrConn = nil
	disconnect(diedConn)
	diedConn = nil

	local torso = getTorso(character)
	local humanoid = character:WaitForChild("Humanoid")

	ragdollAttrConn = character:GetAttributeChangedSignal("IsRagdoll"):Connect(function()
		local isRagdoll = character:GetAttribute("IsRagdoll")
		if isRagdoll and torso then
			humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			torso:ApplyImpulse(torso.CFrame.LookVector * 75)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)

	diedConn = humanoid.Died:Connect(function()
		if torso then
			torso:ApplyImpulse(torso.CFrame.LookVector * 100)
		end
	end)
end

function RagdollClient.Init()
	disconnect(characterAddedConn)
	characterAddedConn = nil

	if player.Character then
		bindCharacter(player.Character)
	end

	characterAddedConn = player.CharacterAdded:Connect(bindCharacter)
end

return RagdollClient
