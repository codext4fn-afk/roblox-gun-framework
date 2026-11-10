--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Fire rate limit per tool, one clock per Tool instance (WeaponService keeps them in a
-- weak table). I trust the caller to pass os.clock(). It doesn't know about ammo or
-- reloads, those are checked before this is consumed.
--
-- It's a token bucket and not a "time since last shot" check because packets arrive
-- bunched up when the network hiccups. A strict interval would drop the second shot of a
-- pair that was fired on time on the client. A burst a little over 1 lets one early shot
-- through, but sustained fire is still capped at 1 per interval.

local ShotClock = {}
ShotClock.__index = ShotClock

export type ShotClock = typeof(setmetatable(
	{} :: {
		interval: number,
		burst: number,
		credit: number,
		last: number?,
	},
	ShotClock
))

function ShotClock.new(interval: number, burst: number): ShotClock
	assert(interval > 0, "interval must be above 0")
	assert(burst >= 1, "burst must be 1 or more")
	return setmetatable({
		interval = interval,
		burst = burst,
		credit = burst, -- full at the start so the first shot after equipping is never refused
		last = nil,
	}, ShotClock)
end

-- max(..., 0) so a clock that goes backwards can't take credit away
function ShotClock.Refill(self: ShotClock, now: number)
	local last = self.last
	if last then
		self.credit = math.min(self.burst, self.credit + math.max(now - last, 0) / self.interval)
	end
	self.last = now
end

function ShotClock.TryConsume(self: ShotClock, now: number): boolean
	self:Refill(now)
	if self.credit < 1 then
		return false
	end
	self.credit -= 1
	return true
end

return ShotClock
