local module = {}

function module.DestroyAfter(inst: Instance?, delaySeconds: number?)
	if not inst then
		return
	end

	local lifeTime = tonumber(delaySeconds) or 0
	if lifeTime <= 0 then
		if inst.Parent then
			inst:Destroy()
		end
		return
	end

	task.delay(lifeTime, function()
		if inst and inst.Parent then
			inst:Destroy()
		end
	end)
end

function module.EmitParticles(root: Instance, defaultEmitCount: number?)
	local fallbackEmitCount = math.max(1, math.floor(tonumber(defaultEmitCount) or 1))
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = tonumber(descendant:GetAttribute("EmitCount")) or fallbackEmitCount
			descendant:Emit(math.max(1, math.floor(emitCount)))
		end
	end
end

function module.ResolvePrimaryPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if not inst:IsA("Model") then
		return nil
	end

	local model = inst :: Model
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart")
end

return table.freeze(module)
