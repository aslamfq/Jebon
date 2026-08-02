# Onrush Phase 1 — Steering and Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A grey-box build where a formation of units runs down a scrolling corridor and you steer it left and right — enough to answer whether steering a crowd feels good, which nothing later can fix.

**Architecture:** Pure-logic units extending `RefCounted` with no scene-tree dependency, views that only read and draw, and one scene script wiring them. World constants live in exactly one place. Logic is 2D on the XZ plane; the world scrolls toward a squad fixed at `y = 0`.

**Tech Stack:** Godot 4.7.1 Standard, GDScript, GUT 9.6.1 (both already installed and working). No new dependencies.

Source spec: `docs/specs/2026-08-02-onrush-design.md`

**No guns, no gates, no enemies, no hazards in this plan.** Those are later steps. Adding them now would mean tuning them against steering nobody has felt.

## Global Constraints

- **Logic is 2D.** `Vector2(x, y)`, `x` lateral, `y` forward. Views map to `Vector3(x, 0, y)`. No rule unit may reference a 3D type.
- **Rule units extend `RefCounted`, never `Node`** — constructible in a test with no scene tree.
- **Views read and draw; they never write.** A view must not mutate state handed to it and must contain no rules.
- **No Godot physics anywhere.** No `Area3D`, `RigidBody3D`, `CharacterBody3D`, `PhysicsServer`. Collision is arithmetic over flat arrays.
- **World constants live only in `Corridor`.** Phase 1 of the old design hardcoded the arc angle in three units; that is the defect this rule exists to prevent.
- **Caps:** 256 units per container. Fixed-size arrays, swap-remove, zero allocation in the hot path.
- **Restart resets units in place.** Never reload the scene, never rebuild objects. Every stateful unit needs `reset()`.
- **Godot 4.7.1**, at the path recorded in `CLAUDE.md`. Test scripts use `extends GutTest`.
- **A test a broken implementation would pass is not a test.** For each test, name the wrong implementation it rules out; if there is none, strengthen it. For load-bearing logic, break the implementation deliberately, confirm the test fails, restore, and verify against a committed baseline.

---

### Task 1: Remove the superseded phase-1 code

Clears the deck. `BarricadeSet` only makes sense standing still, and the old scene carries the Critical camera defect. Doing this first means no later task accidentally builds on a dead unit.

**Files:**
- Delete: `scripts/barricade_set.gd` (+ `.uid`), `scripts/views/barricade_view.gd` (+ `.uid`)
- Delete: `scripts/game.gd` (+ `.uid`), `scenes/game.tscn`
- Delete: `test/test_barricade_set.gd` (+ `.uid`), `test/test_game_integration.gd` (+ `.uid`)
- Modify: `project.godot`

**Interfaces:**
- Consumes: nothing.
- Produces: a repo where `Horde`, `WaveDirector`, `Weapon`, `Projectiles`, `AimInput`, `RunState`, `HordeView` and `ProjectileView` remain green and nothing references a barricade.

- [ ] **Step 1: Confirm what depends on the doomed files**

Run: `grep -rn "BarricadeSet\|BarricadeView\|barricade" scripts/ test/ scenes/ project.godot`

Expected: hits only in the files listed above. If anything else references a barricade, stop and report — the deletion list is wrong.

- [ ] **Step 2: Delete them**

```bash
git rm scripts/barricade_set.gd scripts/barricade_set.gd.uid
git rm scripts/views/barricade_view.gd scripts/views/barricade_view.gd.uid
git rm scripts/game.gd scripts/game.gd.uid
git rm scenes/game.tscn
git rm test/test_barricade_set.gd test/test_barricade_set.gd.uid
git rm test/test_game_integration.gd test/test_game_integration.gd.uid
```

- [ ] **Step 3: Clear the main scene setting**

`project.godot` points `run/main_scene` at the scene just deleted. Remove that line entirely — Task 9 restores it. Leaving it would make every later test run print a load error.

Delete this line from the `[application]` section:

```ini
run/main_scene="res://scenes/game.tscn"
```

- [ ] **Step 4: Run the suite and confirm what remains is green**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS with a lower count than 84 — the barricade and integration tests are gone. Report the new count. Expect no errors about a missing main scene.

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: remove superseded fixed-position code"
```

---

### Task 2: Corridor constants

One home for the world's dimensions. Small, but it goes first because every later task reads from it.

**Files:**
- Create: `scripts/corridor.gd`, `test/test_corridor.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Corridor.HALF_WIDTH: float` = 6.0
  - `Corridor.SPAWN_DISTANCE: float` = 60.0
  - `Corridor.RECYCLE_DISTANCE: float` = -5.0
  - `Corridor.BASE_SCROLL_SPEED: float` = 8.0
  - `Corridor.MAX_SCROLL_SPEED: float` = 14.0
  - `Corridor.SCROLL_RAMP_SECONDS: float` = 120.0
  - `Corridor.scroll_speed_at(elapsed: float) -> float` (static)

- [ ] **Step 1: Write the failing tests**

Create `test/test_corridor.gd`:

```gdscript
extends GutTest

func test_recycle_line_is_behind_the_squad():
    assert_lt(Corridor.RECYCLE_DISTANCE, 0.0,
        "content must only be recycled after it has passed the squad at y=0")

func test_spawn_distance_is_well_ahead():
    assert_gt(Corridor.SPAWN_DISTANCE, 0.0)
    assert_gt(Corridor.SPAWN_DISTANCE, Corridor.MAX_SCROLL_SPEED * 2.0,
        "a player must get at least two seconds of warning at top speed")

func test_scroll_starts_at_base_speed():
    assert_almost_eq(Corridor.scroll_speed_at(0.0), Corridor.BASE_SCROLL_SPEED, 0.001)

func test_scroll_accelerates():
    assert_gt(Corridor.scroll_speed_at(30.0), Corridor.scroll_speed_at(0.0))

func test_scroll_plateaus_and_never_exceeds_the_maximum():
    for seconds in [0.0, 60.0, 300.0, 3600.0, 100000.0]:
        assert_lte(Corridor.scroll_speed_at(seconds), Corridor.MAX_SCROLL_SPEED + 0.001,
            "an endless game that ramps forever becomes a countdown, not a game")

