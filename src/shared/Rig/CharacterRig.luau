--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
local Types = require(script.Parent.Parent.Types)

-- Rig type and liveness checks on a character model. The server uses IsAlive to gate firing
-- and reloading, so it's based on Humanoid.Health and not on anything the client says.

local CharacterRig = {}

function CharacterRig.GetHumanoid(character: Instance?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- anything that isn't R15 counts as R6
function CharacterRig.GetRig(character: Instance?): Types.RigName?
	local humanoid = CharacterRig.GetHumanoid(character)
	if not humanoid then
		return nil
	end
	return if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
end

function CharacterRig.IsR15(character: Instance?): boolean
	return CharacterRig.GetRig(character) == "R15"
end

function CharacterRig.IsAlive(character: Instance?): boolean
	local humanoid = CharacterRig.GetHumanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

return CharacterRig
