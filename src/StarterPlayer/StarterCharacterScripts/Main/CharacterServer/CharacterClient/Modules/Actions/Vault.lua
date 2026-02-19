local ActionsVault = {}

function ActionsVault.Bind(module, context)
	local StateManager = context.StateManager
	local MoveFolder = context.MoveFolder
	local TweenService = context.TweenService
	local canUseVault = context.canUseVault
	local isGripBlocked = context.isGripBlocked
	local anyState = context.anyState
	local refreshParams = context.refreshParams
	local spawnVaultTargetCF = context.spawnVaultTargetCF
	local AnimsHandler = context.AnimsHandler
	local vaultParams = context.vaultParams
	local sounds = context.sounds

	local function isDefenseActive(plr: Player, char: Model): boolean
		if char:GetAttribute("isBlocking") == true or char:GetAttribute("Parrying") == true then
			return true
		end

		return StateManager.GetState(plr, "isBlocking") == true or StateManager.GetState(plr, "Parrying") == true
	end

	function module.Vault(plr: Player)
		if not plr or not canUseVault(plr) then
			return
		end
		if isGripBlocked(plr) then
			return
		end

		local char = plr.Character
		if not char then
			return
		end
		if isDefenseActive(plr, char) then
			return
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		local head: BasePart? = char:FindFirstChild("Head")
		if not humanoid or not hrp or not head then
			return
		end

		if humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		if
			anyState(plr, {
				"Swinging",
				"Sliding",
				"Rolling",
				"Climbing",
				"Vaulting",
				"DoubleJumping",
				"Stunned",
				"WallRunning",
				"WallHopping",
				"Dashing",
				"isBlocking",
				"Parrying",
			})
		then
			return
		end

		StateManager.SetState(plr, "Vaulting", true, 0, true)

		sounds.Vault.TimePosition = 0
		sounds.Vault:Play()

		local vault1 = MoveFolder:FindFirstChild("SideVault")
		local vault2 = MoveFolder:FindFirstChild("MonkeyVault")
		local pick = (math.random(2) == 1) and vault1 or vault2

		local animDone = false
		local tweenDone = false

		local function tryFinish()
			if animDone and tweenDone then
				StateManager.SetState(plr, "Vaulting", false, 0, true)
			end
		end

		local track: AnimationTrack? = nil
		if pick and pick:IsA("Animation") then
			track = AnimsHandler.LoadAnim(char, "Vault", pick.AnimationId, nil, { replaceType = true })
			if track then
				track:AdjustSpeed(2)
				track.Stopped:Once(function()
					animDone = true
					tryFinish()
				end)
			end
		end
		if not track then
			task.delay(0.15, function()
				animDone = true
				tryFinish()
			end)
		end

		local targetCF = spawnVaultTargetCF(hrp, char)
		if not targetCF then
			StateManager.SetState(plr, "Vaulting", false, 0, true)
			return
		end

		local tween = TweenService:Create(
			hrp,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = targetCF }
		)

		hrp.Anchored = true
		tween:Play()

		tween.Completed:Once(function()
			hrp.Anchored = false
			tweenDone = true
			tryFinish()
		end)
	end

	function module.VaultCheck(plr: Player)
		local char = plr.Character
		if not char then
			return
		end
		if isDefenseActive(plr, char) then
			return
		end
		if isGripBlocked(plr) then
			return
		end

		local humanoid: Humanoid? = char:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = char:FindFirstChild("HumanoidRootPart")
		local head: BasePart? = char:FindFirstChild("Head")
		if not humanoid or not hrp or not head then
			return
		end

		if StateManager.GetState(plr, "Vaulting") then
			return
		end
		if humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		if humanoid.MoveDirection.Magnitude <= 0 then
			return
		end

		if
			anyState(plr, {
				"Swinging",
				"Sliding",
				"Rolling",
				"Climbing",
				"DoubleJumping",
				"Stunned",
				"WallRunning",
				"WallHopping",
				"Dashing",
				"isBlocking",
				"Parrying",
			})
		then
			return
		end

		refreshParams(vaultParams, char)

		local result = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 2.5, vaultParams)
		if not (result and result.Instance and result.Instance:IsA("BasePart")) then
			return
		end

		local hitPart = result.Instance :: BasePart
		if hitPart.Size.Y >= 4.1 then
			return
		end
		if (head.Position.Y - hitPart.Position.Y) < 2 then
			return
		end

		module.Vault(plr)
	end
end

return ActionsVault
