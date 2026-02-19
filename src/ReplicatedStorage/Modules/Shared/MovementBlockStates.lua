local StateKeys = require(script.Parent:WaitForChild("StateKeys"))
local MovementBlockStates = {}

MovementBlockStates.InteractionPrompt = {
	StateKeys.Sliding,
	StateKeys.Crouching,
	StateKeys.Dashing,
	StateKeys.WallRunning,
	StateKeys.Climbing,
}

MovementBlockStates.BaseAnimator = {
	StateKeys.Dashing,
	StateKeys.Sliding,
	StateKeys.SlidePush,
	StateKeys.Climbing,
	StateKeys.Vaulting,
	StateKeys.WallRunning,
	StateKeys.WallHopping,
	StateKeys.ClimbUp,
	StateKeys.Stunned,
	StateKeys.Swinging,
	StateKeys.UsingMove,
	StateKeys.IsRagdoll,
	StateKeys.Blocking,
	StateKeys.Parrying,
}

MovementBlockStates.DirectionalWalk = {
	StateKeys.Climbing,
	StateKeys.ClimbUp,
	StateKeys.ClimbDisengage,
	StateKeys.Vaulting,
	StateKeys.WallRunning,
	StateKeys.WallHopping,
	StateKeys.Sliding,
	StateKeys.SlidePush,
	StateKeys.Dashing,
	StateKeys.Stunned,
	StateKeys.Swinging,
	StateKeys.UsingMove,
	StateKeys.Downed,
	StateKeys.Blocking,
	StateKeys.Parrying,
}

return MovementBlockStates
