--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Shrinks R6 scale gun models to fit R15 hands. It runs on the server because Size and
-- joint changes made here replicate, so every client sees the same gun. I expect tools to
-- be authored at R6 scale and WeaponService to call Apply once per tool when the owner is
-- R15. Factor and eye relief come from Settings.R15.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponAxes = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponAxes"))

local WeaponScaler = {}

-- prepareTool can fire more than once for the same tool (backpack, then character), so
-- the attribute is what stops it shrinking twice
local SCALED_ATTRIBUTE = "R15Scale"

local function scaleOffset(cframe: CFrame, factor: number): CFrame
	return CFrame.new(cframe.Position * factor) * cframe.Rotation
end

-- Pull AimPoint back so the camera isn't sitting inside the rear sight. Done after the
-- scaling, so eyeRelief is in final studs and isn't shrunk by the factor
local function moveAimPointToEye(tool: Tool, handle: BasePart, eyeRelief: number)
	local aimPoint = WeaponAxes.GetAttachment(handle, "AimPoint")
	if aimPoint then
		aimPoint.Position -= WeaponAxes.ForwardAxis(tool) * eyeRelief
	end
end

function WeaponScaler.Apply(tool: Tool, factor: number, eyeRelief: number)
	local handle = WeaponAxes.GetHandle(tool)
	if tool:GetAttribute(SCALED_ATTRIBUTE) or not handle then
		return
	end
	local origin = handle.CFrame
	-- WeldConstraints snap parts back when they move, turn them off while we reposition.
	-- Joints are different, they only store C0/C1 so I scale those in the same pass
	local welds: { WeldConstraint } = {}
	for _, item in tool:GetDescendants() do
		if item:IsA("WeldConstraint") and item.Enabled then
			item.Enabled = false
			table.insert(welds, item)
		elseif item:IsA("JointInstance") then
			item.C0 = scaleOffset(item.C0, factor)
			item.C1 = scaleOffset(item.C1, factor)
		elseif item:IsA("Attachment") then
			item.Position *= factor
		end
	end
	-- second pass so every weld is already off before any part moves. Positions are scaled
	-- relative to the handle so the whole gun shrinks toward it
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			local relative = origin:ToObjectSpace(part.CFrame)
			part.Size *= factor
			part.CFrame = origin * scaleOffset(relative, factor)
		end
	end
	for _, weld in welds do
		weld.Enabled = true
	end
	tool.Grip = scaleOffset(tool.Grip, factor)
	moveAimPointToEye(tool, handle, eyeRelief)
	tool:SetAttribute(SCALED_ATTRIBUTE, factor)
end

return WeaponScaler
