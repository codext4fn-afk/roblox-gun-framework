--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
--[[
    This turns the part the server's raycast hit into a damage zone, and finds who owns it
    The client never says which zone it hit
]]
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
	-- BodyPart attribute lets custom hitboxes pick a zone without renaming. It's set by the
	-- game's own content, not by clients (attributes set on the client don't replicate up)
	local bodyPart = part:GetAttribute("BodyPart")
	return ZONES[if type(bodyPart) == "string" then bodyPart else part.Name] or "Limb"
end

-- Only looks at the nearest Model above the part, so a part inside a nested model inside a
-- character won't find the humanoid. Dead humanoids return nil so corpses take no damage
function HitZones.GetLivingHumanoid(part: BasePart): (Humanoid?, Model?)
	local model = part:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, model
	end
	return nil, nil
end

return HitZones
