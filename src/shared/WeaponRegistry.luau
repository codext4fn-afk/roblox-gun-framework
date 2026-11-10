--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.
-- The single lookup from a Tool to its WeaponConfig, used by the server and the client.
-- Every module under Configs is merged over Defaults, validated and stored by module name
-- when this module is first required. A broken config is skipped with a warning so the other
-- weapons still load. GetConfig takes `unknown` on purpose, the server passes it whatever
-- a remote sent and gets nil for anything that isn't a configured Tool.
local ConfigMerge = require(script.Parent.ConfigMerge)
local ConfigValidator = require(script.Parent.ConfigValidator)
local Defaults = require(script.Parent.Defaults)
local Types = require(script.Parent.Types)

local configsFolder = script.Parent:WaitForChild("Configs")

local WeaponRegistry = {}

local configs: { [string]: Types.WeaponConfig } = {}

local function register(module: Instance)
	if not module:IsA("ModuleScript") then
		return
	end
	-- strict mode can't type a runtime require
	local overrides = (require :: any)(module) :: { [string]: any }
	for _, key in ConfigMerge.UnknownKeys(Defaults :: any, overrides) do
		warn(`Weapon '{module.Name}': unknown setting '{key}'`)
	end
	local merged = ConfigMerge.Merge(Defaults :: any, overrides)
	-- the Id is always the module name, so the Id inside a config file can't disagree with it
	merged.Id = module.Name
	local errors = ConfigValidator.Validate(merged)
	-- skip broken configs instead of erroring so the rest still load
	if #errors > 0 then
		warn(`Weapon '{module.Name}' was not registered:\n  {table.concat(errors, "\n  ")}`)
		return
	end
	configs[module.Name] = (merged :: any) :: Types.WeaponConfig
end

for _, module in configsFolder:GetChildren() do
	register(module)
end
-- picks up configs added after startup. Editing an already registered module doesn't reload it
configsFolder.ChildAdded:Connect(register)

function WeaponRegistry.GetConfig(tool: unknown): Types.WeaponConfig?
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil
	end
	-- Weapon attribute lets skins share one config
	local weaponId = tool:GetAttribute("Weapon")
	return configs[if type(weaponId) == "string" then weaponId else tool.Name]
end

function WeaponRegistry.GetById(weaponId: string): Types.WeaponConfig?
	return configs[weaponId]
end

-- FindFirstChildOfClass returns the first Tool, which is fine while a character only holds one
function WeaponRegistry.GetEquipped(character: Model): (Tool?, Types.WeaponConfig?)
	local tool = character:FindFirstChildOfClass("Tool")
	local config = WeaponRegistry.GetConfig(tool)
	if config and tool then
		return tool, config
	end
	return nil, nil
end

return WeaponRegistry
