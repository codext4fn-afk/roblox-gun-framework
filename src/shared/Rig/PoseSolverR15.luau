--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
-- Poses an R15 character's waist and neck from the pose table. The same module runs on the
-- server (PoseReplicator) and the client, JointLayer decides how the offset gets written.
-- It expects UpperTorso with a Waist joint and a Head with a Neck joint, and quietly does
-- nothing for a rig that doesn't have them. Arm posing for R15 isn't here.
local RunService = game:GetService("RunService")

local JointLayer = require(script.Parent.JointLayer)
local Types = require(script.Parent.Parent.Types)

-- how the pitch gets split between waist and neck, waist only bends when aiming
local WAIST_SHARE = 0.45
local NECK_SHARE = 0.55
local BODY_PITCH_DOWN_LIMIT = math.rad(-25) -- stops the torso folding over when looking straight down
local JOINT_PATHS: { [string]: { string } } = {
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
}

type Joint = {
	motor: Motor6D,
	basis: CFrame,
}

type Joints = {
	upperTorso: BasePart,
	motors: { [string]: Joint },
}

-- server writes Transform, client writes C0 (see JointLayer)
local layer = if RunService:IsServer() then JointLayer.Transform else JointLayer.C0
-- found once per character instead of searching for the joints every frame
local jointCache: { [Model]: Joints } = setmetatable({}, { __mode = "k" }) :: any

local function findMotor(character: Model, path: { string }): Motor6D?
	local part = character:FindFirstChild(path[1])
	local motor = part and part:FindFirstChild(path[2])
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function getJoints(character: Model): Joints?
	local joints = jointCache[character]
	-- the Parent check catches a cached part that was swapped out or removed
	if joints and joints.upperTorso.Parent == character then
		return joints
	end
	local upperTorso = character:FindFirstChild("UpperTorso")
	if not (upperTorso and upperTorso:IsA("BasePart")) then
		return nil
	end
	local found: Joints = { upperTorso = upperTorso, motors = {} }
	for key, path in JOINT_PATHS do
		local motor = findMotor(character, path)
		if motor then
			found.motors[key] = { motor = motor, basis = motor.C0.Rotation }
		end
	end
	jointCache[character] = found
	return found
end

-- Some rigs have rotated C0s, so a plain pitch would bend a different way on them. basis is
-- the C0 rotation captured when the joint was first found, and wrapping the offset in it
-- keeps the bend axis the same on every rig
local function applyInParentSpace(joint: Joint?, offset: CFrame)
	if joint then
		layer.Apply(joint.motor, joint.basis:Inverse() * offset * joint.basis)
	end
end

local PoseSolverR15: Types.PoseSolver = {
	NewPose = function(): Types.Pose
		return { pitch = 0, aim = 0, armPitch = 0, armYaw = 0, armBack = 0 }
	end,
	Apply = function(character: Model, pose: Types.Pose)
		local joints = getJoints(character)
		if not joints then
			return
		end
		-- the limit is only on the body (waist and neck here), so looking down can't fold the torso
		local pitch = math.max(pose.pitch, BODY_PITCH_DOWN_LIMIT)
		applyInParentSpace(joints.motors.waist, CFrame.Angles(pitch * WAIST_SHARE * pose.aim, 0, 0))
		applyInParentSpace(joints.motors.neck, CFrame.Angles(pitch * NECK_SHARE, 0, 0))
	end,
	Clear = function(character: Model)
		local joints = jointCache[character]
		if not joints then
			return
		end
		for _, joint in joints.motors do
			layer.Clear(joint.motor)
		end
		jointCache[character] = nil
	end,
}

return PoseSolverR15