func test_scroll_is_close_to_maximum_after_the_ramp():
    var late := Corridor.scroll_speed_at(Corridor.SCROLL_RAMP_SECONDS * 4.0)
    assert_gt(late, Corridor.MAX_SCROLL_SPEED * 0.9,
        "the ramp must actually arrive, not creep forever")

func test_scroll_is_monotonic():
    var previous := 0.0
    for i in 200:
        var current := Corridor.scroll_speed_at(float(i) * 5.0)
        assert_gte(current, previous - 0.001, "speed must never drop mid-run")
        previous = current
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Corridor` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/corridor.gd`:

```gdscript
class_name Corridor extends RefCounted

# The world's dimensions live here and nowhere else. The previous design
# hardcoded its arc angle in three separate units, which is a defect waiting
# to drift the moment one of them changes.

const HALF_WIDTH := 6.0
const SPAWN_DISTANCE := 60.0
const RECYCLE_DISTANCE := -5.0

const BASE_SCROLL_SPEED := 8.0
const MAX_SCROLL_SPEED := 14.0
const SCROLL_RAMP_SECONDS := 120.0

# Approaches MAX_SCROLL_SPEED asymptotically and never reaches it, so the run
# settles into a steady tempo instead of accelerating until failure is certain.
static func scroll_speed_at(elapsed: float) -> float:
    var t: float = 1.0 - exp(-elapsed / SCROLL_RAMP_SECONDS * 3.0)
    return BASE_SCROLL_SPEED + (MAX_SCROLL_SPEED - BASE_SCROLL_SPEED) * t
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Corridor tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/corridor.gd scripts/corridor.gd.uid test/test_corridor.gd test/test_corridor.gd.uid
git commit -m "feat: add Corridor world constants with plateauing scroll speed"
```

---

### Task 3: Units

The generic container, used later for both the squad and enemy crowds. Adapted from `Horde`: storage, swap-remove, `spawn`, `damage_at` and `clear` carry over; movement changes from "walk toward the origin" to "integrate a velocity", because walking toward the origin was fixed-position logic.

`Horde` and its tests are replaced by this and deleted.

**Files:**
- Create: `scripts/units.gd`, `test/test_units.gd`
- Delete: `scripts/horde.gd` (+ `.uid`), `test/test_horde.gd` (+ `.uid`)
- Modify: `scripts/views/horde_view.gd` — retarget to `Units` (Task 7 handles the rename; here just keep it compiling)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Units.MAX_UNITS: int` = 256
  - `Units.new() -> Units`
  - `units.count: int` — live units occupy `[0, count)`
  - `units.positions: PackedVector2Array`, `units.velocities: PackedVector2Array`, `units.healths: PackedFloat32Array`
  - `units.spawn(pos: Vector2, velocity: Vector2, health: float) -> bool`
  - `units.tick(delta: float) -> void`
  - `units.damage_at(point: Vector2, radius: float, amount: float) -> int`
  - `units.remove_beyond(min_y: float) -> int`
  - `units.set_position(i: int, pos: Vector2) -> void`
  - `units.remove_last(n: int) -> void`
  - `units.clear() -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_units.gd`:

```gdscript
extends GutTest

var units: Units

func before_each():
    units = Units.new()

func test_spawn_increases_count():
    assert_true(units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0))
    assert_eq(units.count, 1)

func test_spawn_fails_when_full_and_count_stays_at_the_cap():
    for i in Units.MAX_UNITS:
        assert_true(units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0))
    assert_false(units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0))
    assert_eq(units.count, Units.MAX_UNITS)

func test_tick_integrates_velocity():
    units.spawn(Vector2(0, 10), Vector2(2, -3), 10.0)
    units.tick(0.5)
    assert_almost_eq(units.positions[0].x, 1.0, 0.001)
    assert_almost_eq(units.positions[0].y, 8.5, 0.001)

func test_a_stationary_unit_does_not_move():
    units.spawn(Vector2(4, 4), Vector2.ZERO, 10.0)
    units.tick(1.0)
    assert_almost_eq(units.positions[0].x, 4.0, 0.001)
    assert_almost_eq(units.positions[0].y, 4.0, 0.001)

func test_tick_is_frame_rate_independent():
    var coarse := Units.new()
    var fine := Units.new()
    coarse.spawn(Vector2.ZERO, Vector2(0, 10), 1.0)
    fine.spawn(Vector2.ZERO, Vector2(0, 10), 1.0)
    for i in 10:
        coarse.tick(0.1)
    for i in 100:
        fine.tick(0.01)
    assert_almost_eq(coarse.positions[0].y, fine.positions[0].y, 0.001)

func test_damage_at_kills_and_reports():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 10.0), 1)
    assert_eq(units.count, 0)

func test_damage_at_wounds_without_killing():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 4.0), 0)
    assert_almost_eq(units.healths[0], 6.0, 0.001)

func test_damage_at_misses_outside_radius():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 20), 1.0, 10.0), 0)
    assert_eq(units.count, 1)

func test_damage_at_kills_every_clustered_unit_in_one_call():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(0.2, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(-0.2, 10), Vector2.ZERO, 1.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 5.0), 3,
        "swap-remove must re-test the unit swapped into the vacated slot")
    assert_eq(units.count, 0)

func test_swap_remove_keeps_survivors_intact():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(5, 5), Vector2(1, 2), 7.0)
    units.damage_at(Vector2(0, 10), 0.5, 5.0)
    assert_eq(units.count, 1)
    assert_eq(units.positions[0], Vector2(5, 5))
    assert_eq(units.velocities[0], Vector2(1, 2))
    assert_almost_eq(units.healths[0], 7.0, 0.001)

func test_remove_beyond_drops_only_what_has_passed():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(0, -10), Vector2.ZERO, 1.0)
    assert_eq(units.remove_beyond(-5.0), 1)
    assert_eq(units.count, 1)
    assert_almost_eq(units.positions[0].y, 10.0, 0.001)

func test_remove_beyond_handles_every_unit_passing_at_once():
    for i in 5:
        units.spawn(Vector2(0, -10.0 - float(i)), Vector2.ZERO, 1.0)
    assert_eq(units.remove_beyond(-5.0), 5)
    assert_eq(units.count, 0)

