# Jebon! Visual Re-theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the game's flat-colour primitive rendering (capsules, spheres, grey boxes) with the
real asset packs Aslam sourced — KayKit Adventurers/Skeletons, a Quaternius medieval village kit, and
a CC0 particle-effects pack for projectiles — without changing any existing gameplay behaviour.

**Architecture:** Confined almost entirely to `scripts/views/` and a new top-level `assets/`
directory. The one exception is `Projectiles`, which gains a small additive `removed_positions`
report so projectile impact effects know where to play — a real, GUT-tested logic change, the only
one in this plan. Every other rule unit (`Units`, `Squad`, `Formation`, `TrackGenerator`,
`TrackRunner`, `Volley`, `Weapon`, `RunState`) is untouched.

**Tech Stack:** Godot 4.7.1 (GDScript), GUT 9.6.1 for the one testable task, manual/visual
verification for everything else (this is the project's first pass of work GUT cannot meaningfully
check — there's no rule to assert against, only what's on screen).

## Global Constraints

- **All logic stays 2D on the XZ plane** — `Vector2(x, y)` maps to `Vector3(x, 0, y)` at render time
  only, per the project's established convention. Nothing in this plan changes that mapping.
- **No Godot physics anywhere** — no `Area3D`, `RigidBody3D`, or `CharacterBody3D` driving gameplay.
  The projectile-VFX pack ships its own `CharacterBody3D`-based self-movement; Task 6 explicitly
  disables it rather than using it, to hold this constraint.
- **No allocation in the hot path.** The projectile-effect pool (Task 6) is pre-instantiated once at
  `_ready()`, matching how `Units`/`Projectiles` already pre-size their arrays in `_init()`.
- **Views read state and draw; they never write.** `Projectiles.removed_positions` (Task 4) is state
  the logic layer produces and the view layer only reads — it does not reverse this rule.
- **Godot 4.7.1**, Standard build, GDScript only — read from `CLAUDE.md`, never assumed.
- **Full GUT suite must stay green.** 142/142 before this plan starts; every task that touches
  `scripts/` outside `scripts/views/` must leave it 142+N/142+N, verified with a deliberate-break
  check the same way every prior task in this project has been.

Source spec: `docs/specs/2026-08-04-onrush-visual-retheme-design.md`

---

### Task 1: Import the asset packs

**Files:**
- Create: `assets/kaykit_adventurers/Mage.glb`
- Create: `assets/kaykit_skeletons/Skeleton_Minion.glb`
- Create: `assets/medieval_village/Wall_Plaster_Straight.gltf`, `Wall_Plaster_Straight.bin`,
  `Prop_WoodenFence_Single.gltf`, `Prop_WoodenFence_Single.bin`, `T_WoodTrim_Normal.png`,
  `T_WoodTrim_BaseColor.png`, `T_WoodTrim_Roughness.png`, `T_Plaster_Normal.png`,
  `T_Plaster_BaseColor.png`, `T_Plaster_ORM.png`
- Create: `projectiles/` (verbatim copy of the pack's own folder, at the **project root**, not under
  `assets/` — see the note below)

**Interfaces:**
- Consumes: nothing.
- Produces: the raw asset files every later task loads. `Mage.glb` and `Skeleton_Minion.glb` are
  self-contained (mesh + textures + materials in one file, no separate dependency to track).
  `medieval_village/`'s two `.gltf` files reference their six textures and two `.bin` buffers by
  filename only (`"uri":"T_WoodTrim_Normal.png"`, not a subpath) — they must sit flat in the same
  directory, not under a `textures/` subfolder, or the glTF import will fail to resolve them.

**Why `projectiles/` breaks the `assets/<pack>/` pattern the other three packs use:** every `.tscn` in
this pack references its own textures/meshes/scripts via a hardcoded absolute path —
`res://projectiles/textures/cube2.png`, `res://projectiles/meshes/projectile2.res`, etc. — not a path
relative to the `.tscn` file. Placing this pack anywhere other than `res://projectiles/` would break
every one of those references, and hand-editing a vendored third-party pack's internals to relocate
them is worse than the one-line exception to the naming convention.

- [ ] **Step 1: Copy the character models**

