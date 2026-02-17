script.Parent:RemoveDefaultLoadingScreen()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local Loader = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Loader"))
local SmartBone = require(ReplicatedStorage:WaitForChild("SmartBone"))

local ASSETS = ReplicatedStorage:WaitForChild("Assets")
local LOADING_TEMPLATE = ASSETS:WaitForChild("Ui"):WaitForChild("LoadingScreen")

local LoadingScreen = LOADING_TEMPLATE:Clone()
LoadingScreen.Parent = PLAYER_GUI

local function collectPreloadables(root: Instance, out: { Instance })
	for _, obj in ipairs(root:GetDescendants()) do
		local class = obj.ClassName
		if
			class == "Animation"
			or class == "Sound"
			or class == "Decal"
			or class == "Texture"
			or class == "MeshPart"
			or class == "ImageLabel"
			or class == "ImageButton"
		then
			out[#out + 1] = obj
		end
	end
end

local function safePreload(list: { Instance })
	if #list == 0 then
		return true
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(list)
	end)

	if not ok then
		warn("[Preload] PreloadAsync failed:", err)
	end

	return ok
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local preloadList = {}

local world = workspace:FindFirstChild("World")
if world then
	collectPreloadables(world, preloadList)
end

collectPreloadables(ASSETS, preloadList)

local animFolder = ASSETS:FindFirstChild("animation")
if animFolder then
	collectPreloadables(animFolder, preloadList)
end

local localHandler = ReplicatedStorage:FindFirstChild("LocalHandler")
if localHandler then
	collectPreloadables(localHandler, preloadList)
end

safePreload(preloadList)

Loader.LoadAll()
SmartBone.Start()

while LOCAL_PLAYER.Parent == Players and not CollectionService:HasTag(LOCAL_PLAYER, "Loaded") do
	task.wait(0.1)
end

task.defer(function()
	if LoadingScreen and LoadingScreen.Parent then
		LoadingScreen:Destroy()
	end
end)
