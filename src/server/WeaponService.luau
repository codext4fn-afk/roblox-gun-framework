--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This is the server side of the gun system, the client predicts and this script decides
    It controls ammo, reload state, Aiming and AimPitch, the setup of each character and the four client remotes
    The only things taken from the client are the tool and the pellet directions, and both get checked
    Replicated state: Tool.Ammo, Tool.Reloading, Character.Aiming, Character.AimPitch
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local Raycast = require(WeaponSystem:WaitForChild("Raycast"))
local Remotes = require(WeaponSystem:WaitForChild("Remotes"))
local Rig = require(WeaponSystem:WaitForChild("Rig"))
local Settings = require(WeaponSystem:WaitForChild("Settings"))
local Types = require(WeaponSystem:WaitForChild("Types"))
local WeaponRegistry = require(WeaponSystem:WaitForChild("WeaponRegistry"))

local DamageResolver = require(script.Parent.DamageResolver)
local PoseReplicator = require(script.Parent.PoseReplicator)
local RequestLimiter = require(script.Parent.RequestLimiter)
local ShotClock = require(script.Parent.ShotClock)
local ShotValidator = require(script.Parent.ShotValidator)
local WeaponScaler = require(script.Parent.WeaponScaler)

local CharacterRig = Rig.CharacterRig
local ServerSettings = Settings.Server

type ToolState = {
	clock: ShotClock.ShotClock,
	-- this goes up on every reload and is checked again when the timer ends
	-- that way a timer from an older reload does nothing
	-- right now only onReload changes it, and Reloading already blocks a second reload, so it never differs
	-- it is here so a future cancel (unequip, death) only has to bump it to stop the refill
	reloadToken: number,
}

type PlayerState = {
	desiredAiming: boolean,
	aimFlushPending: boolean,
	characterConnections: { RBXScriptConnection },
}

local WeaponService = {}

local limiter = RequestLimiter.new(ServerSettings.RequestIntervals)
-- weak keys so a destroyed tool takes its clock with it, nothing has to clean these up
local toolStates: { [Tool]: ToolState } = setmetatable({}, { __mode = "k" }) :: any
local playerStates: { [Player]: PlayerState } = {}

local function getPlayerState(player: Player): PlayerState
	local state = playerStates[player]
	if not state then
		state = { desiredAiming = false, aimFlushPending = false, characterConnections = {} }
		playerStates[player] = state
	end
	return state
end

-- created lazily on first use because the config is needed for the fire interval
local function getToolState(tool: Tool, config: Types.WeaponConfig): ToolState
	local state = toolStates[tool]
	if not state then
		state = { clock = ShotClock.new(config.FireInterval, ServerSettings.FireRateBurst), reloadToken = 0 }
		toolStates[tool] = state
	end
	return state
end

local function getAmmo(tool: Tool, config: Types.WeaponConfig): number
	local ammo = tool:GetAttribute("Ammo")
	return if type(ammo) == "number" then ammo else config.MagSize
end

-- the tool comes from the client, so it has to be checked
-- it must be a real configured Tool inside this player's own living character
-- Tool.Parent == character means it is equipped, so a tool in the backpack or in someone else's hands is refused
local function getEquippedGun(player: Player, tool: unknown): (Model?, Tool?, Types.WeaponConfig?)
	local config = WeaponRegistry.GetConfig(tool)
	local character = player.Character
	if not config or not character or typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil, nil, nil
	end
	if tool.Parent ~= character or not CharacterRig.IsAlive(character) then
		return nil, nil, nil
	end
	return character, tool, config
end

local function getHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

-- the shot origin comes from the client, so without this check it could be placed behind a thin wall
-- the ray goes from the head, which the server knows, to the origin
-- accessories and held tools have CanQuery off, so they do not count as walls
local function hasLineOfSight(character: Model, from: Vector3, to: Vector3): boolean
	local offset = to - from
	if offset.Magnitude < 1e-3 then
		return true
	end
	return workspace:Raycast(from, offset, Raycast.Excluding({ character })) == nil
end

-- only players within ReplicateDistance get the effects, since far away clients cannot see the shot anyway
-- the shooter is skipped because they already played it locally
local function getNearbyPlayers(shooter: Player, position: Vector3): { Player }
	local nearby = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = other ~= shooter and character and character:FindFirstChild("HumanoidRootPart")
		if
			root
			and root:IsA("BasePart")
			and (root.Position - position).Magnitude <= ServerSettings.ReplicateDistance
		then
			table.insert(nearby, other)
		end
	end
	return nearby
end