From the extracted pack contents (paths relative to the download):
```
KayKit_Adventurers_2.0_FREE/Characters/gltf/Mage.glb  ->  assets/kaykit_adventurers/Mage.glb
KayKit_Skeletons_1.1_FREE/characters/gltf/Skeleton_Minion.glb  ->  assets/kaykit_skeletons/Skeleton_Minion.glb
```

- [ ] **Step 2: Copy the two village props and their shared textures**

From `Medieval Village MegaKit[Standard]/glTF/`, copy these ten files flat into
`assets/medieval_village/` (no subfolders):
```
Wall_Plaster_Straight.gltf
Wall_Plaster_Straight.bin
Prop_WoodenFence_Single.gltf
Prop_WoodenFence_Single.bin
T_WoodTrim_Normal.png
T_WoodTrim_BaseColor.png
T_WoodTrim_Roughness.png
T_Plaster_Normal.png
T_Plaster_BaseColor.png
T_Plaster_ORM.png
```

(`T_WoodTrim_*` is shared by both props; `T_Plaster_*` is used only by the wall. Confirmed by reading
each `.gltf`'s own `"uri"` references directly — don't guess at a different texture set if a future
prop swap changes this list, re-check the same way.)

- [ ] **Step 3: Copy the projectile-effects pack verbatim**

Copy the entire `projectiles/` folder from the pack's zip to the **project root** (`res://projectiles/`,
a sibling of `scripts/` and `scenes/`, not under `assets/`). This includes `demo.tscn`, `preview.tscn`,
`projectile_1.tscn` through `projectile_4.tscn`, `meshes/`, `scripts/`, and `textures/` exactly as
distributed — every file, no pruning, since the internal absolute-path references mean any file left
out breaks whichever scene needed it.

- [ ] **Step 4: Force an import pass and confirm no errors**

Run: `godot --headless --editor --quit-after 10` from the project root (the same cache-warming
pattern already used in this project for `class_name` registration — importing new resources needs
the same one-time editor pass before headless test/export runs can see them).

Expected: exit code 0. Check the output for any `ERROR`/`Failed to load` lines mentioning the new
`assets/` or `projectiles/` paths — if the editor reports it can't resolve a texture or buffer
reference, a file from Steps 1-3 is missing or misplaced; re-check against the exact filename list
above before proceeding.

- [ ] **Step 5: Confirm the existing suite is unaffected**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: 142/142, unchanged — this task only adds files nothing yet references.

- [ ] **Step 6: Commit**

```bash
git add assets/ projectiles/
git commit -m "assets: import adventurer, skeleton, village prop, and projectile-effect packs"
```

---

### Task 2: Give squad and enemy units their real models

**Files:**
- Create: `scripts/views/mesh_extract.gd`
- Modify: `scripts/views/units_view.gd`
- Modify: `scenes/game.tscn`

**Interfaces:**
- Consumes: `assets/kaykit_adventurers/Mage.glb`, `assets/kaykit_skeletons/Skeleton_Minion.glb`
  (Task 1).
- Produces: `MeshExtract.from_scene(scene: PackedScene) -> Mesh`, reused by Task 3's corridor
  scenery. `UnitsView.model_scene: PackedScene` (exported), falling back to the current placeholder
  capsule when unset — so nothing else instancing this script without setting it breaks.

**Why a helper instead of Godot's import-dock mesh extraction:** an imported `.glb`/`.gltf` lands as a
*scene* (a `Node3D` tree with a `MeshInstance3D` somewhere inside it), not a bare `Mesh` resource —
`MultiMesh.mesh` wants the latter. Godot's editor can extract a mesh as a standalone sub-resource, but
that requires knowing exactly where in each pack's node tree the mesh sits, which varies per asset and
isn't worth hand-verifying per model. Instantiating the scene once at startup and walking it for the
first `MeshInstance3D` is fully mechanical, works regardless of how deep the mesh is nested, and needs
no per-asset investigation.

- [ ] **Step 1: Write `MeshExtract`**

