local ReplicatedStorage = game:GetService("ReplicatedStorage")
--!strict

--[[

            --- Fast replacement for assert (~10x faster) ---

    assert is really slow when using a 2nd argument with concatenation or
    formatting, because it always evaluates that argument no matter the
    condition is met or not, taking lots of seconds for large operations.

        assert(true, string.format("%s", "foo"))
        -- It won't error, but string.format will get evaluated

        affirm(true, "%s", "foo")
        -- No formatting is done since the condition is not met

    affirm efficiently replaces assert by separating the error message from
    the arguments, formatting the string only if the condition is not met.
    Note that it also accepts data types other than strings as 2nd argument
    (Numbers, instances, tables...).


Example:

    affirm exports and is supposed to be used as a single function:

        local affirm = require(path.to.this.module)

        local var1 = 687
        local var2 = "foo"

        affirm(var1 > 0, "number isn't positive [%+i]", var1) -- OK
        affirm(typeof(var1) == "number", "expected number, got %s", typeof(var1)) -- OK

        affirm(
            typeof(var2) == "number",
            "expected number, got %s",
            typeof(var2)
        )

        -- Error: expected number, got string

License:

    MIT License

    Copyright (c) 2023 flamenco687

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

Versions:

    v1.0.4 -> March 4th, 2023 [flamenco687] - Update documentation
    v1.0.3 -> March 3rd, 2023 [flamenco687] - Publish package
    ...
    v1.0.0 -> March 2nd, 2023 [flamenco687] - Create file

--]]

--[=[
    Throws out an error for `affirm` in case error message formatting failed
    due to invalid arguments (anything except strings or numbers)
]=]
local function errorArguments(arguments: { any }): ()
	local errorMessage = "affirm() -> following arguments expected strings or numbers, got:"

	for i, argument in arguments do
		local typeofArgument = typeof(argument)
		if typeofArgument ~= "string" and typeofArgument ~= "number" then -- Only strings and numbers can be formatted
			errorMessage = string.format("%s #%i %s", errorMessage, i, typeofArgument)
		end
	end

	error(errorMessage, 2)
end

--[=[
    [`assert`](https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#assert)
    is really slow when using a 2nd argument with concatenation or
    [formatting](https://create.roblox.com/docs/reference/engine/libraries/string#format),
    because it always evaluates that argument no matter the
    condition is met or not, taking lots of seconds for large operations.

    ```lua
        assert(true, string.format("%s", "foo"))
        -- It won't error, but string.format will get evaluated

        affirm(true, "%s", "foo")
        -- No formatting is done since the condition is not met
    ```

    `affirm` efficiently replaces assert by separating the error message from
    the arguments, formatting the string only if the condition is not met.
    Note that it also accepts data types other than
    [strings](https://create.roblox.com/docs/scripting/luau/strings) as 2nd argument
    ([Numbers](https://create.roblox.com/docs/scripting/luau/numbers),
    [instances](https://create.roblox.com/docs/reference/engine/classes/Instance),
    [tables](https://create.roblox.com/docs/scripting/luau/tables)...).
]=]
local function affirm(condition: any, errorMessage: any?, ...: string | number?): ()
	if not condition then
		if ... and typeof(errorMessage) == "string" then
			local arguments = { ... }

			local function format(): ()
				errorMessage = string.format(errorMessage, unpack(arguments))
			end

			-- Wrap format function in a pcall so that errors formatting
			-- with invalid arguments don't propagate to the whole stack.
			if not pcall(format) then
				errorArguments(arguments :: { any })
			end
		end

		error(if errorMessage then errorMessage else "Affirmation failed", 3)
	end
end

return affirm
