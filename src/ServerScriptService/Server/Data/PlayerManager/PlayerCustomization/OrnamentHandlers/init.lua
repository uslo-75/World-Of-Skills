local DefaultHandler = require(script.Default)
local LunariansHandler = require(script.Lunarians)
local PharaosiensHandler = require(script.Pharaosiens)
local SangivoresHandler = require(script.Sangivores)
local SolariansHandler = require(script.Solarians)
local VaransHandler = require(script.Varans)

local OrnamentHandlers = {}

local HANDLERS_BY_RACE = {
	Lunarians = LunariansHandler,
	Pharaosiens = PharaosiensHandler,
	Sangivores = SangivoresHandler,
	Solarians = SolariansHandler,
	Varans = VaransHandler,
}

function OrnamentHandlers.GetForRace(civilization)
	return HANDLERS_BY_RACE[civilization] or DefaultHandler
end

return OrnamentHandlers
