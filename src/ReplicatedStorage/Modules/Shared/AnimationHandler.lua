local Players = game:GetService("Players")

local module = {}

module.Anims = setmetatable({}, { __mode = "k" })

local PROTECTED_TYPES = {
	Idle = true,
	Walk = true,
}

local PROTECTED_TRACK_NAMES = {
	Idle = true,
	Walk = true,
}

local function isProtectedType(typeKey: string?): boolean
	return typeKey ~= nil and PROTECTED_TYPES[typeKey] == true
end

local function isProtectedTrackName(track: AnimationTrack?): boolean
	return track ~= nil and PROTECTED_TRACK_NAMES[track.Name] == true
end

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator
end

local function normalizeAnimId(animId: any): string?
	if typeof(animId) == "number" then
		return ("rbxassetid://%d"):format(animId)
	elseif typeof(animId) == "string" then
		if animId:match("^rbxassetid://") then
			return animId
		elseif animId:match("^%d+$") then
			return "rbxassetid://" .. animId
		end
	end
	return nil
end

local function ensureCharEntry(char: Model)
	module.Anims[char] = module.Anims[char] or {}

	if not module.Anims[char].__autoCleanupHooked then
		module.Anims[char].__autoCleanupHooked = true

		char.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				module.StopAnims(char, "AllIncludingProtected")
				module.Anims[char] = nil
			end
		end)
	end
end

function module.LoadAnim(
	char: Model,
	_type: string,
	animId: any,
	keyframeCallback: ((string) -> ())?,
	opts: {
		replaceType: boolean?,
		reuseTrack: boolean?,
		fadeTime: number?,
		priority: Enum.AnimationPriority?,
	}?
)
	if not char or not _type then
		return
	end
	animId = normalizeAnimId(animId)
	if not animId then
		return
	end

	local animator = getAnimator(char)
	if not animator then
		return
	end

	ensureCharEntry(char)

	opts = opts or {}
	local replaceType = opts.replaceType == true
	local reuseTrack = opts.reuseTrack == true
	local fadeTime = opts.fadeTime
	local priority = opts.priority

	local charBucket = module.Anims[char]
	if not charBucket then
		-- Defensive: character might have been cleaned up between threads
		ensureCharEntry(char)
		charBucket = module.Anims[char]
		if not charBucket then
			return
		end
	end

	charBucket[_type] = charBucket[_type] or {}
	local typeBucket = charBucket[_type]

	if replaceType then
		for id in pairs(typeBucket) do
			if id ~= animId then
				module.RemoveAnim(char, _type, id, true) -- includeProtected = true
			end
		end
	end

	-- reuse existing track if requested
	local existing = typeBucket[animId]
	if reuseTrack and existing and existing.Track then
		if priority then
			existing.Track.Priority = priority
		end
		if fadeTime ~= nil then
			existing.Track:Play(fadeTime)
		else
			existing.Track:Play()
		end
		return existing.Track
	end

	-- stop previous same key if exists
	if existing then
		module.RemoveAnim(char, _type, animId, true) -- includeProtected = true
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = animator:LoadAnimation(animation)
	animation:Destroy()

	local connections = {}
	local cleaning = false

	if keyframeCallback then
		table.insert(
			connections,
			track.KeyframeReached:Connect(function(name)
				keyframeCallback(name)
			end)
		)
	end

	table.insert(
		connections,
		track.Stopped:Connect(function()
			if cleaning then
				return
			end
			module.RemoveAnim(char, _type, animId, true)
		end)
	)

	typeBucket[animId] = {
		Track = track,
		Connections = connections,
		_Cleaning = function()
			cleaning = true
		end,
	}

	if priority then
		track.Priority = priority
	end
	if fadeTime ~= nil then
		track:Play(fadeTime)
	else
		track:Play()
	end
	return track
end

function module.GetAnims(char: Model, animType: string?)
	if not module.Anims[char] then
		return {}
	end
	if animType then
		return module.Anims[char][animType] or {}
	end
	return module.Anims[char]
end

function module.IsAnim(char: Model, _type: string, animId: any): boolean
	animId = normalizeAnimId(animId)
	if not animId then
		return false
	end
	local entry = module.Anims[char] and module.Anims[char][_type] and module.Anims[char][_type][animId]
	return (entry and entry.Track and entry.Track.IsPlaying) == true
end

