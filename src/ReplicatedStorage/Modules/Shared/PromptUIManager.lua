local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PromptUIManager = {}

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

function PromptUIManager.Init(config)
	if RunService:IsServer() then
		return
	end
	if config == nil then
		-- Auto-loaders call Init() without params; this module needs explicit UI refs.
		return
	end
	config = config or {}
	local player = config.player or Players.LocalPlayer
	local promptUI = config.root
	local template = config.template

	if not promptUI or not template then
		warn("[PromptUIManager] Init requires {root, template}")
		return
	end

	local templateShadow = template:WaitForChild("Shadow")

	local listFrame = promptUI:FindFirstChild("PromptList")
	if not listFrame then
		listFrame = Instance.new("Frame")
		listFrame.Name = "PromptList"
		listFrame.BackgroundTransparency = 1
		listFrame.Size = UDim2.new(template.Size.X.Scale, template.Size.X.Offset, 0, 0)
		listFrame.AutomaticSize = Enum.AutomaticSize.Y
		listFrame.AnchorPoint = template.AnchorPoint
		listFrame.Position = template.Position
		listFrame.ZIndex = template.ZIndex
		listFrame.Parent = promptUI
	end

	local listLayout = listFrame:FindFirstChildOfClass("UIListLayout") or promptUI:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Name = "UIListLayout"
	end
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = listFrame

	template.Visible = false

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local targetTextTransparency = template.TextTransparency
	local targetShadowTransparency = templateShadow.TextTransparency

	local activeHighlights = {}
	local activeEntries = {} -- [Prompt] = {label, shadow, adornee, conns, fadeOut, fadeOut2}
	local hiddenWatchers = {} -- [Prompt] = {conns}
	local orderCounter = 0

	local showPrompt

	local function nextOrder()
		orderCounter += 1
		return orderCounter
	end

	local function createHighlight(target)
		if not target or activeHighlights[target] then
			return
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "TempHighlight"
		highlight.Adornee = target.Parent
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = target.Parent
		activeHighlights[target] = highlight
	end

	local function removeHighlight(target)
		if not target then
			return
		end
		local existing = activeHighlights[target]
		if existing and existing:IsA("Highlight") then
			existing:Destroy()
		end
		activeHighlights[target] = nil
	end

	local function getPromptKey(prompt)
		local key = prompt.KeyboardKeyCode
		if key and key ~= Enum.KeyCode.Unknown then
			return key.Name
		end
		local gk = prompt.GamepadKeyCode
		if gk and gk ~= Enum.KeyCode.Unknown then
			return gk.Name
		end
		return "E"
	end

	local function formatPromptText(prompt)
		local key = getPromptKey(prompt)
		local action = (prompt.ActionText ~= "" and prompt.ActionText) or "Interact"
		local override = prompt:GetAttribute("PromptTextOverride")
		if typeof(override) == "string" and override ~= "" then
			action = override
		end
		local object = (prompt.ObjectText ~= "" and (" " .. prompt.ObjectText)) or ""
		return ("[%s - %s%s]"):format(key, action, object)
	end

	local function getUserId(value)
		if typeof(value) == "number" then
			return value
		end
		if typeof(value) == "string" then
			return tonumber(value)
		end
		return nil
	end

	local function isLocalDowned(): boolean
		local character = player.Character
		return character and character:GetAttribute("Downed") == true or false
	end

	local function shouldHidePrompt(prompt)
		if isLocalDowned() then
			return true
		end
		if prompt.Enabled == false then
			return true
		end
		if prompt:GetAttribute("HidePromptText") == true then
			local dontHide = prompt:GetAttribute("DontHidePromptForPlayer")
			local lockedId = getUserId(prompt:GetAttribute("PromptLockedByUserId"))
			if lockedId and lockedId == player.UserId and (dontHide == true or dontHide == prompt.Name) then
				-- allow show
			else
				return true
			end
		end

		if prompt:GetAttribute("OnePlayerUse") == true then
			local lockedId = getUserId(prompt:GetAttribute("PromptLockedByUserId"))
			if lockedId and lockedId ~= player.UserId then
				return true
			end
		end

		return false
	end

	local function cleanupHiddenWatcher(prompt)
		local entry = hiddenWatchers[prompt]
		if not entry then
			return
		end
		for _, c in ipairs(entry) do
			c:Disconnect()
		end
		hiddenWatchers[prompt] = nil
	end

	local function ensureHiddenWatcher(prompt)
		if hiddenWatchers[prompt] then
			return
		end
		local conns = {}
		local function tryShow()
			if not shouldHidePrompt(prompt) then
				cleanupHiddenWatcher(prompt)
				showPrompt(prompt)
			end
		end
		table.insert(conns, prompt:GetAttributeChangedSignal("HidePromptText"):Connect(tryShow))
		table.insert(conns, prompt:GetPropertyChangedSignal("Enabled"):Connect(tryShow))
		table.insert(conns, prompt:GetAttributeChangedSignal("PromptLockedByUserId"):Connect(tryShow))
		table.insert(conns, prompt:GetAttributeChangedSignal("OnePlayerUse"):Connect(tryShow))
		table.insert(conns, prompt:GetAttributeChangedSignal("DontHidePromptForPlayer"):Connect(tryShow))
		table.insert(
			conns,
			prompt:GetAttributeChangedSignal("PromptTextOverride"):Connect(function()
				if activeEntries[prompt] then
					activeEntries[prompt].label.Text = formatPromptText(prompt)
					if activeEntries[prompt].shadow then
						activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
					end
				else
					tryShow()
				end
			end)
		)
		table.insert(
			conns,
			prompt.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					cleanupHiddenWatcher(prompt)
				end
			end)
		)
		hiddenWatchers[prompt] = conns
	end

	local function cleanupEntry(prompt, immediate)
		local entry = activeEntries[prompt]
		if not entry then
			return
		end

		for _, c in ipairs(entry.conns) do
			c:Disconnect()
		end

		activeEntries[prompt] = nil
		removeHighlight(entry.adornee)

		if immediate then
			if entry.label then
				entry.label:Destroy()
			end
			return
		end

		if entry.fadeOut then
			entry.fadeOut:Play()
		end
		if entry.fadeOut2 then
			entry.fadeOut2:Play()
		end

		task.delay(0.3, function()
			if entry.label and entry.label.Parent then
				entry.label:Destroy()
			end
		end)
	end

	showPrompt = function(prompt)
		local character = player.Character
		if prompt.Parent and prompt.Parent.Parent == character then
			return
		end
		if shouldHidePrompt(prompt) then
			ensureHiddenWatcher(prompt)
			cleanupEntry(prompt, false)
			return
		end

		cleanupHiddenWatcher(prompt)

		local existing = activeEntries[prompt]
		if existing and existing.label then
			existing.label.Text = formatPromptText(prompt)
			if existing.shadow then
				existing.shadow.Text = existing.label.Text
			end
			return
		end

		local label = template:Clone()
		label.Name = "Prompt_" .. prompt.Name
		label.Parent = listFrame
		label.Visible = true
		label.LayoutOrder = nextOrder()

		local shadow = label:FindFirstChild("Shadow")
		label.Text = formatPromptText(prompt)
		if shadow then
			shadow.Text = label.Text
		end

		label.TextTransparency = 1
		if shadow then
			shadow.TextTransparency = 1
		end

		local fadeIn = TweenService:Create(label, tweenInfo, { TextTransparency = targetTextTransparency })
		local fadeOut = TweenService:Create(label, tweenInfo, { TextTransparency = 1 })
		local fadeIn2 = shadow
			and TweenService:Create(shadow, tweenInfo, { TextTransparency = targetShadowTransparency })
		local fadeOut2 = shadow and TweenService:Create(shadow, tweenInfo, { TextTransparency = 1 })

		fadeIn:Play()
		if fadeIn2 then
			fadeIn2:Play()
		end

		local adornee = prompt.Parent
		createHighlight(adornee)

		local conns = {}
		conns[1] = prompt.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				cleanupEntry(prompt, true)
			end
		end)
		conns[2] = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			if activeEntries[prompt] then
				activeEntries[prompt].label.Text = formatPromptText(prompt)
				if activeEntries[prompt].shadow then
					activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
				end
			end
		end)
		conns[3] = prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			if activeEntries[prompt] then
				activeEntries[prompt].label.Text = formatPromptText(prompt)
				if activeEntries[prompt].shadow then
					activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
				end
			end
		end)
		conns[4] = prompt:GetPropertyChangedSignal("KeyboardKeyCode"):Connect(function()
			if activeEntries[prompt] then
				activeEntries[prompt].label.Text = formatPromptText(prompt)
				if activeEntries[prompt].shadow then
					activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
				end
			end
		end)
		conns[5] = prompt:GetPropertyChangedSignal("GamepadKeyCode"):Connect(function()
			if activeEntries[prompt] then
				activeEntries[prompt].label.Text = formatPromptText(prompt)
				if activeEntries[prompt].shadow then
					activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
				end
			end
		end)
		conns[6] = prompt:GetAttributeChangedSignal("HidePromptText"):Connect(function()
			showPrompt(prompt)
		end)
		conns[7] = prompt:GetAttributeChangedSignal("PromptLockedByUserId"):Connect(function()
			showPrompt(prompt)
		end)
		conns[8] = prompt:GetAttributeChangedSignal("OnePlayerUse"):Connect(function()
			showPrompt(prompt)
		end)
		conns[9] = prompt:GetAttributeChangedSignal("DontHidePromptForPlayer"):Connect(function()
			showPrompt(prompt)
		end)
		conns[10] = prompt:GetAttributeChangedSignal("PromptTextOverride"):Connect(function()
			if activeEntries[prompt] then
				activeEntries[prompt].label.Text = formatPromptText(prompt)
				if activeEntries[prompt].shadow then
					activeEntries[prompt].shadow.Text = activeEntries[prompt].label.Text
				end
			else
				showPrompt(prompt)
			end
		end)

		activeEntries[prompt] = {
			label = label,
			shadow = shadow,
			adornee = adornee,
			conns = conns,
			fadeOut = fadeOut,
			fadeOut2 = fadeOut2,
		}
	end

	ProximityPromptService.PromptShown:Connect(function(prompt)
		showPrompt(prompt)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		cleanupEntry(prompt, false)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWho)
		if playerWho == player then
			task.defer(function()
				if prompt and prompt.Parent then
					showPrompt(prompt)
				end
			end)
		end
	end)

	local downConn: RBXScriptConnection? = nil
	local function refreshAllPrompts()
		for prompt in pairs(activeEntries) do
			showPrompt(prompt)
		end
		for prompt in pairs(hiddenWatchers) do
			showPrompt(prompt)
		end
	end
	local function bindDownWatcher(character: Model?)
		if downConn then
			downConn:Disconnect()
			downConn = nil
		end
		if not character then
			return
		end
		downConn = character:GetAttributeChangedSignal("Downed"):Connect(refreshAllPrompts)
		refreshAllPrompts()
	end

	bindDownWatcher(player.Character)
	player.CharacterAdded:Connect(bindDownWatcher)
end

return PromptUIManager
