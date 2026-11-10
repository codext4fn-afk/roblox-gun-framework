--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    Client to server: Fire, Reload, SetAiming, AimPitch
    Server to client: ReplicateShot, ReplicateReload
    Only collects the RemoteEvents, no logic. The client ones are untrusted, WeaponService validates them
]]

-- fail loudly at startup if one is missing
local function get(name: string): RemoteEvent
	local remote = script:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `Remotes.{name} must be a RemoteEvent`)
	return remote
end

return {
	Fire = get("Fire"),
	Reload = get("Reload"),
	SetAiming = get("SetAiming"),
	AimPitch = get("AimPitch"),
	ReplicateShot = get("ReplicateShot"),
	ReplicateReload = get("ReplicateReload"),
}
