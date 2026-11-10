--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
--[[
    Loads the Hold, Aim, Fire and Reload tracks for a weapon and caches them per Animator
    WeaponAnimations picks the ids, this only builds the tracks
    A missing animation is just absent, so callers nil check every track
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local Types = require(WeaponSystem:WaitForChild("Types"))
local WeaponAnimations = require(WeaponSystem:WaitForChild("WeaponAnimations"))

local AnimationTracks = {}

export type Tracks = { [string]: AnimationTrack }

-- each one overrides the one above it, so Reload plays over a held aim pose and Fire plays
-- over Hold or Aim
local PRIORITIES: { [string]: Enum.AnimationPriority } = {
	Hold = Enum.AnimationPriority.Action,
	Aim = Enum.AnimationPriority.Action2,
	Fire = Enum.AnimationPriority.Action3,
	Reload = Enum.AnimationPriority.Action4,
}
local LOOPED: { [string]: boolean } = {
	Hold = true,
	Aim = true,
}
local TRACK_WAIT = 0.5

-- cached per animator so re-equipping doesn't call LoadAnimation again
local tracksByAnimator: { [Animator]: { [string]: Tracks } } = setmetatable({}, { __mode = "k" }) :: any

local function getAnimator(character: Instance): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

function AnimationTracks.Load(humanoid: Humanoid, config: Types.WeaponConfig, rig: Types.RigName): Tracks
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return {}
	end
	local byWeapon = tracksByAnimator[animator]
	if not byWeapon then
		byWeapon = {}
		tracksByAnimator[animator] = byWeapon
	end
	local cacheKey = `{rig}:{config.Id}`
	local cached = byWeapon[cacheKey]
	if cached then
		return cached
	end
	local tracks: Tracks = {}
	for _, name: Types.AnimationName in WeaponAnimations.Names do
		local id = WeaponAnimations.GetId(config, rig, name)
		if id ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local track = animator:LoadAnimation(animation)
			track.Priority = PRIORITIES[name] or Enum.AnimationPriority.Action
			track.Looped = LOOPED[name] == true
			tracks[name] = track
		end
	end
	byWeapon[cacheKey] = tracks
	return tracks
end

-- Other players' anims replicate through their Animator and we have no handle on the track,
-- so search the playing ones by id. The track may not be playing yet when this is called, so
-- it polls for up to TRACK_WAIT seconds instead of checking once
function AnimationTracks.WaitForPlaying(
	character: Model,
	config: Types.WeaponConfig,
	rig: Types.RigName,
	name: Types.AnimationName
): AnimationTrack?
	local id = WeaponAnimations.GetId(config, rig, name)
	local animator = getAnimator(character)
	if not animator or id == "" then
		return nil
	end
	local deadline = os.clock() + TRACK_WAIT
	repeat
		for _, track in animator:GetPlayingAnimationTracks() do
			if track.Animation and track.Animation.AnimationId == id then
				return track
			end
		end
		task.wait()
	until os.clock() > deadline
	return nil
end

return AnimationTracks
