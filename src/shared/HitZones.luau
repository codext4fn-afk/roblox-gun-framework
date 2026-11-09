--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
local Types = require(script.Parent.Types)

-- anything not in here counts as a limb
local ZONES: { [string]: Types.HitZone } = {
	Head = "Head",
	Torso = "Torso",
	HumanoidRootPart = "Torso",
	UpperTorso = "Torso",
	LowerTorso = "Torso",
}

local HitZones = {}

function HitZones.Get(part: BasePart): Types.HitZone
	-- BodyPart attribute lets custom hitboxes pick a zone without renaming
	local bodyPart = part:GetAttribute("BodyPart")
	return ZONES[if type(bodyPart) == "string" then bodyPart else part.Name] or "Limb"
end

function HitZones.GetLivingHumanoid(part: BasePart): (Humanoid?, Model?)
	local model = part:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, model
	end
	return nil, nil
end

return HitZones
