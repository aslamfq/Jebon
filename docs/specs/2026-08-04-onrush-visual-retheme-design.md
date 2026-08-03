# Jebon! — visual re-theme design

Design agreed with Aslam on 2026-08-04. First of three planned sub-projects toward an adventurer-RPG
reskin of Jebon! (weapon classes and enemy-roster progression are separate, later specs). This one
extends `2026-08-02-onrush-design.md` rather than superseding it — the corridor-runner mechanics
underneath are unchanged.

## In plain English

Jebon! currently renders everyone as flat-colour capsules and spheres on a grey corridor: fast to
build, deliberately placeholder. Aslam downloaded a set of free, license-clear asset packs (KayKit
adventurers and skeletons, a Quaternius medieval village kit, a CC0 projectile-effects pack) and wants
the game to actually look like an adventuring party fighting skeletons down a village path, ahead of
building the class/spell system that comes next.

This pass swaps what the existing views draw. It does not touch a single line of game logic.

## Why this comes first

Playtesting surfaced that the game reads as repetitive before it reads as unfinished — a real visual
upgrade is worth doing now, and doing it before the weapon-class work means the class system gets
designed against real character models (the Adventurers pack already ships four class textures on one
shared body) instead of being reskinned again later.

## Scope

| Game entity | Asset source | Notes |
|---|---|---|
| Squad units | KayKit Adventurers 2.0 (FREE) | Static mesh only this pass — no rig animation. Ships four class textures (barbarian/knight/mage/rogue) on one shared body mesh; use one texture for now (mage, since "throwing magic" is the through-line), the other three become available skins when the class system lands. |
| Enemy units | KayKit Skeletons 1.1 (FREE) | Static mesh only. |
| Corridor environment | Quaternius Medieval Village MegaKit (Standard/free tier) | Scenery flanking the corridor, not a rebuild of the ground/wall geometry. |
| Projectiles | Godot Projectile Effects (inspiredsloth, itch.io, CC0) | Replaces the flat sphere mesh; the pack's own trail/smoke/embers parameters give this a "thrown magic" look for free. |

**Explicitly deferred**, each belongs to a later spec:
- Kenney blocky-characters, Kenney graveyard-kit — enemy-roster-progression phase (blocky-characters
  reads well as an early "generic zombie" tier; the graveyard kit as a later/harder scenery variant).
- KayKit BoardGameBits, FantasyWeaponsBits, ResourceBits — weapon-classes and hazards phases.
- KayKit Character Animations, and Adventurers/Skeletons' own animation rigs — a future animation
  pass, once class-specific attack animations (archer draw, dagger throw, spellcast) are being built
  anyway.

All four in-scope packs are confirmed CC0 / public domain — no attribution required, no redistribution
restriction. Record kept here since the asset files themselves won't carry it once imported.

## Architecture

**No change to any rule unit.** `Units`, `Squad`, `Formation`, `TrackGenerator`, `TrackRunner`,
`Volley`, `Projectiles`, `Weapon`, `RunState` — every pure-logic class in `scripts/` — is untouched.
This pass is confined to `scripts/views/` (`UnitsView`, `EnemyView`, `ProjectileView`, `CorridorView`)
and a new `assets/` directory holding the imported packs.

**Asset layout.** New top-level `assets/`, one directory per pack, matching the pack's own internal
name so a future asset update can be diffed against it:

```
assets/
  kaykit_adventurers/   (from KayKit_Adventurers_2.0_FREE/Assets/gltf/)
  kaykit_skeletons/     (from KayKit_Skeletons_1.1_FREE/assets/gltf/)
  medieval_village/     (from Medieval Village MegaKit[Standard]/glTF/)
  projectile_effects/   (from projectiles.zip)
```

Import glTF (`.gltf`+`.bin`), not the FBX variant, everywhere both are offered — Godot 4's glTF
importer maps PBR materials (BaseColor/Normal/Roughness/ORM) natively; FBX import needs the materials
rebuilt by hand more often. Godot 4.7.1 imports both formats without any external tool (built-in FBX
import via ufbx since 4.3), so this is a preference for less manual material work, not a hard
requirement.

**Getting a `Mesh` out of an imported scene, into a `MultiMesh`.** `MultiMeshInstance3D.multimesh.mesh`
wants a single `Mesh` resource; an imported glTF lands as a scene (a `Node3D` with a `MeshInstance3D`
child), not a bare mesh. Two ways to bridge that, pick whichever a given model needs:
- If the import produces exactly one mesh, Godot's import dock can extract it as a standalone `.res`
  under `.godot/imported/` or via "Advanced Import Settings → Extract Non-Imported Resources", which
  can then be `preload()`ed directly, matching how `UnitsView._ready()` currently does
  `CapsuleMesh.new()`.
- Otherwise, instantiate the `PackedScene` once at startup, walk it for the `MeshInstance3D`, take its
  `.mesh`, and discard the instantiated node — a few lines in `_ready()`, run once, not per-frame.

Whichever a given asset needs, each `View._ready()` ends up with a `Mesh` it hands to
`MultiMesh.mesh`, exactly like today — the `render()` methods (which set per-instance transforms
every frame) do not change at all.

**Materials ride with the mesh.** These are low-poly packs, typically one or two materials per model;
Godot's glTF import attaches them to the mesh's surfaces automatically, so no per-instance material
work is needed for a `MultiMesh` (all instances share the mesh's own surface materials).

**Corridor dressing reuses the existing scroll-and-recycle pattern**, it doesn't invent a new one.
`CorridorView` already recycles a fixed pool of ground stripes, repositioning each one as
`TrackRunner.markers` scrolls and wraps (`_ensure_stripes`/`render`). Village scenery (building
facades, fences) becomes a second, coarser-spaced pool built the same way: a fixed set of
`MeshInstance3D`s (or a `MultiMeshInstance3D` if one building type repeats often enough to be worth
it) whose `z` position is recomputed from the same `runner.markers`-driven scroll math, just flanking
the corridor at `x = ±(HALF_WIDTH + margin)` instead of tiling the floor.

**No change to camera, lighting, or HUD.** The existing `Camera3D` framing (derived and verified in
`docs/camera-derivation.md`) and single `DirectionalLight3D` are left as-is; if the real geometry
turns out to need different lighting once it's in, that's a fast follow-up, not part of this design.

## Testing

This is the project's first pass of work that GUT cannot meaningfully verify — there is no rule
change to assert against, only what's on screen. Verification is manual: open the project in the
editor, confirm each model renders (right texture, right scale relative to the corridor, no missing
material warnings in the console), and confirm the existing 142 GUT tests are still 142/142 (they
should be untouched, since nothing in `scripts/` outside `scripts/views/` changes — a regression there
would mean a views-only change accidentally reached into game state, which would itself be a defect
worth catching).

## Deferred

Everything under "Explicitly deferred" above. Also deferred: retexturing the corridor ground/wall
primitives to match the village theme (flat colour is fine for this pass; a stone/dirt material can
follow once the flanking scenery proves the look is worth finishing).
