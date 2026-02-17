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
	RequestCooldown = 0.25, -- anti spam requestSnapshot/equip/etc
	MinSyncInterval = 0.08, -- throttle push snapshot
	MaxItemsInSnapshot = 9999, -- sécurité
}

return Config
