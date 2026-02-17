local SoundUtil = {}

local soundCache = {}

local function findNaturalSound(root, soundName)
	local cached = soundCache[soundName]
	if cached and cached.Parent then
		return cached
	end

	local assets = root:FindFirstChild("Assets")
	local soundRoot = assets and assets:FindFirstChild("sound")
	local natural = soundRoot and soundRoot:FindFirstChild("Natural")
	local sound = natural and natural:FindFirstChild(soundName)

	if sound and sound:IsA("Sound") then
		soundCache[soundName] = sound
		return sound
	end
end

function SoundUtil.PlayNatural(root, soundName, parent)
	local template = findNaturalSound(root, soundName)
	if not template then
		return
	end

	local s = template:Clone()
	s.Parent = parent or workspace
	s:Play()

	local speed = (s.PlaybackSpeed and s.PlaybackSpeed > 0) and s.PlaybackSpeed or 1
	local ttl = (s.TimeLength and s.TimeLength > 0) and ((s.TimeLength / speed) + 0.25) or 3

	task.delay(ttl, function()
		if s and s.Parent then
			s:Destroy()
		end
	end)

	return s
end

return SoundUtil
