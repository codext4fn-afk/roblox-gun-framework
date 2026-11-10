--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    These wrappers make the server rays share one Exclude filter
    The direction has to be unit length, because the range does the scaling
]]

local Raycast = {}

function Raycast.Excluding(instances: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = instances
	return params
end

function Raycast.Cast(origin: Vector3, direction: Vector3, range: number, params: RaycastParams): RaycastResult?
	return workspace:Raycast(origin, direction * range, params)
end

function Raycast.EndPoint(origin: Vector3, direction: Vector3, range: number, params: RaycastParams): Vector3
	local result = workspace:Raycast(origin, direction * range, params)
	return if result then result.Position else origin + direction * range
end

return Raycast