```gdscript
# scripts/views/mesh_extract.gd
class_name MeshExtract extends RefCounted

# Imported glTF/FBX models land as a scene (a Node3D tree containing a
# MeshInstance3D), not a bare Mesh resource -- MultiMesh.mesh needs the
# latter. Instantiates the scene once, takes the first mesh found by
# depth-first search, and discards the instance. Called from _ready(),
# never per-frame.
static func from_scene(scene: PackedScene) -> Mesh:
    var instance := scene.instantiate()
    var mesh := _find_mesh(instance)
    instance.free()
    return mesh

static func _find_mesh(node: Node) -> Mesh:
    if node is MeshInstance3D and node.mesh != null:
        return node.mesh
    for child in node.get_children():
        var found := _find_mesh(child)
        if found != null:
            return found
    return null
```

- [ ] **Step 2: Make `UnitsView`'s mesh configurable**

Replace `scripts/views/units_view.gd` in full:

```gdscript
class_name UnitsView extends MultiMeshInstance3D

const BOB_HEIGHT := 0.12
const BOB_SPEED := 9.0

# Unset by default so any other instance of this script (there are none
# today besides Squad's own UnitsView and Game's EnemyView, both of which
# now set this in game.tscn) still gets a working placeholder.
@export var model_scene: PackedScene

func _ready() -> void:
    var mesh: Mesh = MeshExtract.from_scene(model_scene) if model_scene else null
    if mesh == null:
        var capsule := CapsuleMesh.new()
        capsule.radius = 0.25
        capsule.height = 1.4
        mesh = capsule

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Units.MAX_UNITS
    multimesh.visible_instance_count = 0

func render(units: Units, time: float) -> void:
    multimesh.visible_instance_count = units.count
    for i in units.count:
        var pos := units.positions[i]
        var bob: float = sin(time * BOB_SPEED + float(i) * 0.7) * BOB_HEIGHT
        var basis := Basis().rotated(Vector3.UP, atan2(pos.x, pos.y))
        multimesh.set_instance_transform(i,
            Transform3D(basis, Vector3(pos.x, 0.7 + bob, pos.y)))
```

(`render()` is byte-for-byte unchanged — confirm with `git diff` after this step that only `_ready()`
and the new `@export` line differ from the committed version.)

- [ ] **Step 3: Wire the real meshes into `game.tscn`**

In `scenes/game.tscn`, add the two glb files as `ext_resource` entries and set `model_scene` on each
node:

```
[ext_resource type="PackedScene" path="res://assets/kaykit_adventurers/Mage.glb" id="5_mage"]
[ext_resource type="PackedScene" path="res://assets/kaykit_skeletons/Skeleton_Minion.glb" id="6_skeleton_minion"]
```

```
[node name="UnitsView" type="MultiMeshInstance3D" parent="."]
script = ExtResource("3_units_view")
model_scene = ExtResource("5_mage")

[node name="EnemyView" type="MultiMeshInstance3D" parent="."]
script = ExtResource("3_units_view")
model_scene = ExtResource("6_skeleton_minion")
```

`load_steps` at the top of the file must be bumped to account for the two new `ext_resource` entries
(current count + 2) — Godot's editor does this automatically on save; if hand-editing, count the total
`ext_resource` lines and match it.

- [ ] **Step 4: Verify by launching**

Run: `godot --headless --quit-after 300`
Expected: exit code 0, no script errors. This confirms nothing crashes; it does not confirm the
models look right — that needs the editor.

- [ ] **Step 5: Verify visually**

Open the project in the editor (`godot`), run the main scene. Confirm the squad renders as adventurer
figures (not capsules) and enemies as skeletons, both at a scale that reads sensibly against the
corridor (KayKit models are human-scale; if either looks tiny or huge relative to the ~1.4-unit-tall
capsule they replaced, the model needs a `scale` on its `MultiMeshInstance3D` node, applied uniformly
via `multimesh.set_instance_transform`'s basis in `render()` — do not hack per-instance scale into
`UnitsView`, since that would need to survive Task 3's later work too; note the needed scale factor
here in the report instead and apply it as a single new `@export var scale_factor := 1.0` multiplied
into the basis in `render()` if one is needed).

- [ ] **Step 6: Confirm the suite is still 142/142**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: unchanged — this task only touches `scripts/views/` and `scenes/game.tscn`.

- [ ] **Step 7: Commit**

```bash
git add scripts/views/mesh_extract.gd scripts/views/units_view.gd scenes/game.tscn
git commit -m "feat: render squad and enemies with real KayKit models"
```

---

### Task 3: Corridor scenery dressing

