--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This is two bone IK for R15 arms, and it writes the shoulder, elbow and wrist C0s so the hand reaches the target
    WeaponRig gives it a hand target and a pole, and the weight blends back to the original C0 so an animation can take the arms over
]]
-- TODO(me): explain MAX_PROTRACTION and FOREARM_TWIST, I don't know how those were picked

export type Side = "Right" | "Left"

type Joint = {
	motor: Motor6D,
	base: CFrame,
}

type Chain = {
	shoulder: Joint,
	elbow: Joint,
	wrist: Joint,
	upperLength: number,
	lowerLength: number,
	upperBasis: CFrame?,
	lowerBasis: CFrame?,
}

local ArmSolver = {}

local CHAIN_PARTS = {
	Right = { upper = "RightUpperArm", lower = "RightLowerArm", hand = "RightHand" },
	Left = { upper = "LeftUpperArm", lower = "LeftLowerArm", hand = "LeftHand" },
}
local JOINT_NAMES = {
	Right = { shoulder = "RightShoulder", elbow = "RightElbow", wrist = "RightWrist" },
	Left = { shoulder = "LeftShoulder", elbow = "LeftElbow", wrist = "LeftWrist" },
}
local REACH_LIMIT = 0.999 -- never fully straight, the elbow flips around at full reach
local MAX_PROTRACTION = 0.45 -- how far the shoulder can slide toward the target
local FOREARM_TWIST = 0.6 -- share of the wrist twist the forearm takes

local chainCache: { [Model]: { [Side]: Chain? } } = setmetatable({}, { __mode = "k" }) :: any

