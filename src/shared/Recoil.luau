--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This is the camera recoil in degrees, and only the client uses it
    Kicks add up and then fade back to zero, and the caller reads pitch, yaw and shake from Step
    The randomness comes from the caller, so this never calls math.random
]]

local Recoil = {}
Recoil.__index = Recoil

export type Params = {
	recovery: number,
	sideways: number,
	shakeRecovery: number,
	shakeMax: number,
}

export type Recoil = typeof(setmetatable(
	{} :: {
		params: Params,
		pitch: number,
		yaw: number,
		shake: number,
	},
	Recoil
))

function Recoil.new(params: Params): Recoil
	return setmetatable({
		params = params,
		pitch = 0,
		yaw = 0,
		shake = 0,
	}, Recoil)
end

function Recoil.Kick(self: Recoil, degrees: number, sidewaysRoll: number)
	self.pitch += degrees
	-- roll is 0 to 1, remap so it kicks left or right
	self.yaw += (sidewaysRoll * 2 - 1) * self.params.sideways * degrees
end

function Recoil.Shake(self: Recoil, degrees: number)
	self.shake = math.min(self.shake + degrees, self.params.shakeMax)
end

function Recoil.Step(self: Recoil, deltaTime: number): (number, number, number)
	-- exp decay so recovery takes the same time at any framerate, a flat subtraction per
	-- frame would recover faster on a 144hz screen than a 30fps one
	local decay = math.exp(-deltaTime * self.params.recovery)
	self.pitch *= decay
	self.yaw *= decay
	self.shake *= math.exp(-deltaTime * self.params.shakeRecovery)
	return self.pitch, self.yaw, self.shake
end

function Recoil.Reset(self: Recoil)
	self.pitch, self.yaw, self.shake = 0, 0, 0
end

return Recoil
