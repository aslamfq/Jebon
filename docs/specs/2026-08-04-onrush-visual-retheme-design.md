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

This pass swaps what the existing views draw. It does not touch any *existing* game logic — the one
addition, `Projectiles` reporting where a projectile ended so its impact effect can play there, is new
surface area rather than a behaviour change (see Architecture).

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
| Projectiles | Godot Projectile Effects (inspiredsloth, itch.io, CC0) | Full particle VFX (trail, glow, impact burst on hit), not just a mesh swap — see Architecture for how that reconciles with the flat-array `Projectiles` design. |

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

**No change to any rule unit except `Projectiles`, which gains a small additive report — see below.**
`Units`, `Squad`, `Formation`, `TrackGenerator`, `TrackRunner`, `Volley`, `Weapon`, `RunState` are
fully untouched. This pass is otherwise confined to `scripts/views/` (`UnitsView`, `EnemyView`,
`ProjectileView`, `CorridorView`) and a new `assets/` directory holding the imported packs.

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

**`UnitsView` and `EnemyView` currently share one script with the mesh hardcoded inside it** —
`scenes/game.tscn`'s `EnemyView` node reuses `units_view.gd` as-is, which is fine when both draw the
same placeholder capsule but breaks the moment squad and enemies need different meshes. `units_view.gd`
needs an `@export var mesh: Mesh` (or `@export var mesh_path: String`, loaded in `_ready()`), left
unset by default so nothing else using the pattern is forced to change, with `game.tscn`'s two node
instances each pointing at their own imported mesh — the standard Godot way to let two instances of
one script differ, not a new mechanism.

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

**Projectile VFX: why it can't be a mesh swap, and the design that reconciles it.** Each variant in
the pack (`projectile_1.tscn` .. `projectile_4.tscn`) is a full self-driving actor: `GPUParticles3D`
emitters for the core bolt, glow, and impact burst; a scripted ribbon trail; and its own
`CharacterBody3D` + `CollisionShape3D` that moves itself every physics frame (`_physics_process`) and
detects its own hits via `move_and_collide`. That collides with this project's architecture two ways:
nothing else here has a physics collision shape at all (`Units` is flat array data, `CorridorView`'s
walls are plain `MeshInstance3D`), so the prefab's own hit detection would never actually fire — it
would fly through everything, forever; and letting it move itself would run a second, redundant
position simulation next to `Projectiles.tick()`, which is the one actually authoritative for hits
(and which just got a real accuracy fix for exactly this — swept-segment tunneling prevention).

The integration that avoids both problems:

- **`ProjectileView` owns a pool of pre-instantiated prefab scenes** (one `PackedScene` per pack
  variant, `instantiate()`d up front, not per-shot — this project doesn't allocate in the hot path and
  this shouldn't be the exception). Pool size: 64 per side (squad and enemy `ProjectileView`s each get
  their own pool), comfortably above the 48-concurrent-projectile peak the final phase 2 review
  measured in real play, with headroom. `Projectiles.MAX_PROJECTILES` (512) stays the logic layer's
  hard cap; the pool is a view-layer budget, not a new gameplay limit.
- **Each pooled instance has its physics self-movement disabled immediately after instancing**, via
  `set_physics_process(false)` — a builtin `Node` call, no edit to the vendored script needed. Its
  `_process(delta)` (fade/color bookkeeping) is left running; it's harmless without the physics move.
- **`ProjectileView.render()` drives position directly**, the same way it already does for the current
  sphere mesh: for live projectile index `i < min(count, POOL_SIZE)`, set pool instance `i`'s
  `position` (and a facing basis, matching `UnitsView`'s existing `atan2`-based rotation) from
  `projectiles.positions[i]` every frame. No `launch()` call, no reliance on the prefab's own movement.
- **Overflow beyond the pool keeps the current `MultiMeshInstance3D` sphere approach as a fallback
  layer** — indices `POOL_SIZE .. count-1` render through the existing (still present, unremoved)
  MultiMesh path. This guarantees every live projectile is always rendered somehow regardless of how
  many are in flight, and gives this task a working, low-risk fallback to ship even before the pooled
  VFX piece is fully tuned.
- **Impact bursts need to know where and when a projectile ended, which today's `Projectiles` doesn't
  report.** `tick()`'s despawn-past-radius removals and `resolve_hits()`'s hit removals both currently
  only affect `count`/return a kill total — nothing tells a caller *which* positions were removed this
  call. Add a `removed_positions: PackedVector2Array` (cleared and refilled each call, matching how
  `kills` already resets implicitly per call) that both methods append to via `_remove_at`. `ProjectileView`
  reads it after each `tick()`/`resolve_hits()` call, and for any removed position that still maps to a
  currently-pooled slot, plays that instance's `.explode()` (which stops the trail emitters and starts
  the impact burst) instead of just snapping it away. This is the one piece of this pass that's a real,
  testable logic change — GUT-covered the same as everything else in `scripts/`, unlike the rest of
  this design.
- **Returning a pooled instance to the pool** (after its impact burst finishes, or after a despawn with
  no burst) resets `age = 0`, `collided = false`, hides it, and re-enables its emitters for reuse —
  never lets the prefab's own `queue_free()` (which frees the node permanently) actually run; the pool
  owns the instance's lifetime, not the prefab's own age timer.

**Device performance is a real open question here, not a formality.** Real particle systems (up to
128 pooled instances × ~8 `GPUParticles3D` emitters each, at the pool ceiling) are a different cost
profile than the flat-array approach this project has been built and measured around. This task ends
with a device performance pass on Aslam's phone, the same way Task 8 of phase 2 did — if it drops
meaningfully, the fallback is shrinking `POOL_SIZE` (the overflow path already handles that
gracefully) before anything more drastic.

**No change to camera, lighting, or HUD.** The existing `Camera3D` framing (derived and verified in
`docs/camera-derivation.md`) and single `DirectionalLight3D` are left as-is; if the real geometry
turns out to need different lighting once it's in, that's a fast follow-up, not part of this design.

## Testing

Almost all of this pass is work GUT cannot meaningfully verify — there is no rule change to assert
against for the character/environment/mesh swaps, only what's on screen. Verification there is
manual: open the project in the editor, confirm each model renders (right texture, right scale
relative to the corridor, no missing material warnings in the console), and confirm the existing 142
GUT tests are still 142/142 untouched.

The one exception is `Projectiles.removed_positions`: that's a real, testable logic addition (which
positions were removed by a given `tick()`/`resolve_hits()` call), covered by GUT the same as
everything else in `scripts/`, with its own deliberate-break check like every other change to this
codebase.

The projectile-VFX pooling's actual on-screen behaviour (impact bursts appearing in the right place,
overflow fallback kicking in past the pool ceiling) is manual/visual verification, same as the rest of
this pass — plus the device performance pass called out above.

## Deferred

Everything under "Explicitly deferred" above. Also deferred: retexturing the corridor ground/wall
primitives to match the village theme (flat colour is fine for this pass; a stone/dirt material can
follow once the flanking scenery proves the look is worth finishing).
