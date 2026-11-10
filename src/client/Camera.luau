--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    This sits on top of the default camera and changes FOV, sensitivity, shoulder, body rotation, recoil and scope
    It runs after the default camera every frame, so collisions still come from Roblox
    Render order: camera +1, AimPose +3, scope +4, WeaponController +5
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponSystem = ReplicatedStorage:WaitForChild("WeaponSystem")
local AngleMath = require(WeaponSystem:WaitForChild("AngleMath"))
local Recoil = require(WeaponSystem:WaitForChild("Recoil"))
local Settings = require(WeaponSystem:WaitForChild("Settings"))
local Types = require(WeaponSystem:WaitForChild("Types"))
local WeaponAxes = require(WeaponSystem:WaitForChild("WeaponAxes"))

local player = Players.LocalPlayer
local CameraSettings = Settings.Camera

local Camera = {}

local CAMERA_BIND_NAME = "GunCamera"
local SCOPE_BIND_NAME = "GunScope"
local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value + 1
-- after AimPose places the gun, since the scope snaps to the gun's AimPoint
local SCOPE_PRIORITY = Enum.RenderPriority.Camera.Value + 4

local lerp = AngleMath.Lerp

local active = false
local config: Types.WeaponConfig? = nil
local tool: Tool? = nil
local defaultFOV = 70

local aiming = false
local zooming = false
local zoomAlpha = 0
local readyAlpha = 0
local firstPersonAlpha = 0
local firstPerson = false
local shoulderSide = 1

local controllingRotation, savedAutoRotate = false, true
local warnedMissingAimPoint: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()
local recoil = Recoil.new({
	recovery = CameraSettings.RecoilRecovery,
	sideways = CameraSettings.RecoilSideways,
	shakeRecovery = CameraSettings.ShakeRecovery,
	shakeMax = CameraSettings.ShakeMax,
})

