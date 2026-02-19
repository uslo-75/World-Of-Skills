local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local AnimationHandler = require(RS:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("AnimationHandler"))

local CarryVisual = {}

local active: { [BasePart]: { carrier: BasePart, offset: CFrame } } = {}
local pending: {
	[BasePart]: { carrier: BasePart, offset: CFrame, animId: string?, conns: { RBXScriptConnection } },
} =
	{}
local animTargets: { [BasePart]: Model } = {}
local updaterConn: RBXScriptConnection? = nil

local CARRY_ANIM_TYPE = "CarryVisual"
local CARRY_TRACK_NAME = "Carried"

local function disconnectAll(conns: { RBXScriptConnection }?)
	if not conns then
		return
	end
	for _, c in ipairs(conns) do
		if c and c.Connected then
			c:Disconnect()
		end
	end
end

local function stopUpdaterIfIdle()
	if next(active) ~= nil then
		return
	end

	if updaterConn then
		updaterConn:Disconnect()
		updaterConn = nil
	end
end

local function ensureUpdater()
	if updaterConn then
		return
	end

	updaterConn = RunService.RenderStepped:Connect(function()
		for targetHrp, state in pairs(active) do
			local carrierHrp = state.carrier
			if not carrierHrp or not carrierHrp.Parent or not targetHrp.Parent then
				CarryVisual.Stop(targetHrp)
				continue
			end

			targetHrp.CFrame = carrierHrp.CFrame * state.offset
			targetHrp.AssemblyLinearVelocity = carrierHrp.AssemblyLinearVelocity
			targetHrp.AssemblyAngularVelocity = carrierHrp.AssemblyAngularVelocity
		end
	end)
end

local function playCarryAnim(targetHrp: BasePart, animId: string?)
	if typeof(animId) ~= "string" or animId == "" then
		return
	end
	local targetChar = targetHrp.Parent
	if not targetChar or not targetChar:IsA("Model") then
		return
	end
	animTargets[targetHrp] = targetChar
	local track = AnimationHandler.LoadAnim(targetChar, CARRY_ANIM_TYPE, animId, nil, {
		replaceType = true,
		priority = Enum.AnimationPriority.Action,
	})
	if track then
		track.Name = CARRY_TRACK_NAME
	end
end

function CarryVisual.Start(carrierHrp: BasePart, targetHrp: BasePart, offset: CFrame?, animId: string?)
	if not carrierHrp or not targetHrp then
		return
	end
	CarryVisual.Stop(targetHrp)

	local useOffset = (typeof(offset) == "CFrame") and offset or CFrame.new()

	if not carrierHrp.Parent or not targetHrp.Parent then
		local conns = {}
		local function tryStart()
			if carrierHrp.Parent and targetHrp.Parent then
				disconnectAll(conns)
				pending[targetHrp] = nil
				CarryVisual.Start(carrierHrp, targetHrp, useOffset, animId)
			end
		end
		table.insert(conns, carrierHrp.AncestryChanged:Connect(tryStart))
		table.insert(conns, targetHrp.AncestryChanged:Connect(tryStart))
		pending[targetHrp] = { carrier = carrierHrp, offset = useOffset, animId = animId, conns = conns }
		return
	end

	playCarryAnim(targetHrp, animId)

	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.Character and targetHrp:IsDescendantOf(localPlayer.Character) then
		return
	end

	active[targetHrp] = {
		carrier = carrierHrp,
		offset = useOffset,
	}
	ensureUpdater()
end

function CarryVisual.Stop(targetHrp: BasePart)
	if targetHrp then
		active[targetHrp] = nil
	end
	local pend = targetHrp and pending[targetHrp]
	if pend then
		disconnectAll(pend.conns)
		pending[targetHrp] = nil
	end

	local targetChar = targetHrp and animTargets[targetHrp]
	if targetChar then
		AnimationHandler.StopAnims(targetChar, CARRY_ANIM_TYPE)
		animTargets[targetHrp] = nil
	end

	stopUpdaterIfIdle()
end

return CarryVisual
