local module = {}

function module.Init(context)
	if context == nil then
		return
	end

	local script = context and context.script or error("missing script context")
	local root = context and context.root or script.Parent
	if not game:IsLoaded() then game.Loaded:Wait() end
	
	if not game:IsLoaded() then game.Loaded:Wait() end
	
	local RS = game:GetService("ReplicatedStorage")
	local uis = game:GetService("UserInputService")
	local TS = game:GetService("TweenService")
	local RunService = game:GetService("RunService")
	local ContentProvider = game:GetService("ContentProvider")
	local CollectionService = game:GetService("CollectionService")
	
	-- Events
	local CooldownRetriever = RS:WaitForChild("Remotes"):WaitForChild("CooldownRetriever")
	local GetWeaponInfo = RS:WaitForChild("Remotes"):WaitForChild("GetWeaponInfo")
	local MainRemote = RS:WaitForChild("Remotes"):WaitForChild("Main")
	
	-- Player
	local player = game.Players.LocalPlayer
	
	local bootstrapCharacter = player.Character or player.CharacterAdded:Wait()
	repeat task.wait() until bootstrapCharacter:GetAttribute("CustomizationLoaded") == true
	
	local char = workspace:FindFirstChild("Live") and workspace.Live:FindFirstChild(player.Name) or bootstrapCharacter
	local bp = player:WaitForChild("Backpack")
	local hum = char:WaitForChild("Humanoid")
	
	local StatsFolder = player:WaitForChild("Stats")
	local AttributesFolder = player:WaitForChild("Attributes")
	
	-- UI
	local uiParent = script.Parent
	local HotBar = uiParent.hotbars  -- hotbar frame
	local template = script:FindFirstChild("Template")
	local selectedTemplate = script:FindFirstChild("Selected")
	local InventoryUI = uiParent:WaitForChild("Inventory")
	local Inventory = InventoryUI:WaitForChild("ScrollingFrame")
	local Capacity = InventoryUI:WaitForChild("ProfilePreviewFrame"):WaitForChild("CarryTip"):WaitForChild("Amount")
	local MaxCapacity = InventoryUI:WaitForChild("ProfilePreviewFrame"):WaitForChild("CarryTip"):WaitForChild("Capacity")
	local SearchBar = InventoryUI:WaitForChild("Search")
	local ToolTip = uiParent:WaitForChild("ToolTip")
	local AddingList = uiParent:WaitForChild("Notifications")
	local AddingTemplate = script:WaitForChild("NotificationTemplate")
	local MoneyUI = uiParent:WaitForChild("MoneyUI")
	
	local Healthbars = uiParent:WaitForChild("Healthbars")
	local BarsRoot = Healthbars:WaitForChild("Bar")
	local HealthFrame = BarsRoot:WaitForChild("Health")
	local PostureFrame = BarsRoot:WaitForChild("Posture")
	local EtherFrame = BarsRoot:WaitForChild("Stamina")
	
	local function getTopBarByName(parentFrame, barName)
		local best = nil
		for _, child in ipairs(parentFrame:GetChildren()) do
			if child:IsA("ImageLabel") and child.Name == barName then
				if not best or child.ZIndex > best.ZIndex then
					best = child
				end
			end
		end
		return best
	end
	
	local HealthFill = HealthFrame:WaitForChild("Bar")
	local PostureFill = PostureFrame:WaitForChild("Bar")
	local EtherFill = getTopBarByName(EtherFrame, "bar") or EtherFrame:WaitForChild("bar")
	local LifesLabel = HealthFrame:WaitForChild("Border"):FindFirstChild("Lifes")
	
	if LifesLabel then
		LifesLabel.Text = "3"
	end
	
	-- Initial state
	local isUIVisible = false
	local toolSlotLookup = {}
	local tooltipConnections = {}
	local draggedItems = {}
	local guiSlots = {}
	local knownTools = {}
	local properties = {
		prevToolTip = 0,
	}
	
	-- settings
	local blockNewToolDetection = false
	local mouseDownTime = 0
	local mouseDragging = false
	local clickedSlot = nil
	local dragThreshold = 0.1
	local stackedNotifications = {}
	local NOTIF_DURATION = 3
	
	-- Drag-and-drop variables
	local draggedItem = nil
	local originalParent = nil
	local dragPreview
	local originalSlot
	local dragging = false
	
	-- variables
	HotBar.Visible = true
	
	local healthFillBaseSize = HealthFill.Size
	local postureFillBaseSize = PostureFill.Size
	local etherFillBaseSize = EtherFill.Size
	local BAR_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local activeBarTweens = {}
	
	local function toSafeRatio(currentValue, maxValue)
		local maxNumeric = tonumber(maxValue) or 0
		if maxNumeric <= 0 then
			return 0
		end
		return math.clamp((tonumber(currentValue) or 0) / maxNumeric, 0, 1)
	end
	
	local function setBarFill(fillBar, baseSize, ratio)
		if not fillBar then
			return
		end
	
		local targetSize = UDim2.new(
			baseSize.X.Scale * ratio,
			math.floor((baseSize.X.Offset * ratio) + 0.5),
			baseSize.Y.Scale,
			baseSize.Y.Offset
		)
	
		if fillBar.Size == targetSize then
			return
		end
	
		local runningTween = activeBarTweens[fillBar]
		if runningTween then
			runningTween:Cancel()
			activeBarTweens[fillBar] = nil
		end
	
		local tween = TS:Create(fillBar, BAR_TWEEN_INFO, { Size = targetSize })
		activeBarTweens[fillBar] = tween
		tween.Completed:Connect(function()
			if activeBarTweens[fillBar] == tween then
				activeBarTweens[fillBar] = nil
			end
		end)
		tween:Play()
	end
	
	local function getNumberValue(folder, valueName)
		local valueObject = folder and folder:FindFirstChild(valueName)
		if valueObject and valueObject:IsA("NumberValue") then
			return valueObject
		end
		return nil
	end
	
	local function updateHealthBar()
		local currentHealth = hum and hum.Health or 0
		local maxHealth = hum and hum.MaxHealth or 0
		local ratio = toSafeRatio(currentHealth, maxHealth)
	
		setBarFill(HealthFill, healthFillBaseSize, ratio)
	end
	
	local function updateEtherBar()
		local etherValue = getNumberValue(AttributesFolder, "Ether")
		local maxEtherValue = getNumberValue(AttributesFolder, "MaxEther")
		local ratio = toSafeRatio(etherValue and etherValue.Value, maxEtherValue and maxEtherValue.Value)
	
		setBarFill(EtherFill, etherFillBaseSize, ratio)
	end
	
	local function updatePostureBar()
		local postureValue = getNumberValue(AttributesFolder, "Posture")
		local maxPostureValue = getNumberValue(AttributesFolder, "MaxPosture")
		local ratio = toSafeRatio(postureValue and postureValue.Value, maxPostureValue and maxPostureValue.Value)
	
		setBarFill(PostureFill, postureFillBaseSize, ratio)
	end
	
	local function updateAllStatusBars()
		updateHealthBar()
		updateEtherBar()
		updatePostureBar()
	end
	
	local function bindResourceValue(resourceName, callback)
		local valueObject = getNumberValue(AttributesFolder, resourceName)
		if valueObject then
			valueObject.Changed:Connect(callback)
		end
	end
	
	local function bindStatusBars()
		if hum then
			hum.HealthChanged:Connect(updateHealthBar)
			hum:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealthBar)
		end
	
		bindResourceValue("Ether", updateEtherBar)
		bindResourceValue("MaxEther", updateEtherBar)
		bindResourceValue("Posture", updatePostureBar)
		bindResourceValue("MaxPosture", updatePostureBar)
	
		AttributesFolder.ChildAdded:Connect(function(child)
			if not child:IsA("NumberValue") then
				return
			end
	
			if child.Name == "Ether" or child.Name == "MaxEther" then
				child.Changed:Connect(updateEtherBar)
				updateEtherBar()
			elseif child.Name == "Posture" or child.Name == "MaxPosture" then
				child.Changed:Connect(updatePostureBar)
				updatePostureBar()
			end
		end)
	
		AttributesFolder.ChildRemoved:Connect(function(child)
			if not child:IsA("NumberValue") then
				return
			end
			if child.Name == "Ether" or child.Name == "MaxEther" then
				updateEtherBar()
			elseif child.Name == "Posture" or child.Name == "MaxPosture" then
				updatePostureBar()
			end
		end)
	end
	
	local function formatRubiText(rawValue)
		local rubiAmount = tonumber(rawValue) or 0
		rubiAmount = math.max(0, math.floor(rubiAmount + 0.5))
		return "- " .. tostring(rubiAmount)
	end
	
	local function bindMoneyUI()
		local cacData = player:WaitForChild("CACData")
		local rubiValue = cacData:WaitForChild("Rubi")
	
		local function updateMoneyUI()
			local value = 0
			if rubiValue and (rubiValue:IsA("NumberValue") or rubiValue:IsA("IntValue")) then
				value = rubiValue.Value
			end
			MoneyUI.Text = formatRubiText(value)
		end
	
		updateMoneyUI()
		rubiValue.Changed:Connect(updateMoneyUI)
	end
	
	local viewportCamera = Instance.new("Camera")
	viewportCamera.CFrame = CFrame.new()
	viewportCamera.FieldOfView = 18
	viewportCamera.Parent = InventoryUI.ItemPreviewFrame.Viewport
	InventoryUI.ItemPreviewFrame.Viewport.CurrentCamera = viewportCamera
	
	-- Keys
	local inputKeys = {
		One = { txt = "1" },
		Two = { txt = "2" },
		Three = { txt = "3" },
		Four = { txt = "4" },
		Five = { txt = "5" },
		Six = { txt = "6" },
		Seven = { txt = "7" },
		Eight = { txt = "8" },
		Nine = { txt = "9" },
	}
	local inputOrder = {
		inputKeys.One, inputKeys.Two, inputKeys.Three, inputKeys.Four,
		inputKeys.Five, inputKeys.Six, inputKeys.Seven, inputKeys.Eight,
		inputKeys.Nine,
	}
	local toolTypeImages = {
		Attack = "rbxassetid://116409748515875",
		Ability = "rbxassetid://116409748515875",
		Tools  = "rbxassetid://116409748515875",
	}
	local toolTypeColors = {
		Ability = Color3.fromRGB(123, 156, 200),
		--
		Epic = Color3.fromRGB(134, 82, 231),
		Rare = Color3.fromRGB(123, 156, 200),
		Common  = Color3.fromRGB(220, 183, 135),
	}
	local toolTypeColors2 = {
		Ability = Color3.fromRGB(157, 199, 255),
		--
		Epic = Color3.fromRGB(94, 59, 165),
		Rare = Color3.fromRGB(57, 81, 112),
		Common  = Color3.fromRGB(159, 133, 98),
	}
	
	----------------------------------------------------------
	-- Fonctions d'optimisation pour le drag-and-drop
	----------------------------------------------------------
	
	local function ToggleAvailableSlot(toggle)
		if toggle then
			for _, slot in ipairs(HotBar:GetChildren()) do
				if slot:IsA("ImageButton") and slot.Name ~= "Template" then
					slot.Visible = true
				end
			end
		else
			for _, slot in ipairs(HotBar:GetChildren()) do
				if slot:IsA("ImageButton") and slot.Name ~= "Template" and slot:FindFirstChild("Selected") then
					slot.Visible = true
				elseif slot:IsA("ImageButton") and slot.Name ~= "Template" and not slot:FindFirstChild("Selected") then
					slot.Visible = false
				end
			end
		end
	end
	
	local function getDropArea(mousePosition)
		local pos, size = InventoryUI.AbsolutePosition, InventoryUI.AbsoluteSize
		return mousePosition.X > pos.X and mousePosition.X < (pos.X + size.X) and
			mousePosition.Y > pos.Y and mousePosition.Y < (pos.Y + size.Y)
	end
	
	local function findFirstAvailableSlot(mousePosition)
		local closestSlot = nil
		local closestDistance = math.huge
		local isSlotOccupied = false
	
		for _, slot in ipairs(HotBar:GetChildren()) do
			if slot:IsA("ImageButton") and slot.Name ~= "Template" then
				local center = slot.AbsolutePosition + slot.AbsoluteSize / 2
				local distance = (mousePosition - center).Magnitude
	
				if distance < closestDistance then
					closestDistance = distance
					closestSlot = slot
					isSlotOccupied = slot:FindFirstChild("Selected") ~= nil
				end
			end
		end
	
		return closestSlot, isSlotOccupied
	end
	
	local function setZRecursive(guiObject, z)
		guiObject.ZIndex = z
		for _, child in ipairs(guiObject:GetChildren()) do
			if child:IsA("GuiObject") then
				setZRecursive(child, z + 1)
			end
		end
	end
	
	local function setSlotVisualHidden(slot)
		slot.BackgroundTransparency = 1
		local imgLabel = slot:FindFirstChild("ImageLabel")
		if imgLabel then imgLabel.ImageTransparency = 1 end
		local toolName = slot:FindFirstChild("ToolName")
		if toolName then toolName.TextTransparency = 1 end
		local quantity = slot:FindFirstChild("Quantity")
		if quantity then
			quantity.TextTransparency = 1
			quantity.BackgroundTransparency = 1
			local icon = quantity:FindFirstChild("ImageLabel")
			if icon then icon.ImageTransparency = 1 end
		end
	end
	
	local function restoreSlotVisual(slot)
		slot.BackgroundTransparency = 0
		local imgLabel = slot:FindFirstChild("ImageLabel")
		if imgLabel then imgLabel.ImageTransparency = 0 end
		local toolName = slot:FindFirstChild("ToolName")
		if toolName then toolName.TextTransparency = 0 end
		local quantity = slot:FindFirstChild("Quantity")
		if quantity then
			quantity.TextTransparency = 0
			quantity.BackgroundTransparency = 0
			local icon = quantity:FindFirstChild("ImageLabel")
			if icon then icon.ImageTransparency = 0 end
		end
	end
	
	local function onDragStarted(item)
		if dragging or not item then
			return
		end
		dragging = true
		originalSlot = item
	
		dragPreview = item:Clone()
		dragPreview.Parent = uiParent
		dragPreview.AnchorPoint = Vector2.new(0.5, 0.5)
	
		local function getDragPreviewPosition()
			local m = uis:GetMouseLocation()
			local inset = game:GetService("GuiService"):GetGuiInset()
			local absSize = dragPreview.AbsoluteSize
			return UDim2.new(0, m.X  + inset.X, 0, m.Y - inset.Y)
		end
	
		dragPreview.Position = getDragPreviewPosition()
		dragPreview.ZIndex = 50
		setZRecursive(dragPreview, 50)
	
		if item:IsA("ImageButton") then
			setSlotVisualHidden(item)
		end
	
		local conn
		conn = uis.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				dragPreview.Position = getDragPreviewPosition()
			elseif not dragging then
				if conn then conn:Disconnect() end
			end
		end)
	end
	
	local function onDragStopped(mousePosition)
		if not dragging then
			return
		end
		dragging = false
	
		local mousePos = uis:GetMouseLocation()
		local dropArea    = getDropArea(mousePos)
		local closestSlot, isSlotOccupied = findFirstAvailableSlot(mousePos)
		
		local targetParent, targetPos
		if dropArea then
			targetParent = Inventory
			targetPos = UDim2.new(0.5, 0, 0.5, 0)
		elseif closestSlot and isSlotOccupied then
			local occupyingSlot = closestSlot:FindFirstChild("Selected")
			
			if occupyingSlot then
				targetParent = occupyingSlot.Parent
				targetPos = UDim2.new(0.5, 0, 0.5, 0)
				
				occupyingSlot.Parent = originalSlot.Parent
			end
		elseif closestSlot and not isSlotOccupied  then
			targetParent = closestSlot
			targetPos = UDim2.new(0.5, 0, 0.5, 0)
		else
			targetParent = originalSlot.Parent
			targetPos = originalSlot.Position
		end
	
		originalSlot.Parent = targetParent
		originalSlot.Position = targetPos
		
		if originalSlot:IsA("ImageButton") then
			restoreSlotVisual(originalSlot)
		end
	
		if dragPreview then
			dragPreview:Destroy()
			dragPreview = nil
		end
		originalSlot = nil
	end
	
	----------------------------------------------------------
	-- Gestion de l'équipement et de la configuration des slots
	----------------------------------------------------------
	
	local function onNewItemDiscovered(tool)
		local toolName = tool:GetAttribute("Name")
		local toolType = tool:GetAttribute("Type")
		local toolRarity = tool:GetAttribute("Rarity")
	
		if not toolName then return end
	
		local baseColor = toolTypeColors[toolRarity]
		local bgColor = toolTypeColors2[toolRarity]
	
		if stackedNotifications[toolName] then
			local notif = stackedNotifications[toolName]
			notif.count += 1
			notif.label.Text = "> " .. toolName .. " x" .. notif.count
	
			notif.timeout = tick()
		else
			local addClone = AddingTemplate:Clone()
			addClone.Parent = AddingList
			addClone.TextLabel.Text = "> " .. toolName .. " x1"
			if baseColor then
				addClone.TextLabel.TextColor3 = baseColor
			end
			if bgColor then
				addClone.ImageLabel.ImageColor3 = bgColor
			end
	
			stackedNotifications[toolName] = {
				count = 1,
				label = addClone.TextLabel,
				ui = addClone,
				timeout = tick()
			}
		end
	end
	
	local function disconnectTooltipConnections(slot)
		if tooltipConnections[slot] then
			for _, conn in pairs(tooltipConnections[slot]) do
				if conn and typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
			tooltipConnections[slot] = nil
		end
	end
	
	local function showTooltip(tool, guiSlot)
		if not tool or dragging then return end
	
		-- Texte du tooltip
		local typeAttr = tool:GetAttribute("Type") or "UNKNOWN"
		local typeDisplay = ({
			Attack = "Weapon",
			Tools = "Materials",
			Equip = "Equipment"
		})[typeAttr] or string.upper(typeAttr)
	
		ToolTip.AnchorPoint = Vector2.new(0, 0)
		ToolTip.NameLabel.Text = tool:GetAttribute("Name") or "Unnamed"
		ToolTip.TypeLabel.Text = typeDisplay
	
		local statText = ""
	
		-- Si c'est une arme, utiliser WeaponInfo
		if typeAttr == "Attack" then
			local weaponInfo = RS.Remotes.GetWeaponInfo:InvokeServer("Weapon", tool.Name)
			if weaponInfo then
				local Description = weaponInfo.Description
				local damage = weaponInfo.Damage or "?"
				local swingSpeed = weaponInfo.SwingSpeed or "?"
				local range = weaponInfo.Range or "?"
				statText = string.format("- Damage : %s\n- SwingSpeed : %s\n- Range : %s", damage, swingSpeed, range)
				ToolTip.TipLabel.Text = Description or "No description"
			else
				statText = "No weapon stats available"
				ToolTip.TipLabel.Text = tool:GetAttribute("Description") or "No description"
			end
		elseif typeAttr == "Equip" then
			local weaponInfo = RS.Remotes.GetWeaponInfo:InvokeServer("Equipment", tool.Name)
			if weaponInfo then
				local Description = weaponInfo.Description
				local ItemStat = tool:GetAttribute("Stats") or ""
				statText = ItemStat
				ToolTip.TipLabel.Text = Description or "No description"
			else
				statText = "No weapon stats available"
				ToolTip.TipLabel.Text = tool:GetAttribute("Description") or "No description"
			end
		else
			statText = tool:GetAttribute("Stats") or ""
			ToolTip.TipLabel.Text = tool:GetAttribute("Description") or "No description"
		end
	
		ToolTip.StatLabel.Text = statText
	
		-- Position dynamique selon parent
		local absPos = guiSlot.AbsolutePosition
		local absSize = guiSlot.AbsoluteSize
		local parentName = guiSlot.Parent and guiSlot.Parent.Name or ""
	
		local x, y
		if not dragging then
			if parentName == "ScrollingFrame" then -- inventaire
				ToolTip.AnchorPoint = Vector2.new(0.5, 0.5)
				x = absPos.X + absSize.X + 100
				y = absPos.Y + absSize.Y / 2
			else -- hotbar
				ToolTip.AnchorPoint = Vector2.new(0.5, 1)
				x = absPos.X + absSize.X / 2
				y = absPos.Y - 5
			end
		end
	
		local originalHandle = tool
		if originalHandle then
			local handle: BasePart = originalHandle:clone()
			handle.Parent = InventoryUI.ItemPreviewFrame.Viewport
			handle:PivotTo(CFrame.new(0, 0, -8.5))
			InventoryUI.ItemPreviewFrame.Visible = true
	
			viewportCamera.CameraSubject = handle
			viewportCamera.FieldOfView = 18
	
			local accumulated = 0
			local connection = nil
			connection = RunService.RenderStepped:connect(function(deltaTime)
				if (not handle or not handle.Parent) or (handle and (viewportCamera.CameraSubject ~= handle)) then
					connection:Disconnect()
					connection = nil
				else
					accumulated += deltaTime
					handle:PivotTo(CFrame.new(Vector3.new(0, 0, -8.5)) * CFrame.Angles(0, accumulated*3, 0))
					--print(handle:GetPivot())
				end
			end)
		end
	
		ToolTip.Position = UDim2.new(0, x, 0, y)
		ToolTip.Visible = true
	end
	
	local function hideTooltip()
		ToolTip.Visible = false
		InventoryUI.ItemPreviewFrame.Visible = false
		InventoryUI.ItemPreviewFrame.Viewport:ClearAllChildren()
	end
	
	local function updateCapacity()
		local itemCount = 0
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") then
				itemCount = itemCount + 1
			end
		end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				itemCount = itemCount + 1
			end
		end
		Capacity.Text = tostring(itemCount)
		MaxCapacity.Text = StatsFolder:WaitForChild("MaxCapacity").Value
	end
	
	local function handleEquip(tool)
		local stunned = char:GetAttribute('Stunned')
		local attacking = char:GetAttribute('Attacking')
		local swing = char:GetAttribute('Swing')
		local blocking = char:GetAttribute('isBlocking')
		local dashing = char:GetAttribute('Dashing')
	
		if tool and tool.Parent ~= char and not (stunned or attacking or swing or blocking or dashing) then
			if tool:GetAttribute('Type') == 'Ability' then
				local currentCooldowns = CooldownRetriever:InvokeServer()
				local abilityCooldown = tool:GetAttribute('HotbarCooldown')
	
				if currentCooldowns[player.Name] and currentCooldowns[player.Name][tool.Name] and (tick() - currentCooldowns[player.Name][tool.Name] >= abilityCooldown) then
					hum:EquipTool(tool)
				elseif not currentCooldowns[player.Name] or not currentCooldowns[player.Name][tool.Name] then
					hum:EquipTool(tool)
				end
			else
				hum:EquipTool(tool)
			end
		elseif not (stunned or attacking or swing or blocking or dashing) then
			hum:UnequipTools()
		end
	end
	
	local function setupSlot(clone, tool, parent)
		if not clone then warn("setupSlot: 'clone' est nil") return end
	
		disconnectTooltipConnections(clone)
	
		clone.Parent = parent
		if tool then
			clone.Visible = true
			clone.ImageTransparency = 0
		else
			clone.ImageTransparency = 1
			clone.Visible = false
		end
		clone.Active = true
		clone.AutoButtonColor = false
	
		-- Infos du tool
		local toolName = clone:FindFirstChild("ToolName")
		local currentTool = clone:FindFirstChild("CurrentTool")
		local quantity = clone:FindFirstChild("Quantity")
		local imageLabel = clone:FindFirstChild("ImageLabel")
	
		if tool then
			if toolName then toolName.Text = tool:GetAttribute("Name") or "-" end
			if currentTool then currentTool.Value = tool end
			local toolType = tool:GetAttribute("Type")
			local toolRarity = tool:GetAttribute("Rarity")
			clone.Image = toolTypeImages[toolType] or ""
	
			if quantity and imageLabel then
				local baseColor = toolTypeColors[toolRarity]
				local bgColor = toolTypeColors2[toolRarity]
	
				if baseColor then
					quantity.BackgroundColor3 = baseColor
					imageLabel.ImageColor3 = baseColor
				end
	
				if bgColor then
					clone.BackgroundColor3 = bgColor
				end
				clone.ImageTransparency = 1
				quantity.Text = "x1"
			end
	
			-- Nouveau système : clic court ou drag long
			clone.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					hideTooltip()
					clickedSlot = tool
					mouseDownTime = tick()
					mouseDragging = true
					draggedItem = clone
	
					task.delay(dragThreshold, function()
						if mouseDragging and draggedItem == clone and isUIVisible then
							onDragStarted(clone)
						end
					end)
				end
			end)
		end
	
		draggedItems[clone] = { originalParent = parent, tool = tool }
		if tool then
			toolSlotLookup[tool] = clone
		end
	
		tooltipConnections[clone] = {
			clone.MouseEnter:Connect(function()
				if tick() - properties.prevToolTip < 0.15 and isUIVisible then
					if not dragging then
						showTooltip(tool, clone)
					end
				else
					if not dragging and isUIVisible then
						showTooltip(tool, clone)
					end
				end
				properties.prevToolTip = tick()
			end),
			clone.MouseLeave:Connect(hideTooltip)
		}
	end
	
	local function isToolInHotbar(toolName)
		for _, slot in ipairs(HotBar:GetChildren()) do
			if slot:IsA("ImageButton") and slot.Name ~= "Template" then
				local selected = slot:FindFirstChild("Selected")
				if selected then
					local currentTool = selected:FindFirstChild("CurrentTool")
					if currentTool and currentTool.Value then
						local name = currentTool.Value:GetAttribute("Name")
						if name == toolName then
							return true
						end
					end
				end
			end
		end
		return false
	end
	
	local function getHotbarSelectedByToolName(toolName)
		for _, slot in ipairs(HotBar:GetChildren()) do
			if slot:IsA("ImageButton") and slot.Name ~= "Template" then
				local selected = slot:FindFirstChild("Selected")
				if selected then
					local currentTool = selected:FindFirstChild("CurrentTool")
					if currentTool and currentTool.Value then
						local currentName = currentTool.Value:GetAttribute("Name")
						if currentName == toolName then
							return selected
						end
					end
				end
			end
		end
		return nil
	end
	
	local function findReplacementToolForHotbar(removedTool)
		if not removedTool then
			return nil
		end
	
		local removedName = removedTool:GetAttribute("Name") or removedTool.Name
		if typeof(removedName) ~= "string" or removedName == "" then
			return nil
		end
	
		local removedType = removedTool:GetAttribute("Type")
		local removedStats = removedTool:GetAttribute("Stats")
		local removedEnchant = removedTool:GetAttribute("Enchant")
		local fallback = nil
	
		local function scan(container)
			if not container then
				return nil
			end
	
			for _, candidate in ipairs(container:GetChildren()) do
				if candidate:IsA("Tool") and candidate ~= removedTool then
					local candidateName = candidate:GetAttribute("Name") or candidate.Name
					if candidateName == removedName then
						if fallback == nil then
							fallback = candidate
						end
	
						if candidate:GetAttribute("Type") == removedType
							and candidate:GetAttribute("Stats") == removedStats
							and candidate:GetAttribute("Enchant") == removedEnchant then
							return candidate
						end
					end
				end
			end
	
			return nil
		end
	
		local exact = scan(bp)
		if exact then
			return exact
		end
	
		exact = scan(char)
		if exact then
			return exact
		end
	
		return fallback
	end
	
	local function cleanupSlot(tool)
		local toolName = tool:GetAttribute("Name") or tool.Name
		local slot = toolSlotLookup[tool]
		if slot then
			local slotParent = slot.Parent
			local isHotbarSlot = slotParent and slotParent:IsA("ImageButton") and slotParent.Parent == HotBar
	
			if isHotbarSlot and selectedTemplate then
				local replacement = findReplacementToolForHotbar(tool)
				if replacement then
					disconnectTooltipConnections(slot)
					if slot.Parent then
						slot:Destroy()
					end
					toolSlotLookup[tool] = nil
	
					local selectedClone = selectedTemplate:Clone()
					setupSlot(selectedClone, replacement, slotParent)
				else
					disconnectTooltipConnections(slot)
					if slot.Parent then
						slot:Destroy()
					end
					toolSlotLookup[tool] = nil
				end
			else
				disconnectTooltipConnections(slot)
				if slot.Parent then
					slot:Destroy()
				end
				toolSlotLookup[tool] = nil
			end
		end
	
		if guiSlots[toolName] and not isToolInHotbar(toolName) then
			guiSlots[toolName]:Destroy()
			guiSlots[toolName] = nil
		end
	end
	
	local function fillHotbarSlot(tool)
		local toolType = tool:GetAttribute("Type")
		if toolType == "Attack" and tool:FindFirstChild("EquipedWeapon") or toolType == "Ability" then
			for _, slot in pairs(HotBar:GetChildren()) do
				if slot:IsA("ImageButton") and slot.Name ~= "Template" then
					if not slot:FindFirstChild("Selected") then
						if selectedTemplate then
							local selectedClone = selectedTemplate:Clone()
							setupSlot(selectedClone, tool, slot)
							return true
						else
							warn("Template 'Selected' introuvable !")
						end
					end
				end
			end
		end
		return false
	end
	
	local function addInventoryItem(tool)
		if selectedTemplate then
			local clone = selectedTemplate:Clone()
			setupSlot(clone, tool, Inventory)
		else
			warn("Template 'Selected' introuvable !")
		end
	end
	
	local function refreshInventoryUI()
		local toolCounts = {}
	
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") then
				local name = tool:GetAttribute("Name")
				local toolType = tool:GetAttribute("Type")
				if toolType ~= "Attack" and toolType ~= "Equip" then
					toolCounts[name] = (toolCounts[name] or 0) + 1
				end
			end
		end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				local name = tool:GetAttribute("Name")
				local toolType = tool:GetAttribute("Type")
				if toolType ~= "Attack" and toolType ~= "Equip" then
					toolCounts[name] = (toolCounts[name] or 0) + 1
				end
			end
		end
	
		for toolName, count in pairs(toolCounts) do
			local hotbarSelected = getHotbarSelectedByToolName(toolName)
			if hotbarSelected then
				local hotbarQuantity = hotbarSelected:FindFirstChild("Quantity")
				if hotbarQuantity then
					hotbarQuantity.Text = "x" .. count
				end
	
				if guiSlots[toolName] and guiSlots[toolName] ~= hotbarSelected then
					guiSlots[toolName]:Destroy()
					guiSlots[toolName] = nil
				end
			elseif guiSlots[toolName] then
				local quantity = guiSlots[toolName]:FindFirstChild("Quantity")
				if quantity then
					quantity.Text = "x" .. count
				end
			else
				local foundTool = nil
	
				for _, tool in ipairs(bp:GetChildren()) do
					if tool:IsA("Tool") and tool:GetAttribute("Name") == toolName then
						foundTool = tool
						break
					end
				end
				if not foundTool then
					for _, tool in ipairs(char:GetChildren()) do
						if tool:IsA("Tool") and tool:GetAttribute("Name") == toolName then
							foundTool = tool
							break
						end
					end
				end
				if foundTool then
					local toolType = foundTool:GetAttribute("Type")
	
					if toolType == "Attack" or toolType == "Ability" then
						task.wait()
						if not fillHotbarSlot(foundTool) then
							addInventoryItem(foundTool)
						end
					else
						task.wait()
						if not isToolInHotbar(toolName) then
							addInventoryItem(foundTool)
						end
					end
	
					local newSlot = nil
					for _, slot in ipairs(HotBar:GetChildren()) do
						if slot:IsA("ImageButton") and slot.Name ~= "Template" then
							local selected = slot:FindFirstChild("Selected")
							if selected then
								local currentTool = selected:FindFirstChild("CurrentTool")
								if currentTool and currentTool.Value and currentTool.Value:GetAttribute("Name") == toolName then
									newSlot = selected
									break
								end
							end
						end
					end
					if not newSlot then
						for _, slot in ipairs(Inventory:GetChildren()) do
							if slot:IsA("ImageButton") then
								local currentTool = slot:FindFirstChild("CurrentTool")
								if currentTool and currentTool.Value and currentTool.Value:GetAttribute("Name") == toolName then
									newSlot = slot
									break
								end
							end
						end
					end
					if newSlot then
						local toolType = foundTool:GetAttribute("Type")
						if toolType ~= "Attack" and toolType ~= "Equip" then
							guiSlots[toolName] = newSlot
							local quantity = newSlot:FindFirstChild("Quantity")
							if quantity then
								quantity.Text = "x" .. count
							end
						end
					end
				end
			end
		end
	
		for toolName, slot in pairs(guiSlots) do
			if not toolCounts[toolName] or toolCounts[toolName] == 0 then
				slot:Destroy()
				guiSlots[toolName] = nil
			end
		end
	end
	
	if refreshInventoryUI then
		local originalRefresh = refreshInventoryUI
		refreshInventoryUI = function()
			originalRefresh()
			for tool, slot in pairs(toolSlotLookup) do
				if not tool or not tool:IsDescendantOf(bp) and not tool:IsDescendantOf(char) then
					if slot and slot.Parent then
						slot:Destroy()
					end
					toolSlotLookup[tool] = nil
				end
			end
		end
	end
	
	----------------------------------------------------------
	-- Gestion des entrées et des événements
	----------------------------------------------------------
	
	local function isItemAlreadyPresent(itemName)
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("Name") == itemName then
				return true
			end
		end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("Name") == itemName then
				return true
			end
		end
		return false
	end
	
	local function onKeyPress(inputObject)
		local key = inputObject.KeyCode.Name
		local value = inputKeys[key]
	
		if key == "Backspace" and uis:GetFocusedTextBox() == nil then
			local currentCharacter = player.Character
			local equippedTool = currentCharacter and currentCharacter:FindFirstChildWhichIsA("Tool")
			MainRemote:FireServer("inventory", {
				action = "dropEquipped",
				itemId = equippedTool and equippedTool:GetAttribute("InventoryId") or nil,
				itemName = equippedTool and (equippedTool:GetAttribute("Name") or equippedTool.Name) or nil,
			})
			return
		end
	
		if value and uis:GetFocusedTextBox() == nil then
			if HotBar[value.txt] and HotBar[value.txt]:FindFirstChild('Selected') then
				handleEquip(HotBar[value.txt]:FindFirstChild('Selected'):FindFirstChild('CurrentTool').Value)
			else
				handleEquip(nil)
			end
		end
	end
	
	local function handleAddition(adding)
		if not adding:IsA("Tool") then return end
		if adding.Parent ~= bp then return end
		
		if not knownTools[adding] then
			knownTools[adding] = true
			if not blockNewToolDetection then
				onNewItemDiscovered(adding)
			end
		end
		
		local toolNameAttr = adding:GetAttribute("Name")
		local toolType = adding:GetAttribute("Type")
	
		for _, value in ipairs(inputOrder) do
			if value.tool == adding then
				return
			end
		end
	
		if toolSlotLookup[adding] then
			updateCapacity()
			return
		end
		
		if toolType == "Attack" then
			if not fillHotbarSlot(adding) then
				addInventoryItem(adding)
			end
			updateCapacity()
			return
		elseif toolType == "Equip" then
			addInventoryItem(adding)
			updateCapacity()
			return
		end
	
		updateCapacity()
		refreshInventoryUI()
	end
	
	local function handleRemoval(removing)
		if not removing:IsA("Tool") then return end
		task.defer(function()
			if removing.Parent == bp or removing.Parent == char then return end
			
			cleanupSlot(removing)
	
			for i, value in ipairs(inputOrder) do
				if value.tool == removing then
					table.remove(inputOrder, i)
					break
				end
			end
	
			for item, data in pairs(draggedItems) do
				if data.instance == removing then
					draggedItems[item] = nil
					break
				end
			end
			
			ToggleAvailableSlot(isUIVisible)
			refreshInventoryUI()
			updateCapacity()
			knownTools[removing] = nil
		end)
	end
	
	local function initializeHotbar()
		local toShow = #inputOrder 
		HotBar.Visible = true
	
		for index, slotInfo in ipairs(inputOrder) do
			local slotClone = template:Clone()
			slotClone.AnchorPoint = Vector2.new(0.5, 0.5)
			slotClone.Label.Text = slotInfo.txt or ""
			slotClone.Name = slotInfo.txt or "Unnamed"
			setupSlot(slotClone, nil, HotBar)
		end
	end
	
	local function filterInventorySlots(query)
		query = query:lower()
		for _, slot in pairs(Inventory:GetChildren()) do
			if slot:IsA("ImageButton") and slot.Name ~= "Template" then
				local toolNameLabel = slot:FindFirstChild("ToolName")
				if toolNameLabel then
					if query == "" or toolNameLabel.Text:lower():find(query) then
						slot.Visible = true
					else
						slot.Visible = false
					end
				end
			end
		end
	end
	
	local function toggleUI()
		if char and game:GetService("CollectionService"):HasTag(char, "InDialogue") then
			if isUIVisible then
				isUIVisible = false
				hideTooltip()
				task.spawn(function()
					InventoryUI.Visible = false
					ToggleAvailableSlot(false)
					uiParent:WaitForChild("Healthbars").Visible = true
				end)
			end
			return
		end
	
		-- Sinon on toggle normalement
		isUIVisible = not isUIVisible
		hideTooltip()
	
		task.spawn(function()
			InventoryUI.Visible = isUIVisible
			ToggleAvailableSlot(isUIVisible)
			uiParent:WaitForChild("Healthbars").Visible = not isUIVisible
		end)
	end
	
	local function start()
		blockNewToolDetection = true
		MainRemote:FireServer("inventory", { action = "requestSnapshot" })
		initializeHotbar()
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") and not toolSlotLookup[tool] then
				handleAddition(tool)
			end
		end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and not toolSlotLookup[tool] then
				handleAddition(tool)
			end
		end
		refreshInventoryUI()
		updateCapacity()
		ToggleAvailableSlot(false)
		task.delay(2.5, function()
			blockNewToolDetection = false
		end)
	end
	
	local function onTagAdded(instance)
		if instance == char and CollectionService:HasTag(char, "InDialogue") and isUIVisible then
			isUIVisible = false
			hideTooltip()
			task.spawn(function()
				InventoryUI.Visible = false
				ToggleAvailableSlot(false)
				uiParent:WaitForChild("CombatStats").Visible = true
			end)
		end
	end
	
	if char then
		CollectionService:GetInstanceAddedSignal("InDialogue"):Connect(onTagAdded)
	end
	
	----------------------------------------------------------
	-- Démarrage et connexions d'événements
	----------------------------------------------------------
	repeat task.wait() until char:GetAttribute("CustomizationLoaded")
	
	bindStatusBars()
	updateAllStatusBars()
	bindMoneyUI()
	
	start()
	uis.InputBegan:Connect(onKeyPress)
	bp.ChildAdded:Connect(handleAddition)
	bp.ChildRemoved:Connect(handleRemoval)
	char.ChildRemoved:Connect(handleRemoval)
	
	--
	
	uis.InputBegan:Connect(function(input, gameProcessedEvent)
		if input.KeyCode == Enum.KeyCode.Tab and not gameProcessedEvent then
			toggleUI()
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDownTime = tick()
			mouseDragging = true
		end
	end)
	
	uis.InputEnded:Connect(function(input, gameProcessedEvent)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local heldTime = tick() - mouseDownTime
			mouseDragging = false
			if draggedItem then
				if heldTime < dragThreshold and clickedSlot then
					handleEquip(clickedSlot)
					clickedSlot = nil
				end
				onDragStopped(uis:GetMouseLocation())
				draggedItem = nil
			end
		end
	end)
	
	--
	
	MainRemote.OnClientEvent:Connect(function(eventName, payload)
		if eventName ~= "inventorySync" then
			return
		end
	
		local snapshot = payload and payload.snapshot
		if typeof(snapshot) ~= "table" then
			return
		end
	
		local count = tonumber(snapshot.count)
		if count ~= nil then
			Capacity.Text = tostring(math.max(0, math.floor(count)))
		end
	
		local maxCapacity = tonumber(snapshot.maxCapacity)
		if maxCapacity ~= nil then
			MaxCapacity.Text = tostring(math.max(0, math.floor(maxCapacity)))
		end
	end)
	
	--
	
	StatsFolder:WaitForChild("MaxCapacity").Changed:Connect(updateCapacity)
	
	SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
		filterInventorySlots(SearchBar.Text)
	end)
	
	RunService.Heartbeat:Connect(function()
		for itemName, notif in pairs(stackedNotifications) do
			if tick() - notif.timeout > NOTIF_DURATION then
				if notif.ui then notif.ui:Destroy() end
				stackedNotifications[itemName] = nil
			end
		end
		
	end)
	
	
end

return module
