--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This poses armed characters on the server from the AimPitch and Aiming attributes
    WeaponService calls Start and Stop when a gun is equipped or put away
    AimPitch was already clamped before it gets here, so only its type is checked
]]
-- TODO(me): explain why the server poses characters at all when the client has AimPose, I can't tell from the code

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local AngleMath = require(WeaponSystem:WaitForChild("AngleMath"))
local Rig = require(WeaponSystem:WaitForChild("Rig"))
local Settings = require(WeaponSystem:WaitForChild("Settings"))
local Types = require(WeaponSystem:WaitForChild("Types"))

local PoseReplicator = {}

type Posed = {
	pose: Types.Pose,
	solver: Types.PoseSolver,
}

local posed: { [Model]: Posed } = {}
local connection: RBXScriptConnection? = nil

local function step(deltaTime: number)
	-- pitch only arrives in steps (the limiter caps it at 30 a second) so I ease toward it
	-- ExpBlend takes deltaTime so the smoothing feels the same at any server frame rate
	local blend = AngleMath.ExpBlend(deltaTime, Settings.Server.PoseSmoothing)
	for character, entry in posed do
		-- backup for a character that was removed without Stop being called, so this table
		-- can't hold dead models forever
		if not character.Parent then
			posed[character] = nil
			continue
		end
		local pitch = character:GetAttribute("AimPitch")
		local targetPitch = if type(pitch) == "number" then pitch else 0
		local targetAim = if character:GetAttribute("Aiming") == true then 1 else 0
		local pose = entry.pose
		pose.pitch += (targetPitch - pose.pitch) * blend
		pose.aim += (targetAim - pose.aim) * blend
		entry.solver.Apply(character, pose)
	end
end

-- Called on every tool child change, so it has to be safe to call twice
function PoseReplicator.Start(character: Model)
	if posed[character] then
		return
	end
	local solver = Rig.GetPoseSolver(character)
	if solver then
		posed[character] = { pose = solver.NewPose(), solver = solver }
	end
end

-- Clear hands the joints back to the animations, otherwise an unequipped character would
-- stay stuck in the last aim pose
function PoseReplicator.Stop(character: Model)
	local entry = posed[character]
	if entry then
		posed[character] = nil
		entry.solver.Clear(character)
	end
end

function PoseReplicator.Run()
	if not connection then
		-- PreSimulation is after the Animator so we layer on top of the anims
		connection = RunService.PreSimulation:Connect(step)
	end
end

return PoseReplicator
