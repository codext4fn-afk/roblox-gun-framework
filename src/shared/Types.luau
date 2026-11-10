--!strict
-- Copyright (c) 2026 Fahd (Roblox: XXmello_iceXX). All rights reserved. Not licensed for reuse.

--[[
    These are the shared types, there is no runtime code
    ConfigValidator is what checks that real configs match them
]]

export type FireMode = "Auto" | "Semi"
export type HitZone = "Head" | "Torso" | "Limb"
export type RigName = "R6" | "R15"
export type AnimationName = "Hold" | "Aim" | "Fire" | "Reload"
-- RockIn is AK style, BoltFeed loads through the open bolt
export type ReloadStyle = "Straight" | "RockIn" | "BoltFeed"
export type ReloadPouch = "Chest" | "Hip"
export type RackRule = "Never" | "Empty" | "Always"

export type DamageTable = {
	Head: number,
	Torso: number,
	Limb: number,
}

export type BoltConfig = {
	Part: string,
	Travel: number,
	OutTime: number,
	ReturnTime: number,
}

export type MagazineConfig = {
	Part: string,
	Hand: string,
	GripAttachment: string,
	HoldOffset: CFrame,
	UseMarkers: boolean,
	-- Out, Drop, Grab and In are fractions of ReloadTime
	Out: number,
	Drop: number,
	Grab: number,
	In: number,
	InsertDepth: number,
	SlideTime: number,
	AttachTime: number,
	AlignTime: number,
	SeatTime: number,
	SeatKick: number,
	DropLifetime: number,
}

export type ReloadConfig = {
	Style: ReloadStyle,
	Pouch: ReloadPouch,
	Tap: boolean,
	Rack: RackRule,
	Prop: string, -- only used when the model has no mag part of its own
}

export type AnimationIds = {
	Hold: string,
	Aim: string,
	Fire: string,
	Reload: string,
}

export type HandlingConfig = {
	FirstPersonGrip: Vector3,
	FirstPersonHip: CFrame,
	LowReady: CFrame,
	DrawnDown: CFrame,
	DrawTime: number,
	ReloadTilt: CFrame,
	SprintCarry: CFrame,
	ReloadUsesAnimation: boolean,
}

export type WeaponConfig = {
	Id: string,
	Mode: FireMode,
	FireInterval: number, -- seconds, configs write it as 60 / rpm
	Damage: DamageTable,
	FriendlyFire: boolean,
	Pellets: number,
	Range: number,
	MagSize: number,
	ReloadTime: number,
	HipSpread: number,
	AimSpread: number,
	AimFOV: number,
	FirstPersonFOV: number,
	ScopeFOV: number,
	ScopeOverlay: boolean,
	AimSensitivity: number,
	ShowCrosshair: boolean,
	FirstPersonPushR6: number, -- R6 only, slides the gun forward in first person
	EyeOffset: Vector3, -- camera offset from AimPoint when scoped
	AimWalkSpeed: number,
	Recoil: number,
	AimRecoilMultiplier: number,
	CameraShake: number,
	ArmKick: number, -- pose units, not degrees
	EjectCasings: boolean,
	CasingSize: Vector3,
	CasingColor: Color3,
	Bolt: BoltConfig,
	Magazine: MagazineConfig,
	Reload: ReloadConfig,
	Animations: {
		R6: AnimationIds,
		R15: AnimationIds,
	},
	Handling: HandlingConfig,
}

-- this is the same as WeaponConfig but everything is optional
-- a weapon file only lists what it changes, and ConfigMerge fills the rest from Defaults
-- the two have to be edited together, because nothing checks that they match
export type WeaponOverrides = {
	Mode: FireMode?,
	FireInterval: number?,
	Damage: { Head: number?, Torso: number?, Limb: number? }?,
	FriendlyFire: boolean?,
	Pellets: number?,
	Range: number?,
	MagSize: number?,
	ReloadTime: number?,
	HipSpread: number?,
	AimSpread: number?,
	AimFOV: number?,
	FirstPersonFOV: number?,
	ScopeFOV: number?,
	ScopeOverlay: boolean?,
	AimSensitivity: number?,
	ShowCrosshair: boolean?,
	FirstPersonPushR6: number?,
	EyeOffset: Vector3?,
	AimWalkSpeed: number?,
	Recoil: number?,
	AimRecoilMultiplier: number?,
	CameraShake: number?,
	ArmKick: number?,
	EjectCasings: boolean?,
	CasingSize: Vector3?,
	CasingColor: Color3?,
	Bolt: {
		Part: string?,
		Travel: number?,
		OutTime: number?,
		ReturnTime: number?,
	}?,
	Magazine: {
		Part: string?,
		Hand: string?,
		GripAttachment: string?,
		HoldOffset: CFrame?,
		UseMarkers: boolean?,
		Out: number?,
		Drop: number?,
		Grab: number?,
		In: number?,
		InsertDepth: number?,
		SlideTime: number?,
		AttachTime: number?,
		AlignTime: number?,
		SeatTime: number?,
		SeatKick: number?,
		DropLifetime: number?,
	}?,
	Reload: {
		Style: ReloadStyle?,
		Pouch: ReloadPouch?,
		Tap: boolean?,
		Rack: RackRule?,
		Prop: string?,
	}?,
	Animations: {
		R6: { Hold: string?, Aim: string?, Fire: string?, Reload: string? }?,
		R15: { Hold: string?, Aim: string?, Fire: string?, Reload: string? }?,
	}?,
	Handling: {
		FirstPersonGrip: Vector3?,
		FirstPersonHip: CFrame?,
		LowReady: CFrame?,
		DrawnDown: CFrame?,
		DrawTime: number?,
		ReloadTilt: CFrame?,
		SprintCarry: CFrame?,
		ReloadUsesAnimation: boolean?,
	}?,
}

export type Pose = {
	pitch: number,
	aim: number,
	armPitch: number,
	armYaw: number,
	armBack: number, -- studs
}

export type PoseSolver = {
	NewPose: () -> Pose,
	Apply: (character: Model, pose: Pose) -> (),
	Clear: (character: Model) -> (),
}

return nil
