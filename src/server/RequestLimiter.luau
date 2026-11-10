--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Per-player minimum gap between requests of the same kind, used for the cheap remotes
-- (Reload, SetAiming, AimPitch). Fire does not go through here, ShotClock handles that
-- because it needs burst credit. I trust the caller to pass os.clock() as `now` so this
-- module never touches the clock itself. WeaponService owns the instance and has to call
-- Forget when a player leaves.

local RequestLimiter = {}
RequestLimiter.__index = RequestLimiter

export type RequestLimiter = typeof(setmetatable(
	{} :: {
		intervals: { [string]: number },
		lastTimes: { [any]: { [string]: number } },
	},
	RequestLimiter
))

function RequestLimiter.new(intervals: { [string]: number }): RequestLimiter
	return setmetatable({
		intervals = intervals,
		lastTimes = {},
	}, RequestLimiter)
end

function RequestLimiter.Allow(self: RequestLimiter, key: any, kind: string, now: number): boolean
	local interval = self.intervals[kind]
	-- a missing interval is my bug in Settings, not something a client can cause, so it asserts
	assert(interval, `no interval for request kind '{kind}'`)
	local times = self.lastTimes[key]
	if not times then
		times = {}
		self.lastTimes[key] = times
	end
	local last = times[kind]
	if last and now - last < interval then
		return false
	end
	-- only stamped on success: a client spamming the remote doesn't keep pushing its own
	-- window out, the next request after the interval always gets through
	times[kind] = now
	return true
end

function RequestLimiter.Interval(self: RequestLimiter, kind: string): number
	return self.intervals[kind]
end

-- keyed by the Player instance, so without this the table holds every player that ever joined
function RequestLimiter.Forget(self: RequestLimiter, key: any)
	self.lastTimes[key] = nil
end

return RequestLimiter