func test_remove_last_shrinks_from_the_end():
    for i in 5:
        units.spawn(Vector2(float(i), 0), Vector2.ZERO, 1.0)
    units.remove_last(2)
    assert_eq(units.count, 3)
    assert_almost_eq(units.positions[0].x, 0.0, 0.001)

func test_remove_last_cannot_go_negative():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    units.remove_last(50)
    assert_eq(units.count, 0)

func test_clear_empties():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    units.clear()
    assert_eq(units.count, 0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Units` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/units.gd`:

```gdscript
class_name Units extends RefCounted

const MAX_UNITS := 256

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var healths := PackedFloat32Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_UNITS)
    velocities.resize(MAX_UNITS)
    healths.resize(MAX_UNITS)

func spawn(pos: Vector2, velocity: Vector2, health: float) -> bool:
    if count >= MAX_UNITS:
        return false
    positions[count] = pos
    velocities[count] = velocity
    healths[count] = health
    count += 1
    return true

func tick(delta: float) -> void:
    for i in count:
        positions[i] += velocities[i] * delta

func set_position(i: int, pos: Vector2) -> void:
    positions[i] = pos

func damage_at(point: Vector2, radius: float, amount: float) -> int:
    var kills := 0
    var radius_sq := radius * radius
    var i := 0
    while i < count:
        if positions[i].distance_squared_to(point) <= radius_sq:
            healths[i] -= amount
            if healths[i] <= 0.0:
                _remove_at(i)
                kills += 1
                continue   # slot i now holds a different unit; re-test it
        i += 1
    return kills

func remove_beyond(min_y: float) -> int:
    var removed := 0
    var i := 0
    while i < count:
        if positions[i].y < min_y:
            _remove_at(i)
            removed += 1
            continue
        i += 1
    return removed

func remove_last(n: int) -> void:
    count = max(count - n, 0)

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    velocities[i] = velocities[last]
    healths[i] = healths[last]
    count = last
```

The `continue` without incrementing `i`, in both `damage_at` and `remove_beyond`, is load-bearing. Swap-remove moves the tail into slot `i`, and that unit has not been tested yet.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Units tests PASS.

- [ ] **Step 5: Verify the swap-remove tests bite**

Commit first, so the restoration check is meaningful. Then temporarily change `damage_at`'s `continue` to `i += 1` and re-run: `test_damage_at_kills_every_clustered_unit_in_one_call` must FAIL. Do the same for `remove_beyond` against `test_remove_beyond_handles_every_unit_passing_at_once`. Restore, and confirm `git diff scripts/units.gd` is empty.

- [ ] **Step 6: Delete Horde and repoint the view**

```bash
git rm scripts/horde.gd scripts/horde.gd.uid test/test_horde.gd test/test_horde.gd.uid
```

`scripts/views/horde_view.gd` references `Horde.MAX_ZOMBIES` and takes a `Horde` parameter. Change those to `Units.MAX_UNITS` and `Units`. Do not rename the file yet — Task 7 does that.

- [ ] **Step 7: Run the suite and commit**

Run the suite; expected PASS. Then:

```bash
git add -A
git commit -m "feat: replace Horde with generic Units container"
```

---

### Task 4: Formation

Turns a unit index into a target slot. Pure, static, stateless — the shape of the crowd is a function, not a thing that holds state.

**Files:**
- Create: `scripts/formation.gd`, `test/test_formation.gd`

**Interfaces:**
- Consumes: `Corridor.HALF_WIDTH`.
- Produces:
  - `Formation.Kind` enum: `WIDE = 0`, `COLUMN = 1`, `WEDGE = 2`
  - `Formation.SPACING: float` = 0.9
  - `Formation.WIDE_COLUMNS: int` = 11
  - `Formation.COLUMN_COLUMNS: int` = 3
  - `Formation.slot(index: int, kind: int, centre_x: float) -> Vector2` (static)

Note `slot` does not need `count` — every layout is determined by index alone, which keeps it a pure function of position in the queue and makes growth visually stable (existing units do not jump when new ones arrive).

- [ ] **Step 1: Write the failing tests**

Create `test/test_formation.gd`:

```gdscript
extends GutTest

func test_first_unit_sits_at_the_centre_line_in_a_column():
    var p := Formation.slot(0, Formation.Kind.COLUMN, 0.0)
    assert_almost_eq(p.x, 0.0, 0.001)
    assert_almost_eq(p.y, 0.0, 0.001)

func test_formation_follows_the_centre():
    var a := Formation.slot(0, Formation.Kind.COLUMN, 0.0)
    var b := Formation.slot(0, Formation.Kind.COLUMN, 3.0)
    assert_almost_eq(b.x - a.x, 3.0, 0.001)

func test_wide_is_wider_than_column():
    var wide_span := _span(Formation.Kind.WIDE, 33)
    var column_span := _span(Formation.Kind.COLUMN, 33)
    assert_gt(wide_span, column_span,
        "if these matched, the formation gate would be cosmetic")

func test_wedge_is_between_the_other_two():
    var wedge := _span(Formation.Kind.WEDGE, 33)
    assert_gt(wedge, _span(Formation.Kind.COLUMN, 33))
    assert_lt(wedge, _span(Formation.Kind.WIDE, 33) + 0.001)

func test_ranks_extend_backwards_not_forwards():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        for i in 60:
            assert_lte(Formation.slot(i, kind, 0.0).y, 0.001,
                "the squad must trail behind its centre, never lead it")

func test_no_slot_leaves_the_corridor():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        for centre in [-Corridor.HALF_WIDTH, 0.0, Corridor.HALF_WIDTH]:
            for i in Units.MAX_UNITS:
                var x: float = Formation.slot(i, kind, centre).x
                assert_between(x, -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001,
                    "units must never be laid out beyond the corridor walls")

func test_slots_are_distinct():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        var seen := {}
        for i in 40:
            var p := Formation.slot(i, kind, 0.0)
            var key := "%.3f,%.3f" % [p.x, p.y]
            assert_false(seen.has(key),
                "two units stacked in one slot looks like a rendering bug")
            seen[key] = true

func test_layout_is_stable_as_the_squad_grows():
    var before := Formation.slot(5, Formation.Kind.WIDE, 0.0)
    var after := Formation.slot(5, Formation.Kind.WIDE, 0.0)
    assert_eq(before, after,
        "an existing unit must not jump when the squad grows")

func _span(kind: int, n: int) -> float:
    var lo := 1000.0
    var hi := -1000.0
    for i in n:
        var x: float = Formation.slot(i, kind, 0.0).x
        lo = min(lo, x)
        hi = max(hi, x)
    return hi - lo
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Formation` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/formation.gd`:

```gdscript
class_name Formation extends RefCounted

enum Kind { WIDE = 0, COLUMN = 1, WEDGE = 2 }

const SPACING := 0.9
const WIDE_COLUMNS := 11
const COLUMN_COLUMNS := 3

# Slot position is a function of index alone, so an existing unit never moves
# when the squad grows. Ranks extend backwards (negative y) from the centre.
static func slot(index: int, kind: int, centre_x: float) -> Vector2:
    var offset := Vector2.ZERO
    match kind:
        Kind.WEDGE:
            offset = _wedge_offset(index)
        Kind.COLUMN:
            offset = _grid_offset(index, COLUMN_COLUMNS)
        _:
            offset = _grid_offset(index, WIDE_COLUMNS)
    var x: float = clamp(centre_x + offset.x, -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)
    return Vector2(x, offset.y)

static func _grid_offset(index: int, columns: int) -> Vector2:
    var row := index / columns
    var col := index % columns
    var x := (float(col) - float(columns - 1) * 0.5) * SPACING
    return Vector2(x, -float(row) * SPACING)

# Row r holds r+1 units, so the crowd forms a triangle with its point forward.
static func _wedge_offset(index: int) -> Vector2:
    var row := 0
    var consumed := 0
    while consumed + row + 1 <= index:
        consumed += row + 1
        row += 1
    var col := index - consumed
    var x := (float(col) - float(row) * 0.5) * SPACING
    return Vector2(x, -float(row) * SPACING)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Formation tests PASS.

**Understand what the `clamp` is and is not doing.** At a centred squad, `WIDE` spans ±4.5 and sits
inside the ±6 corridor on its own — the clamp does nothing. The clamp only engages when the centre is
driven to a wall, where it compresses the near edge of the formation against it. That is acceptable
for this phase and is why `test_slots_are_distinct` checks a centred squad only.

What is **not** acceptable is the clamp doing work at centre zero, because that means the formation is
wider than the corridor and units are stacking on the walls in normal play. If `test_slots_are_distinct`
fails, that is the cause: reduce `WIDE_COLUMNS` or `SPACING` until a centred squad fits unclamped, and
report what you changed.

- [ ] **Step 5: Commit**

```bash
git add scripts/formation.gd scripts/formation.gd.uid test/test_formation.gd test/test_formation.gd.uid
git commit -m "feat: add Formation with wide, column and wedge layouts"
```

---

### Task 5: SteerInput

Adapted from `AimInput`. The frame-independent `1 - exp(-k·dt)` smoothing and the clamp carry over directly; the clamp bound becomes corridor width instead of an angle, and the output becomes a lateral position instead of a direction vector.

`AimInput` and its tests are replaced by this and deleted.

**Files:**
- Create: `scripts/steer_input.gd`, `test/test_steer_input.gd`
- Delete: `scripts/aim_input.gd` (+ `.uid`), `test/test_aim_input.gd` (+ `.uid`)

**Interfaces:**
- Consumes: `Corridor.HALF_WIDTH`.
- Produces:
  - `SteerInput.SMOOTHING: float` = 14.0
  - `SteerInput.PIXELS_PER_UNIT: float` = 90.0
  - `SteerInput.new() -> SteerInput`
  - `steer.centre_x: float` — starts at 0.0
  - `steer.steer_to_screen_delta(delta_pixels: Vector2) -> void`
  - `steer.tick(delta: float) -> void`
  - `steer.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_steer_input.gd`:

```gdscript
extends GutTest

var steer: SteerInput

func before_each():
    steer = SteerInput.new()

func test_starts_centred():
    assert_almost_eq(steer.centre_x, 0.0, 0.001)

func test_dragging_right_moves_right():
    steer.steer_to_screen_delta(Vector2(180, 0))
    for i in 120:
        steer.tick(1.0 / 60.0)
    assert_gt(steer.centre_x, 0.0)

func test_dragging_left_moves_left():
    steer.steer_to_screen_delta(Vector2(-180, 0))
    for i in 120:
        steer.tick(1.0 / 60.0)
    assert_lt(steer.centre_x, 0.0)

func test_vertical_drag_is_ignored():
    steer.steer_to_screen_delta(Vector2(0, 500))
    for i in 60:
        steer.tick(1.0 / 60.0)
    assert_almost_eq(steer.centre_x, 0.0, 0.001,
        "this game steers on one axis only")

func test_never_leaves_the_corridor_in_either_direction():
    for pixels in [100000.0, -100000.0]:
        var s := SteerInput.new()
        s.steer_to_screen_delta(Vector2(pixels, 0))
        for i in 600:
            s.tick(1.0 / 60.0)
        assert_between(s.centre_x,
            -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001,
            "the squad must never leave the corridor, however hard you drag")

func test_movement_is_smoothed_not_instant():
    steer.steer_to_screen_delta(Vector2(100000, 0))
    steer.tick(1.0 / 60.0)
    assert_lt(steer.centre_x, Corridor.HALF_WIDTH * 0.9,
        "one frame must not teleport the squad across the corridor")

func test_smoothing_is_frame_rate_independent():
    var coarse := SteerInput.new()
    var fine := SteerInput.new()
    coarse.steer_to_screen_delta(Vector2(300, 0))
    fine.steer_to_screen_delta(Vector2(300, 0))
    for i in 10:
        coarse.tick(1.0 / 60.0)
    for i in 100:
        fine.tick(1.0 / 600.0)
    assert_almost_eq(coarse.centre_x, fine.centre_x, 0.001,
        "the same elapsed time must produce the same position at any frame rate")

func test_it_settles_rather_than_drifting():
    steer.steer_to_screen_delta(Vector2(200, 0))
    for i in 600:
        steer.tick(1.0 / 60.0)
    var settled := steer.centre_x
    steer.tick(1.0 / 60.0)
    assert_almost_eq(steer.centre_x, settled, 0.0001)

func test_reset_recentres_and_clears_the_pending_target():
    steer.steer_to_screen_delta(Vector2(300, 0))
    for i in 60:
        steer.tick(1.0 / 60.0)
    steer.reset()
    assert_almost_eq(steer.centre_x, 0.0, 0.001)
    steer.tick(1.0 / 60.0)
    assert_almost_eq(steer.centre_x, 0.0, 0.001,
        "a stale target must not drag the squad back off centre after a reset")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `SteerInput` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/steer_input.gd`:

```gdscript
class_name SteerInput extends RefCounted

const SMOOTHING := 14.0
const PIXELS_PER_UNIT := 90.0

var centre_x := 0.0

var _target_x := 0.0

func steer_to_screen_delta(delta_pixels: Vector2) -> void:
    _target_x = clamp(delta_pixels.x / PIXELS_PER_UNIT,
        -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)

func tick(delta: float) -> void:
    # Exponential smoothing. A raw lerp(a, b, k*delta) changes feel with frame
    # rate and can overshoot on a long frame; steering feel is the one thing
    # this whole phase exists to evaluate, so it must not vary by machine.
    var t: float = 1.0 - exp(-SMOOTHING * delta)
    centre_x += (_target_x - centre_x) * t

func reset() -> void:
    centre_x = 0.0
    _target_x = 0.0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all SteerInput tests PASS.

- [ ] **Step 5: Verify the clamp and the smoothing bite**

Commit first. Then replace the `exp` smoothing with `centre_x = _target_x` and confirm `test_movement_is_smoothed_not_instant` fails. Restore. Then remove the `clamp` and confirm `test_never_leaves_the_corridor_in_either_direction` fails. Restore, and confirm `git diff scripts/steer_input.gd` is empty.

- [ ] **Step 6: Delete AimInput and commit**

```bash
git rm scripts/aim_input.gd scripts/aim_input.gd.uid test/test_aim_input.gd test/test_aim_input.gd.uid
git add -A
git commit -m "feat: replace AimInput with SteerInput for lateral steering"
```

---

### Task 6: Squad

The player's units. Owns the count, formation and lateral centre, and moves units toward their slots.

**Files:**
- Create: `scripts/squad.gd`, `test/test_squad.gd`

**Interfaces:**
- Consumes: `Units`, `Formation`, `Corridor`.
- Produces:
  - `Squad.SLOT_LERP: float` = 12.0
  - `Squad.STARTING_COUNT: int` = 12
  - `Squad.new() -> Squad`
  - `squad.units: Units`
  - `squad.formation: int` — a `Formation.Kind`
  - `squad.centre_x: float`
  - `squad.count() -> int`
  - `squad.set_count(n: int) -> void` — clamps to `[0, Units.MAX_UNITS]`
  - `squad.tick(delta: float, centre_x: float) -> void`
  - `squad.is_wiped() -> bool`
  - `squad.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_squad.gd`:

```gdscript
extends GutTest

var squad: Squad

func before_each():
    squad = Squad.new()

func test_starts_with_the_starting_count():
    assert_eq(squad.count(), Squad.STARTING_COUNT)

func test_starts_wide():
    assert_eq(squad.formation, Formation.Kind.WIDE)

func test_set_count_grows():
    squad.set_count(40)
    assert_eq(squad.count(), 40)

func test_set_count_shrinks():
    squad.set_count(3)
    assert_eq(squad.count(), 3)

func test_set_count_clamps_to_the_cap():
    squad.set_count(10000)
    assert_eq(squad.count(), Units.MAX_UNITS,
        "a multiplier gate must not be able to exceed the cap")

func test_set_count_cannot_go_negative():
    squad.set_count(-5)
    assert_eq(squad.count(), 0)

func test_wiped_only_at_zero():
    squad.set_count(1)
    assert_false(squad.is_wiped())
    squad.set_count(0)
    assert_true(squad.is_wiped())

func test_units_converge_on_their_slots():
    squad.tick(0.0, 0.0)
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    for i in squad.count():
        var target := Formation.slot(i, squad.formation, 0.0)
        assert_almost_eq(squad.units.positions[i].x, target.x, 0.05)
        assert_almost_eq(squad.units.positions[i].y, target.y, 0.05)

func test_the_squad_follows_a_moving_centre():
    for i in 200:
        squad.tick(1.0 / 60.0, 4.0)
    for i in squad.count():
        assert_gt(squad.units.positions[i].x, 2.0,
            "the whole squad must travel with the centre, not just its lead unit")

func test_convergence_is_gradual_not_instant():
    squad.tick(1.0 / 60.0, 5.0)
    assert_lt(squad.units.positions[0].x, 5.0,
        "one frame must not snap the squad to its new slot")

func test_changing_formation_moves_the_squad():
    squad.set_count(30)
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    var wide_span := _span()
    squad.formation = Formation.Kind.COLUMN
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    assert_lt(_span(), wide_span,
        "a formation gate must visibly reshape the crowd")

func test_growth_places_new_units_inside_the_corridor():
    squad.set_count(Units.MAX_UNITS)
    for i in squad.count():
        assert_between(squad.units.positions[i].x,
            -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001)

func test_reset_restores_the_opening_state():
    squad.set_count(200)
    squad.formation = Formation.Kind.WEDGE
    for i in 60:
        squad.tick(1.0 / 60.0, 5.0)
    squad.reset()
    assert_eq(squad.count(), Squad.STARTING_COUNT)
    assert_eq(squad.formation, Formation.Kind.WIDE)
    assert_almost_eq(squad.centre_x, 0.0, 0.001)

func _span() -> float:
    var lo := 1000.0
    var hi := -1000.0
    for i in squad.count():
        lo = min(lo, squad.units.positions[i].x)
        hi = max(hi, squad.units.positions[i].x)
    return hi - lo
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Squad` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/squad.gd`:

```gdscript
class_name Squad extends RefCounted

const SLOT_LERP := 12.0
const STARTING_COUNT := 12
const UNIT_HEALTH := 1.0

var units: Units
var formation: int = Formation.Kind.WIDE
var centre_x := 0.0

func _init() -> void:
    units = Units.new()
    reset()

func count() -> int:
    return units.count

func set_count(n: int) -> void:
    var target: int = clamp(n, 0, Units.MAX_UNITS)
    if target < units.count:
        units.remove_last(units.count - target)
        return
    while units.count < target:
        # New units appear at their own slot rather than at the centre, so a
        # growth gate reads as the crowd widening instead of erupting from a point.
        var slot := Formation.slot(units.count, formation, centre_x)
        units.spawn(slot, Vector2.ZERO, UNIT_HEALTH)

func tick(delta: float, new_centre_x: float) -> void:
    centre_x = new_centre_x
    var t: float = 1.0 - exp(-SLOT_LERP * delta)
    for i in units.count:
        var target := Formation.slot(i, formation, centre_x)
        units.set_position(i, units.positions[i] + (target - units.positions[i]) * t)

func is_wiped() -> bool:
    return units.count <= 0

func reset() -> void:
    formation = Formation.Kind.WIDE
    centre_x = 0.0
    units.clear()
    set_count(STARTING_COUNT)
```

Units are positioned directly rather than through `Units.tick`, because the squad is driven by its formation rather than by velocity. `Units.velocities` stays zero for the squad and is used by enemy crowds later.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Squad tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/squad.gd scripts/squad.gd.uid test/test_squad.gd test/test_squad.gd.uid
git commit -m "feat: add Squad with formation-driven slot convergence"
```

---

### Task 7: TrackRunner and the views

The scroll, and enough to see it. Without visible ground motion the corridor reads as a static screen with a wobbling crowd, and the question this phase asks cannot be answered.

**Files:**
- Create: `scripts/track_runner.gd`, `test/test_track_runner.gd`
- Create: `scripts/views/corridor_view.gd`
- Rename: `scripts/views/horde_view.gd` → `scripts/views/units_view.gd` (class `HordeView` → `UnitsView`)

**Interfaces:**
- Consumes: `Corridor`.
- Produces:
  - `TrackRunner.MARKER_SPACING: float` = 6.0
  - `TrackRunner.new() -> TrackRunner`
  - `runner.distance: float`
  - `runner.elapsed: float`
  - `runner.markers: PackedFloat32Array`
  - `runner.tick(delta: float) -> void`
  - `runner.reset() -> void`
  - `UnitsView.render(units: Units, time: float) -> void`
  - `CorridorView.render(runner: TrackRunner) -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_track_runner.gd`:

```gdscript
extends GutTest

var runner: TrackRunner

func before_each():
    runner = TrackRunner.new()

func test_starts_at_zero_distance():
    assert_almost_eq(runner.distance, 0.0, 0.001)

func test_distance_accumulates():
    runner.tick(1.0)
    assert_gt(runner.distance, 0.0)

func test_distance_matches_the_scroll_speed():
    runner.tick(1.0)
    assert_almost_eq(runner.distance, Corridor.scroll_speed_at(0.0), 0.5,
        "distance is accumulated scroll, so the two must agree")

func test_distance_never_decreases():
    var previous := 0.0
    for i in 300:
        runner.tick(1.0 / 60.0)
        assert_gte(runner.distance, previous)
        previous = runner.distance

func test_markers_move_toward_the_squad():
    var before := runner.markers[0]
    runner.tick(0.25)
    assert_lt(runner.markers[0], before)

func test_markers_recycle_instead_of_running_out():
    for i in 6000:
        runner.tick(1.0 / 60.0)
    assert_gt(runner.markers.size(), 0)
    for m in runner.markers:
        assert_between(m, Corridor.RECYCLE_DISTANCE - 0.001,
            Corridor.SPAWN_DISTANCE + TrackRunner.MARKER_SPACING + 0.001,
            "a marker outside the corridor means recycling is broken")

func test_marker_count_stays_constant():
    var initial := runner.markers.size()
    for i in 6000:
        runner.tick(1.0 / 60.0)
    assert_eq(runner.markers.size(), initial,
        "markers must be recycled, never allocated per frame")

func test_markers_stay_evenly_spaced():
    for i in 500:
        runner.tick(1.0 / 60.0)
    var sorted := Array(runner.markers)
    sorted.sort()
    for i in range(1, sorted.size()):
        assert_almost_eq(sorted[i] - sorted[i - 1], TrackRunner.MARKER_SPACING, 0.001,
            "uneven spacing would read as stuttering ground")

func test_scroll_accelerates_over_a_run():
    var early := runner.distance
    runner.tick(1.0)
    var first_second := runner.distance - early
    for i in 6000:
        runner.tick(1.0 / 60.0)
    var later := runner.distance
    runner.tick(1.0)
    assert_gt(runner.distance - later, first_second,
        "the run must speed up, or the ramp does nothing")

func test_reset_returns_to_the_start():
    for i in 600:
        runner.tick(1.0 / 60.0)
    runner.reset()
    assert_almost_eq(runner.distance, 0.0, 0.001)
    assert_almost_eq(runner.elapsed, 0.0, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `TrackRunner` is not a known class.

- [ ] **Step 3: Write TrackRunner**

Create `scripts/track_runner.gd`:

```gdscript
class_name TrackRunner extends RefCounted

const MARKER_SPACING := 6.0

var distance := 0.0
var elapsed := 0.0
var markers := PackedFloat32Array()

func _init() -> void:
    var span := Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE
    markers.resize(int(ceil(span / MARKER_SPACING)) + 1)
    reset()

func tick(delta: float) -> void:
    elapsed += delta
    var speed := Corridor.scroll_speed_at(elapsed)
    var step := speed * delta
    distance += step
    var span := float(markers.size()) * MARKER_SPACING
    for i in markers.size():
        var y := markers[i] - step
        # Wrap rather than reallocate, so a long run allocates nothing.
        while y < Corridor.RECYCLE_DISTANCE:
            y += span
        markers[i] = y

func reset() -> void:
    distance = 0.0
    elapsed = 0.0
    for i in markers.size():
        markers[i] = Corridor.RECYCLE_DISTANCE + float(i) * MARKER_SPACING
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all TrackRunner tests PASS.

- [ ] **Step 5: Rename HordeView to UnitsView**

```bash
git mv scripts/views/horde_view.gd scripts/views/units_view.gd
git rm scripts/views/horde_view.gd.uid
```

Inside the file change `class_name HordeView` to `class_name UnitsView`. Its `render` already takes the container and a time value; confirm the parameter type is `Units` after Task 3's edit. Godot regenerates the `.uid` — commit the new one.

- [ ] **Step 6: Write CorridorView**

Create `scripts/views/corridor_view.gd`:

```gdscript
class_name CorridorView extends Node3D

const WALL_HEIGHT := 1.2
const STRIPE_DEPTH := 0.6

var _stripes: Array[MeshInstance3D] = []

func _ready() -> void:
    _add_ground()
    _add_wall(-Corridor.HALF_WIDTH)
    _add_wall(Corridor.HALF_WIDTH)

func render(runner: TrackRunner) -> void:
    _ensure_stripes(runner.markers.size())
    for i in runner.markers.size():
        var stripe := _stripes[i]
        var pos := stripe.position
        pos.z = runner.markers[i]
        stripe.position = pos

func _ensure_stripes(n: int) -> void:
    while _stripes.size() < n:
        var mesh := BoxMesh.new()
        mesh.size = Vector3(Corridor.HALF_WIDTH * 2.0, 0.02, STRIPE_DEPTH)
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.45, 0.45, 0.5)
        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = material
        instance.position = Vector3(0, 0.01, 0)
        add_child(instance)
        _stripes.append(instance)

func _add_ground() -> void:
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(Corridor.HALF_WIDTH * 2.0,
        Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.62, 0.6, 0.58)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = Vector3(0, 0,
        (Corridor.SPAWN_DISTANCE + Corridor.RECYCLE_DISTANCE) * 0.5)
    add_child(instance)

func _add_wall(x: float) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.2, WALL_HEIGHT,
        Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.5, 0.52, 0.58)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = Vector3(x, WALL_HEIGHT * 0.5,
        (Corridor.SPAWN_DISTANCE + Corridor.RECYCLE_DISTANCE) * 0.5)
    add_child(instance)

