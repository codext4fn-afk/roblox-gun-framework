--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
-- Finds the handle, attachments and joints on a gun model. Models aren't all built facing
-- the same way, so nothing here assumes a direction, the barrel axis is worked out from
-- where the Muzzle attachment sits. Used by WeaponScaler on the server among others. Everything can return nil when a model is missing a piece, callers have to cope.
local AngleMath = require(script.Parent.AngleMath)

local WeaponAxes = {}

-- used when there's no Muzzle attachment
local DEFAULT_MUZZLE = Vector3.new(-1, 0, 0)
local SHOOT_POINT = "ShootFirst"

function WeaponAxes.GetHandle(tool: Instance): BasePart?
	local handle = tool:FindFirstChild("Handle")
	return if handle and handle:IsA("BasePart") then handle else nil
end

function WeaponAxes.GetAttachment(parent: Instance?, name: string): Attachment?
	local attachment = parent and parent:FindFirstChild(name)
	return if attachment and attachment:IsA("Attachment") then attachment else nil
end

-- barrel axis comes from where the Muzzle sits since models aren't all built the same way
function WeaponAxes.ForwardAxis(tool: Instance): Vector3
	local muzzle = WeaponAxes.GetAttachment(WeaponAxes.GetHandle(tool), "Muzzle")
	return AngleMath.DominantAxis(if muzzle then muzzle.Position else DEFAULT_MUZZLE)
end

function WeaponAxes.GunRay(tool: Instance): (Vector3?, Vector3?)
	local handle = WeaponAxes.GetHandle(tool)
	-- recursive search because the shoot point sits on a child part (the barrel), not the handle
	local point = tool:FindFirstChild(SHOOT_POINT, true)
	if not (handle and point and point:IsA("Attachment")) then
		return nil, nil
	end
	return point.WorldPosition, handle.CFrame:VectorToWorldSpace(WeaponAxes.ForwardAxis(tool))
end

-- Bolt and mag parts are expected to carry a Motor6D called GunJoint
function WeaponAxes.FindJoint(tool: Instance, partName: string?): (Motor6D?, BasePart?)
	if type(partName) ~= "string" then
		return nil, nil
	end
	local part = tool:FindFirstChild(partName, true)
	if not (part and part:IsA("BasePart")) then
		return nil, nil
	end
	local joint = part:FindFirstChild("GunJoint")
	if joint and joint:IsA("Motor6D") then
		return joint, part
	end
	return nil, nil
end

return WeaponAxes
