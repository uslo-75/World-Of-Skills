local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = {}

local function formatSlotText(slotValue, levelValue)
	local slot = math.max(1, math.floor(tonumber(slotValue) or 1))
	local level = math.max(1, math.floor(tonumber(levelValue) or 1))
	return string.format("Slot-%d [Lv.%d]", slot, level)
end

local function formatRegionCountry(rawRegion, rawCountry)
	local regionText = tostring(rawRegion or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local countryText = tostring(rawCountry or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if regionText == "" and countryText == "" then
		return "--"
	end
	if regionText == "" then
		return string.upper(countryText)
	end
	if countryText == "" then
		return regionText
	end

	return string.format("%s, %s", regionText, string.upper(countryText))
end

function module.Init(context)
	if context == nil then
		return
	end

	local scriptRef = context and context.script or script
	local root = context and context.root or scriptRef.Parent

	local player = Players.LocalPlayer
	if not player or not root then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local serverInfoEvent = remotes:WaitForChild("ServerInfo")

	local infoFrame = root:WaitForChild("InfoFrame")
	local characterInfo = infoFrame:WaitForChild("CharacterInfo")
	local gameInfo = infoFrame:WaitForChild("GameInfo")
	local serverInfo = infoFrame:WaitForChild("ServerInfo")

	local characterLabel = characterInfo:WaitForChild("Character")
	local slotLabel = characterInfo:WaitForChild("Slot")
	local serverRegionLabel = serverInfo:WaitForChild("ServerRegion")
	local serverTitleLabel = serverInfo:WaitForChild("ServerTitle")
	local serverAgeLabel = infoFrame:WaitForChild("AgeInfo"):WaitForChild("ServerAge")
	local gameVersionLabel = gameInfo:WaitForChild("GameVersion")

	local function applyFallback()
		characterLabel.Text = player.DisplayName or player.Name
		slotLabel.Text = formatSlotText(1, 1)
		serverTitleLabel.Text = "---"
		serverRegionLabel.Text = "--"
		serverAgeLabel.Text = "0d 0h 0m"
		gameVersionLabel.Text = "---"
	end

	local function applyPayload(payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.playerName ~= nil then
			characterLabel.Text = tostring(payload.playerName)
		end
		if payload.slotText ~= nil or payload.slot ~= nil or payload.level ~= nil then
			slotLabel.Text = tostring(payload.slotText or formatSlotText(payload.slot, payload.level))
		end
		if payload.serverName ~= nil then
			serverTitleLabel.Text = tostring(payload.serverName)
		end
		if payload.serverRegion ~= nil or payload.serverCountry ~= nil then
			serverRegionLabel.Text = formatRegionCountry(payload.serverRegion, payload.serverCountry)
		end
		if payload.serverAge ~= nil then
			serverAgeLabel.Text = tostring(payload.serverAge)
		end
		if payload.gameVersion ~= nil then
			gameVersionLabel.Text = tostring(payload.gameVersion)
		end
	end

	local function requestServerInfo()
		pcall(function()
			serverInfoEvent:FireServer("request")
		end)
	end

	serverInfoEvent.OnClientEvent:Connect(applyPayload)
	player.CharacterAdded:Connect(function()
		task.defer(requestServerInfo)
	end)

	applyFallback()
	requestServerInfo()
end

return module
