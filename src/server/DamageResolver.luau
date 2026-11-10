--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    Turns accepted pellet directions into damage
    Every pellet is recast here and damage comes from the server's config and hit zones
    Trusts that WeaponService already validated the shooter, tool and directions
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local HitZones = require(WeaponSystem:WaitForChild("HitZones"))
local Raycast = require(WeaponSystem:WaitForChild("Raycast"))
local Settings = require(WeaponSystem:WaitForChild("Settings"))
local Types = require(WeaponSystem:WaitForChild("Types"))

local DamageResolver = {}

type Hit = {
	model: Model,
	damage: number,
}

-- Friendly fire is decided per victim after pellets are summed. NPCs have no Player and
-- neutral players have no team, so both count as fair targets
local function canDamage(shooter: Player, victimModel: Model, config: Types.WeaponConfig): boolean
	if config.FriendlyFire then
		return true
	end
	local victim = Players:GetPlayerFromCharacter(victimModel)
	if not victim or shooter.Neutral or victim.Neutral then
		return true
	end
	return victim.Team ~= shooter.Team
end

-- Classic creator tag so leaderboards and kill feeds know who to credit. The old one is
-- replaced so the last shooter gets the kill. It expires after CreatorTagLifetime so old
-- credit doesn't stay on the humanoid
local function tagCreator(humanoid: Humanoid, shooter: Player)
	local existing = humanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = shooter
	tag.Parent = humanoid
	task.delay(Settings.Server.CreatorTagLifetime, function()
		if tag.Parent then
			tag:Destroy()
		end
	end)
end

function DamageResolver.Resolve(
	shooter: Player,
	character: Model,
	config: Types.WeaponConfig,
	origin: Vector3,
	directions: { Vector3 }
): { Vector3 }
	-- Only the shooter's own character is excluded. Held tools and accessories have
	-- CanQuery off (see WeaponService.prepareDescendant) so they don't block either
	local params = Raycast.Excluding({ character })
	local hitPositions = table.create(#directions)
	-- sum pellets per humanoid so a shotgun blast lands as one hit and one creator tag
	local hits: { [Humanoid]: Hit } = {}

	for _, direction in directions do
		local result = Raycast.Cast(origin, direction, config.Range, params)
		-- misses still get an endpoint so other clients can draw a full length tracer, and
		-- these are the server's positions, not whatever the client claimed it hit
		table.insert(hitPositions, if result then result.Position else origin + direction * config.Range)
		local part = result and result.Instance
		if part and part:IsA("BasePart") then
			-- TODO(me): explain. A dead body still stops the pellet here (no cast through it), not sure if that's on purpose
			local humanoid, model = HitZones.GetLivingHumanoid(part)
			if humanoid and model then
				local hit = hits[humanoid] or { model = model, damage = 0 }
				hit.damage += config.Damage[HitZones.Get(part)]
				hits[humanoid] = hit
			end
		end
	end

	for humanoid, hit in hits do
		if canDamage(shooter, hit.model, config) then
			tagCreator(humanoid, shooter)
			humanoid:TakeDamage(hit.damage)
		end
	end

	return hitPositions
end

return DamageResolver
