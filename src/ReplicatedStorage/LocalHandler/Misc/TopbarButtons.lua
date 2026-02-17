local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")

type IconSpec = {
	id: string,
	order: number,
	assetId: string,
	rectOffset: Vector2,
	rectSize: Vector2,
}

local ICONS: { IconSpec } = {
	{
		id = "Settings",
		order = 1,
		assetId = "rbxassetid://6764432408",
		rectOffset = Vector2.new(150, 850),
		rectSize = Vector2.new(50, 50),
	},
	{
		id = "Menu",
		order = 2,
		assetId = "rbxassetid://6764432408",
		rectOffset = Vector2.new(200, 350),
		rectSize = Vector2.new(50, 50),
	},
	{
		id = "Help",
		order = 3,
		assetId = "rbxassetid://6764432408",
		rectOffset = Vector2.new(100, 300),
		rectSize = Vector2.new(50, 50),
	},
}

local TopbarButtons = {}

local initialized = false
local initializing = false
local quickLeaving = false

local function waitForLoadedTag(player: Player): boolean
	while player.Parent == Players do
		if CollectionService:HasTag(player, "Loaded") then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function safeCall(target, methodName: string, ...): boolean
	local method = target and target[methodName]
	if typeof(method) ~= "function" then
		return false
	end

	local ok = pcall(method, target, ...)
	return ok
end

local function notify(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 3,
		})
	end)
end

local function applyIconSprite(iconObject, spec: IconSpec)
	local states = { "Deselected", "Selected", "Viewing", "Hovering" }
	for _, state in ipairs(states) do
		safeCall(iconObject, "setImage", spec.assetId, state)
		safeCall(iconObject, "setImageRectOffset", spec.rectOffset, state)
		safeCall(iconObject, "setImageRectSize", spec.rectSize, state)
		safeCall(iconObject, "setImageRect", spec.rectOffset, spec.rectSize, state)
	end

	safeCall(iconObject, "setImage", spec.assetId)
	safeCall(iconObject, "setImageRectOffset", spec.rectOffset)
	safeCall(iconObject, "setImageRectSize", spec.rectSize)
	safeCall(iconObject, "setImageRect", spec.rectOffset, spec.rectSize)

	local themeProps = {
		{ "Image", spec.assetId },
		{ "ImageRectOffset", spec.rectOffset },
		{ "ImageRectSize", spec.rectSize },
	}
	for _, prop in ipairs(themeProps) do
		safeCall(iconObject, "modifyTheme", { "Widget", "IconImage", prop[1] }, prop[2])
		safeCall(iconObject, "modifyTheme", { "Widget", prop[1] }, prop[2])
	end

	local function applyToInstance(inst: Instance)
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			pcall(function()
				inst.Image = spec.assetId
				inst.ImageRectOffset = spec.rectOffset
				inst.ImageRectSize = spec.rectSize
			end)
		end
	end

	local function applyViaGetInstance(instanceName: string)
		local getter = iconObject and iconObject.getInstance
		if typeof(getter) ~= "function" then
			return
		end
		local ok, inst = pcall(function()
			return getter(iconObject, instanceName)
		end)
		if ok and typeof(inst) == "Instance" then
			applyToInstance(inst)
			for _, child in ipairs(inst:GetDescendants()) do
				applyToInstance(child)
			end
		end
	end

	applyViaGetInstance("IconImage")
	applyViaGetInstance("IconButton")
	applyViaGetInstance("Widget")

	pcall(function()
		iconObject.imageRectOffset = spec.rectOffset
		iconObject.imageRectSize = spec.rectSize
	end)
end

local function configureIcon(iconObject, spec: IconSpec)
	safeCall(iconObject, "setLabel", "")
	safeCall(iconObject, "setCaption", "")
	safeCall(iconObject, "setTip", "")
	safeCall(iconObject, "setName", spec.id)
	safeCall(iconObject, "setOrder", spec.order)
	safeCall(iconObject, "setLeft")
	safeCall(iconObject, "align", "Left")
	safeCall(iconObject, "autoDeselect", true)
	applyIconSprite(iconObject, spec)

	-- TopBarPlus may build/rebuild widget instances asynchronously.
	task.spawn(function()
		for _ = 1, 12 do
			task.wait()
			applyIconSprite(iconObject, spec)
		end
	end)
end

local function bindPress(iconObject, callback: () -> ())
	local function wrapped()
		callback()
		safeCall(iconObject, "deselect")
	end

	if safeCall(iconObject, "bindEvent", "selected", wrapped) then
		return
	end

	local selectedSignal = iconObject and iconObject.selected
	if typeof(selectedSignal) == "RBXScriptSignal" then
		selectedSignal:Connect(wrapped)
	end
end

local function onSettingsPressed()
	notify("Settings", "Settings panel not connected yet.")
end

local function onQuickLeavePressed(player: Player)
	if quickLeaving then
		return
	end
	quickLeaving = true

	notify("Quick Leave", "Teleporting...")
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		quickLeaving = false
		warn("[TopbarButtons] Quick leave teleport failed:", err)
		notify("Quick Leave", "Teleport failed.")
	end
end

local function onHelpPressed()
	notify("Help", "Help panel not connected yet.")
end

function TopbarButtons.Init()
	if initialized or initializing then
		return
	end
	initializing = true

	local player = Players.LocalPlayer
	if not player then
		initializing = false
		return
	end

	local iconModule = ReplicatedStorage:WaitForChild("Icon")
	local ok, Icon = pcall(require, iconModule)
	if not ok then
		initializing = false
		warn("[TopbarButtons] Failed to require Icon module:", Icon)
		return
	end

	local handlers: { [string]: () -> () } = {
		Settings = onSettingsPressed,
		Menu = function()
			onQuickLeavePressed(player)
		end,
		Help = onHelpPressed,
	}

	if waitForLoadedTag(player) then
		for _, spec in ipairs(ICONS) do
			local iconObject = Icon.new()
			configureIcon(iconObject, spec)

			local handler = handlers[spec.id]
			if handler then
				bindPress(iconObject, handler)
			end
		end
		initialized = true
	end

	initializing = false
end

return TopbarButtons