local function findMotor(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function basisFrom(primary: Vector3, secondary: Vector3): CFrame?
	local x = primary.Unit
	local y = secondary - x * secondary:Dot(x)
	if y.Magnitude < 1e-5 then
		return nil
	end
	y = y.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

-- the lengths and bone directions are measured from the rig's own joints, so it works for differently proportioned R15 avatars
-- it gives nil if the arm is missing a joint
local function buildChain(character: Model, side: Side): Chain?
	local parts, names = CHAIN_PARTS[side], JOINT_NAMES[side]
	local shoulder = findMotor(character, parts.upper, names.shoulder)
	local elbow = findMotor(character, parts.lower, names.elbow)
	local wrist = findMotor(character, parts.hand, names.wrist)
	if not (shoulder and elbow and wrist) then
		return nil
	end
	local upperRest = elbow.C0.Position - shoulder.C1.Position
	local lowerRest = wrist.C0.Position - elbow.C1.Position
	return {
		shoulder = { motor = shoulder, base = shoulder.C0 },
		elbow = { motor = elbow, base = elbow.C0 },
		wrist = { motor = wrist, base = wrist.C0 },
		upperLength = upperRest.Magnitude,
		lowerLength = lowerRest.Magnitude,
		upperBasis = basisFrom(upperRest, Vector3.zAxis),
		lowerBasis = basisFrom(lowerRest, Vector3.zAxis),
	}
end

-- chains are cached per character, and rebuilt if the cached shoulder motor lost its Parent
local function getChain(character: Model, side: Side): Chain?
	local chains = chainCache[character]
	if not chains then
		chains = {}
		chainCache[character] = chains
	end
	local chain = chains[side]
	if chain and chain.shoulder.motor.Parent then
		return chain
	end
	local built = buildChain(character, side)
	chains[side] = built
	return built
end

local function partFrame(pivot: Vector3, rotation: CFrame, childOffset: Vector3): CFrame
	return CFrame.new(pivot) * rotation * CFrame.new(-childOffset)
end

-- Transform is divided out so IK wins over the arm animation
-- Roblox applies C0 * Transform * C1^-1, so without the inverse the animation would be added on top of the solved pose
-- a weight below 1 blends from the original C0 toward the solved one
local function writeJoint(joint: Joint, part0: CFrame, part1: CFrame, weight: number)
	local motor = joint.motor
	local solved = part0:Inverse() * part1 * motor.C1 * motor.Transform:Inverse()
	motor.C0 = if weight >= 1 then solved else joint.base:Lerp(solved, weight)
end

function ArmSolver.Solve(
	character: Model,
	side: Side,
	torsoCFrame: CFrame,
	handTarget: CFrame,
	pole: Vector3,
	weight: number,
	shoulderSpace: CFrame?
)
	local chain = getChain(character, side)
	if not chain or weight <= 0 then
		return
	end
	local shoulder, elbow, wrist = chain.shoulder, chain.elbow, chain.wrist
	local upperLength, lowerLength = chain.upperLength, chain.lowerLength
	local space = shoulderSpace or torsoCFrame

	local shoulderPivot = space * shoulder.base.Position
	local toWrist = handTarget * wrist.motor.C1.Position - shoulderPivot
	-- if the target is out of reach, the shoulder slides forward first, up to MAX_PROTRACTION
	-- only after that is the arm clamped to REACH_LIMIT
	local excess = toWrist.Magnitude - (upperLength + lowerLength) * REACH_LIMIT
	if excess > 0 then
		local shift = toWrist.Unit * math.min(excess, MAX_PROTRACTION)
		shoulderPivot += shift
		toWrist -= shift
	end
	local axis = toWrist.Unit
	local reach = math.clamp(
		toWrist.Magnitude,
		math.abs(upperLength - lowerLength) + 1e-3,
		(upperLength + lowerLength) * REACH_LIMIT
	)
	local wristPivot = shoulderPivot + axis * reach

	-- law of cosines
	-- along is how far down the shoulder to wrist line the elbow sits, and height is how far it is pushed off that line
	local along = (upperLength * upperLength - lowerLength * lowerLength + reach * reach) / (2 * reach)
	local height = math.sqrt(math.max(upperLength * upperLength - along * along, 0))
	local toPole = pole - shoulderPivot
	-- the elbow points at the pole
	-- if the pole is on the shoulder to wrist line there is no side to pick, so it points down
	local bend = toPole - axis * toPole:Dot(axis)
	if bend.Magnitude < 1e-4 then
		bend = -space.UpVector
	end
	bend = bend.Unit
	local elbowPivot = shoulderPivot + axis * along + bend * height

	local upperWorld = basisFrom(elbowPivot - shoulderPivot, bend)
	local forearmAxis = (wristPivot - elbowPivot).Unit
	local lowerBasis = chain.lowerBasis
	local handSide = handTarget:VectorToWorldSpace(if lowerBasis then lowerBasis.YVector else Vector3.zAxis)
	handSide -= forearmAxis * handSide:Dot(forearmAxis)
	local forearmSide = bend
	if handSide.Magnitude > 1e-3 then
		forearmSide = bend:Lerp(handSide.Unit, FOREARM_TWIST)
	end
	local lowerWorld = basisFrom(wristPivot - elbowPivot, forearmSide)
	local upperBasis = chain.upperBasis
	if not (upperWorld and lowerWorld and upperBasis and lowerBasis) then
		return
	end
	local upperArm = partFrame(shoulderPivot, upperWorld * upperBasis:Inverse(), shoulder.motor.C1.Position)
	local lowerArm = partFrame(elbowPivot, lowerWorld * lowerBasis:Inverse(), elbow.motor.C1.Position)
	local hand = partFrame(wristPivot, handTarget.Rotation, wrist.motor.C1.Position)

	writeJoint(shoulder, torsoCFrame, upperArm, weight)
	writeJoint(elbow, upperArm, lowerArm, weight)
	writeJoint(wrist, lowerArm, hand, weight)
end

-- this gives WeaponRig the shoulder rest position and the max reach
-- that way it can place poles and pull the gun in for short arms without measuring by itself
function ArmSolver.GetShoulder(character: Model, side: Side): (Vector3?, number)
	local chain = getChain(character, side)
	if not chain then
		return nil, 0
	end
	return chain.shoulder.base.Position, (chain.upperLength + chain.lowerLength) * REACH_LIMIT + MAX_PROTRACTION
end

function ArmSolver.Reset(character: Model)
	local chains = chainCache[character]
	if not chains then
		return
	end
	for _, chain in chains do
		if chain then
			for _, joint in { chain.shoulder, chain.elbow, chain.wrist } do
				if joint.motor.Parent then
					joint.motor.C0 = joint.base
				end
			end
		end
	end
	chainCache[character] = nil
end

return ArmSolver
