return {
	TickRate = 2.5, -- delay between regen ticks
	StepSeconds = 1, -- regen time chunk applied each tick
	AttributesFolderName = "Attributes",
	EtherValueName = "Ether",
	MaxEtherValueName = "MaxEther",
	CombatTag = "Combats", -- placeholder tag, combat system hookup comes later
	DownedExitRatio = 0.05, -- match DownHandler exit threshold
	DownedRecoverSeconds = 10, -- time to recover DownedExitRatio health regardless of MaxHP
	DebugHealthRegen = false,
}
