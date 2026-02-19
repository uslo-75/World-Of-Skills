return {
	AnimType = "ToolEquip",
	TrackName = "ToolNone_EquipTrack",

	AssetsPath = { "Assets", "animation", "item" },
	ToolNoneAnimationName = "ToolNone",

	StopWhileRunning = true,
	FadeTime = 0.1,
	Priority = Enum.AnimationPriority.Idle,

	WeaponEquipAnimType = "WeaponEquipTransition",
	WeaponUnequipAnimType = "WeaponUnequipTransition",
	WeaponEquipAnimationName = "equip",
	WeaponUnequipAnimationName = "unequip",
	WeaponTransitionFadeTime = 0.06,
	WeaponTransitionPriority = Enum.AnimationPriority.Action2,

	WeaponIdleAnimType = "WeaponIdleOverlay",
	WeaponIdleTrackName = "WeaponIdleOverlayTrack",
	WeaponIdleFadeTime = 0.1,
	WeaponIdlePriority = Enum.AnimationPriority.Action,
}
