local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Snow = {}
Snow.__index = Snow

local RAYCAST_FRAME_UPDATE = 30
local BATCH_UPDATE_RAYCAST = 1
local RAYCAST_DISTANCE = 100

local EMITTER_HEIGHT_OFFSET = 60
local GRID_SIZE = 6
local TILE_SPACING = 78
local SHIFT_TRIGGER_CELLS = 2

local LEVEL_STEP = 62
local LEVEL_OFFSETS = { -2, -1, 0, 1 } -- 4 niveaux: 2 bas, niveau joueur, 1 haut

local GROUND_CAST_HEIGHT = 200
local GROUND_CAST_DISTANCE = 700
local HIDDEN_Y = -10000

local SIZE_RATIO_MIN = 0.6
local SIZE_RATIO_MAX = 1.8
local PLACEMENT_CHECK_SCALE = 0.9
local DEFAULT_AMBIENCE_FADE_TIME = 0.8

local GRID_CELL_OFFSETS = table.create(GRID_SIZE * GRID_SIZE)
do
	local half = math.floor(GRID_SIZE / 2)
	for offsetX = -half + 1, -half + GRID_SIZE do
		for offsetZ = -half + 1, -half + GRID_SIZE do
			table.insert(GRID_CELL_OFFSETS, {
				x = offsetX,
				z = offsetZ,
			})
		end
	end
end

local function getTemplatePart()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assets and assets:FindFirstChild("vfx")
	local ambiance = vfxFolder and vfxFolder:FindFirstChild("Ambiance")
	local snowFolder = ambiance and ambiance:FindFirstChild("SNOW")
	if not snowFolder then
		return nil
	end

	local template = snowFolder:FindFirstChild("Snow top")
	if template and template:IsA("BasePart") then
		return template
	end

	return nil
end

local function getWindSoundTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local soundFolder = assets and assets:FindFirstChild("sound")
	local naturalFolder = soundFolder and soundFolder:FindFirstChild("Natural")
	if not naturalFolder then
		return nil
	end

	local template = naturalFolder:FindFirstChild("Wind")
	if template and template:IsA("Sound") then
		return template
	end

	return nil
end

