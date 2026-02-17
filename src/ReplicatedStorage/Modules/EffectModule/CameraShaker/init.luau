--!nocheck
local RunService = game:GetService("RunService")

local CameraShaker = {}
CameraShaker.__index = CameraShaker

local profileBegin = debug.profilebegin
local profileEnd = debug.profileend

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local RAD = math.rad
local V3One = Vector3.one
local CFZero = CFrame.new()
local V3Zero = Vector3.zero

local CameraShakeInstance = require(script.CameraShakeInstance)
local CameraShakeState = CameraShakeInstance.CameraShakeState

local defaultPosInfluence = V3(0.15, 0.15, 0.15)

CameraShaker.CameraShakeInstance = CameraShakeInstance
CameraShaker.Presets = require(script.CameraShakePresets)

function CameraShaker.new(renderPriority, callback)
	assert(type(renderPriority) == "number", "RenderPriority must be a number (e.g.: Enum.RenderPriority.Camera.Value)")
	assert(type(callback) == "function", "Callback must be a function")

	local self = setmetatable({
		_running = false,
		_renderName = "CameraShaker" .. tostring(os.clock()),
		_renderPriority = renderPriority,
		_posAddShake = Vector3.zero,
		_rotAddShake = Vector3.zero,
		_camShakeInstances = {},
		_removeInstances = {},
		_callback = callback,
	}, CameraShaker)

	return self
end

function CameraShaker:Start()
	if self._running then
		return
	end
	self._running = true

	RunService:BindToRenderStep(self._renderName, self._renderPriority, function(dt)
		profileBegin("CameraShakerUpdate")

		local cf = self:Update(dt)
		if cf == CFZero then
			return self:Stop()
		end

		profileEnd()
		self._callback(cf)
	end)
end

function CameraShaker:Stop()
	if not self._running then
		return
	end

	RunService:UnbindFromRenderStep(self._renderName)
	self._running = false
end

function CameraShaker:StopSustained(duration)
	for _, c in pairs(self._camShakeInstances) do
		if c.fadeOutDuration == 0 then
			c:StartFadeOut(duration or c.fadeInDuration)
		end
	end
end

function CameraShaker:Update(dt)
	local posAddShake = V3Zero

	local instances = self._camShakeInstances

	-- Update all instances:
	for i = 1, #instances do
		local c = instances[i]
		local state = c:GetState()

		c.Elapsed += dt

		if c.Elapsed < c.Lifetime then
			if state == CameraShakeState.Inactive and c.DeleteOnInactive then
				self._removeInstances[#self._removeInstances + 1] = i
			elseif state ~= CameraShakeState.Inactive then
				posAddShake = c:UpdateShake(dt) * c.PositionInfluence
			end
		else
			self._removeInstances[#self._removeInstances + 1] = i
		end
	end

	-- Remove dead instances:
	for i = #self._removeInstances, 1, -1 do
		local instIndex = self._removeInstances[i]
		table.remove(instances, instIndex)
		self._removeInstances[i] = nil
	end

	return CF(posAddShake) * ANG(0, 0, 0)
end

function CameraShaker:EndCameraShake()
	for i = 1, #self._camShakeInstances do
		self._removeInstances[#self._removeInstances + 1] = i
	end
end

function CameraShaker:Shake(shakeInstance)
	assert(
		type(shakeInstance) == "table" and shakeInstance._camShakeInstance,
		"ShakeInstance must be of type CameraShakeInstance"
	)
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	return shakeInstance
end

function CameraShaker:ShakeSustain(shakeInstance)
	assert(
		type(shakeInstance) == "table" and shakeInstance._camShakeInstance,
		"ShakeInstance must be of type CameraShakeInstance"
	)
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	shakeInstance:StartFadeIn(shakeInstance.fadeInDuration)
	return shakeInstance
end

function CameraShaker:ShakeOnce(magnitude, roughness, fadeInTime, fadeOutTime, posInfluence, rotInfluence)
	local shakeInstance = CameraShakeInstance.new(magnitude, roughness, fadeInTime, fadeOutTime)
	shakeInstance.PositionInfluence = typeof(posInfluence) == "Vector3" and posInfluence or defaultPosInfluence
	shakeInstance.RotationInfluence = typeof(rotInfluence) == "Vector3" and rotInfluence or V3One
	shakeInstance.Lifetime = fadeInTime + fadeOutTime
	shakeInstance.Elapsed = 0
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance

	return shakeInstance
end

function CameraShaker:StartShake(magnitude, roughness, fadeInTime, posInfluence, rotInfluence)
	local shakeInstance = CameraShakeInstance.new(magnitude, roughness, fadeInTime)
	shakeInstance.PositionInfluence = typeof(posInfluence) == "Vector3" and posInfluence or defaultPosInfluence
	shakeInstance.RotationInfluence = typeof(rotInfluence) == "Vector3" and rotInfluence or V3One
	shakeInstance:StartFadeIn(fadeInTime)
	self._camShakeInstances[#self._camShakeInstances + 1] = shakeInstance
	return shakeInstance
end

return CameraShaker