local function getCharacterParts(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return character:FindFirstChildOfClass("Humanoid"), if root and root:IsA("BasePart") then root else nil
end

local function faceDirection(root: BasePart, direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

-- savedAutoRotate is only captured the first time, otherwise taking rotation twice would
-- save my own `false` and AutoRotate would never come back
local function takeRotation(humanoid: Humanoid)
	if not controllingRotation then
		savedAutoRotate = humanoid.AutoRotate
		controllingRotation = true
	end
	humanoid.AutoRotate = false
end

local function releaseRotation(humanoid: Humanoid)
	if controllingRotation then
		humanoid.AutoRotate = savedAutoRotate
		controllingRotation = false
	end
end

local function getAimPoint(): Attachment?
	local current = tool
	if not current then
		return nil
	end
	local point = WeaponAxes.GetAttachment(WeaponAxes.GetHandle(current), "AimPoint")
	if point then
		return point
	end
	if not warnedMissingAimPoint[current] then
		warnedMissingAimPoint[current] = true
		-- once per tool, this runs every frame while scoped and would flood the output
		warn(`{current.Name}: add an Attachment named 'AimPoint' in Handle for first-person scoping`)
	end
	return nil
end

local function updateZoom(camera: Camera, weapon: Types.WeaponConfig, blend: number)
	zoomAlpha = lerp(zoomAlpha, if zooming then 1 else 0, blend)
	readyAlpha = lerp(readyAlpha, if aiming then 1 else 0, blend)
	firstPersonAlpha = lerp(firstPersonAlpha, if firstPerson then 1 else 0, blend)

	local baseFOV = lerp(defaultFOV, weapon.FirstPersonFOV, firstPersonAlpha)
	local zoomFOV = if firstPerson then weapon.ScopeFOV else weapon.AimFOV
	camera.FieldOfView = lerp(baseFOV, zoomFOV, zoomAlpha)

	-- tan ratio keeps crosshair movement the same at any zoom, AimSensitivity is the per
	-- weapon extra on top
	local zoomSensitivity = math.tan(math.rad(zoomFOV) / 2) / math.tan(math.rad(baseFOV) / 2) * weapon.AimSensitivity
	UserInputService.MouseDeltaSensitivity = lerp(1, zoomSensitivity, zoomAlpha)
end

-- CameraOffset so the default camera still handles collisions
local function updateShoulder(humanoid: Humanoid, blend: number)
	local offset = CameraSettings.ShoulderOffset
	local shoulder = Vector3.new(offset.X * shoulderSide, offset.Y, offset.Z)
	local target = if zooming and not firstPerson then shoulder else Vector3.zero
	humanoid.CameraOffset = humanoid.CameraOffset:Lerp(target, blend)
end

-- While aiming the character faces where the camera looks, so the gun points at the crosshair
-- Writing root.CFrame is fine here since the client owns its own character's physics
local function updateBodyRotation(camera: Camera, humanoid: Humanoid, root: BasePart)
	if aiming then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		takeRotation(humanoid)
		faceDirection(root, camera.CFrame.LookVector)
	else
		releaseRotation(humanoid)
	end
end

local function updateRecoilAndShake(camera: Camera, deltaTime: number)
	local pitch, yaw, shake = recoil:Step(deltaTime)
	-- applied on top every frame and not baked into the player's real camera angle, so it
	-- recovers by itself. Because GetAimRay reads this camera, shots do follow the kick
	camera.CFrame *= CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
	if shake > 1e-3 and firstPerson then
		local t = os.clock() * CameraSettings.ShakeFrequency
		camera.CFrame *= CFrame.Angles(
			math.rad(math.noise(t, 0.3) * 2 * shake),
			math.rad(math.noise(t, 7.1) * 2 * shake),
			math.rad(math.noise(t, 13.7) * 1.2 * shake)
		)
	end
end

local function updateCamera(deltaTime: number)
	local weapon = config
	local humanoid, root = getCharacterParts()
	if not (weapon and humanoid and root) then
		return
	end
	local camera = workspace.CurrentCamera
	local blend = AngleMath.ExpBlend(deltaTime, CameraSettings.ZoomSpeed)

	-- default camera has no first person flag, this is close enough: in first person the
	-- camera sits on its focus point
	firstPerson = (camera.Focus.Position - camera.CFrame.Position).Magnitude < 1
	updateZoom(camera, weapon, blend)
	updateShoulder(humanoid, blend)
	updateBodyRotation(camera, humanoid, root)
	updateRecoilAndShake(camera, deltaTime)
end

local function updateScope()
	local weapon = config
	if not weapon or not firstPerson or zoomAlpha < 1e-3 then
		return
	end
	local point = getAimPoint()
	if not point then
		return
	end
	local camera = workspace.CurrentCamera
	local rotation = camera.CFrame.Rotation
	-- AimPoint is pulled back by WeaponScaler on R15 so the eye isn't inside the rear sight,
	-- EyeOffset is the per weapon tweak on top, zoomAlpha blends the snap in and out
	local eye = point.WorldPosition + rotation:VectorToWorldSpace(weapon.EyeOffset)
	camera.CFrame = CFrame.new(camera.CFrame.Position:Lerp(eye, zoomAlpha)) * rotation
end

function Camera.Enable(weaponConfig: Types.WeaponConfig, fov: number, weaponTool: Tool)
	config = weaponConfig
	defaultFOV = fov
	tool = weaponTool
	if active then
		return
	end
	active = true
	RunService:BindToRenderStep(CAMERA_BIND_NAME, CAMERA_PRIORITY, updateCamera)
	RunService:BindToRenderStep(SCOPE_BIND_NAME, SCOPE_PRIORITY, updateScope)
end

-- Puts back everything Enable and the update loop touched: sensitivity, FOV, AutoRotate,
-- CameraOffset and mouse lock, otherwise unequipping would leave the camera zoomed or locked
function Camera.Disable()
	if not active then
		return
	end
	Camera.SetZoom(false)
	Camera.SetAiming(false)
	active = false
	zoomAlpha, readyAlpha, firstPersonAlpha = 0, 0, 0
	recoil:Reset()
	tool = nil
	RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
	RunService:UnbindFromRenderStep(SCOPE_BIND_NAME)

	UserInputService.MouseDeltaSensitivity = 1
	workspace.CurrentCamera.FieldOfView = defaultFOV
	local humanoid = getCharacterParts()
	if humanoid then
		releaseRotation(humanoid)
		humanoid.CameraOffset = Vector3.zero
	end
end

function Camera.SetAiming(state: boolean)
	if aiming == state then
		return
	end
	aiming = state
	if not state then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

function Camera.SetZoom(state: boolean)
	zooming = state
end

function Camera.ToggleShoulder()
	shoulderSide = -shoulderSide
end

function Camera.Kick(degrees: number)
	recoil:Kick(degrees, rng:NextNumber())
end

function Camera.Shake(degrees: number)
	recoil:Shake(degrees)
end

function Camera.GetAimRay(useScreenCenter: boolean): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	local point = if useScreenCenter then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	return ray.Origin, ray.Direction
end

function Camera.GetAimAlpha(): number
	return zoomAlpha
end

function Camera.GetReadyAlpha(): number
	return readyAlpha
end

function Camera.IsFirstPerson(): boolean
	return firstPerson
end

return Camera