local function setPartPhysics(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function toCellCoord(value)
	return math.floor(value / TILE_SPACING + 0.5)
end

local function toWorldCoord(cell)
	return cell * TILE_SPACING
end

local function cellKey(cellX, cellZ)
	return string.format("%d:%d", cellX, cellZ)
end

local function placementKey(levelIndex, cellX, cellZ)
	return string.format("%d|%s", levelIndex, cellKey(cellX, cellZ))
end

local function getPlayerRoot()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return hrp, character, humanoid
end

local function getRotationOnly(cf)
	return CFrame.fromMatrix(Vector3.zero, cf.XVector, cf.YVector, cf.ZVector)
end

local function isSimilarSize(referenceSize, targetSize)
	if referenceSize.X <= 0 or referenceSize.Y <= 0 or referenceSize.Z <= 0 then
		return false
	end

	local ratioX = targetSize.X / referenceSize.X
	local ratioY = targetSize.Y / referenceSize.Y
	local ratioZ = targetSize.Z / referenceSize.Z

	return ratioX >= SIZE_RATIO_MIN
		and ratioX <= SIZE_RATIO_MAX
		and ratioY >= SIZE_RATIO_MIN
		and ratioY <= SIZE_RATIO_MAX
		and ratioZ >= SIZE_RATIO_MIN
		and ratioZ <= SIZE_RATIO_MAX
end

local function getTransitionTime(options, defaultValue)
	if type(options) ~= "table" then
		return defaultValue
	end

	local value = tonumber(options.transitionTime)
	if not value or value <= 0 then
		return defaultValue
	end

	return value
end

function Snow.new()
	local self = setmetatable({}, Snow)

	self._running = false
	self._connection = nil
	self._warnedMissingTemplate = false

	self._model = nil
	self._tiles = {}
	self._tileByPart = {}
	self._parts = {}
	self._activeTiles = {}

	self._placementToPart = {}
	self._partToPlacement = {}

	self._centerCellX = nil
	self._centerCellZ = nil
	self._centerLevelIndex = nil
	self._tileSize = nil

	self._raycastFrameUpdateCounter = 0
	self._raycastCursor = 1
	self._queryIgnore = {}
	self._queryDirty = true
	self._trackedCharacter = nil
	self._warnedMissingWindSound = false

	self._windSound = nil
	self._windTargetVolume = nil
	self._windTween = nil
	self._windTweenToken = 0

	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.FilterDescendantsInstances = self._queryIgnore
	self._raycastParams.RespectCanCollide = true
	self._raycastParams.IgnoreWater = false

	self._groundParams = RaycastParams.new()
	self._groundParams.FilterType = Enum.RaycastFilterType.Exclude
	self._groundParams.FilterDescendantsInstances = self._queryIgnore
	self._groundParams.RespectCanCollide = true
	self._groundParams.IgnoreWater = false

	self._overlapParams = OverlapParams.new()
	self._overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self._overlapParams.FilterDescendantsInstances = self._queryIgnore
	self._overlapParams.MaxParts = 8

	return self
end

function Snow:_cancelWindTween()
	if self._windTween then
		self._windTween:Cancel()
		self._windTween = nil
	end
end

function Snow:_getOrCreateWindSound()
	if self._windSound and self._windSound.Parent then
		return self._windSound
	end

	local template = getWindSoundTemplate()
	if not template then
		if not self._warnedMissingWindSound then
			self._warnedMissingWindSound = true
			warn("[DynamicAmbience:Snow] Sound manquant: ReplicatedStorage.Assets.sound.Natural.Wind")
		end
		return nil
	end

	local sound = template:Clone()
	self._windTargetVolume = template.Volume
	sound.Name = "DynamicSnowWind"
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService

	self._windSound = sound
	return sound
end

function Snow:_playWindAmbience(options)
	local sound = self:_getOrCreateWindSound()
	if not sound then
		return
	end

	local fadeTime = getTransitionTime(options, DEFAULT_AMBIENCE_FADE_TIME)
	local targetVolume = self._windTargetVolume or sound.Volume
	if targetVolume <= 0 then
		targetVolume = 0.35
	end

	self._windTweenToken += 1
	self:_cancelWindTween()

	if not sound.IsPlaying then
		sound:Play()
	end

	if fadeTime <= 0 then
		sound.Volume = targetVolume
		return
	end

	self._windTween = TweenService:Create(
		sound,
		TweenInfo.new(fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = targetVolume }
	)
	self._windTween:Play()
end

function Snow:_stopWindAmbience(options)
	local sound = self._windSound
	if not sound or not sound.Parent then
		return
	end

	local fadeTime = getTransitionTime(options, DEFAULT_AMBIENCE_FADE_TIME)
	self._windTweenToken += 1
	local token = self._windTweenToken

	self:_cancelWindTween()

	if fadeTime <= 0 then
		sound.Volume = 0
		sound:Stop()
		return
	end

	self._windTween = TweenService:Create(
		sound,
		TweenInfo.new(fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = 0 }
	)
	self._windTween:Play()

	task.delay(fadeTime, function()
		if self._windTweenToken ~= token then
			return
		end
		if sound.Parent and sound.Volume <= 0.001 then
			sound:Stop()
		end
	end)
end

function Snow:_updateQueryFilters(character, force)
	if not force and not self._queryDirty and self._trackedCharacter == character then
		return
	end

	table.clear(self._queryIgnore)

	for _, part in ipairs(self._parts) do
		table.insert(self._queryIgnore, part)
	end

	if self._model and self._model.PrimaryPart then
		table.insert(self._queryIgnore, self._model.PrimaryPart)
	end

	if character then
		table.insert(self._queryIgnore, character)
	end

	self._raycastParams.FilterDescendantsInstances = self._queryIgnore
	self._groundParams.FilterDescendantsInstances = self._queryIgnore
	self._overlapParams.FilterDescendantsInstances = self._queryIgnore
	self._trackedCharacter = character
	self._queryDirty = false
end

function Snow:_setTileActive(tile, active)
	if tile.emitterEnabled == active then
		return
	end

	tile.emitterEnabled = active
	if tile.emitter then
		tile.emitter.Enabled = active
	end
end

function Snow:_movePartHidden(part, rotation)
	part.CFrame = CFrame.new(0, HIDDEN_Y, 0) * rotation
end

function Snow:_disconnectRuntimeConnections()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function Snow:_restoreEmitterDefaults()
	for _, tile in ipairs(self._tiles) do
		if tile.emitter and tile.emitter.Parent then
			tile.emitter.Rate = tile.defaultRate or tile.emitter.Rate
			local isActive = self._partToPlacement[tile.part] ~= nil
			self:_setTileActive(tile, isActive)
		end
	end
end

function Snow:_destroyEmitter()
	self:_disconnectRuntimeConnections()

	if self._model then
		self._model:Destroy()
		self._model = nil
	end

	table.clear(self._tiles)
	table.clear(self._tileByPart)
	table.clear(self._parts)
	table.clear(self._activeTiles)
	table.clear(self._placementToPart)
	table.clear(self._partToPlacement)
	table.clear(self._queryIgnore)

	self._centerCellX = nil
	self._centerCellZ = nil
	self._centerLevelIndex = nil
	self._tileSize = nil
	self._raycastFrameUpdateCounter = 0
	self._raycastCursor = 1
	self._queryDirty = true
	self._trackedCharacter = nil
	self._running = false
end

function Snow:_stopNow(options)
	self:_stopWindAmbience(options)
	self._running = false
	self:_destroyEmitter()
end

function Snow:_createEmitter()
	if self._model and self._model.Parent then
		return true
	end

	local template = getTemplatePart()
	if not template then
		if not self._warnedMissingTemplate then
			self._warnedMissingTemplate = true
			warn("[DynamicAmbience:Snow] Template manquant: ReplicatedStorage.Assets.vfx.Ambiance.SNOW['Snow top']")
		end
		return false
	end

	self._tileSize = template.Size

	local model = Instance.new("Model")
	model.Name = "SnowEmitter"
	model.Parent = Workspace

	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Size = Vector3.new(1, 1, 1)
	rootPart.Transparency = 1
	setPartPhysics(rootPart)
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	local targetCount = GRID_SIZE * GRID_SIZE * #LEVEL_OFFSETS
	for index = 1, targetCount do
		local tilePart = template:Clone()
		tilePart.Name = string.format("Tile_%d", index)
		setPartPhysics(tilePart)
		tilePart.Parent = model

		local tile = {
			part = tilePart,
			rotation = getRotationOnly(tilePart.CFrame),
			emitter = tilePart:FindFirstChildWhichIsA("ParticleEmitter", true),
			defaultRate = nil,
			emitterEnabled = false,
		}
		if tile.emitter then
			tile.defaultRate = tile.emitter.Rate
		end

		self:_setTileActive(tile, false)
		self:_movePartHidden(tilePart, tile.rotation)

		table.insert(self._tiles, tile)
		table.insert(self._parts, tilePart)
		self._tileByPart[tilePart] = tile
	end

	self._model = model
	self._queryDirty = true
	return true
end

function Snow:_getGroundY(worldX, worldZ, fallbackY)
	local castOrigin = Vector3.new(worldX, fallbackY + GROUND_CAST_HEIGHT, worldZ)
	local castDirection = Vector3.new(0, -GROUND_CAST_DISTANCE, 0)
	local result = Workspace:Raycast(castOrigin, castDirection, self._groundParams)
	if result then
		return result.Position.Y
	end

	return fallbackY
end

function Snow:_getPlayerLevelIndex(hrp, humanoid)
	-- In air we keep the current level to avoid jump-triggered level swaps.
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air and self._centerLevelIndex ~= nil then
		return self._centerLevelIndex
	end

	return math.floor(hrp.Position.Y / LEVEL_STEP + 0.5)
end

function Snow:_isPlacementBlocked(worldX, worldY, worldZ)
	if not self._tileSize then
		return false
	end

	local querySize = Vector3.new(
		self._tileSize.X * PLACEMENT_CHECK_SCALE,
		self._tileSize.Y * PLACEMENT_CHECK_SCALE,
		self._tileSize.Z * PLACEMENT_CHECK_SCALE
	)

	local hits = Workspace:GetPartBoundsInBox(CFrame.new(worldX, worldY, worldZ), querySize, self._overlapParams)
	for _, hit in ipairs(hits) do
		if
			hit:IsA("BasePart")
			and hit.CanCollide
			and hit.Transparency < 0.98
			and isSimilarSize(self._tileSize, hit.Size)
		then
			return true
		end
	end

	return false
end

function Snow:_buildDesiredPlacements(centerCellX, centerCellZ, centerLevelIndex)
	local placements = {}

	for _, levelOffset in ipairs(LEVEL_OFFSETS) do
		local levelIndex = centerLevelIndex + levelOffset
		local levelY = levelIndex * LEVEL_STEP + EMITTER_HEIGHT_OFFSET

		for _, offset in ipairs(GRID_CELL_OFFSETS) do
			local cellX = centerCellX + offset.x
			local cellZ = centerCellZ + offset.z
			local worldX = toWorldCoord(cellX)
			local worldZ = toWorldCoord(cellZ)

			if not self:_isPlacementBlocked(worldX, levelY, worldZ) then
				table.insert(placements, {
					key = placementKey(levelIndex, cellX, cellZ),
					x = worldX,
					y = levelY,
					z = worldZ,
				})
			end
		end
	end

	return placements
end

function Snow:_assignPartToPlacement(part, placement)
	local tile = self._tileByPart[part]
	if not tile then
		return
	end

	local oldPlacement = self._partToPlacement[part]
	if oldPlacement then
		self._placementToPart[oldPlacement] = nil
	end

	part.CFrame = CFrame.new(placement.x, placement.y, placement.z) * tile.rotation
	self._partToPlacement[part] = placement.key
	self._placementToPart[placement.key] = part
	self:_setTileActive(tile, true)
end

function Snow:_setPartInactive(part)
	local tile = self._tileByPart[part]
	if not tile then
		return
	end

	local oldPlacement = self._partToPlacement[part]
	if oldPlacement then
		self._placementToPart[oldPlacement] = nil
		self._partToPlacement[part] = nil
	end

	self:_setTileActive(tile, false)
	self:_movePartHidden(part, tile.rotation)
end

function Snow:_rebuildActiveTiles()
	table.clear(self._activeTiles)
	for _, tile in ipairs(self._tiles) do
		local isActive = self._partToPlacement[tile.part] ~= nil
		self:_setTileActive(tile, isActive)
		if isActive then
			table.insert(self._activeTiles, tile)
		end
	end

	if self._raycastCursor > #self._activeTiles then
		self._raycastCursor = 1
	end
end

function Snow:_applyPlacements(placements)
	local desiredMap = {}
	local missingPlacements = {}

	for _, placement in ipairs(placements) do
		desiredMap[placement.key] = placement
		if not self._placementToPart[placement.key] then
			table.insert(missingPlacements, placement)
		end
	end

	local extraParts = {}
	local keysToRemove = {}
	for key, part in pairs(self._placementToPart) do
		if not desiredMap[key] then
			table.insert(extraParts, part)
			table.insert(keysToRemove, key)
		end
	end

	for _, key in ipairs(keysToRemove) do
		self._placementToPart[key] = nil
	end

	local freeParts = {}
	for _, tile in ipairs(self._tiles) do
		if not self._partToPlacement[tile.part] then
			table.insert(freeParts, tile.part)
		end
	end

	local function popReusablePart()
		if #extraParts > 0 then
			return table.remove(extraParts)
		end
		if #freeParts > 0 then
			return table.remove(freeParts)
		end
		return nil
	end

	for _, placement in ipairs(missingPlacements) do
		local part = popReusablePart()
		if not part then
			break
		end
		self:_assignPartToPlacement(part, placement)
	end

	for _, part in ipairs(extraParts) do
		self:_setPartInactive(part)
	end

	for _, part in ipairs(freeParts) do
		self:_setPartInactive(part)
	end

	self:_rebuildActiveTiles()
end

function Snow:_refreshGridForCenter(centerCellX, centerCellZ, centerLevelIndex)
	local placements = self:_buildDesiredPlacements(centerCellX, centerCellZ, centerLevelIndex)
	self:_applyPlacements(placements)

	self._centerCellX = centerCellX
	self._centerCellZ = centerCellZ
	self._centerLevelIndex = centerLevelIndex
end

function Snow:_updateCenterFromPlayer(hrp, humanoid)
	local playerCellX = toCellCoord(hrp.Position.X)
	local playerCellZ = toCellCoord(hrp.Position.Z)
	local playerLevelIndex = self:_getPlayerLevelIndex(hrp, humanoid)

	if self._centerCellX == nil or self._centerCellZ == nil or self._centerLevelIndex == nil then
		self:_refreshGridForCenter(playerCellX, playerCellZ, playerLevelIndex)
		return
	end

	local deltaX = playerCellX - self._centerCellX
	local deltaZ = playerCellZ - self._centerCellZ
	local shiftX = 0
	local shiftZ = 0

	if deltaX >= SHIFT_TRIGGER_CELLS then
		shiftX = deltaX - (SHIFT_TRIGGER_CELLS - 1)
	elseif deltaX <= -SHIFT_TRIGGER_CELLS then
		shiftX = deltaX + (SHIFT_TRIGGER_CELLS - 1)
	end

	if deltaZ >= SHIFT_TRIGGER_CELLS then
		shiftZ = deltaZ - (SHIFT_TRIGGER_CELLS - 1)
	elseif deltaZ <= -SHIFT_TRIGGER_CELLS then
		shiftZ = deltaZ + (SHIFT_TRIGGER_CELLS - 1)
	end

	local needRefresh = false
	local newCenterX = self._centerCellX
	local newCenterZ = self._centerCellZ
	local newLevelIndex = self._centerLevelIndex

	if shiftX ~= 0 then
		newCenterX += shiftX
		needRefresh = true
	end
	if shiftZ ~= 0 then
		newCenterZ += shiftZ
		needRefresh = true
	end
	if playerLevelIndex ~= self._centerLevelIndex then
		newLevelIndex = playerLevelIndex
		needRefresh = true
	end

	if needRefresh then
		self:_refreshGridForCenter(newCenterX, newCenterZ, newLevelIndex)
	end
end

function Snow:_updateRaycastBatch()
	self._raycastFrameUpdateCounter += 1
	if self._raycastFrameUpdateCounter < RAYCAST_FRAME_UPDATE then
		return
	end
	self._raycastFrameUpdateCounter = 0

	local tileCount = #self._activeTiles
	if tileCount <= 0 then
		return
	end

	local updates = math.min(BATCH_UPDATE_RAYCAST, tileCount)
	for _ = 1, updates do
		if self._raycastCursor > tileCount then
			self._raycastCursor = 1
		end

		local tile = self._activeTiles[self._raycastCursor]
		self._raycastCursor += 1

		if tile and tile.part and tile.part.Parent and tile.emitter and tile.emitter.Parent then
			local raycastResult =
				Workspace:Raycast(tile.part.Position, Vector3.new(0, -RAYCAST_DISTANCE, 0), self._raycastParams)
			if raycastResult and raycastResult.Position then
				local speedMax = tile.emitter.Speed.Max
				if speedMax > 0 then
					local lifeTime = (raycastResult.Position - tile.part.Position).Magnitude / speedMax
					local minLife = math.max(lifeTime - 5, 0.05)
					local maxLife = math.max(lifeTime, minLife)
					tile.emitter.Lifetime = NumberRange.new(minLife, maxLife)
				end
			end
		end
	end
end

function Snow:Start(options)
	if self == nil or self == Snow then
		-- Called by generic loader without instance context; ignore.
		return
	end

	self:_playWindAmbience(options)

	if self._running then
		return
	end
	self:_disconnectRuntimeConnections()

	if not self:_createEmitter() then
		return
	end

	local hrp, character, humanoid = getPlayerRoot()
	self:_updateQueryFilters(character, true)
	if hrp then
		self:_updateCenterFromPlayer(hrp, humanoid)
	end

	self:_restoreEmitterDefaults()
	self._running = true
	self._connection = RunService.RenderStepped:Connect(function()
		local hrp, character, humanoid = getPlayerRoot()
		if not hrp then
			return
		end

		self:_updateQueryFilters(character, false)
		self:_updateCenterFromPlayer(hrp, humanoid)
		self:_updateRaycastBatch()
	end)
end

function Snow:Stop(options)
	if self == nil or self == Snow then
		return
	end

	self:_stopNow(options)
end

return Snow
