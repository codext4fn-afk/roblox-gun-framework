--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    These are command bar helpers for rigging gun models
    require(game.ServerStorage.WeaponEditor.GunSetup).Build(workspace.MyGun)
    It only runs while editing, and it gives the gun one Handle, welds the parts to it, and adds a GunJoint to the bolt and mag parts named in the config
    Mechanics treats the GunJoint C0 as the rest position, so the whole offset has to be in C0
]]
-- TODO(me): explain why Scale exists here as well as WeaponScaler on the server, I can't tell if both are meant to be used

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local WeaponRegistry = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponRegistry"))

local GunSetup = {}

export type NudgeOptions = {
	left: number?,
	up: number?,
	forward: number?,
	yaw: number?,
	pitch: number?,
	roll: number?,
}

-- this only removes joints made by this script, matched by name
-- that way a weld or joint that came with the model is not deleted when Build or Scale runs again
local JOINT_NAMES: { [string]: boolean } = {
	GunWeld = true,
	GunJoint = true,
}
local SOUND_NAMES = { "Fire", "Reload", "Empty", "MagOut", "MagIn" }

-- pcall so a failed waypoint never stops the build
local function waypoint(name: string)
	pcall(ChangeHistoryService.SetWaypoint, ChangeHistoryService, name)
end

local function getParts(tool: Tool): { BasePart }
	local parts = {}
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

local function getMovingPartNames(tool: Tool): { [string]: boolean }
	local names = {}
	local config = WeaponRegistry.GetConfig(tool)
	if config then
		names[config.Bolt.Part] = true
		names[config.Magazine.Part] = true
	end
	return names
end

local function removeJoints(tool: Tool)
	for _, item in tool:GetDescendants() do
		if JOINT_NAMES[item.Name] and (item:IsA("WeldConstraint") or item:IsA("JointInstance")) then
			item:Destroy()
		end
	end
end

-- no collision, touch or queries and massless so the gun doesn't mess with the character
local function attachToHandle(tool: Tool, handle: BasePart): { string }
	local movingNames = getMovingPartNames(tool)
	local movable = {}
	for _, part in getParts(tool) do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		if part ~= handle then
			part.Massless = true
			if movingNames[part.Name] then
				-- all the offset goes in C0, Mechanics treats it as rest
				local joint = Instance.new("Motor6D")
				joint.Name = "GunJoint"
				joint.Part0 = handle
				joint.Part1 = part
				joint.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
				joint.C1 = CFrame.identity
				joint.Parent = part
				table.insert(movable, part.Name)
			else
				local weld = Instance.new("WeldConstraint")
				weld.Name = "GunWeld"
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	return movable
end

local function hasAttachment(parent: Instance?, name: string, recursive: boolean?): boolean
	local item = parent and parent:FindFirstChild(name, recursive)
	return item ~= nil and item:IsA("Attachment")
end