-- aiming is required for firing
-- desiredAiming is checked too, because the attribute can lag behind when SetAiming was rate limited
-- without it a shot from someone who really pressed aim first would be rejected
local function isAiming(player: Player, character: Model): boolean
	return character:GetAttribute("Aiming") == true or getPlayerState(player).desiredAiming
end

-- the order matters here
-- cheap checks go first, then the raycast for line of sight
-- ShotClock goes last, because a request that gets refused anyway should not use up burst credit
-- ammo only changes after everything passed, and Fire has no limiter, ShotClock is the limit
local function onFire(player: Player, tool: unknown, origin: unknown, aimDirection: unknown, directions: unknown)
	local character, equipped, config = getEquippedGun(player, tool)
	if not (character and equipped and config) or not isAiming(player, character) then
		return
	end
	if ShotValidator.CheckArguments(origin, aimDirection, directions, config.Pellets) then
		return
	end
	local shotOrigin = origin :: Vector3
	local aim = (aimDirection :: Vector3).Unit
	if equipped:GetAttribute("Reloading") == true then
		return
	end
	local ammo = getAmmo(equipped, config)
	if ammo <= 0 then
		return
	end
	local head = getHead(character)
	-- TODO(me): explain why MaxOriginOffset is 6 studs, don't know how that number was picked
	if not head or not ShotValidator.OriginWithinReach(shotOrigin, head.Position, ServerSettings.MaxOriginOffset) then
		return
	end
	if not hasLineOfSight(character, head.Position, shotOrigin) then
		return
	end
	if not getToolState(equipped, config).clock:TryConsume(os.clock()) then
		return
	end

	equipped:SetAttribute("Ammo", ammo - 1)
	-- the server cannot know how far into ADS the client was, so hip spread plus a tolerance is the widest cone that could be real
	-- bad pellets are dropped one by one, the shot is not
	local accepted = ShotValidator.FilterDirections(
		directions :: { unknown },
		aim,
		config.HipSpread + ServerSettings.SpreadTolerance
	)
	local hitPositions = DamageResolver.Resolve(player, character, config, shotOrigin, accepted)
	for _, other in getNearbyPlayers(player, shotOrigin) do
		Remotes.ReplicateShot:FireClient(other, equipped, hitPositions)
	end
end

-- the server decides when a reload finishes, and the client animation is only for looks
-- the ammo is refilled by the delay below
local function onReload(player: Player, tool: unknown)
	if not limiter:Allow(player, "Reload", os.clock()) then
		return
	end
	local character, equipped, config = getEquippedGun(player, tool)
	if not (character and equipped and config) then
		return
	end
	if equipped:GetAttribute("Reloading") == true or getAmmo(equipped, config) >= config.MagSize then
		return
	end

	local state = getToolState(equipped, config)
	state.reloadToken += 1
	local token = state.reloadToken
	-- blocks firing for the whole reload, onFire checks this attribute
	equipped:SetAttribute("Reloading", true)
	local head = getHead(character)
	if head then
		for _, other in getNearbyPlayers(player, head.Position) do
			Remotes.ReplicateReload:FireClient(other, equipped)
		end
	end

	task.delay(config.ReloadTime, function()
		if state.reloadToken ~= token then
			return
		end
		-- Reloading is always cleared
		-- the ammo only comes back if the gun is still held by a living owner, otherwise swapping away mid reload would be a free refill
		if equipped.Parent == player.Character and CharacterRig.IsAlive(player.Character) then
			equipped:SetAttribute("Ammo", config.MagSize)
		end
		equipped:SetAttribute("Reloading", false)
	end)
end