func _stripe_count() -> int:
    return _stripes.size()
```

- [ ] **Step 7: Smoke-check the views headlessly**

The views have no unit tests — they hold no rules. But a typo here becomes a blank screen in Task 9, which is far harder to debug. Write a THROWAWAY script (not in `test/`, deleted before committing) that instantiates `UnitsView` and `CorridorView`, calls `_ready()`, drives each with real state, and prints `multimesh.visible_instance_count` and the stripe count. Confirm no runtime errors and that the counts match the input. Report its output and confirm deletion.

Note: `MultiMesh.get_instance_transform()` reads back zero under `--headless` because the dummy renderer does not retain transform data. That is a known engine artifact — check `visible_instance_count`, not transforms.

- [ ] **Step 8: Run the suite and commit**

```bash
git add -A
git commit -m "feat: add TrackRunner scroll and corridor view"
```

---

### Task 8: Camera, derived and verified

**Do not guess these numbers.** The previous design's camera was signed off as verified when only its facing direction had been checked, and it could not see two-thirds of its play area. Facing is not framing.

**Files:**
- Create: `docs/camera-derivation.md`

**Interfaces:**
- Consumes: `Corridor`.
- Produces: a documented camera position, rotation, `fov` and `keep_aspect` for Task 9 to place in the scene.

- [ ] **Step 1: Establish the framing requirement**

The camera must show, with at least 15% angular margin:
- both corridor walls at `x = ±Corridor.HALF_WIDTH` at the squad's depth (`y = 0`)
- the corridor floor from `y = 0` out to at least `y = 30` so approaching content is visible early
- a unit capsule (0.5 units wide) at no less than 10 screen pixels at `y = 30`

The viewport is **1080×1920 portrait, aspect 0.5625** — read it from `project.godot` and use what
is actually there rather than this line, which is a transcription and could drift.

- [ ] **Step 2: Set keep_aspect correctly**

Godot's `Camera3D.fov` is **vertical** by default (`keep_aspect = KEEP_HEIGHT = 1`). On a portrait screen that makes the horizontal field far narrower than the number suggests, which is precisely how the previous camera failed.

Set `keep_aspect = 0` (`KEEP_WIDTH`) so `fov` specifies the **horizontal** field. Vertical then follows from the aspect, which on a tall screen means generous forward visibility for free.

- [ ] **Step 3: Derive the values**

Write a throwaway script that, for candidate camera positions and rotations:
1. builds the camera basis from position and Euler rotation,
2. computes the angle off the forward axis for each of: `(±HALF_WIDTH, 0, 0)`, `(±HALF_WIDTH, 0, 30)`, `(0, 0, 30)`,
3. compares each against the horizontal and vertical half-FOV implied by the chosen `fov`, `keep_aspect` and aspect ratio,
4. computes the on-screen pixel width of a 0.5-unit capsule at `y = 0` and `y = 30`.

Search until every requirement in Step 1 holds. Start near position `(0, 6, -9)` with rotation `(-22, 180, 0)` and `fov` around 62 — this is a starting point to test, not an answer to adopt.

- [ ] **Step 4: Record the derivation**

Create `docs/camera-derivation.md` containing the chosen values, the computed off-axis angle for every checked point, the horizontal and vertical half-FOV, the margin in each case, and the pixel widths. Someone changing `Corridor.HALF_WIDTH` later must be able to see immediately whether the camera still works.

- [ ] **Step 5: Commit**

```bash
git add docs/camera-derivation.md
git commit -m "docs: derive and verify the corridor camera framing"
```

---

### Task 9: Wire it into something playable

**Files:**
- Create: `scripts/game.gd`, `scenes/game.tscn`, `test/test_game_integration.gd`
- Modify: `project.godot` — restore `run/main_scene`

**Interfaces:**
- Consumes: every unit above.
- Produces: a running game.

- [ ] **Step 1: Write the failing integration tests**

Create `test/test_game_integration.gd`:

```gdscript
extends GutTest

