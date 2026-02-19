local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(script:WaitForChild("Config"))
local StatsUtil = require(script.Util:WaitForChild("StatsUtil"))
local ToolFactory = require(script.Util:WaitForChild("ToolFactory"))
local DropService = require(script.Drops:WaitForChild("DropService"))
local InventoryNet = require(script.Net:WaitForChild("InventoryNet"))
local InventoryService = require(script:WaitForChild("InventoryService"))
local WeaponService = require(script:WaitForChild("WeaponService"))

local DataManager = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Data")
		:WaitForChild("PlayerManager")
		:WaitForChild("DataManager")
)

local toolFactory = ToolFactory.new({ Config = Config, StatsUtil = StatsUtil, DataManager = DataManager })
local weaponService = WeaponService.new({ DataManager = DataManager })

local service = InventoryService.new({
	Config = Config,
	DataManager = DataManager,
	ToolFactory = toolFactory,
	WeaponService = weaponService,
	DropService = nil,
	Net = nil,
})

local net = InventoryNet.new({
	Config = Config,
	InventoryService = service,
})

local drops = DropService.new({
	Config = Config,
	ToolFactory = toolFactory,
	StatsUtil = StatsUtil,
	DataManager = DataManager,
	InventoryService = service,
})

service.DropService = drops
service.Net = net

if toolFactory and toolFactory.ClearCache then
	toolFactory:ClearCache()
end
weaponService:Init()
service:Init()
net:Bind()

return {
	Service = service,
	Net = net,
	Drops = drops,
}
