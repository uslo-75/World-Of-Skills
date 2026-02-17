local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolEquipAnim = {}
ToolEquipAnim.__index = ToolEquipAnim

local function getFolderByPath(root: Instance, path: { string })
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

function ToolEquipAnim.new(deps)
	local self = setmetatable({}, ToolEquipAnim)

	self.Config = deps.Config
	self.AnimationHandler = deps.AnimationHandler

	self._cachedAnim = nil
	self._warnedMissing = false
	self._playing = false

	return self
end

function ToolEquipAnim:isPlaying()
	return self._playing
end

function ToolEquipAnim:stop(character: Model?)
	if not character then
		self._playing = false
		return
	end
	self.AnimationHandler.StopAnims(character, self.Config.AnimType)
	self._playing = false
end

function ToolEquipAnim:_resolveToolNoneAnimation(): Animation?
	local a = self._cachedAnim
	if a and a.Parent then
		return a
	end

	local folder = getFolderByPath(ReplicatedStorage, self.Config.AssetsPath)
	local anim = folder and folder:FindFirstChild(self.Config.ToolNoneAnimationName)

	if anim and anim:IsA("Animation") then
		self._cachedAnim = anim
		return anim
	end

	if not self._warnedMissing then
		self._warnedMissing = true
		warn(
			("[ToolEquipAnim] Missing animation: %s/%s"):format(
				table.concat(self.Config.AssetsPath, "/"),
				self.Config.ToolNoneAnimationName
			)
		)
	end

	return nil
end

function ToolEquipAnim:play(character: Model?)
	if not character then
		return false
	end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end

	local anim = self:_resolveToolNoneAnimation()
	if not anim then
		return false
	end

	self:stop(character)

	local track = self.AnimationHandler.LoadAnim(character, self.Config.AnimType, anim.AnimationId, nil, {
		replaceType = true,
		priority = self.Config.Priority,
		fadeTime = self.Config.FadeTime,
	})
	if not track then
		return false
	end

	track.Name = self.Config.TrackName
	self._playing = true
	return true
end

return ToolEquipAnim
