# Onrush

A free mobile crowd-runner for Android. No ads, no in-app purchases, no monetisation of any kind —
that's a deliberate choice, not a gap to fill later.

A squad of soldiers runs forward down a corridor on its own, firing ahead on its own. You drag left
and right to steer. Enemy crowds come the other way and shoot back. When your last soldier dies, the
run ends, you see how far you got, and you're straight back in.

The repo is still named `Holdout` after an earlier design (a fixed-position horde defence); the game
itself is now called Onrush. See [`docs/specs/2026-08-02-onrush-design.md`](docs/specs/2026-08-02-onrush-design.md)
for the full design and the pivot's history.

## Status

- **Phase 1 — steering and scroll** is merged to `main`: a squad you can steer down a scrolling
  corridor, camera derived and verified, Android export working.
- **Phase 2 — guns and enemies** is on branch `onrush-phase-2`, pending its final review before
  merge: weapon tiers, enemy crowds, both projectile pools, a device performance pass on a real
  phone.
- Gates, hazards, art, and audio are not built yet. See the design doc's Build Order for what's next.

## Requirements

- **Godot 4.7.1**, Standard build (not Mono) — this project is GDScript only.
- An Android SDK and build tools if you want to export an APK. Not required to run the game in the
  editor or on desktop.

## Running it

```
godot
```

Opens the project in the editor; press Play to run the main scene, or run it standalone:

```
godot --path . scenes/game.tscn
```

## Testing

Tests use [GUT](https://github.com/bitwes/Gut), vendored at `addons/gut/`. Run the whole suite
headlessly:

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Exit code 0 means every test passed.

## Architecture

Game rules live in `scripts/` as plain `RefCounted` classes with no reference to the scene tree, so
every rule is testable without a running game. Views in `scripts/views/` read that state and draw it;
they never write to it. There's no Godot physics anywhere — collision is arithmetic over flat arrays,
sized to a fixed cap.

`docs/plans/` holds the implementation plan for each phase; `docs/specs/` holds the design each plan
implements.

## Controls

Drag anywhere on screen to steer the squad left and right. That's the whole input surface.
