local SoundUtil = {}

local soundCache = {}

local function dedupeNames(names: { string }): { string }
	local result = {}
	local seen = {}
	for _, name in ipairs(names) do
		if typeof(name) ~= "string" or name == "" then
			continue
		end
		if not seen[name] then
			seen[name] = true
			table.insert(result, name)
		end
	end
	return result
end

local function asNameList(value: any): { string }
	if typeof(value) == "string" then
		if value == "" then
			return {}
		end
		return { value }
	end

	if typeof(value) == "table" then
		local list = {}
		for _, entry in ipairs(value) do
			if typeof(entry) == "string" and entry ~= "" then
				table.insert(list, entry)
			end
		end
		return dedupeNames(list)
	end

	return {}
end

local function getSoundRoot(root: Instance): Instance?
	local assets = root:FindFirstChild("Assets")
	local assetsSound = assets and assets:FindFirstChild("sound")
	if assetsSound then
		return assetsSound
	end

	return root:FindFirstChild("sound")
end

local function findNaturalSound(root, soundName)
	local cacheKey = "Natural::" .. tostring(soundName)
	local cached = soundCache[cacheKey]
	if cached and cached.Parent then
		return cached
	end

	local soundRoot = getSoundRoot(root)
	local natural = soundRoot and soundRoot:FindFirstChild("Natural")
	local sound = natural and natural:FindFirstChild(soundName)

	if sound and sound:IsA("Sound") then
		soundCache[cacheKey] = sound
		return sound
	end
end

local function findSoundCaseInsensitive(folder: Instance?, targetName: string): Sound?
	if not folder or targetName == "" then
		return nil
	end

	local direct = folder:FindFirstChild(targetName)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local lower = string.lower(targetName)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Sound") and string.lower(child.Name) == lower then
			return child
		end
	end

	return nil
end

local function findToolFolder(root: Instance, weaponNameOrList: any): Folder?
	local weaponNames = asNameList(weaponNameOrList)
	if #weaponNames == 0 then
		return nil
	end

	local soundRoot = getSoundRoot(root)
	local tools = soundRoot and soundRoot:FindFirstChild("Tools")
	if not tools then
		return nil
	end

	for _, weaponName in ipairs(weaponNames) do
		local folder = tools:FindFirstChild(weaponName)
		if folder and folder:IsA("Folder") then
			return folder
		end
	end

	return nil
end

local function findToolSound(root: Instance, weaponNameOrList: any, soundNameOrList: any): Sound?
	local weaponNames = asNameList(weaponNameOrList)
	local soundNames = asNameList(soundNameOrList)
	if #weaponNames == 0 or #soundNames == 0 then
		return nil
	end

	local toolFolder = findToolFolder(root, weaponNames)
	if not toolFolder then
		return nil
	end

	local found = {}
	for _, soundName in ipairs(soundNames) do
		local sound = findSoundCaseInsensitive(toolFolder, soundName)
		if sound then
			table.insert(found, sound)
		end
	end

	if #found == 0 then
		return nil
	end

	return found[math.random(1, #found)]
end

local function playTemplate(template: Sound?, parent: Instance?): Sound?
	if not template then
		return nil
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

function SoundUtil.PlayNatural(root, soundName, parent)
	local template = findNaturalSound(root, soundName)
	return playTemplate(template, parent)
end

function SoundUtil.PlayTool(root: Instance, weaponNameOrList: any, soundNameOrList: any, parent: Instance?)
	local template = findToolSound(root, weaponNameOrList, soundNameOrList)
	return playTemplate(template, parent)
end

return SoundUtil
