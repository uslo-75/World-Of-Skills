return {
	AnimFolder = "GripFolder",
	CarryOffset = CFrame.new(2, 1.5, 0),
	VisualReplicationRadius = 180,

	Align = {
		Responsiveness = 400,
		MaxForce = 1000000,
		MaxTorque = 1000000,
		MaxVelocity = 1000,
		MaxAngularVelocity = 1000,
	},

	DisabledStates = {
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.RunningNoPhysics,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
	},
}