# Mirrors game.gd's _process ordering with no scene tree.
func _simulate(seconds: float, drag_pixels: float) -> Dictionary:
    var squad := Squad.new()
    var steer := SteerInput.new()
    var runner := TrackRunner.new()
    var step := 1.0 / 60.0
    var elapsed := 0.0
    steer.steer_to_screen_delta(Vector2(drag_pixels, 0))
    while elapsed < seconds:
        runner.tick(step)
        steer.tick(step)
        squad.tick(step, steer.centre_x)
        elapsed += step
    return {"squad": squad, "steer": steer, "runner": runner}

func test_a_run_covers_ground():
    var result := _simulate(10.0, 0.0)
    assert_gt(result["runner"].distance, 50.0)

func test_steering_moves_the_whole_squad():
    var result := _simulate(3.0, 400.0)
    var squad: Squad = result["squad"]
    for i in squad.count():
        assert_gt(squad.units.positions[i].x, 1.0,
            "every unit must follow, not only the lead one")

func test_the_squad_never_leaves_the_corridor():
    for drag in [100000.0, -100000.0]:
        var squad: Squad = _simulate(20.0, drag)["squad"]
        for i in squad.count():
            assert_between(squad.units.positions[i].x,
                -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001)

func test_the_squad_survives_when_nothing_attacks_it():
    var squad: Squad = _simulate(60.0, 0.0)["squad"]
    assert_eq(squad.count(), Squad.STARTING_COUNT)
    assert_false(squad.is_wiped(),
        "nothing in this phase can kill a unit, so nothing may")

