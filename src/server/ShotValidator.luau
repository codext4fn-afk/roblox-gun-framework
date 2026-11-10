--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This checks the arguments of the Fire remote, and everything arrives as unknown because an exploiter can send anything
    It only looks at the values and never at the world
    DamageResolver relies on what comes out being finite and unit length
]]

local ShotValidator = {}

export type Rejection =
	"OriginNotVector"
	| "AimNotDirection"
	| "DirectionsNotList"
	| "TooManyPellets"
	| "NoPellets"
	| "OriginTooFar"

-- real directions are unit length, 0.5 is just far enough from zero that .Unit stays sane
local MIN_DIRECTION_MAGNITUDE = 0.5

-- NaN ~= NaN, so that is how NaN is caught
-- the inf checks matter because an inf vector would pass the magnitude test and then .Unit turns it into NaN
local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function ShotValidator.IsFiniteVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isFinite(vector.X) and isFinite(vector.Y) and isFinite(vector.Z)
end

function ShotValidator.IsDirection(value: unknown): boolean
	return ShotValidator.IsFiniteVector(value) and (value :: Vector3).Magnitude > MIN_DIRECTION_MAGNITUDE
end

function ShotValidator.CheckArguments(
	origin: unknown,
	aimDirection: unknown,
	directions: unknown,
	pellets: number
): Rejection?
	if not ShotValidator.IsFiniteVector(origin) then
		return "OriginNotVector"
	end
	if not ShotValidator.IsDirection(aimDirection) then
		return "AimNotDirection"
	end
	if type(directions) ~= "table" then
		return "DirectionsNotList"
	end
	local list = directions :: { [any]: any }
	local length = #list
	if length == 0 then
		return "NoPellets"
	end
	if length > pellets then
		return "TooManyPellets"
	end
	-- # only counts the array part, so a table padded with hash keys would slip past the length check
	-- so everything is counted, and it stops at length + 1 so it cannot run long
	local count = 0
	for _ in list do
		count += 1
		if count > length then
			return "DirectionsNotList"
		end
	end
	return nil
end

-- the server cannot replay the client's random spread, so it only checks that the pellet is inside a cone around the aim
-- the clamp is there because float error can push the dot slightly past 1, and then acos gives NaN
function ShotValidator.WithinSpread(direction: Vector3, aimDirection: Vector3, maxDegrees: number): boolean
	local cosine = math.clamp(direction.Unit:Dot(aimDirection.Unit), -1, 1)
	return math.acos(cosine) <= math.rad(maxDegrees)
end

-- bad pellets are dropped one at a time instead of rejecting the whole shot
-- the Unit here makes the ray length depend on config.Range and not on what the client sent
function ShotValidator.FilterDirections(directions: { unknown }, aimDirection: Vector3, maxDegrees: number): { Vector3 }
	local accepted = {}
	for _, direction in directions do
		if ShotValidator.IsDirection(direction) then
			local unit = (direction :: Vector3).Unit
			if ShotValidator.WithinSpread(unit, aimDirection, maxDegrees) then
				table.insert(accepted, unit)
			end
		end
	end
	return accepted
end

-- the origin comes from the client, and the head is the only position the server already knows
-- anything further than maxOffset from the head is a fake origin
function ShotValidator.OriginWithinReach(origin: Vector3, headPosition: Vector3, maxOffset: number): boolean
	return (origin - headPosition).Magnitude <= maxOffset
end

return ShotValidator
