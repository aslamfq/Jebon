@../../CLAUDE.md

# Holdout

Fixed-position endless horde-defense game. Godot 4, GDScript, Android target. Free, no ads,
no IAP.

Design spec: `../Planner/Holdout/specs/2026-08-02-holdout-design.md`
Phase 1 plan: `../Planner/Holdout/plans/2026-08-02-phase-1-greybox.md`

Both still live in `Planner` only because this repo did not exist when they were written.
Move them into `docs/` here and delete `Planner/Holdout/` — workspace convention puts a
project's own plans beside its code.

## Engine

**Godot 4.7.1** (`4.7.1.stable.official.a13da4feb`), Standard build — not Mono, this project is
GDScript only. Installed via `winget install GodotEngine.GodotEngine` on 2026-08-02.

    C:\Users\aslam\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64.exe

winget added a `godot` alias to PATH. Read the version above rather than assuming one.

## Testing

**GUT 9.6.1**, vendored at `addons/gut/` (downloaded from the tagged release, not AssetLib).
Test scripts use `extends GutTest` — verified: `addons/gut/test.gd` declares
`class_name GutTest`.

Enabling the plugin in Project Settings is **not** required for headless runs; `gut_cmdln.gd`
runs standalone. Enable it only if you want the editor's GUT panel.

Run the whole suite:

    godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit

Exit code 0 means green. GUT reports that 9.7.1 exists; 9.6.1 is what is vendored and it works
against 4.7.1. Upgrade deliberately, not incidentally.

Run the game:

    godot

## Architecture

Rule units in `scripts/` extend `RefCounted` and hold no Godot node references, so every rule is
testable without a scene tree. Views in `scripts/views/` read state and draw; they never write.

All logic is **2D on the XZ plane** — `Vector2(x, y)` maps to `Vector3(x, 0, y)` at render time
only. `x` is right, `y` is forward. Angle of a point is `atan2(pos.x, pos.y)`, so `0` is straight
ahead and the playable arc is `-PI/2` to `+PI/2`.

**No Godot physics anywhere**: no `Area3D`, no `RigidBody3D`, no `CharacterBody3D`. Collision is
arithmetic over flat arrays with swap-remove, sized to a fixed cap and allocating nothing in the
hot path.
