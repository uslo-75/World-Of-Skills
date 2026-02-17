local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(task)
	local t = typeof(task)
	if t == "RBXScriptConnection" or t == "Instance" or t == "function" or t == "table" then
		table.insert(self._tasks, task)
		return task
	end
	return task
end

function Maid:DoCleaning()
	for i = #self._tasks, 1, -1 do
		local task = self._tasks[i]
		self._tasks[i] = nil

		local t = typeof(task)
		if t == "RBXScriptConnection" then
			pcall(function()
				task:Disconnect()
			end)
		elseif t == "Instance" then
			pcall(function()
				task:Destroy()
			end)
		elseif t == "function" then
			pcall(task)
		elseif t == "table" and task.Destroy then
			pcall(function()
				task:Destroy()
			end)
		end
	end
end

return Maid
