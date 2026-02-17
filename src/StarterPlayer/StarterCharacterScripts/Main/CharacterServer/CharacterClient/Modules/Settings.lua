local Settings = {
	Combats = {
		lastMouseButton1Pressed = nil,
		lastMouseButton2Pressed = nil,
		TimeToFeint = 0.25,
		blockCooldown = 0.5,
	},

	Run = {
		Normal = 9,
		Extra = 20,
		Max = 26,
		MaxTicksWTap = 0.2,
		RunCooldown = 0,
		LastTime = tick(),
	},

	WallRun = {
		Cooldown = 1.25,
		wallRunSpeed = 40,
		wallRunDownwardSpeed = 3,
		wallRunDuration = 4,
		wallRunRange = 2.3,
	},

	Dash = {
		Cooldown = 1.5,
		Duration = 0.20,
		Distance = 12,
		CancelDur = 0.25,
		CancelDist = 10,
	},

	CancelRoll = {
		Cooldown = 1.85,
	},

	Sliding = {
		Cooldown = 1.5,
		BaseSpeed = 50,
		HipHeight = {
			Normal = 0,
			Slide = -2,
		},
		MaxMultiplier = 1.5,
		SpeedChangeRate = {
			Forward = 1,
			Upward = 2,
			Downward = 1,
		},
		PushOnCancel = true,
		PushVelocity = {
			MinForward = 0,
			MaxForward = 90,
			Up = 42,
		},
	},

	Landing = {
		Height = 6.5,
		MaxVaultHeight = 4,
	},

	Vault = {
		Cooldown = 0.5,
	},

	Climb = {
		Cooldown = 0.30,
		studHeight = 1.5,
		vaultPower = 25,
		vaultForwardPower = 20,
		latchDistance = 5,
		Force = 35,
		Decay = 1,
	},

	DoubleJump = {
		Cooldown = 2,
		Power = 40,
		Decay = 2,
	},

	FallDamage = {
		Factor = 6.5,
	},

	Camera = {
		MaxTiltAngle = 1,
		MinFOV = 70,
		MaxFOV = 75,
	},
}

return Settings
