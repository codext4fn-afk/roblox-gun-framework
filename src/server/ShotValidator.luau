--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Argument checks for the Fire remote. Every parameter starts as `unknown` because an
-- exploiter can send anything over a RemoteEvent, including NaN, inf, a table with hash
-- keys mixed in, or ten thousand pellets. This module only looks at values, it never
-- touches the world. WeaponService calls it before anything is spent or changed, and
-- DamageResolver relies on what comes out being finite and unit length.
-- Rejection tells you why, but onFire only checks that it's non-nil and drops the shot.

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

-- NaN ~= NaN. The inf checks matter because an inf vector would pass the magnitude test
-- and then .Unit turns it into NaN
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
	-- # only counts the array part, so a table padded with hash keys would slip past the
	-- length check above. Counting everything is bounded because it bails out at length + 1
	local count = 0
	for _ in list do
		count += 1
		if count > length then
			return "DirectionsNotList"
		end
	end
	return nil
end

-- The server can't replay the client's random spread, so all it can check is that the
-- pellet is inside a cone around the aim direction. The clamp is there because float
-- error can push the dot slightly past 1 and acos would return NaN
function ShotValidator.WithinSpread(direction: Vector3, aimDirection: Vector3, maxDegrees: number): boolean
	local cosine = math.clamp(direction.Unit:Dot(aimDirection.Unit), -1, 1)
	return math.acos(cosine) <= math.rad(maxDegrees)
end

-- Bad pellets are dropped one at a time instead of rejecting the whole shot. The Unit here
-- is what makes the ray length depend on config.Range and not on whatever the client sent
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

-- The origin comes from the client (camera or muzzle), the head is the only position the
-- server already knows. Anything further than maxOffset from it is a spoofed origin
function ShotValidator.OriginWithinReach(origin: Vector3, headPosition: Vector3, maxOffset: number): boolean
	return (origin - headPosition).Magnitude <= maxOffset
end

return ShotValidator