local function applyDesiredAiming(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("Aiming", getPlayerState(player).desiredAiming)
	end
end

-- unlike pitch, an aim toggle cannot be dropped, because a lost release would leave the player aiming forever
-- so the newest value is saved right away and applied when the limiter allows
-- one delayed flush at a time is enough, since it applies whatever the newest value is when it runs
local function onSetAiming(player: Player, aiming: unknown)
	local state = getPlayerState(player)
	state.desiredAiming = aiming == true
	if limiter:Allow(player, "SetAiming", os.clock()) then
		applyDesiredAiming(player)
	elseif not state.aimFlushPending then
		state.aimFlushPending = true
		task.delay(limiter:Interval("SetAiming"), function()
			state.aimFlushPending = false
			-- the player may have left (or been reset) while this was waiting
			if playerStates[player] == state then
				applyDesiredAiming(player)
			end
		end)
	end
end

-- pitch is continuous, so if it is over the rate limit it is dropped and the next sample replaces it
-- NaN fails pitch ~= pitch, and the clamp handles inf and huge values
local function onAimPitch(player: Player, pitch: unknown)
	local character = player.Character
	if not character or type(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	if limiter:Allow(player, "AimPitch", os.clock()) then
		character:SetAttribute("AimPitch", math.clamp(pitch, -ServerSettings.MaxPitch, ServerSettings.MaxPitch))
	end
end

local function prepareTool(tool: Tool, isR15: boolean)
	local config = WeaponRegistry.GetConfig(tool)
	if not config then
		return
	end
	-- this is called from several places for the same tool, so it has to be safe to repeat
	-- WeaponScaler guards itself, and Ammo is only set when it is nil
	if isR15 then
		WeaponScaler.Apply(tool, Settings.R15.WeaponScale, Settings.R15.EyeRelief)
	end
	if tool:GetAttribute("Ammo") == nil then
		tool:SetAttribute("Ammo", config.MagSize)
		tool:SetAttribute("Reloading", false)
	end
end

local function prepareDescendant(item: Instance, isR15: boolean)
	if item:IsA("Tool") then
		prepareTool(item, isR15)
	elseif
		item:IsA("BasePart") and (item:FindFirstAncestorOfClass("Accessory") or item:FindFirstAncestorOfClass("Tool"))
	then
		-- hats and held tools shouldn't block shots, and this is also what keeps them from
		-- blocking the line of sight check on the origin
		item.CanQuery = false
	end
end

-- posing follows whether a tool is equipped
-- Aiming is reset when there is none, so an old true cannot let someone fire the moment they equip again
local function refreshPosing(character: Model)
	if WeaponRegistry.GetEquipped(character) then
		PoseReplicator.Start(character)
	else
		character:SetAttribute("Aiming", false)
		PoseReplicator.Stop(character)
	end
end

local function disconnectCharacter(state: PlayerState)
	for _, connection in state.characterConnections do
		connection:Disconnect()
	end
	table.clear(state.characterConnections)
end

-- everything for a character goes through here
-- every connection is saved in characterConnections, so respawning or leaving can drop them all at once
local function watchCharacter(player: Player, character: Model)
	if not character.Parent then
		return
	end
	-- this yields, so the character can be gone by the time it returns, hence the second
	-- Parent check
	local humanoid = character:WaitForChild("Humanoid", ServerSettings.HumanoidWait)
	if not (character.Parent and humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local state = getPlayerState(player)
	-- a player who joins can reach this twice for the same character (CharacterAdded and the first spawn)
	-- disconnecting first makes the second run replace the first
	disconnectCharacter(state)
	state.desiredAiming = false
	local isR15 = CharacterRig.IsR15(character)
	local connections = state.characterConnections

	character:SetAttribute("AimPitch", 0)
	character:SetAttribute("Aiming", false)

	-- tools in the backpack are prepared up front so Ammo and the R15 scale are already set
	-- by the time they get equipped
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") then
				prepareTool(item, isR15)
			end
		end
		table.insert(
			connections,
			backpack.ChildAdded:Connect(function(item)
				if item:IsA("Tool") then
					prepareTool(item, isR15)
				end
			end)
		)
	end
	for _, item in character:GetDescendants() do
		prepareDescendant(item, isR15)
	end
	table.insert(
		connections,
		character.DescendantAdded:Connect(function(item)
			prepareDescendant(item, isR15)
		end)
	)
	local function onToolChanged(child: Instance)
		if child:IsA("Tool") then
			refreshPosing(character)
		end
	end
	table.insert(connections, character.ChildAdded:Connect(onToolChanged))
	table.insert(connections, character.ChildRemoved:Connect(onToolChanged))
	table.insert(
		connections,
		humanoid.Died:Connect(function()
			character:SetAttribute("Aiming", false)
			PoseReplicator.Stop(character)
		end)
	)
	refreshPosing(character)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		PoseReplicator.Stop(character)
		local state = playerStates[player]
		if state then
			disconnectCharacter(state)
		end
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

-- cleanup when a player leaves
-- the connections, state and limiter entries would all keep the Player alive otherwise
local function forgetPlayer(player: Player)
	local state = playerStates[player]
	if state then
		disconnectCharacter(state)
		playerStates[player] = nil
	end
	limiter:Forget(player)
end

function WeaponService.Start()
	Remotes.Fire.OnServerEvent:Connect(onFire)
	Remotes.Reload.OnServerEvent:Connect(onReload)
	Remotes.SetAiming.OnServerEvent:Connect(onSetAiming)
	Remotes.AimPitch.OnServerEvent:Connect(onAimPitch)
	PoseReplicator.Run()

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(forgetPlayer)
	-- players who joined before this ran (happens in Studio)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return WeaponService
