# Roblox Gun Framework

Gun system I made for Roblox. Works on R6 and R15, the server checks every shot, and new guns are just a config file + a Tool model.

![Showcase](docs/showcase.gif)

[Full video](https://github.com/codext4fn-afk/roblox-gun-framework/raw/main/docs/showcase.mp4) (58 MB)

## What it does

- Hitscan with client prediction, the server re-raycasts + validates everything (origin, line of sight, fire rate, spread cone, ammo, reload state)
- 6 guns: AK, M16A1, SCAR, FNIWS, TRex, URGI
- Third person ADS w/ shoulder swap, first person sights, scope overlay
- Procedural recoil, sway, walk bob, sprint carry, wall obstruction
- R15 arm IK so the hands stay on the gun at any angle
- Reloads (straight / rock-in / bolt feed, mag taps, charging handle) all timed from config
- Pooled tracers, flashes, impacts, bullet holes, casings
- Keyboard, controller and mobile

## Setup

Needs Roblox Studio + [Rokit](https://github.com/rojo-rbx/rokit)

```bash
git clone https://github.com/codext4fn-afk/roblox-gun-framework.git
cd roblox-gun-framework
rokit install
rojo build -o WeaponSystem.rbxl
```

Open the place, then run `rojo serve` to sync code. Build it first because Rojo can't live sync mesh IDs.

## Adding a gun

1. Put a Tool in `assets/Weapons/<Name>.model.json` with a `Handle` that has a `Muzzle` attachment (plus `AimPoint` / `ShootFirst` for ADS and `SupportGrip` for R15)
2. Add `src/shared/Configs/<Name>.luau`, anything you leave out uses `Defaults.luau`

```luau
local config: Types.WeaponOverrides = {
	Mode = "Auto",
	FireInterval = 60 / 700,
	Damage = { Head = 50, Torso = 26, Limb = 17 },
	MagSize = 30,
	ReloadTime = 2.3,
	HipSpread = 2.4,
	AimSpread = 0.35,
	Recoil = 0.32,
}
```

Look at the existing configs for the full list. `GunSetup.Build(tool)` in the command bar welds the model and sets up the joints for you.

## Controls

| | Keyboard & mouse | Controller | Mobile |
|---|---|---|---|
| Shoot | LMB | R2 | Fire button |
| Aim | RMB | L2 | Aim button |
| Reload | R | X | Reload button |
| Swap shoulder | Q | D-pad right | Swap button |

## Dev

```bash
stylua --check src tests
selene src
lune run tests/run.luau
```

---

Made by Fahd (Roblox: XXmello_iceXX). Portfolio only, not for reuse.
