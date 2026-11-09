--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Camera recoil in degrees, kicks stack up and decay back to zero

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
	-- exp decay so recovery takes the same time at any framerate
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