func test_a_long_run_stays_bounded():
    var result := _simulate(120.0, 0.0)
    for m in result["runner"].markers:
        assert_between(m, Corridor.RECYCLE_DISTANCE - 0.001,
            Corridor.SPAWN_DISTANCE + TrackRunner.MARKER_SPACING + 0.001)

func test_the_simulation_is_reproducible():
    var a := _simulate(20.0, 250.0)
    var b := _simulate(20.0, 250.0)
    assert_almost_eq(a["runner"].distance, b["runner"].distance, 0.0001)
    assert_almost_eq(a["steer"].centre_x, b["steer"].centre_x, 0.0001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: RED. Confirm before proceeding.

- [ ] **Step 3: Write the game script**

Create `scripts/game.gd`:

```gdscript
extends Node3D

@onready var units_view: UnitsView = $UnitsView
@onready var corridor_view: CorridorView = $CorridorView
@onready var hud: Label = $HUD/DistanceLabel

var squad: Squad
var steer: SteerInput
var runner: TrackRunner

var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_base := 0.0
var _time := 0.0

func _ready() -> void:
    squad = Squad.new()
    steer = SteerInput.new()
    runner = TrackRunner.new()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
            _drag_base = steer.centre_x
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        var moved := event.position.x - _drag_origin.x
        steer.steer_to_screen_delta(
            Vector2(moved + _drag_base * SteerInput.PIXELS_PER_UNIT, 0))

func _process(delta: float) -> void:
    _time += delta
    runner.tick(delta)
    steer.tick(delta)
    squad.tick(delta, steer.centre_x)

    units_view.render(squad.units, _time)
    corridor_view.render(runner)
    hud.text = "%d m" % int(runner.distance)

func _restart() -> void:
    squad.reset()
    steer.reset()
    runner.reset()
```

Drag is relative to where the current centre already was, so a second drag continues from the squad's position instead of snapping it back to a fresh origin.

- [ ] **Step 4: Build the scene by hand**

Create `scenes/game.tscn` as text. Node tree:

```
Game            (Node3D)              → scripts/game.gd
├── Camera3D                          → position, rotation, fov, keep_aspect
│                                       ALL FROM docs/camera-derivation.md
├── DirectionalLight3D                → rotation (-50, -30, 0)
├── CorridorView   (Node3D)           → scripts/views/corridor_view.gd
├── UnitsView      (MultiMeshInstance3D) → scripts/views/units_view.gd
└── HUD            (CanvasLayer)
    └── DistanceLabel (Label)         → anchored top-left, 16px margin
```

Restore in `project.godot`:

```ini
run/main_scene="res://scenes/game.tscn"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: full suite PASS. Report the count and the runtime.

- [ ] **Step 6: Confirm the game runs**

Run: `godot --headless --quit-after 900`
Expected: starts, runs, exits 0, no script errors, no missing-scene error. Report the output verbatim.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: wire steering and scroll into a playable corridor"
```

- [ ] **Step 8: Hand to Aslam — do not attempt this yourself**

This step is not automatable and must not be faked. Aslam runs `godot` and answers:

- Does steering feel responsive, or laggy and disconnected?
- Does the crowd feel like a crowd, or like a rigid block sliding around?
- Is the scroll speed right? Too slow to be exciting, too fast to react?
- Can you see far enough ahead to plan a move?
- Does the corridor feel too wide, too narrow, about right?

If steering feels bad, tune `SteerInput.SMOOTHING`, `SteerInput.PIXELS_PER_UNIT` and `Squad.SLOT_LERP` before building anything on top. Everything later compounds on this feel, and no gate design rescues a crowd that is unpleasant to move.

## Self-review notes

**Spec coverage.** This plan covers step 1 of the spec's build order (steering and scroll) plus step 2 (the camera), which is included because step 1's own success criterion — does steering feel good — cannot be evaluated without seeing the corridor. Guns, enemies, gates and hazards are steps 4 through 6 and deliberately absent.

**Deliberate deviations from the spec, recorded here:**

1. `RunState` is not adapted in this plan. It currently carries a wave counter, and there is no fail state yet for it to record. `TrackRunner.distance` covers the HUD's needs. It returns when enemies do.
2. `Projectiles`, `Weapon`, `WaveDirector` and `ProjectileView` are left untouched and unused on `main`. They are correct and tested; they get adapted when guns and enemies arrive. Deleting or rewriting them now would be churn.

**Known gap.** The spec targets 60fps at full unit caps on a mid-range phone, and nothing here measures it. That is the next step's job, and it comes before gates — this plan delivers a build worth measuring.
