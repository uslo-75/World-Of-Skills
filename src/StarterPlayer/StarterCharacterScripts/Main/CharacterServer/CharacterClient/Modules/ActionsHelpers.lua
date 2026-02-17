local module = {}

function module.Create(deps)
	local lastUsed = {} -- key: "userId_action" -> time()
	local vaultLastUsed = {} -- userId -> time()

	local function anyState(plr: Player, list: { string }): boolean
		for _, k in ipairs(list) do
			if deps.StateManager.GetState(plr, k) == true then
				return true
			end
		end
		return false
	end

	local function isCarrying(plr: Player): boolean
		local char = plr and plr.Character
		return char and char:GetAttribute("Carrying") == true or false
	end

	local function isGripping(plr: Player): boolean
		local char = plr and plr.Character
		return char and char:GetAttribute("Gripping") == true or false
	end

	local function isCarryOrGripBlocked(plr: Player): boolean
		return isCarrying(plr) or isGripping(plr)
	end

	local function isGripBlocked(plr: Player): boolean
		return isGripping(plr)
	end

	local function canUse(plr: Player, action: string): boolean
		local cfg = deps.Settings[action]
		if not cfg or not cfg.Cooldown then
			return true
		end

		local key = plr.UserId .. "_" .. action
		local last = lastUsed[key]
		local now = os.clock()
		if last and (now - last) < cfg.Cooldown then
			return false
		end
		lastUsed[key] = now
		return true
	end

	local function canUseVault(plr: Player): boolean
		local cd = (deps.Settings.Vault and deps.Settings.Vault.Cooldown) or 0.6
		local last = vaultLastUsed[plr.UserId]
		local now = os.clock()
		if last and (now - last) < cd then
			return false
		end
		vaultLastUsed[plr.UserId] = now
		return true
	end

	local function playMoveAnim(char: Model, typeKey: string, animName: string): AnimationTrack?
		local anim = deps.MoveFolder:FindFirstChild(animName)
		if anim and anim:IsA("Animation") then
			local t = deps.AnimsHandler.LoadAnim(char, typeKey, anim.AnimationId, nil, { replaceType = true })
			if t then
				t.Name = animName
			end
			return t
		end
		return nil
	end

	local function refreshParams(params: RaycastParams, char: Model)
		local exclude = { char }

		local live = workspace:FindFirstChild("Live")
		if live then
			table.insert(exclude, live)
		end

		-- only fall needs these extra ignores
		if params == deps.fallParams then
			local map = workspace:FindFirstChild("World")
			local map2 = map and map:FindFirstChild("Map")
			local interactions = map2 and map2:FindFirstChild("Interactions")
			if interactions then
				table.insert(exclude, interactions)
			end
		else
			local debrisFolder = workspace:FindFirstChild("Debris")
			if debrisFolder then
				table.insert(exclude, debrisFolder)
			end

			local effectsFolder = workspace:FindFirstChild("Thrown")
			if effectsFolder then
				table.insert(exclude, effectsFolder)
			end
		end

		params.FilterDescendantsInstances = exclude
	end

	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end

	local function ensureAttachment(part: BasePart, name: string): Attachment
		local att = part:FindFirstChild(name)
		if att and att:IsA("Attachment") then
			return att
		end
		local newAtt = Instance.new("Attachment")
		newAtt.Name = name
		newAtt.Parent = part
		return newAtt
	end

	local function createLinearVelocity(part: BasePart, name: string, maxAxesForce: Vector3): LinearVelocity
		local lv = Instance.new("LinearVelocity")
		lv.Name = name
		lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		lv.MaxAxesForce = maxAxesForce
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Attachment0 = ensureAttachment(part, "RootAttachment")
		lv.Parent = part
		return lv
	end

	local function createAlignOrientation(part: BasePart, name: string, responsiveness: number?): AlignOrientation
		local align = Instance.new("AlignOrientation")
		align.Name = name
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = ensureAttachment(part, "RootAttachment")
		align.Responsiveness = responsiveness or 100
		align.Parent = part
		return align
	end

	local function getDashAnimNameFromLocalDir(dir: Vector3, cancel: boolean): string
		if dir.Magnitude <= 0 then
			return cancel and "CancelRight" or "ForwardRoll"
		end

		local x, z = dir.X, dir.Z

		if math.abs(z) >= math.abs(x) then
			if z < 0 then
				return cancel and "CancelRight" or "ForwardRoll"
			else
				return cancel and "CancelLeft" or "BackRoll"
			end
		end

		if x > 0 then
			return cancel and "CancelRight" or "RightRoll"
		else
			return cancel and "CancelLeft" or "LeftRoll"
		end
	end

	local function getDashAnimIdFromDir(dir: Vector3, cancel: boolean): string?
		local animName = getDashAnimNameFromLocalDir(dir, cancel)
		local animObj = deps.MoveFolder:FindFirstChild(animName)
		if not animObj then
			warn("[Dash] Missing animation in MoveFolder:", animName)
			return nil
		end

		if animObj:IsA("Animation") then
			return animObj.AnimationId
		end

		local inner = animObj:FindFirstChildWhichIsA("Animation")
		if inner then
			return inner.AnimationId
		end

		warn("[Dash] Invalid animation object for:", animName, animObj.ClassName)
		return nil
	end

	local function getFallBucket(char: Model)
		local b = deps.fallData[char]
		if not b then
			b = { oldY = 0, fallMag = 0 }
			deps.fallData[char] = b
		end
		return b
	end

	local function rockDebris(origin: BasePart, amount: number, color: Color3?, material: Enum.Material, collide: boolean)
		for _ = 1, amount do
			local p = Instance.new("Part")
			p.Anchored = false
			p.Name = "DebrisPart"
			p.Shape = Enum.PartType.Block
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.Material = material
			p.CanCollide = collide
			p.CFrame = origin.CFrame * CFrame.new(0, -5, 0)
			p.Color = color or Color3.fromRGB(128, 128, 128)

			p.CustomPhysicalProperties = PhysicalProperties.new(25, 1, 0, 1, 25)
			p.Velocity = Vector3.new(math.random(-33, 33), math.random(-5, 25), math.random(-33, 33))
			p.CFrame = p.CFrame
				* CFrame.Angles(
					math.rad(math.random(30, 90)),
					math.rad(math.random(30, 90)),
					math.rad(math.random(30, 90))
				)

			local debrisFolder = workspace:FindFirstChild("Debris") or workspace
			p.Parent = debrisFolder

			pcall(function()
				p.CollisionGroup = "Debris"
			end)

			deps.destroyAfter(p, math.random(5, 7))
		end
	end

	local function restoreMovement(plr: Player, humanoid: Humanoid)
		humanoid.JumpPower = deps.StarterPlayer.CharacterJumpPower

		if deps.StateManager.GetState(plr, "PlayClimb") then
			humanoid.WalkSpeed = deps.Settings.Run.Normal
			return
		end

		humanoid.WalkSpeed = (deps.StateManager.GetState(plr, "Running") == true) and deps.Settings.Run.Extra
			or deps.Settings.Run.Normal
	end

	local function spawnVaultTargetCF(hrp: BasePart, char: Model): CFrame?
		refreshParams(deps.vaultParams, char)

		local lookVector = hrp.CFrame.LookVector
		local upVector = hrp.CFrame.UpVector

		local spawnDistance = 8
		local stepSize = 0.5
		local minDistance = 2

		local function isSpaceAvailable(pos: Vector3): boolean
			local origin = hrp.Position
			local dir = pos - origin
			return workspace:Raycast(origin, dir, deps.vaultParams) == nil
		end

		local spawnPos = hrp.Position + lookVector * spawnDistance + upVector * 3
		while not isSpaceAvailable(spawnPos) and spawnDistance > minDistance do
			spawnDistance -= stepSize
			spawnPos = hrp.Position + lookVector * spawnDistance + upVector * 3
		end

		if spawnDistance <= minDistance then
			return nil
		end

		return CFrame.new(spawnPos, spawnPos + lookVector)
	end

	local function vaultRayCheckForClimb(char: Model, part: BasePart, distance: number): boolean
		if not part or not part.Parent then
			return false
		end
		refreshParams(deps.vaultParams, char)
		local vaultRay = workspace:Raycast(part.Position, part.CFrame.LookVector * distance, deps.vaultParams)
		return vaultRay == nil
	end

	return {
		anyState = anyState,
		isCarryOrGripBlocked = isCarryOrGripBlocked,
		isGripBlocked = isGripBlocked,
		canUse = canUse,
		canUseVault = canUseVault,
		playMoveAnim = playMoveAnim,
		refreshParams = refreshParams,
		lerp = lerp,
		createLinearVelocity = createLinearVelocity,
		createAlignOrientation = createAlignOrientation,
		getDashAnimIdFromDir = getDashAnimIdFromDir,
		getFallBucket = getFallBucket,
		rockDebris = rockDebris,
		restoreMovement = restoreMovement,
		spawnVaultTargetCF = spawnVaultTargetCF,
		vaultRayCheckForClimb = vaultRayCheckForClimb,
	}
end

return module
