@../../CLAUDE.md

# Holdout

Fixed-position endless horde-defense game. Godot 4, GDScript, Android target. Free, no ads,
no IAP.

**Current design: `docs/specs/2026-08-02-onrush-design.md`.** Read that one.

Superseded, kept for its decision record and for the units the current design inherits:
`docs/specs/2026-08-02-holdout-design.md` and `docs/plans/2026-08-02-phase-1-greybox.md`.
That earlier design was a fixed-position horde defense; it was built to a working state
(seven units, 84 tests, merged to `main`) before the game pivoted to a crowd runner.
`BarricadeSet`, `BarricadeView`, `game.gd` and `game.tscn` on `main` belong to that old
design and are superseded — do not build on them.

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

## Exporting (Android)

`export_presets.cfg` is **git-ignored** — it holds signing config — so nothing in it survives a
fresh clone. Two things shrink the APK under the 30MB delivery limit, and only one of them is
tracked: the village prop texture downscale (2048px → 512px) is committed and needs no action,
but the export filter is not. A fresh checkout rebuilds at roughly 31.5MB, i.e. over the limit,
until the Android preset's `exclude_filter` is set back to this value:

    exclude_filter="addons/gut/*,test/*,projectiles/demo.tscn,projectiles/preview.tscn,projectiles/projectile_2.tscn,projectiles/projectile_3.tscn,projectiles/projectile_4.tscn,projectiles/scripts/demo.gd,projectiles/scripts/demo.gd.uid"

Set it in the editor under Project → Export → Android → Resources → "Filters to exclude…", or
paste the line into the `[preset.0.options]` section of `export_presets.cfg` (which lives at the
project root, untracked). `export_filter` stays `all_resources`. What it drops: the GUT addon and
the test suite, neither of which ships, plus the vendored projectile pack's demo/preview scenes
and the projectile variants the game never instantiates — the game uses `projectile_1.tscn` only.
Re-check the exclusions if a new variant is ever wired into a scene, since anything listed here
is silently absent at runtime.

## Architecture

Rule units in `scripts/` extend `RefCounted` and hold no Godot node references, so every rule is
testable without a scene tree. Views in `scripts/views/` read state and draw; they never write.

All logic is **2D on the XZ plane** — `Vector2(x, y)` maps to `Vector3(x, 0, y)` at render time
only. `x` is right, `y` is forward. Angle of a point is `atan2(pos.x, pos.y)`, so `0` is straight
ahead and the playable arc is `-PI/2` to `+PI/2`.

**No Godot physics anywhere**: no `Area3D`, no `RigidBody3D`, no `CharacterBody3D`. Collision is
arithmetic over flat arrays with swap-remove, sized to a fixed cap and allocating nothing in the
hot path.