**Files:**
- Modify: `scripts/views/corridor_view.gd`
- Modify: `scenes/game.tscn`

**Interfaces:**
- Consumes: `MeshExtract.from_scene()` (Task 2), `assets/medieval_village/*.gltf` (Task 1),
  `TrackRunner.markers: PackedFloat32Array` (existing, unchanged).
- Produces: nothing new for later tasks.

**Design:** reuses `TrackRunner.markers`'s existing scroll-and-wrap math rather than inventing a
second one. `markers` is already a fixed array of `z` positions, one per `MARKER_SPACING` (6.0 units)
along the corridor, recomputed by `CorridorView.render()` every frame from `runner.markers`. Scenery
takes every third marker (`SCENERY_STRIDE`) as its own `z`, at roughly 18-unit spacing, and places one
prop flanking each side of the corridor at that `z` — inheriting the exact same wrap-around
correctness `_ensure_stripes` already has, for free.

- [ ] **Step 1: Add the scenery pool to `CorridorView`**

Modify `scripts/views/corridor_view.gd` — add alongside the existing `_stripes` pool:

```gdscript
const SCENERY_STRIDE := 3
const SCENERY_MARGIN := 1.0

@export var wall_prop: PackedScene
@export var fence_prop: PackedScene

var _walls: Array[MeshInstance3D] = []
var _fences: Array[MeshInstance3D] = []
```

In `render(runner: TrackRunner)`, after the existing stripe loop:

```gdscript
    _render_scenery(runner)

func _render_scenery(runner: TrackRunner) -> void:
    var n := runner.markers.size() / SCENERY_STRIDE
    _ensure_scenery(n)
    for i in n:
        var z := runner.markers[i * SCENERY_STRIDE]
        var left := _walls[i].position
        left.z = z
        _walls[i].position = left
        var right := _fences[i].position
        right.z = z
        _fences[i].position = right

func _ensure_scenery(n: int) -> void:
    while _walls.size() < n:
        _walls.append(_spawn_prop(wall_prop, -(Corridor.HALF_WIDTH + SCENERY_MARGIN)))
        _fences.append(_spawn_prop(fence_prop, Corridor.HALF_WIDTH + SCENERY_MARGIN))

func _spawn_prop(scene: PackedScene, x: float) -> MeshInstance3D:
    var mesh := MeshExtract.from_scene(scene)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = Vector3(x, 0, 0)
    add_child(instance)
    return instance
```

(Two separate pools — `_walls` always on the left, `_fences` always on the right — rather than one
pool alternating sides, matching the existing code's preference for explicit, simple state over a
cleverer single array with parity checks.)

- [ ] **Step 2: Wire the props into `game.tscn`**

```
[ext_resource type="PackedScene" path="res://assets/medieval_village/Wall_Plaster_Straight.gltf" id="7_wall"]
[ext_resource type="PackedScene" path="res://assets/medieval_village/Prop_WoodenFence_Single.gltf" id="8_fence"]
```

```
[node name="CorridorView" type="Node3D" parent="."]
script = ExtResource("2_corridor_view")
wall_prop = ExtResource("7_wall")
fence_prop = ExtResource("8_fence")
```

Bump `load_steps` by 2 again, same as Task 2 Step 3.

- [ ] **Step 3: Verify by launching, then visually**

Run: `godot --headless --quit-after 300`, expect exit code 0.

Open in the editor, run the main scene, confirm village walls and fences scroll past on either side
of the corridor at a steady interval, moving at the same rate as the ground stripes (they share the
same `runner.markers` positions, so any visible desync would indicate a bug in this task's code, not
in `TrackRunner`).

- [ ] **Step 4: Confirm the suite is still 142/142**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`

- [ ] **Step 5: Commit**

```bash
git add scripts/views/corridor_view.gd scenes/game.tscn
git commit -m "feat: dress the corridor with scrolling village scenery"
```

---

### Task 4: `Projectiles.removed_positions`

**Files:**
- Modify: `scripts/projectiles.gd`
- Modify: `test/test_projectiles.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Projectiles.removed_positions: PackedVector2Array` — the positions of every projectile
  removed by the most recent `tick()` or `resolve_hits()` call, in removal order. Cleared at the start
  of each call (so it always reflects only that call, never accumulating across frames). Read by
  Task 6.

This is the one piece of this plan that's a real, testable logic change — TDD it the same way every
other task in this project has been.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_projectiles.gd`:

