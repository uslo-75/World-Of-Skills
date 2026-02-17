local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldDropVisuals = {}

local TAG_NAME = "WorldDropVisual"
local ROTATE_SPEED = math.rad(75)
local BOB_SPEED = 2.4
local BOB_HEIGHT = 0.08
local HIGHLIGHT_MAX_DISTANCE = 50

local tracked: {
	[BasePart]: {
		baseCFrame: CFrame,
		time: number,
		seed: number,
		highlight: Highlight?,
	},
} =
	{}

local function findDropHighlight(part: BasePart): Highlight?
	local model = part.Parent
	if not model or not model:IsA("Model") then
		return nil
	end
	local highlight = model:FindFirstChild("DropHighlight")
	if highlight and highlight:IsA("Highlight") then
		return highlight
	end
	return nil
end

local function track(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	if tracked[part] then
		return
	end

	tracked[part] = {
		baseCFrame = part.CFrame,
		time = 0,
		seed = math.random() * math.pi * 2,
		highlight = findDropHighlight(part),
	}
end

local function untrack(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	tracked[part] = nil
end

local function onStep(dt: number)
	local camera = Workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position or nil

	for part, state in pairs(tracked) do
		if not part.Parent then
			tracked[part] = nil
			continue
		end

		state.time += dt
		local bobY = math.sin((state.time * BOB_SPEED) + state.seed) * BOB_HEIGHT
		local yaw = state.time * ROTATE_SPEED

		part.CFrame = state.baseCFrame * CFrame.new(0, bobY, 0) * CFrame.Angles(0, yaw, 0)

		if state.highlight == nil or not state.highlight.Parent then
			state.highlight = findDropHighlight(part)
		end

		if state.highlight and cameraPosition then
			local isVisible = (part.Position - cameraPosition).Magnitude <= HIGHLIGHT_MAX_DISTANCE
			if state.highlight.Enabled ~= isVisible then
				state.highlight.Enabled = isVisible
			end
		end
	end
end

function WorldDropVisuals.Init()
	if WorldDropVisuals._initialized then
		return
	end
	WorldDropVisuals._initialized = true

	for _, inst in ipairs(CollectionService:GetTagged(TAG_NAME)) do
		track(inst)
	end

	CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(untrack)
	RunService.RenderStepped:Connect(onStep)
end

return WorldDropVisuals
