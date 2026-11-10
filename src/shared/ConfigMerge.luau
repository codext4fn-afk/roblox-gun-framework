--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Used by WeaponRegistry when it loads weapon modules: Merge lays a weapon's overrides
-- over Defaults and UnknownKeys warns about typos. It works on plain nested tables and
-- doesn't know about WeaponConfig itself.

local ConfigMerge = {}

-- Copy so a weapon never shares a nested table with Defaults, otherwise editing one
-- weapon's Damage at runtime would change every other weapon too. Vector3, CFrame and
-- Color3 are userdata, not tables, so they fall through and get shared, which is fine
-- because they're immutable
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = deepCopy(item)
	end
	return result
end

function ConfigMerge.Merge(base: { [string]: any }, override: { [string]: any }): { [string]: any }
	local result = deepCopy(base)
	for key, value in override do
		-- only merge when both sides are tables, anything else the override just replaces
		if type(value) == "table" and type(base[key]) == "table" then
			result[key] = ConfigMerge.Merge(base[key], value)
		else
			result[key] = deepCopy(value)
		end
	end
	return result
end

-- Catches typos in weapon configs like Recoil.Kik. Merge would happily carry an unknown
-- key along and nothing would ever read it. This only works because Defaults lists every
-- key, so a new setting has to be added there first
function ConfigMerge.UnknownKeys(base: { [string]: any }, override: { [string]: any }, path: string?): { string }
	local unknown = {}
	for key, value in override do
		local fullKey = if path then `{path}.{key}` else key
		if base[key] == nil then
			table.insert(unknown, fullKey)
		elseif type(value) == "table" and type(base[key]) == "table" then
			for _, nested in ConfigMerge.UnknownKeys(base[key], value, fullKey) do
				table.insert(unknown, nested)
			end
		end
	end
	table.sort(unknown)
	return unknown
end

return ConfigMerge
