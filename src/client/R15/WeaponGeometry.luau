--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This reads AimPoint, SupportGrip and the mag well from a gun model, and uses guesses if they are missing
    It works in the Handle's space and is cached per tool, and WeaponRig is the only one that uses it
]]
-- TODO(me): explain where SUPPORT_ALONG, SUPPORT_BELOW_BORE and the FALLBACK_EYE values come from

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local AngleMath = require(WeaponSystem:WaitForChild("AngleMath"))
local Types = require(WeaponSystem:WaitForChild("Types"))
local WeaponAxes = require(WeaponSystem:WaitForChild("WeaponAxes"))

export type Geometry = {
	handle: BasePart,
	eyeFrame: CFrame,
	supportFrame: CFrame,
	magazineWell: Vector3?,
	verticalGrip: boolean,
	reach: number,
}

local WeaponGeometry = {}

local SUPPORT_ALONG = 0.38
local SUPPORT_BELOW_BORE = 0.16
local FALLBACK_EYE_HEIGHT = 0.35
local FALLBACK_EYE_BACK = 0.25

-- false means there's no Handle, so a broken tool isn't rebuilt on every frame
local cache: { [Tool]: Geometry | false } = setmetatable({}, { __mode = "k" }) :: any

local function attachmentPosition(handle: BasePart, name: string): Vector3?
	local attachment = WeaponAxes.GetAttachment(handle, name)
	return if attachment then attachment.Position else nil
end

-- this prefers the GunJoint's C0, since that is where the mag sits at rest
-- otherwise it uses the position of the mag part
local function findMagazineWell(tool: Tool, handle: BasePart, config: Types.WeaponConfig): Vector3?
	local part = tool:FindFirstChild(config.Magazine.Part, true)
	local joint = part and part:FindFirstChild("GunJoint")
	if joint and joint:IsA("Motor6D") and joint.Part0 == handle then
		return joint.C0.Position
	end
	return if part and part:IsA("BasePart") then handle.CFrame:PointToObjectSpace(part.Position) else nil
end

local function build(tool: Tool, config: Types.WeaponConfig): Geometry?
	local handle = WeaponAxes.GetHandle(tool)
	if not handle then
		return nil
	end
	local forward = WeaponAxes.ForwardAxis(tool)
	local muzzle = attachmentPosition(handle, "Muzzle") or forward * handle.Size:Dot(forward:Abs()) / 2
	local length = handle.Size:Dot(forward:Abs())
	local eye = attachmentPosition(handle, "AimPoint")
	-- the sights sit above the bore, so that is used for up
	-- the offset of AimPoint from the barrel axis points toward the sights, and it is snapped to an axis
	-- without an AimPoint, up is world up and the eye is a guess
	local up: Vector3
	if eye then
		local lateral = eye - forward * eye:Dot(forward)
		up = if lateral.Magnitude > 1e-3 then AngleMath.DominantAxis(lateral) else Vector3.yAxis
	else
		up = Vector3.yAxis
		eye = up * handle.Size.Y * FALLBACK_EYE_HEIGHT - forward * length * FALLBACK_EYE_BACK
	end
	local eyePoint = eye :: Vector3
	local back = -forward
	local right = up:Cross(back)
	local orientation = CFrame.fromMatrix(Vector3.zero, right, up, back)

	local boreHeight = muzzle:Dot(up)
	local reach = (muzzle - eyePoint):Dot(forward)
	-- no SupportGrip means the off hand position is an estimate along the gun below the bore
	local supportAttachment = WeaponAxes.GetAttachment(handle, "SupportGrip")
	local supportPoint = attachmentPosition(handle, "SupportGrip")
	if not supportPoint then
		local estimate = eyePoint + forward * reach * SUPPORT_ALONG
		supportPoint = estimate + up * (boreHeight - estimate:Dot(up) - SUPPORT_BELOW_BORE)
	end

	return {
		handle = handle,
		eyeFrame = CFrame.new(eyePoint) * orientation,
		supportFrame = CFrame.new(supportPoint :: Vector3) * orientation,
		magazineWell = findMagazineWell(tool, handle, config),
		verticalGrip = supportAttachment ~= nil and supportAttachment:GetAttribute("VerticalGrip") == true,
		reach = reach,
	}
end

function WeaponGeometry.Get(tool: Tool, config: Types.WeaponConfig): Geometry?
	local cached = cache[tool]
	if typeof(cached) == "table" then
		return cached
	elseif cached == false then
		return nil
	end
	local geometry = build(tool, config)
	cache[tool] = if geometry then geometry else false
	return geometry
end

return WeaponGeometry