```gdscript
func test_removed_positions_is_empty_when_nothing_is_removed():
    units.spawn(Vector2(0, 100), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 0), Vector2(0, 1), 1.0)
    projectiles.tick(0.1, 1000.0)
    assert_eq(projectiles.removed_positions.size(), 0)

func test_removed_positions_reports_a_despawn():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0, "sanity check: the despawn actually happened")
    assert_eq(projectiles.removed_positions.size(), 1)
    assert_almost_eq(projectiles.removed_positions[0].y, 100.0, 0.001,
        "must report where the projectile actually was when it despawned, not the origin")

func test_removed_positions_reports_a_hit():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 1)
    assert_almost_eq(projectiles.removed_positions[0], Vector2(0, 10), 0.001)

func test_removed_positions_is_cleared_at_the_start_of_each_call():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.removed_positions.size(), 1, "sanity check: first call reported one")
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 1.0)
    projectiles.tick(0.01, 1000.0)
    assert_eq(projectiles.removed_positions.size(), 0,
        "a call that removes nothing must clear last call's report, not accumulate")

func test_removed_positions_reports_every_removal_in_one_call():
    # Two bullets that both despawn in the same tick() call.
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.fire(Vector2(5, 0), Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0)
    assert_eq(projectiles.removed_positions.size(), 2,
        "both removals in this call must be reported, not just the last one")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `removed_positions` does not exist on `Projectiles`.

- [ ] **Step 3: Implement**

Modify `scripts/projectiles.gd`:

```gdscript
var removed_positions := PackedVector2Array()
```
(add alongside the existing `positions`/`previous_positions`/`velocities`/`count` declarations, no
`_init()` resize needed — this one grows/shrinks per call rather than being a fixed-size slot array.)

```gdscript
func tick(delta: float, despawn_radius: float) -> void:
    removed_positions.clear()
    var radius_sq := despawn_radius * despawn_radius
    var i := 0
    while i < count:
        previous_positions[i] = positions[i]
        positions[i] += velocities[i] * delta
        if positions[i].length_squared() > radius_sq:
            removed_positions.append(positions[i])
            _remove_at(i)
            continue
        i += 1
```

```gdscript
func resolve_hits(units: Units, hit_radius: float, damage: float) -> int:
    removed_positions.clear()
    var kills := 0
    var radius_sq := hit_radius * hit_radius
    var i := 0
    while i < count:
        var hit_index := -1
        for j in units.count:
            var closest := Geometry2D.get_closest_point_to_segment(
                units.positions[j], previous_positions[i], positions[i])
            if closest.distance_squared_to(units.positions[j]) <= radius_sq:
                hit_index = j
                break
        if hit_index >= 0:
            kills += units.damage_at(units.positions[hit_index], 0.001, damage)
            removed_positions.append(positions[i])
            _remove_at(i)
            continue
        i += 1
    return kills
```

(`removed_positions.clear()` at the top of each method, not `_remove_at`, since `_remove_at` is also
used internally by the same call — clearing once per call, not once per removal, is what Step 1's
"is cleared at the start of each call" and "reports every removal in one call" tests are guarding.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all pass. Report the exact count (should be 142 pre-existing + 5 new = 147).

- [ ] **Step 5: Verify with a deliberate break**

Commit first. Then temporarily remove the `removed_positions.clear()` line from `tick()` only.
Confirm `test_removed_positions_is_cleared_at_the_start_of_each_call` fails and nothing else does.
Restore, confirm `git diff scripts/projectiles.gd` is empty. Repeat for `resolve_hits()`'s clear line
against the same test (it exercises `tick()` specifically — if you want resolve_hits' clear covered
too, that's worth adding as a 6th test rather than trusting the tick() one implicitly covers both;
add it now if the break-check reveals resolve_hits' clear line is currently unguarded).

- [ ] **Step 6: Commit**

```bash
git add scripts/projectiles.gd test/test_projectiles.gd
git commit -m "feat: report removed projectile positions for impact-effect triggering"
```

---

### Task 5: Pooled projectile VFX — movement, no impact burst yet

**Files:**
- Modify: `scripts/views/projectile_view.gd`
- Modify: `scenes/game.tscn`

**Interfaces:**
- Consumes: `projectiles/projectile_1.tscn` (Task 1), `Projectiles.positions`/`count` (existing,
  unchanged).
- Produces: `ProjectileView.model_scene: PackedScene` (exported; both `SquadProjectileView` and
  `EnemyProjectileView` reuse this script, same pattern as Task 2's `UnitsView`).

**Design, from the spec:** a fixed pool of 64 pre-instantiated `projectile_1.tscn` copies per view
(128 total across squad+enemy), each with physics self-movement disabled so the view drives its
position every frame instead of letting the prefab's own `CharacterBody3D` move it. Live projectile
indices `0 .. min(count, POOL_SIZE) - 1` get a pooled visual; anything beyond `POOL_SIZE` falls back to
the existing flat-sphere `MultiMeshInstance3D`, which stays in place as a permanent overflow path, not
a temporary one.

This task deliberately stops short of impact bursts (Task 6) — pooled instances just track position
and pop back into the pool silently on despawn/hit, same visible behaviour as today's instant vanish.
Shipping this much on its own is a real, working intermediate state worth its own commit.

- [ ] **Step 1: Replace `projectile_view.gd`**

```gdscript
class_name ProjectileView extends MultiMeshInstance3D

