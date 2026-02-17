local AnimUtil = {}

local folderCache = {}
local animCache = {}

local function getFolder(root, folderName)
	local key = tostring(root) .. "|" .. folderName
	local cached = folderCache[key]
	if cached and cached.Parent then
		return cached
	end

	local assets = root:FindFirstChild("Assets")
	local animRoot = assets and assets:FindFirstChild("animation")
	local combatRoot = animRoot and animRoot:FindFirstChild("combat")
	local folder = combatRoot and combatRoot:FindFirstChild(folderName)

	folderCache[key] = folder
	return folder
end

function AnimUtil.FindCombatAnimation(root, folderName, animName)
	if not root or not folderName or not animName then
		return
	end
	local cacheKey = tostring(root) .. "|" .. folderName .. "|" .. animName

	local cached = animCache[cacheKey]
	if cached and cached.Parent then
		return cached
	end

	local folder = getFolder(root, folderName)
	if not folder then
		return
	end

	local anim = folder:FindFirstChild(animName)
	if anim and anim:IsA("Animation") then
		animCache[cacheKey] = anim
		return anim
	end
end

function AnimUtil.LoadTrack(humanoid, animation, trackName)
	if not humanoid or not animation then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local track = animator:LoadAnimation(animation)
	if trackName then
		track.Name = trackName
	end
	return track
end

return AnimUtil
