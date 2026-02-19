local M1Calc = {}

function M1Calc.ToNumber(value, fallback)
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	return n
end

function M1Calc.NextCombo(
	character: Model,
	lastComboAt: number?,
	maxComboRaw: any,
	comboResetRaw: any,
	now: number,
	comboAttrName: string
): (number, number)
	local maxCombo = math.max(1, math.floor(M1Calc.ToNumber(maxComboRaw, 4)))
	local comboResetTime = math.max(0.1, M1Calc.ToNumber(comboResetRaw, 2))
	local combo = M1Calc.ToNumber(character:GetAttribute(comboAttrName), 0) or 0

	if lastComboAt == nil or (now - lastComboAt) > comboResetTime then
		combo = 1
	else
		combo += 1
		if combo > maxCombo then
			combo = 1
		end
	end

	character:SetAttribute(comboAttrName, combo)
	return combo, now
end

function M1Calc.ResolveDamage(player: Player, baseDamageRaw: any): number
	local baseDamage = math.max(0, M1Calc.ToNumber(baseDamageRaw, 5))
	local strengthMul = 1

	local statsFolder = player:FindFirstChild("Stats")
	local strengthMulValue = statsFolder and statsFolder:FindFirstChild("StrengthMul")
	if strengthMulValue and strengthMulValue:IsA("NumberValue") then
		strengthMul = math.max(0, strengthMulValue.Value)
	end

	return baseDamage * strengthMul
end

function M1Calc.IsBlockingInFront(attackerRoot: BasePart, targetRoot: BasePart): boolean
	local towardAttacker = attackerRoot.Position - targetRoot.Position
	if towardAttacker.Magnitude <= 0.001 then
		return true
	end
	return towardAttacker.Unit:Dot(targetRoot.CFrame.LookVector) > 0
end

function M1Calc.ResolveFlatDirection(attackerRoot: BasePart, targetRoot: BasePart): Vector3
	local direction = Vector3.new(
		targetRoot.Position.X - attackerRoot.Position.X,
		0,
		targetRoot.Position.Z - attackerRoot.Position.Z
	)

	if direction.Magnitude <= 0.001 then
		local look = attackerRoot.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end

	if direction.Magnitude <= 0.001 then
		direction = Vector3.new(0, 0, -1)
	end

	return direction.Unit
end

return table.freeze(M1Calc)
