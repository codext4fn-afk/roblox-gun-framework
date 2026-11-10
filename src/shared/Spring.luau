--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This is the spring for weapon sway, and it keeps no state because the caller holds the position and velocity
]]

local Spring = {}

export type Params = {
	stiffness: number,
	damping: number,
	step: number,
}

-- slightly underdamped so sway overshoots a bit
Spring.Sway = table.freeze({
	stiffness = 140,
	damping = 18,
	step = 1 / 240,
}) :: Params

function Spring.Step(
	position: number,
	velocity: number,
	target: number,
	deltaTime: number,
	params: Params
): (number, number)
	-- Fixed substeps so it behaves the same at any framerate. One big step with this much
	-- stiffness would overshoot wildly on a slow frame, so the step size is capped
	local steps = math.max(1, math.ceil(deltaTime / params.step))
	local step = deltaTime / steps
	for _ = 1, steps do
		local acceleration = (target - position) * params.stiffness - velocity * params.damping
		velocity += acceleration * step
		position += velocity * step
	end
	return position, velocity
end

return Spring