function module.RemoveAnim(char: Model, _type: string, animId: any, includeProtected: boolean?)
	animId = normalizeAnimId(animId)
	if not animId then
		return
	end
	includeProtected = includeProtected == true

	local charBucket = module.Anims[char]
	local typeBucket = charBucket and charBucket[_type]
	local animData = typeBucket and typeBucket[animId]
	if not animData then
		return
	end

	if not includeProtected then
		if isProtectedType(_type) then
			return
		end
		if animData.Track and isProtectedTrackName(animData.Track) then
			return
		end
	end

	if animData._Cleaning then
		animData._Cleaning()
	end

	if animData.Connections then
		for _, connection in ipairs(animData.Connections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
	end

	if animData.Track then
		pcall(function()
			animData.Track:Stop()
		end)
		pcall(function()
			animData.Track:Destroy()
		end)
	end

	typeBucket[animId] = nil

	if next(typeBucket) == nil then
		charBucket[_type] = nil
	end

	local onlyMetaLeft = true
	for k, _ in pairs(charBucket) do
		if k ~= "__autoCleanupHooked" then
			onlyMetaLeft = false
			break
		end
	end
	if onlyMetaLeft then
		module.Anims[char] = nil
	end
end

function module.StopAnims(char: Model, modeOrType: string, animId: any?)
	local charBucket = module.Anims[char]
	if not charBucket then
		return
	end

	local includeProtected = false
	local _type = modeOrType

	if modeOrType == "TrueAll" or modeOrType == "AllIncludingProtected" then
		_type = "AllIncludingProtected"
		includeProtected = true
	elseif modeOrType == "All" then
		_type = "All"
		includeProtected = false
	end

	local function tryRemove(typeKey: string, id: any)
		local animIdNorm = normalizeAnimId(id)
		if not animIdNorm then
			return
		end
		module.RemoveAnim(char, typeKey, animIdNorm, includeProtected)
	end

	if _type == "All" or _type == "AllIncludingProtected" then
		for typeKey, anims in pairs(charBucket) do
			if typeKey ~= "__autoCleanupHooked" then
				for id in pairs(anims) do
					tryRemove(typeKey, id)
				end
			end
		end
		return
	end

	if animId then
		tryRemove(_type, animId)
	else
		local typeBucket = charBucket[_type]
		if not typeBucket then
			return
		end
		for id in pairs(typeBucket) do
			tryRemove(_type, id)
		end
	end
end

------------------------
-- AnimationTracks
------------------------

local function shouldStopTrack(
	track: AnimationTrack,
	protectedNames: { [string]: boolean }?,
	includeProtected: boolean?
): boolean
	if includeProtected then
		return true
	end
	if protectedNames and protectedNames[track.Name] == true then
		return false
	end
	return true
end

function module.StopTracks(animatorOrHumanoid: Instance, fadeTime: number?, includeProtected: boolean?)
	fadeTime = fadeTime or 0.15
	includeProtected = includeProtected == true

	local tracks = animatorOrHumanoid:GetPlayingAnimationTracks()
	for _, t in ipairs(tracks) do
		if shouldStopTrack(t, PROTECTED_TRACK_NAMES, includeProtected) then
			t:Stop(fadeTime)
		end
	end
end

function module.StopTracksInstant(animatorOrHumanoid: Instance, includeProtected: boolean?)
	includeProtected = includeProtected == true
	local tracks = animatorOrHumanoid:GetPlayingAnimationTracks()
	for _, t in ipairs(tracks) do
		if shouldStopTrack(t, PROTECTED_TRACK_NAMES, includeProtected) then
			t:Stop(0)
		end
	end
end

function module.StopTracksAll(animatorOrHumanoid: Instance)
	local tracks = animatorOrHumanoid:GetPlayingAnimationTracks()
	for _, t in ipairs(tracks) do
		t:Stop(0)
	end
end

function module.StopSpecificTrack(animatorOrHumanoid: Instance, name: string, fadeTime: number?)
	fadeTime = fadeTime or 0.45
	local tracks = animatorOrHumanoid:GetPlayingAnimationTracks()
	for _, t in ipairs(tracks) do
		if t.Name == name then
			t:Stop(fadeTime)
		end
	end
end

Players.PlayerRemoving:Connect(function(plr)
	local char = plr.Character
	if char then
		module.StopAnims(char, "AllIncludingProtected")
		module.Anims[char] = nil
	end
end)

return module
