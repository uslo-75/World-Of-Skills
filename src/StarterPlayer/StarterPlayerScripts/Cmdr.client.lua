local ReplicatedStorage = game:GetService("ReplicatedStorage")

local cmdrClientModule = ReplicatedStorage:WaitForChild("CmdrClient", 10)
if not cmdrClientModule then
	warn("[CmdrSetup] CmdrClient not found in ReplicatedStorage.")
	return
end

local okClient, CmdrClient = pcall(require, cmdrClientModule)
if not okClient then
	warn("[CmdrSetup] Failed to require CmdrClient:", CmdrClient)
	return
end

CmdrClient:SetActivationKeys({
	Enum.KeyCode.F2,
})

CmdrClient:SetPlaceName(game.Name)
