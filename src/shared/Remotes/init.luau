--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Client to server: Fire, Reload, SetAiming, AimPitch
-- Server to client: ReplicateShot, ReplicateReload
--
-- This only collects the RemoteEvents that live under this module so both sides get the
-- same typed handles. It has no logic. The four client to server ones carry untrusted
-- input, WeaponService is the only listener and has to validate every argument.

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
