local module = {}

function module.Execute(_service, _context)
	return false, "WeaponModuleMissing"
end

return table.freeze(module)
