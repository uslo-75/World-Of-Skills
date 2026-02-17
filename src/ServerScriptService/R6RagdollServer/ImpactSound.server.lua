--||Services||--
local SoundService = game:GetService("SoundService")

--||Values||--
local air = false
local imp = false

--||Other||--
local part = script.Parent

--||Settings||--
local NumberOfSounds = 1 --if you wanna add more sounds just add one in the impact folder and make sure to name it "Impact" and then just count up, so next ones would be "Impact2", "Impact3" etc.

------------------------------------------------------------------------------------------------------------------

part.Touched:connect(function(h)
	if not h:IsDescendantOf(part.Parent) and air == true and imp == false and h and h.Transparency < 1 then
		air = false
		imp = true

		local sou = math.random(1, NumberOfSounds)

		local s = SoundService.SFX.Impact["Impact" .. sou]:clone()
		s.Parent = part
		s.Name = "Impact"
		s:Play()

		task.delay(3, function()
			if s and s.Parent then
				s:Destroy()
			end
		end)

		script:Destroy()
	end
end)

while true do
	task.wait()
	local ray = Ray.new(part.Position, Vector3.new(0, -3, 0))
	local h, p = game.Workspace:FindPartOnRay(ray, part.Parent)

	if not h then
		air = true
		imp = false
	end
end
