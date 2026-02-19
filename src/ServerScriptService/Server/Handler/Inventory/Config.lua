local Config = {
	RemotesFolderName = "Remotes",
	MainRemoteName = "Main",
	SyncEventName = "inventorySync",

	ToolsFolderName = "Tools",
	StatsFolderName = "Stats",
	AttributesFolderName = "Attributes",
	InventoryCountValueName = "InventoryCount",

	DropFolderName = "DroppedItems",
	DropLifetimeSeconds = 180,
	DropVisualTag = "WorldDropVisual",
	DropStackDistance = 8,
	DropPickupDelay = 0.25,
	BatchAddInterval = 0.035,
	DropForwardDistance = 3.5,
	DropRaycastStartHeight = 10,
	DropRaycastDepth = 64,
	DropGroundOffset = 0.05,

	-- Net
	RequestCooldown = 0.25, -- anti-spam for requests
	MinSyncInterval = 0.08, -- throttle outgoing syncs
	EnableSnapshotCoalescing = true, -- queue and merge sync requests during throttle
	UseStandaloneRequestListener = false, -- requests are routed by RemoteHandler
	SyncIncludeItemsOnRequest = false, -- keep request payloads lightweight by default
	SyncIncludeItemsDefault = false, -- routine syncs include count/capacity only
	SyncIncludeItemsByReason = {}, -- optional per-reason overrides
	MaxItemsInSnapshot = 9999, -- safety cap when item list is included
}

return Config