const POOL_SIZE := 64

@export var model_scene: PackedScene

var _pool: Array[Node3D] = []

func _ready() -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 0.08
    mesh.height = 0.16

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Projectiles.MAX_PROJECTILES
    multimesh.visible_instance_count = 0

    if model_scene:
        for i in POOL_SIZE:
            var instance: Node3D = model_scene.instantiate()
            instance.set_physics_process(false)
            instance.visible = false
            add_child(instance)
            _pool.append(instance)

func render(projectiles: Projectiles) -> void:
    var pooled := mini(projectiles.count, _pool.size())

    for i in pooled:
        var instance := _pool[i]
        instance.visible = true
        instance.position = Vector3(projectiles.positions[i].x, 0.8, projectiles.positions[i].y)
    for i in range(pooled, _pool.size()):
        _pool[i].visible = false

    # Overflow beyond the pool renders through the original flat-sphere
    # MultiMesh path, so every live projectile is always drawn somehow
    # regardless of how many are in flight.
    var overflow := projectiles.count - pooled
    multimesh.visible_instance_count = max(overflow, 0)
    for i in overflow:
        var src := pooled + i
        var pos := projectiles.positions[src]
        multimesh.set_instance_transform(i,
            Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))
```

(`set_physics_process(false)` right after `instantiate()` is what stops the prefab's own
`_physics_process`-driven movement and `CharacterBody3D.move_and_collide` from ever running — see the
spec's Architecture section for why that self-driven behaviour would never actually detect a hit in
this project anyway, since nothing else here has a physics collision shape.)

- [ ] **Step 2: Wire the projectile scene into `game.tscn`**

```
[ext_resource type="PackedScene" path="res://projectiles/projectile_1.tscn" id="9_projectile"]
```

```
[node name="SquadProjectileView" type="MultiMeshInstance3D" parent="."]
script = ExtResource("4_projectile_view")
model_scene = ExtResource("9_projectile")

[node name="EnemyProjectileView" type="MultiMeshInstance3D" parent="."]
script = ExtResource("4_projectile_view")
model_scene = ExtResource("9_projectile")
```

Bump `load_steps` by 1.

- [ ] **Step 3: Verify by launching**

Run: `godot --headless --quit-after 300`, expect exit code 0. If `set_physics_process` errors because
`model_scene.instantiate()` doesn't return a `Node3D` (the prefab's root type — confirm this matches;
it was `Node3D` per the pack's own scene file, checked directly), that's the first thing to
re-diagnose — don't guess a fix, re-open `projectiles/projectile_1.tscn` and confirm the root node's
declared `type=`.

- [ ] **Step 4: Verify visually**

Open in the editor, run the main scene, fire some shots. Confirm: pooled projectiles show the real
bolt/glow effect and move correctly with the game's projectiles (not drifting, not stuck at origin);
firing enough shots to exceed 64 concurrent shows the remainder as the old flat spheres, not missing
entirely; despawned/hit projectiles disappear (no burst yet — that's Task 6) rather than lingering.

- [ ] **Step 5: Confirm the suite is still 147/147**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`

