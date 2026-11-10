--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This is the spread math for the shot pattern and the crosshair
    The random numbers come from the caller
    The server does not roll again, since ShotValidator only checks the cone
]]

local Spread = {}

export type NextNumber = () -> number

function Spread.Current(hipSpread: number, aimSpread: number, aimAlpha: number): number
	return hipSpread + (aimSpread - hipSpread) * aimAlpha
end

-- pixels, just a visual
function Spread.CrosshairGap(spreadDegrees: number): number
	return 6 + spreadDegrees * 5
end

-- sqrt so shots spread evenly over the cone instead of bunching in the middle. A plain
-- random angle would crowd the pellets near the center of the disc
function Spread.SampleCone(direction: Vector3, degrees: number, nextNumber: NextNumber): Vector3
	local angle = math.rad(degrees) * math.sqrt(nextNumber())
	local roll = nextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

function Spread.Pattern(aimDirection: Vector3, degrees: number, pellets: number, nextNumber: NextNumber): { Vector3 }
	local directions = table.create(pellets)
	for index = 1, pellets do
		directions[index] = Spread.SampleCone(aimDirection, degrees, nextNumber)
	end
	return directions
end

function Spread.AngleBetween(a: Vector3, b: Vector3): number
	-- clamp or float error can make acos return NaN
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

return Spread