-- it is safe to run again, since the old GunWeld and GunJoint objects are removed before new ones are made
-- the Handle is the given part, else the existing one, else the biggest part, and that last one is only a guess
function GunSetup.Build(tool: Tool, handlePart: BasePart?): BasePart
	assert(typeof(tool) == "Instance" and tool:IsA("Tool"), "Pass a Tool")
	local parts = getParts(tool)
	assert(#parts > 0, "The Tool has no parts")

	local existing = tool:FindFirstChild("Handle")
	local handle: BasePart
	if handlePart then
		handle = handlePart
	elseif existing and existing:IsA("BasePart") then
		handle = existing
	else
		table.sort(parts, function(a, b)
			return a.Size.Magnitude > b.Size.Magnitude
		end)
		handle = parts[1]
	end
	for _, item in tool:GetDescendants() do
		-- Roblox grips the first Handle it finds
		if item.Name == "Handle" and item ~= handle then
			item.Name = "GunPart"
		end
	end
	handle.Name = "Handle"
	handle.Parent = tool

	removeJoints(tool)
	local movable = attachToHandle(tool, handle)
	tool.RequiresHandle = true

	print(`GunSetup: {tool.Name} built, movable parts: {if #movable > 0 then table.concat(movable, ", ") else "none"}`)
	waypoint("GunSetup.Build")
	GunSetup.Validate(tool)
	return handle
end

-- this prints a checklist
-- MISSING ones break the gun, and OPTIONAL ones only turn off a feature or fall back to an estimate (see WeaponGeometry and Effects)
function GunSetup.Validate(tool: Tool)
	assert(typeof(tool) == "Instance" and tool:IsA("Tool"), "Pass a Tool")
	local config = WeaponRegistry.GetConfig(tool)
	local handle = tool:FindFirstChild("Handle")
	local lines = {}

	local function check(passed: boolean, required: boolean, description: string)
		local status = if passed then "OK      " elseif required then "MISSING " else "OPTIONAL"
		table.insert(lines, `{status}  {description}`)
	end

	local weaponId = tool:GetAttribute("Weapon")
	check(
		config ~= nil,
		true,
		`Config module named '{if type(weaponId) == "string" then weaponId else tool.Name}' in Configs`
	)
	check(handle ~= nil and handle:IsA("BasePart"), true, "Part named Handle directly in the Tool")
	check(hasAttachment(handle, "Muzzle"), true, "Attachment 'Muzzle' in Handle at the barrel tip")
	check(
		hasAttachment(tool, "ShootFirst", true),
		false,
		"Attachment 'ShootFirst' on the sight line (first-person shots)"
	)
	check(hasAttachment(handle, "AimPoint"), false, "Attachment 'AimPoint' in Handle behind the sight (scope camera)")
	check(hasAttachment(handle, "Ejection"), false, "Attachment 'Ejection' in Handle at the ejection port")
	check(
		hasAttachment(handle, "SupportGrip"),
		false,
		"Attachment 'SupportGrip' in Handle where the support hand holds (R15)"
	)

	if config then
		local features: { { name: string, part: string } } = {
			{ name = "Bolt", part = config.Bolt.Part },
			{ name = "Magazine", part = config.Magazine.Part },
		}
		for _, feature in features do
			local part = tool:FindFirstChild(feature.part, true)
			local joint = part and part:FindFirstChild("GunJoint")
			check(joint ~= nil, false, `{feature.name} part '{feature.part}' with a GunJoint (run GunSetup.Build)`)
		end
	end

	for _, soundName in SOUND_NAMES do
		local sound = handle and handle:FindFirstChild(soundName)
		check(sound ~= nil and sound:IsA("Sound"), false, `Sound '{soundName}' in Handle`)
	end

	print(`GunSetup.Validate: {tool.Name}\n{table.concat(lines, "\n")}`)
end

-- this resizes everything around the Handle and then rebuilds the joints
-- scaling with the welds on would snap parts back, which is the same problem WeaponScaler solves at runtime
function GunSetup.Scale(tool: Tool, factor: number)
	local handle = tool:FindFirstChild("Handle")
	assert(handle and handle:IsA("BasePart"), "Run GunSetup.Build first")
	removeJoints(tool)

	local origin = handle.CFrame
	for _, part in getParts(tool) do
		local relative = origin:ToObjectSpace(part.CFrame)
		part.Size *= factor
		part.CFrame = origin * (relative - relative.Position) + origin:VectorToWorldSpace(relative.Position * factor)
	end
	for _, item in tool:GetDescendants() do
		if item:IsA("Attachment") then
			item.Position *= factor
		end
	end
	local grip = tool.Grip
	tool.Grip = CFrame.new(grip.Position * factor) * (grip - grip.Position)

	attachToHandle(tool, handle)
	waypoint("GunSetup.Scale")
end

function GunSetup.AddAimPoint(tool: Tool): Attachment
	local handle = tool:FindFirstChild("Handle")
	assert(handle and handle:IsA("BasePart"), "Run GunSetup.Build first")
	local existing = handle:FindFirstChild("AimPoint")
	local point: Attachment
	if existing and existing:IsA("Attachment") then
		point = existing
	else
		point = Instance.new("Attachment")
		point.Name = "AimPoint"
		point.Parent = handle
	end
	Selection:Set({ point })
	waypoint("GunSetup.AddAimPoint")
	return point
end

function GunSetup.Nudge(tool: Tool, options: NudgeOptions?)
	local settings: NudgeOptions = options or {}
	local offset = Vector3.new(-(settings.left or 0), settings.up or 0, -(settings.forward or 0))
	local rotation = CFrame.Angles(0, math.rad(-(settings.yaw or 0)), 0)
		* CFrame.Angles(math.rad(settings.pitch or 0), 0, 0)
		* CFrame.Angles(0, 0, math.rad(-(settings.roll or 0)))
	-- Grip is the hand relative to the handle, so it is inverted
	-- moving the gun one way means moving the grip the other way
	tool.Grip = tool.Grip * rotation:Inverse() * CFrame.new(-offset)
	waypoint("GunSetup.Nudge")
end

return GunSetup
