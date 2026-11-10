--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This adds an offset on a Motor6D without fighting the character's animations
    The server writes Transform and the client writes C0
    Callers have to Clear when they stop posing, or the offset stays on
]]

export type Layer = {
	Apply: (motor: Motor6D, offset: CFrame) -> (),
	Clear: (motor: Motor6D) -> (),
}

type TransformRecord = {
	offset: CFrame,
	written: CFrame,
}

local MATCH_EPSILON = 1e-4 -- replication drifts a little so an exact compare fails

local transformLayers: { [Motor6D]: TransformRecord } = setmetatable({}, { __mode = "k" }) :: any
local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

-- If Transform still holds what I wrote last frame, nothing animated it since (a motor with
-- no animation playing keeps its old Transform), so my offset has to be peeled back off or it
-- would stack on itself every frame. If an animation did write to it, that value is the base
local function getBaseTransform(motor: Motor6D, record: TransformRecord?): CFrame
	if record and motor.Transform:FuzzyEq(record.written, MATCH_EPSILON) then
		return record.offset:Inverse() * record.written
	end
	return motor.Transform
end

-- server: the Animator rewrites Transform every frame so I stack on top of it after the
-- animation step (PoseReplicator runs on PreSimulation for that reason)
local Transform: Layer = {
	Apply = function(motor: Motor6D, offset: CFrame)
		local record = transformLayers[motor]
		local written = offset * getBaseTransform(motor, record)
		motor.Transform = written
		if record then
			record.offset = offset
			record.written = written
		else
			transformLayers[motor] = { offset = offset, written = written }
		end
	end,
	Clear = function(motor: Motor6D)
		local record = transformLayers[motor]
		if record then
			motor.Transform = getBaseTransform(motor, record)
			transformLayers[motor] = nil
		end
	end,
}

-- client: C0 doesn't replicate and animations don't write it, so there's nothing to peel off
-- The original is remembered on first Apply and put back by Clear, which assumes nothing
-- else edits C0 on these motors in between
local C0: Layer = {
	Apply = function(motor: Motor6D, offset: CFrame)
		local base = originalC0[motor]
		if not base then
			base = motor.C0
			originalC0[motor] = base
		end
		motor.C0 = base * offset
	end,
	Clear = function(motor: Motor6D)
		local base = originalC0[motor]
		if base then
			motor.C0 = base
			originalC0[motor] = nil
		end
	end,
}

return {
	Transform = Transform,
	C0 = C0,
}
