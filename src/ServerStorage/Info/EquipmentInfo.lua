local module = {}

local info = {

	["Delver Helmet"] = {
		AmorsType = "Top",
		WeldTo = "Head",
		WeldPos = CFrame.new(0, -0.6, 0) * CFrame.Angles(0, math.rad(180), 0),

		Description = "A rugged helmet with lights and filters, built for surviving the Abyss.\nPress H to toggle light",
	},

	["Delver Belt"] = {
		AmorsType = "Upper",
		WeldTo = "Torso",
		WeldPos = CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(180), 0),

		Description = "A sturdy belt designed to carry climbing tools and support safe descent into the Abyss.\nAllows you to use rope in the Abyss",
	},

	["Delver Backpack"] = {
		AmorsType = "Backpack",
		WeldTo = "Torso",
		WeldPos = CFrame.new(0, -0.12, 1.2) * CFrame.Angles(0, math.rad(180), 0),

		Description = "A reliable pack used by Delvers to store relics and essentials while exploring the Abyss.",
	},

	["Delver Glove"] = {
		AmorsType = "Arms",
		WeldTo = "Hands",
		WeldPosRight = CFrame.new(0, 0.38, 0),
		WeldPosLeft = CFrame.new(0, 0.63, 0),

		Description = "Sturdy gloves used by cave delvers for climbing and handling ancient surfaces.\nPress space near a wall to use",
	},

	["Delver Boots"] = {
		AmorsType = "Lower",
		WeldTo = "Legs",
		WeldPosRight = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(180), 0),
		WeldPosLeft = CFrame.new(0, 0.32, 0) * CFrame.Angles(0, math.rad(180), 0),

		Description = "Lightweight boots designed for underground exploration, offering agility and grip in tight spaces.\nReduces fall damage by 5%",
	},
}

function module:getEquipment(EquipmentName: string)
	return info[EquipmentName]
end

return module
