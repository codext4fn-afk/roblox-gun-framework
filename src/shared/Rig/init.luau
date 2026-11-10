--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
-- Entry point for rig detection. Picks the pose solver that matches the character's rig, or
-- nil when there's no Humanoid. Server (PoseReplicator) and client both go through this.
local CharacterRig = require(script.CharacterRig)
local PoseSolverR15 = require(script.PoseSolverR15)
local PoseSolverR6 = require(script.PoseSolverR6)
local Types = require(script.Parent.Types)

local Rig = {
	CharacterRig = CharacterRig,
}

function Rig.GetPoseSolver(character: Instance?): Types.PoseSolver?
	local rig = CharacterRig.GetRig(character)
	if rig == "R15" then
		return PoseSolverR15
	elseif rig == "R6" then
		return PoseSolverR6
	end
	return nil
end

return Rig
