--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

-- Server side of the gun system. The client predicts everything for responsiveness, and
-- this module is the one that decides what actually happened. It owns ammo, reload state,
-- the Aiming and AimPitch attributes, per character setup and the four client remotes.
-- Replicated state: Tool.Ammo, Tool.Reloading, Character.Aiming, Character.AimPitch.
--
-- I only trust two things from a client: which tool it says it's using and a set of
-- directions, and both get validated (ShotValidator for the values, getEquippedGun for
-- the tool). Damage math lives in DamageResolver, posing in PoseReplicator, and I expect
-- WeaponRegistry.GetConfig to accept junk and return nil, since the tool argument comes
-- straight off a remote.

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
	-- TODO(me): explain. Only onReload bumps this and Reloading blocks a second reload, so I can't see when a token goes stale
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

-- The tool comes from the client, so check it's a real configured Tool, parented to this
-- player's own living character. Tool.Parent == character is what means "equipped", a
-- tool sitting in the backpack or in someone else's hands is refused
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

-- The shot origin is client supplied, so without this you could put it on the far side of
-- a thin wall and shoot through. Cast from the head, which the server knows, to the origin.
-- Accessories and held tools have CanQuery off so they don't count as walls
local function hasLineOfSight(character: Model, from: Vector3, to: Vector3): boolean
	local offset = to - from
	if offset.Magnitude < 1e-3 then
		return true
	end
	return workspace:Raycast(from, offset, Raycast.Excluding({ character })) == nil
end

-- Only players within ReplicateDistance get the effects, so far away clients aren't sent
-- remote calls for shots they can't see. The shooter is skipped because they already
-- played it locally
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

-- Aiming counts as a requirement for firing. desiredAiming is checked too because the
-- attribute can lag behind when SetAiming was rate limited, and I don't want to reject
-- a shot from someone who really did press aim first
local function isAiming(player: Player, character: Model): boolean
	return character:GetAttribute("Aiming") == true or getPlayerState(player).desiredAiming
end

-- Order matters here. Cheap checks first, then the raycast for line of sight, and the
-- ShotClock goes last so a request that was going to be refused anyway doesn't use up
-- burst credit. Ammo is only touched once everything has passed. There's no limiter on
-- Fire itself, the ShotClock is the limit.
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
	-- hip spread + tolerance since we can't know how far into ADS the client was, so hip
	-- spread is the widest cone that could be legit. Bad pellets are dropped, the shot isn't
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

-- The server decides when a reload finishes. The client animation is only cosmetic, ammo
-- is refilled by the delay below
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
		-- Reloading is always cleared, but the ammo only comes back if the gun is still in
		-- the hands of a living owner. Otherwise swapping away mid reload would be a free refill
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

-- Unlike pitch, an aim toggle can't just be dropped: a lost release would leave the
-- player aiming for good. So the latest wish is stored right away and applied when the
-- limiter allows. One delayed flush at a time is enough since it applies whatever the
-- newest value is when it runs
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

-- Pitch is continuous, so if it's over the rate limit I just drop it, the next sample
-- replaces it. NaN fails pitch ~= pitch, and the clamp handles inf and huge values
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
	-- called from several places for the same tool, so everything in here has to be safe to
	-- repeat. WeaponScaler guards itself and Ammo is only seeded when it's nil
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

-- Posing follows whether a tool is equipped. Aiming is reset when there isn't one so a
-- stale true can't let someone fire the moment they re-equip
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

-- Everything per character goes through here and every connection is put in
-- characterConnections so respawning or leaving can drop them all at once
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
	-- the join path can reach here twice for the same character (CharacterAdded and the
	-- initial spawn), disconnecting first makes the second run replace the first
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

-- PlayerRemoving cleanup: connections, state and limiter entries all hold the Player
-- alive otherwise
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