- [ ] **Step 6: Commit**

```bash
git add scripts/views/projectile_view.gd scenes/game.tscn
git commit -m "feat: render projectiles with pooled particle-effect instances"
```

---

### Task 6: Impact bursts and pool return

**Files:**
- Modify: `scripts/views/projectile_view.gd`

**Interfaces:**
- Consumes: `Projectiles.removed_positions` (Task 4).
- Produces: nothing new for later tasks — this is the last piece of the projectile-effect work.

**Design:** after each frame's `squad_projectiles.tick()`/`.resolve_hits()` and
`enemy_projectiles.tick()`/`.resolve_hits()` calls (in `game.gd`, already existing), the corresponding
`ProjectileView.render()` call can check `projectiles.removed_positions` for any position matching a
still-pooled slot and play that instance's impact burst there, instead of just letting it vanish. A
pooled instance whose burst has finished (or which despawned with no burst) returns to the pool: reset
to its idle state, ready for reuse next time `count` grows again.

The correlation problem from the spec: `_remove_at`'s swap-remove keeps live indices contiguous
(`0 .. count-1`), so a pooled slot `i` this frame is the projectile that was at logical index `i` when
`tick()`/`resolve_hits()` ran — which may not be the *same* projectile pooled slot `i` represented last
frame if something at a lower index was removed and something from higher up got swapped into it. This
task does not attempt to track identity precisely across a swap — it plays a burst at whichever
`removed_positions` entry has no corresponding *still-live* projectile within the pool's tracked range,
which is exactly right for the common case (a projectile removed with nothing behind it moving into its
slot) and only imprecise in a swap, where the burst plays at the correct *position* regardless of which
logical projectile owned it — visually indistinguishable at the game's speed and scale (this is the
"approximate is fine" resolution the spec flagged as a real design option; it was chosen over adding a
stable-identity scheme because the visible outcome is the same).

- [ ] **Step 1: Extend `ProjectileView`**

Modify `scripts/views/projectile_view.gd`'s `render()` to accept and act on removals:

```gdscript
func render(projectiles: Projectiles) -> void:
    var pooled := mini(projectiles.count, _pool.size())

    for pos in projectiles.removed_positions:
        _trigger_burst_near(pos)

    for i in pooled:
        var instance := _pool[i]
        if not instance.visible:
            instance.visible = true
            instance.get_node("Emitters").scale = Vector3.ONE
            for e in instance.get_node("Emitters").get_children():
                e.emitting = true
                e.visible = true
        instance.position = Vector3(projectiles.positions[i].x, 0.8, projectiles.positions[i].y)
    for i in range(pooled, _pool.size()):
        if _pool[i].visible and not _pool[i].get("collided"):
            _pool[i].visible = false

    var overflow := projectiles.count - pooled
    multimesh.visible_instance_count = max(overflow, 0)
    for i in overflow:
        var src := pooled + i
        var pos := projectiles.positions[src]
        multimesh.set_instance_transform(i,
            Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))

func _trigger_burst_near(pos: Vector2) -> void:
    var world := Vector3(pos.x, 0.8, pos.y)
    for instance in _pool:
        if instance.visible and not instance.get("collided") \
                and instance.position.distance_to(world) < 0.5:
            instance.explode()
            return
```

(`instance.get("collided")` reads the prefab's own exported `collided` bool via Godot's generic
property getter, rather than assuming a cast — the prefab is a vendored `.tscn`, not a GDScript class
this project defines, so there's no `class_name` to type against. `explode()` is the prefab's own
method, confirmed by reading its embedded script in full during design — it stops the trail emitters
and starts the impact burst, which is exactly the visual this step wants.)

