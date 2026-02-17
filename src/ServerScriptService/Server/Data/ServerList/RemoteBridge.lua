local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteBridge = {}

function RemoteBridge.ensureRemote(remotesFolderName: string, remoteName: string)
	local remotes = ReplicatedStorage:FindFirstChild(remotesFolderName)
	if remotes and not remotes:IsA("Folder") then
		remotes:Destroy()
		remotes = nil
	end
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = remotesFolderName
		remotes.Parent = ReplicatedStorage
	end

	local remote = remotes:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotes
	end

	return remote
end

function RemoteBridge.push(remote: RemoteEvent, player: Player, payload: any)
	remote:FireClient(player, payload)
end

function RemoteBridge.pushAll(remote: RemoteEvent, players: { Player }, payload: any)
	for _, plr in ipairs(players) do
		remote:FireClient(plr, payload)
	end
end

return RemoteBridge
