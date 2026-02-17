local StateKeys = {
	Sliding = "Sliding",
	Crouching = "Crouching",
	Dashing = "Dashing",
	WallRunning = "WallRunning",
	WallHopping = "WallHopping",
	Climbing = "Climbing",
	ClimbUp = "ClimbUp",
	ClimbDisengage = "ClimbDisengage",
	Vaulting = "Vaulting",
	Stunned = "Stunned",
	SlowStunned = "SlowStunned",
	Swinging = "Swinging",
	UsingMove = "UsingMove",
	IsRagdoll = "IsRagdoll",
	Downed = "Downed",
	Running = "Running",
	SlidePush = "slidePush",
	Parrying = "Parrying",
	Blocking = "isBlocking",
	Gripping = "Gripping",
}

return table.freeze(StateKeys)