Pool-return (making a bursted instance available for reuse again) rides on the existing
`if not instance.visible:` re-arm block in the main loop above — once `_trigger_burst_near` marks an
instance `collided` (implicitly, via the prefab's own `explode()`), the overflow-cleanup loop's
`not _pool[i].get("collided")` guard leaves it visible (and its burst playing) instead of hiding it
mid-effect; the prefab's own `_process()` fades the trail and eventually the instance becomes eligible
for `_trigger_burst_near`'s `not instance.get("collided")` check to skip it until its next natural
`instance.visible = true` re-arm resets `collided` — confirm during Step 3's visual check that a
bursted instance's `collided` flag does reset when `explode()` isn't called again during its fade
(read the prefab script's `_process()`/`explode()` interaction if this doesn't hold; the report should
say plainly if the pool-return behaviour needed a different trigger than assumed here, rather than
silently patching around a wrong assumption).

- [ ] **Step 2: Verify by launching**

Run: `godot --headless --quit-after 300`, expect exit code 0.

- [ ] **Step 3: Verify visually**

Open in the editor, run the main scene. Confirm hits and despawns now show an impact burst at the
right location before the instance disappears, and that sustained firing (enough to cycle the pool
many times over) doesn't leave orphaned instances stuck mid-burst or never returning to the pool —
watch a few minutes of continuous fire specifically for this, since a leak here wouldn't be visible in
a short check.

- [ ] **Step 4: Confirm the suite is still 147/147**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`

- [ ] **Step 5: Commit**

```bash
git add scripts/views/projectile_view.gd
git commit -m "feat: play impact bursts and return pooled projectile instances"
```

---

### Task 7: Device performance pass — hand to Aslam, do not attempt

**This step cannot be performed by an agent.** It requires Aslam's physical Android device, same as
phase 2's Task 8.

Real particle systems (up to 128 pooled instances × ~8 `GPUParticles3D` emitters each, at the pool
ceiling, on top of textured character/environment models replacing flat-colour primitives) are a
different cost profile than anything measured in this project so far. This is a real open question,
not a formality.

- [ ] **Step 1: Build the debug APK**

```
godot --headless --export-debug "Android" builds/jebon-debug.apk
```

- [ ] **Step 2: Hand to Aslam with this checklist**

- Does FPS hold steady near 60 during normal play, same as before this plan?
- Does it drop specifically when many projectiles are in flight at once (the pooled-VFX path), versus
  when many enemies/squad units are visible (the real-model path)? Distinguishing which is worth
  knowing, since the fixes differ — shrink `POOL_SIZE` for the former, nothing obvious for the latter
  beyond reducing model complexity.
- Does the corridor scenery (Task 3) show any visible popping or misalignment as it scrolls, especially
  right at the point where it wraps around?
- Any visible seam, z-fighting, or scale mismatch between the real models and the corridor now that
  everything isn't flat-colour primitives at a known, deliberately-chosen scale?

If FPS holds near 60, no further action needed. If projectile VFX specifically causes a drop, reduce
`ProjectileView.POOL_SIZE` (currently 64 per side) and re-test before considering anything more
drastic — the overflow path already handles a smaller pool gracefully, this is a one-constant change.

## Self-review notes

**Spec coverage.** Covers every row of the spec's scope table: squad (Task 2), enemies (Task 2),
corridor environment (Task 3), and projectile VFX (Tasks 4-6, split at the natural
"movement works" / "impact effects work" boundary the spec's own design section drew). Covers the
spec's `Projectiles.removed_positions` addition (Task 4), the `UnitsView`/`EnemyView` shared-script
mesh problem (Task 2), and the device performance pass (Task 7), matching phase 2's Task 8 precedent
exactly as the spec called for.

**Deliberate simplifications, recorded here rather than hidden:**
1. **One village prop pair (a wall, a fence), not the full modular building kit.** The pack is a
   piece-by-piece assembly system (doors, floors, overhangs, roof segments); composing an actual
   building from those pieces is real additional design work with no clear "one correct way," better
   done later against real playtest feedback on whether flanking scenery alone is enough or a fuller
   streetscape is worth the effort.
2. **One character skin each** (Mage for squad, Minion for enemies), matching the already-approved
   spec decision — the other three adventurer classes and three skeleton variants wait for the
   weapon-classes and enemy-progression phases respectively.
3. **Impact-burst correlation is approximate, not identity-tracked**, as explained in Task 6 — a
   deliberate choice over adding a stable-ID scheme, since the visible result is the same either way
   at this game's speed and scale.

**Known gap.** Task 6's pool-return mechanism depends on how the vendored prefab's `collided` flag and
`_process()` fade interact — Step 1 flags this explicitly as something to confirm during visual
verification rather than an assumption baked in silently. If it doesn't hold as described, that's
useful information for the report, not a sign the step was written wrong.
