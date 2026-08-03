# Onrush Phase 2 — Guns and Enemies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add weapon tiers, a second (enemy) crowd, and both projectile pools to the phase 1 corridor, so the game is a horde shooter rather than an empty scrolling steering demo. Delivers something a human can play and judge whether the shooting feels good — the second half of the question phase 1's steering answered the first half of.

**Architecture:** Extends phase 1's units without touching their tested behaviour where avoidable. `Weapon` becomes a stateless-except-accumulator tier lookup; a new `Volley` static-function class turns a shot count into per-unit fanned projectiles, used identically for both sides; a new `TrackGenerator` replaces `WaveDirector` with corridor-shaped enemy spawning; `Units.tick` gains one backward-compatible parameter so enemies can compose scroll speed and their own closing speed fresh every frame, per the spec's explicit requirement that the two stay separate numbers.

**Tech Stack:** Godot 4.7.1 Standard, GDScript, GUT 9.6.1. No new dependencies.

Source spec: `docs/specs/2026-08-02-onrush-design.md` (`## Gates` for weapon tiers, `## Threats` for enemy motion and contact, `## Architecture` for unit shapes)

**No gates, no hazards in this plan.** Those are build-order steps 5 and 6. Weapon tiers exist and are steppable (`step_tier`... actually not even that — see Task 1) but nothing in this phase changes a tier once a run starts; that lever arrives with gates.

## Global Constraints

- **Logic is 2D.** `Vector2(x, y)`, `x` lateral, `y` forward. Views map to `Vector3(x, 0, y)`. No rule unit may reference a 3D type.
- **Rule units extend `RefCounted`, never `Node`.**
- **No Godot physics anywhere.** No `Area3D`, `RigidBody3D`, `CharacterBody3D`. Collision stays arithmetic over flat arrays.
- **`Projectiles.resolve_hits` stays a naive nested loop.** The spec explicitly defers the broadphase to a profiling phase; this plan's Task 8 is that profiling phase, and if it finds a real problem, the fix is scoped there, not smuggled in early.
- **Firepower scales with squad size.** Every live unit on a side fires each trigger pulse — this is what makes "more units" and "better weapon" a real trade-off rather than two ways of saying the same thing.
- **Weapon holds no tier of its own.** Tier is a plain `int` living on `Squad` (`weapon_tier`) for the player's side, and a fixed constant for enemies. `Weapon.tick`/`Weapon.damage_at`/etc. take `tier` as a parameter, mirroring how `Squad.tick(delta, centre_x)` takes its centre from `SteerInput` rather than owning it.
- **Scroll speed and closing speed are composed fresh every frame, never baked into a stored velocity.** This is why `Units.tick` gains a parameter instead of enemies getting scroll baked in at spawn.
- **`Units.remove_beyond` is reused for enemy contact, not duplicated.** It already does exactly "count and remove everything past a `y` threshold" — enemy contact with the squad is a second, unrelated use of that same generic method.
- **A test a broken implementation would pass is not a test.** For each test, name the wrong implementation it rules out. For load-bearing logic, break the implementation deliberately, confirm the test fails, restore, and verify against a committed baseline — this has caught something in every task of every phase so far.

---

### Task 1: Weapon — tier tables

**Files:**
- Modify: `scripts/weapon.gd`
- Modify: `test/test_weapon.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Weapon.TIER_COUNT: int` = 5
  - `Weapon.TIER_FIRE_INTERVAL: PackedFloat32Array` — public, read directly by index (no getter; only `tick()` and tests need it, both index it by `tier` directly, matching the plain-const style `Corridor`'s constants already use)
  - `Weapon.damage_at(tier: int) -> float` (static)
  - `Weapon.projectiles_per_shot_at(tier: int) -> int` (static)
  - `Weapon.spread_degrees_at(tier: int) -> float` (static)
  - `Weapon.new() -> Weapon`
  - `weapon.projectile_speed: float` = 35.0
  - `weapon.tick(delta: float, tier: int) -> int`
  - `weapon.reset() -> void`

This is a breaking signature change (`tick` gains a required `tier` parameter; `fire_interval` and `damage` stop being mutable instance fields). Every existing test in `test/test_weapon.gd` needs updating — this is expected, not a sign something is wrong.

- [ ] **Step 1: Write the failing tests**

Replace `test/test_weapon.gd` in full:

```gdscript
extends GutTest

var weapon: Weapon

func before_each():
    weapon = Weapon.new()

func test_tier_count_matches_the_tables():
    assert_eq(Weapon.TIER_COUNT, 5)

func test_tier_tables_are_monotonically_increasing_in_damage():
    # Not a strict requirement of the design, but a sanity check on the
    # placeholder numbers below: a "higher tier" that hits softer than a
    # lower one would be a data-entry bug, not a balance choice.
    var previous := 0.0
    for tier in Weapon.TIER_COUNT:
        var damage := Weapon.damage_at(tier)
        assert_gt(damage, previous, "tier %d must hit harder than tier %d" % [tier, tier - 1])
        previous = damage

func test_no_shots_before_the_interval_elapses():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 0)

func test_one_shot_per_interval():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0], 0), 1)

func test_a_long_frame_fires_the_whole_backlog():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 3.0, 0), 3,
        "a stutter must not silently swallow shots")

func test_remainder_carries_into_the_next_frame():
    weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.75, 0)
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 1,
        "0.75 + 0.5 = 1.25 intervals, so exactly one shot")

func test_rate_is_frame_independent():
    var coarse := Weapon.new()
    var fine := Weapon.new()
    var coarse_shots := 0
    var fine_shots := 0
    for i in 60:
        coarse_shots += coarse.tick(1.0 / 60.0, 0)
    for i in 240:
        fine_shots += fine.tick(1.0 / 240.0, 0)
    assert_eq(coarse_shots, fine_shots,
        "one second of fire must be the same at any frame rate")

func test_higher_tier_fires_faster():
    # Tier 4's interval must be strictly shorter than tier 0's, and the
    # accumulator must actually use the tier passed to THIS call, not one
    # baked in earlier -- ticking the same weapon at different tiers on
    # consecutive calls must change its rate immediately.
    assert_lt(Weapon.TIER_FIRE_INTERVAL[4], Weapon.TIER_FIRE_INTERVAL[0])
    var w := Weapon.new()
    var one_second_tier0 := 0
    var one_second_tier4 := 0
    for i in 60:
        one_second_tier0 += w.tick(1.0 / 60.0, 0)
    w.reset()
    for i in 60:
        one_second_tier4 += w.tick(1.0 / 60.0, 4)
    assert_gt(one_second_tier4, one_second_tier0,
        "a higher tier must fire more often per second, not just hit harder")

func test_reset_clears_the_accumulator():
    weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.9, 0)
    weapon.reset()
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 0)

func test_projectiles_per_shot_and_spread_scale_with_tier():
    # Not every tier needs spread (a single tight shot is a valid tier), but
    # the top tier must fire more projectiles than the bottom one, or the
    # tier table has no reason to exist.
    assert_gt(Weapon.projectiles_per_shot_at(4), Weapon.projectiles_per_shot_at(0))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `TIER_COUNT`, `TIER_FIRE_INTERVAL`, `damage_at` etc. are not known.

- [ ] **Step 3: Write the implementation**

Replace `scripts/weapon.gd` in full:

```gdscript
class_name Weapon extends RefCounted

const TIER_COUNT := 5

# Placeholder first-pass numbers. Expect to retune these after playing, the
# same way SteerInput.SMOOTHING and PIXELS_PER_UNIT were tuned post-playtest
# in phase 1 -- these are the values that make the wiring provably correct,
# not a claim about final balance.
const TIER_FIRE_INTERVAL := PackedFloat32Array([0.5, 0.42, 0.35, 0.3, 0.25])
const TIER_DAMAGE := PackedFloat32Array([4.0, 5.0, 6.0, 7.0, 9.0])
const TIER_PROJECTILES_PER_SHOT := PackedInt32Array([1, 1, 2, 3, 4])
const TIER_SPREAD_DEGREES := PackedFloat32Array([0.0, 0.0, 8.0, 14.0, 20.0])

var projectile_speed := 35.0

var _accumulator := 0.0

static func damage_at(tier: int) -> float:
    return TIER_DAMAGE[tier]

static func projectiles_per_shot_at(tier: int) -> int:
    return TIER_PROJECTILES_PER_SHOT[tier]

static func spread_degrees_at(tier: int) -> float:
    return TIER_SPREAD_DEGREES[tier]

func tick(delta: float, tier: int) -> int:
    _accumulator += delta
    var interval := TIER_FIRE_INTERVAL[tier]
    var shots := int(_accumulator / interval)
    _accumulator -= float(shots) * interval
    return shots

func reset() -> void:
    _accumulator = 0.0
```

`tier` is read fresh from the table on every `tick()` call rather than cached, which is what makes `test_higher_tier_fires_faster` meaningful: an implementation that captured `tier` once (e.g. in a constructor) would still pass every other test here but fail that one.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Weapon tests PASS.

- [ ] **Step 5: Verify the frame-independence and tier-switch properties bite**

Commit first. Then temporarily hardcode `tick`'s `interval` to always use `TIER_FIRE_INTERVAL[0]` regardless of the `tier` argument; confirm `test_higher_tier_fires_faster` fails. Restore, confirm `git diff scripts/weapon.gd` is empty.

- [ ] **Step 6: Commit**

```bash
git add scripts/weapon.gd scripts/weapon.gd.uid test/test_weapon.gd
git commit -m "feat: redesign Weapon around a 5-tier stat table"
```

---

### Task 2: Volley — per-unit multi-fire with spread

The core new combat logic. Fires a shot event from every live unit in a `Units` container, fanning multiple projectiles across an angular spread when the tier calls for it. Used identically for the squad (firing at enemies) and enemy crowds (firing at the squad) — only the `Units`/`Projectiles` pair and the `forward` direction differ between the two calls.

**Files:**
- Create: `scripts/volley.gd`, `test/test_volley.gd`

**Interfaces:**
- Consumes: `Units` (positions, count), `Projectiles` (fire).
- Produces:
  - `Volley.fire(units: Units, projectiles: Projectiles, shots: int, projectiles_per_shot: int, spread_degrees: float, forward: Vector2, speed: float) -> void` (static)

Deliberately knows nothing about weapon tiers — the caller resolves `Weapon.projectiles_per_shot_at(tier)` etc. into plain numbers first. This keeps `Volley` testable with hand-picked numbers instead of needing a `Weapon` instance, and keeps the tier concept in exactly one place.

- [ ] **Step 1: Write the failing tests**

Create `test/test_volley.gd`:

```gdscript
extends GutTest

var units: Units
var projectiles: Projectiles

func before_each():
    units = Units.new()
    projectiles = Projectiles.new()

func test_zero_shots_fires_nothing():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 0, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 0)

func test_one_shot_one_unit_one_projectile_per_shot():
    units.spawn(Vector2(3, 4), Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 1)
    assert_eq(projectiles.positions[0], Vector2(3, 4),
        "the projectile must originate at the firing unit's own position")

func test_firepower_scales_with_unit_count():
    # This is the property the whole class exists for: N units at the same
    # tier must fire N times the projectiles of one unit, not a fixed
    # number from an abstract origin. An implementation that fires once
    # regardless of unit count would pass test_one_shot_one_unit... above
    # but fail this.
    for i in 5:
        units.spawn(Vector2(float(i), 0), Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 5)

func test_multiple_shots_multiply_the_count():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 3, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 3,
        "a long frame firing 3 trigger pulses must not silently collapse to 1")

func test_projectiles_per_shot_multiplies_the_count_too():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 4, 20.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 4)

func test_no_spread_fires_straight_along_forward():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_almost_eq(projectiles.positions[0].x, 0.0, 0.0001)

func test_spread_fans_symmetrically_around_forward():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 2, 20.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 2)
    # Two projectiles at +-10 degrees off straight-ahead must have equal and
    # opposite lateral displacement after moving the same distance forward.
    var a := projectiles.positions[0]
    var b := projectiles.positions[1]
    assert_almost_eq(a.x, -b.x, 0.0001,
        "an even projectile count must fan symmetrically, not lean to one side")
    assert_gt(abs(a.x), 0.001, "some spread must actually be applied")

func test_direction_reverses_for_the_opposite_side():
    # Proves the same call works unmodified for enemies firing the other
    # way -- the only difference from the squad's own call is this vector.
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, -1), 10.0)
    for i in 60:
        projectiles.tick(1.0 / 60.0, 1000.0)
    assert_lt(projectiles.positions[0].y, 0.0,
        "firing with forward=(0,-1) must send the projectile toward negative y")

func test_speed_is_honoured():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    projectiles.tick(1.0, 1000.0)
    assert_almost_eq(projectiles.positions[0].y, 10.0, 0.01)

func test_stops_firing_once_the_projectile_pool_is_full():
    for i in 3:
        units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    # Fill the pool to exactly one slot short of capacity, then fire from
    # 3 units -- only one of the three can possibly land.
    for i in Projectiles.MAX_PROJECTILES - 1:
        projectiles.fire(Vector2.ZERO, Vector2(0, 1), 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, Projectiles.MAX_PROJECTILES,
        "must cap at the pool size rather than overflow or crash")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Volley` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `scripts/volley.gd`:

```gdscript
class_name Volley extends RefCounted

# Fires `shots` trigger pulses from every live unit in `units`, each pulse
# fanning `projectiles_per_shot` projectiles evenly across `spread_degrees`
# around `forward`, into `projectiles`. Pure spawn geometry -- knows nothing
# about weapon tiers; the caller resolves those into plain numbers first.
# Used for both the squad (forward toward the enemies) and enemy crowds
# (forward toward the squad); the only difference between the two calls is
# which Units/Projectiles pair and which direction is passed in.
static func fire(units: Units, projectiles: Projectiles, shots: int,
        projectiles_per_shot: int, spread_degrees: float, forward: Vector2, speed: float) -> void:
    if shots <= 0 or projectiles_per_shot <= 0:
        return
    var spread := deg_to_rad(spread_degrees)
    for _shot in shots:
        for i in units.count:
            var origin := units.positions[i]
            if projectiles_per_shot == 1:
                projectiles.fire(origin, forward, speed)
            else:
                for p in projectiles_per_shot:
                    var t: float = float(p) / float(projectiles_per_shot - 1) - 0.5
                    projectiles.fire(origin, forward.rotated(t * spread), speed)
```

`Vector2.rotated(angle)` is a Godot built-in (counter-clockwise, radians) — do not hand-roll the rotation matrix.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Volley tests PASS.

- [ ] **Step 5: Verify firepower-scales-with-count bites**

Commit first. Then temporarily change the outer loop to fire once regardless of `units.count` (e.g. hardcode a single iteration). Confirm `test_firepower_scales_with_unit_count` fails. Restore, confirm `git diff scripts/volley.gd` is empty.

- [ ] **Step 6: Commit**

```bash
git add scripts/volley.gd scripts/volley.gd.uid test/test_volley.gd test/test_volley.gd.uid
git commit -m "feat: add Volley for per-unit multi-fire with angular spread"
```

---

### Task 3: Units.tick — optional extra_velocity

A small, backward-compatible extension. Lets a caller apply one uniform additional velocity (e.g. the corridor's current scroll speed) on top of each unit's own individually-stored velocity, composed fresh every call rather than baked in at spawn time. Existing callers that never pass the new argument are completely unaffected.

**Files:**
- Modify: `scripts/units.gd`
- Modify: `test/test_units.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Units.tick(delta: float, extra_velocity: Vector2 = Vector2.ZERO) -> void`

**Do not change any other method on `Units`.** The 15 existing tests must all still pass — this task adds one optional parameter with a default that reproduces the old behaviour exactly.

- [ ] **Step 1: Write the failing test**

Add to `test/test_units.gd` (do not remove or alter any existing test):

```gdscript
func test_tick_without_extra_velocity_is_unchanged():
    # Guards the default-argument backward-compatibility this task depends
    # on: every existing caller of tick(delta) must behave identically.
    units.spawn(Vector2(0, 10), Vector2(0, -2), 1.0)
    units.tick(1.0)
    assert_almost_eq(units.positions[0].y, 8.0, 0.001)

func test_extra_velocity_composes_with_each_units_own_velocity():
    units.spawn(Vector2(0, 10), Vector2(0, -2), 1.0)
    units.tick(1.0, Vector2(0, -3))
    assert_almost_eq(units.positions[0].y, 5.0, 0.001,
        "own velocity (-2) and extra_velocity (-3) must both apply, summed")

func test_extra_velocity_applies_uniformly_to_every_unit():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(5, 20), Vector2(0, -1), 1.0)
    units.tick(1.0, Vector2(0, -4))
    assert_almost_eq(units.positions[0].y, 6.0, 0.001)
    assert_almost_eq(units.positions[1].y, 15.0, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `tick` does not accept a second argument.

- [ ] **Step 3: Write the implementation**

In `scripts/units.gd`, replace:

```gdscript
func tick(delta: float) -> void:
    for i in count:
        positions[i] += velocities[i] * delta
```

with:

```gdscript
func tick(delta: float, extra_velocity: Vector2 = Vector2.ZERO) -> void:
    for i in count:
        positions[i] += (velocities[i] + extra_velocity) * delta
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Units tests PASS, including every pre-existing one — report the exact count (should be 15 pre-existing + 3 new = 18) to confirm nothing regressed.

- [ ] **Step 5: Verify composition genuinely happens**

Commit first. Then temporarily change `tick` to ignore `extra_velocity` (revert to the one-argument body above). Confirm `test_extra_velocity_composes_with_each_units_own_velocity` and `test_extra_velocity_applies_uniformly_to_every_unit` both fail, and every pre-existing test still passes (proving the default-argument path alone is not what broke). Restore, confirm `git diff scripts/units.gd` is empty.

- [ ] **Step 6: Commit**

```bash
git add scripts/units.gd test/test_units.gd
git commit -m "feat: let Units.tick compose an optional uniform extra velocity"
```

---

### Task 4: TrackGenerator — replaces WaveDirector

Seeded, deterministic enemy-group spawner shaped for the corridor (a lateral strip, not an arc) rather than the old fixed-position design's circular arena. `WaveDirector`'s escalation ideas (seeded RNG, headroom-aware, an asymptotic difficulty curve) carry over in spirit; its arc-based spawn geometry and wave-counter escalation do not, so this is a fresh build behind a new name, not a migration.

**Files:**
- Create: `scripts/track_generator.gd`, `test/test_track_generator.gd`
- Delete: `scripts/wave_director.gd` (+ `.uid`), `test/test_wave_director.gd` (+ `.uid`)

**Interfaces:**
- Consumes: `Corridor.HALF_WIDTH`, `Corridor.SPAWN_DISTANCE`, `Units.MAX_UNITS`.
- Produces:
  - `TrackGenerator.GROUP_SPREAD: float` = 2.0
  - `TrackGenerator.new(rng_seed: int) -> TrackGenerator`
  - `generator.tick(delta: float, live_count: int) -> PackedVector2Array` — spawn positions this tick
  - `generator.enemy_health() -> float`
  - `generator.enemy_speed() -> float`
  - `generator.reset() -> void`

`enemy_speed()` returns the enemy's OWN closing speed only — it does not include the corridor's scroll speed. The caller (Task 6) composes both via `Units.tick`'s `extra_velocity` from Task 3.

- [ ] **Step 1: Confirm nothing outside WaveDirector's own files depends on it**

Run: `grep -rn "WaveDirector\|SPAWN_RADIUS\|zombie_health\|zombie_speed" scripts/ test/`
Expected: hits only in `scripts/wave_director.gd` and `test/test_wave_director.gd`. If anything else references it, stop and report rather than deleting.

- [ ] **Step 2: Write the failing tests**

Create `test/test_track_generator.gd`:

```gdscript
extends GutTest

func test_health_and_speed_start_at_their_base_values():
    var g := TrackGenerator.new(42)
    var early_health := g.enemy_health()
    var early_speed := g.enemy_speed()
    for i in 10:
        g.tick(1.0 / 60.0, 0)
    assert_almost_eq(g.enemy_health(), early_health, 0.5)
    assert_almost_eq(g.enemy_speed(), early_speed, 0.5)

func test_health_and_speed_escalate_and_plateau():
    var g := TrackGenerator.new(42)
    var early_health := g.enemy_health()
    var early_speed := g.enemy_speed()
    for i in 36000:  # 600s at 1/60
        g.tick(1.0 / 60.0, 0)
    assert_gt(g.enemy_health(), early_health)
    assert_gt(g.enemy_speed(), early_speed)
    var plateaued_health := g.enemy_health()
    var plateaued_speed := g.enemy_speed()
    for i in 6000:  # another 100s
        g.tick(1.0 / 60.0, 0)
    assert_almost_eq(g.enemy_health(), plateaued_health, 0.5,
        "difficulty must plateau, or an endless game becomes a countdown")
    assert_almost_eq(g.enemy_speed(), plateaued_speed, 0.5)

func test_spawns_land_at_the_spawn_distance():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(10.0, 0)
    assert_gt(spawns.size(), 0, "ten seconds must produce at least one spawn")
    for p in spawns:
        assert_almost_eq(p.y, Corridor.SPAWN_DISTANCE, 0.001)

func test_spawns_stay_inside_the_corridor():
    var g := TrackGenerator.new(42)
    for i in 600:
        var spawns := g.tick(1.0, 0)
        for p in spawns:
            assert_between(p.x, -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001)

func test_group_size_escalates_so_later_spawns_have_more_enemies_per_group():
    # A group is however many spawns land at the same tick call. Measures
    # the largest single-tick burst in a short window near the start (well
    # inside GROUP_SIZE_RAMP_SECONDS=90, so size must still be small)
    # against a window well past it (near GROUP_SIZE_MAX). Two windows of
    # the SAME long duration back-to-back would both already sit at the
    # plateau and make this assertion trivially true regardless of whether
    # escalation happens at all -- the windows must straddle the ramp, not
    # just be "early" and "late" in name.
    var g := TrackGenerator.new(42)
    var early_max := 0
    for i in 10:
        early_max = max(early_max, g.tick(1.0, 0).size())
    for i in 300:
        g.tick(1.0, 0)
    var late_max := 0
    for i in 10:
        late_max = max(late_max, g.tick(1.0, 0).size())
    assert_gt(late_max, early_max,
        "group size must genuinely grow, not start at its plateau value")

func test_is_deterministic_for_a_given_seed():
    var a := TrackGenerator.new(7)
    var b := TrackGenerator.new(7)
    for i in 200:
        assert_eq(a.tick(1.0, 0), b.tick(1.0, 0),
            "same seed must produce an identical run")

func test_different_seeds_diverge():
    var a := TrackGenerator.new(1)
    var b := TrackGenerator.new(2)
    var same := true
    for i in 200:
        if a.tick(1.0, 0) != b.tick(1.0, 0):
            same = false
    assert_false(same, "different seeds must produce different runs")

func test_respects_the_concurrency_cap():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(60.0, Units.MAX_UNITS)
    assert_eq(spawns.size(), 0, "must not spawn past the cap")

func test_spawns_only_up_to_remaining_headroom():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(60.0, Units.MAX_UNITS - 3)
    assert_eq(spawns.size(), 3,
        "must fill the available headroom exactly, not merely stay under it")

func test_reset_replays_the_same_spawn_sequence():
    var g := TrackGenerator.new(42)
    var first := []
    for i in 50:
        first.append(g.tick(1.0, 0))
    g.reset()
    var second := []
    for i in 50:
        second.append(g.tick(1.0, 0))
    for i in 50:
        assert_eq(first[i], second[i])

func test_reset_restores_base_difficulty():
    var g := TrackGenerator.new(42)
    for i in 36000:
        g.tick(1.0 / 60.0, 0)
    var escalated_health := g.enemy_health()
    g.reset()
    assert_lt(g.enemy_health(), escalated_health)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `TrackGenerator` is not a known class.

- [ ] **Step 4: Write the implementation**

Create `scripts/track_generator.gd`:

```gdscript
class_name TrackGenerator extends RefCounted

const GROUP_INTERVAL_BASE := 2.5
const GROUP_INTERVAL_MIN := 0.6
const GROUP_INTERVAL_DECAY := 0.02

const GROUP_SIZE_BASE := 1
const GROUP_SIZE_MAX := 5
const GROUP_SIZE_RAMP_SECONDS := 90.0

const ENEMY_BASE_HEALTH := 8.0
const ENEMY_MAX_HEALTH := 24.0
const ENEMY_HEALTH_RAMP_SECONDS := 120.0

const ENEMY_BASE_SPEED := 2.5
const ENEMY_MAX_SPEED := 5.0
const ENEMY_SPEED_RAMP_SECONDS := 120.0

const GROUP_SPREAD := 2.0

var _rng := RandomNumberGenerator.new()
var _seed: int
var _elapsed := 0.0
var _spawn_clock := 0.0

func _init(rng_seed: int) -> void:
    _seed = rng_seed
    _rng.seed = rng_seed

func tick(delta: float, live_count: int) -> PackedVector2Array:
    _elapsed += delta
    var spawns := PackedVector2Array()
    var interval := _group_interval()
    var headroom := Units.MAX_UNITS - live_count

    _spawn_clock += delta
    while _spawn_clock >= interval:
        _spawn_clock -= interval
        var size := _group_size()
        var margin: float = min(GROUP_SPREAD, Corridor.HALF_WIDTH)
        var centre_x := _rng.randf_range(-Corridor.HALF_WIDTH + margin, Corridor.HALF_WIDTH - margin)
        for i in size:
            if spawns.size() >= headroom:
                continue
            var x: float = clamp(centre_x + _rng.randf_range(-GROUP_SPREAD, GROUP_SPREAD),
                -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)
            spawns.append(Vector2(x, Corridor.SPAWN_DISTANCE))
    return spawns

func enemy_health() -> float:
    var t := 1.0 - exp(-_elapsed / ENEMY_HEALTH_RAMP_SECONDS)
    return ENEMY_BASE_HEALTH + (ENEMY_MAX_HEALTH - ENEMY_BASE_HEALTH) * t

func enemy_speed() -> float:
    var t := 1.0 - exp(-_elapsed / ENEMY_SPEED_RAMP_SECONDS)
    return ENEMY_BASE_SPEED + (ENEMY_MAX_SPEED - ENEMY_BASE_SPEED) * t

func reset() -> void:
    _elapsed = 0.0
    _spawn_clock = 0.0
    _rng.seed = _seed

func _group_interval() -> float:
    var scaled := GROUP_INTERVAL_BASE * exp(-GROUP_INTERVAL_DECAY * _elapsed)
    return max(scaled, GROUP_INTERVAL_MIN)

func _group_size() -> int:
    var t := 1.0 - exp(-_elapsed / GROUP_SIZE_RAMP_SECONDS)
    return int(round(float(GROUP_SIZE_BASE) + float(GROUP_SIZE_MAX - GROUP_SIZE_BASE) * t))
```

The `continue` inside the spawn loop (not `break`) when headroom is exhausted mirrors `WaveDirector`'s own proven pattern: the spawn clock keeps draining at the full rate even when nothing can spawn, so a run sitting at the cap doesn't bank credit and dump a burst the instant space frees up.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all TrackGenerator tests PASS.

- [ ] **Step 6: Verify the replay and headroom properties bite**

Commit first. Then temporarily remove `_rng.seed = _seed` from `reset()`; confirm `test_reset_replays_the_same_spawn_sequence` fails while unrelated tests stay green. Restore. Then temporarily change the headroom check from `spawns.size() >= headroom` to `false` (never gate); confirm `test_respects_the_concurrency_cap` and `test_spawns_only_up_to_remaining_headroom` both fail. Restore, confirm `git diff scripts/track_generator.gd` is empty.

- [ ] **Step 7: Delete WaveDirector**

```bash
git rm scripts/wave_director.gd scripts/wave_director.gd.uid
git rm test/test_wave_director.gd test/test_wave_director.gd.uid
```

- [ ] **Step 8: Run the full suite and commit**

```bash
git add scripts/track_generator.gd scripts/track_generator.gd.uid test/test_track_generator.gd test/test_track_generator.gd.uid
git commit -m "feat: replace WaveDirector with corridor-shaped TrackGenerator"
```

---

### Task 5: Squad.weapon_tier

A one-field addition. Squad owns the data (matching how it already owns `formation`); the actual firing logic lives elsewhere and reads this field.

**Files:**
- Modify: `scripts/squad.gd`
- Modify: `test/test_squad.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `squad.weapon_tier: int` — starts at `0`, restored to `0` by `reset()`.

**Do not add any method that fires a weapon.** That is Task 7's job in `game.gd`; `Squad` stays a pure data-and-position unit.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_squad.gd`:

```gdscript
func test_starts_at_weapon_tier_zero():
    assert_eq(squad.weapon_tier, 0)

func test_reset_restores_weapon_tier_zero():
    squad.weapon_tier = 3
    squad.reset()
    assert_eq(squad.weapon_tier, 0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `weapon_tier` does not exist on `Squad`.

- [ ] **Step 3: Write the implementation**

In `scripts/squad.gd`, add the field next to `formation`:

```gdscript
var weapon_tier := 0
```

In `reset()`, add `weapon_tier = 0` alongside the existing `formation = Formation.Kind.WIDE` and `centre_x = 0.0` resets.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Squad tests PASS, including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add scripts/squad.gd test/test_squad.gd
git commit -m "feat: add Squad.weapon_tier"
```

---

### Task 6: RunState — distance instead of wave

`RunState` currently tracks a `wave` counter inherited from the old fixed-position design. Onrush measures progress by distance (`TrackRunner.distance`), so this is a rename with a type change (`int` wave → `float` distance), not a rewrite — every other piece of `RunState`'s behaviour (kills, best-value promotion without demotion, save/load, reset) carries over unchanged.

**Files:**
- Modify: `scripts/run_state.gd`
- Modify: `test/test_run_state.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `RunState.SAVE_PATH` — unchanged.
  - `run_state.distance: float` (was `wave: int`)
  - `run_state.kills: int`, `run_state.elapsed: float`, `run_state.is_over: bool` — unchanged.
  - `run_state.best_distance: float` (was `best_wave: int`)
  - `run_state.tick(delta: float, current_distance: float) -> void` (was `tick(delta, current_wave: int)`)
  - `record_kills(n)`, `end_run()`, `reset()`, `save_best()`, `load_best()` — unchanged behaviour, renamed fields inside.

- [ ] **Step 1: Write the failing tests**

Replace `test/test_run_state.gd` in full (identical structure to the existing file, `wave`→`distance`, `best_wave`→`best_distance`, integer literals changed to floats where they represent distance):

```gdscript
extends GutTest

var run_state: RunState

func before_all():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func before_each():
    run_state = RunState.new()

func after_all():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func test_starts_empty_and_live():
    assert_eq(run_state.kills, 0)
    assert_almost_eq(run_state.distance, 0.0, 0.001)
    assert_almost_eq(run_state.elapsed, 0.0, 0.001)
    assert_almost_eq(run_state.best_distance, 0.0, 0.001)
    assert_false(run_state.is_over)

func test_tick_accumulates_elapsed_time():
    run_state.tick(0.5, 1.0)
    run_state.tick(0.25, 1.0)
    assert_almost_eq(run_state.elapsed, 0.75, 0.001)

func test_tick_mirrors_the_runners_distance():
    run_state.tick(0.1, 42.5)
    assert_almost_eq(run_state.distance, 42.5, 0.001)

func test_kills_accumulate():
    run_state.record_kills(3)
    run_state.record_kills(2)
    assert_eq(run_state.kills, 5)

func test_end_run_marks_it_over():
    run_state.end_run()
    assert_true(run_state.is_over)

func test_end_run_promotes_a_new_best():
    run_state.tick(0.1, 90.0)
    run_state.end_run()
    assert_almost_eq(run_state.best_distance, 90.0, 0.001)

func test_end_run_does_not_demote_an_existing_best():
    run_state.best_distance = 200.0
    run_state.tick(0.1, 30.0)
    run_state.end_run()
    assert_almost_eq(run_state.best_distance, 200.0, 0.001,
        "a bad run must never erase a good one")

func test_reset_clears_the_run_but_keeps_the_best():
    run_state.tick(0.1, 90.0)
    run_state.record_kills(5)
    run_state.end_run()
    run_state.reset()
    assert_eq(run_state.kills, 0)
    assert_almost_eq(run_state.distance, 0.0, 0.001)
    assert_almost_eq(run_state.elapsed, 0.0, 0.001)
    assert_false(run_state.is_over)
    assert_almost_eq(run_state.best_distance, 90.0, 0.001)

func test_best_distance_survives_a_save_and_load():
    run_state.tick(0.1, 120.0)
    run_state.end_run()
    run_state.save_best()

    var reloaded := RunState.new()
    reloaded.load_best()
    assert_almost_eq(reloaded.best_distance, 120.0, 0.001)
    assert_almost_eq(reloaded.distance, 0.0, 0.001,
        "load_best must not touch the run's other fields")

func test_load_without_a_save_file_is_harmless():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
    var fresh := RunState.new()
    fresh.best_distance = 99.0
    fresh.load_best()
    assert_almost_eq(fresh.best_distance, 0.0, 0.001,
        "a first launch must not crash or corrupt")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `distance`/`best_distance` do not exist on `RunState`.

- [ ] **Step 3: Write the implementation**

Replace `scripts/run_state.gd` in full:

```gdscript
class_name RunState extends RefCounted

const SAVE_PATH := "user://holdout.cfg"

var distance := 0.0
var kills := 0
var elapsed := 0.0
var best_distance := 0.0
var is_over := false

func tick(delta: float, current_distance: float) -> void:
    elapsed += delta
    distance = current_distance

func record_kills(n: int) -> void:
    kills += n

func end_run() -> void:
    is_over = true
    if distance > best_distance:
        best_distance = distance

func reset() -> void:
    distance = 0.0
    kills = 0
    elapsed = 0.0
    is_over = false

func save_best() -> void:
    var config := ConfigFile.new()
    config.set_value("progress", "best_distance", best_distance)
    config.save(SAVE_PATH)

func load_best() -> void:
    var config := ConfigFile.new()
    if config.load(SAVE_PATH) != OK:
        best_distance = 0.0
        return
    best_distance = config.get_value("progress", "best_distance", 0.0)
```

**Note the save key changed** (`best_wave` → `best_distance`). Any save file from a prior playtest build becomes unreadable by `get_value`'s default fallback (harmless — it just returns `0.0`, same as a first launch), not a crash. Worth knowing if a "my best score reset" question ever comes up.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all RunState tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_state.gd test/test_run_state.gd
git commit -m "feat: rename RunState's wave counter to distance"
```

---

### Task 7: Wire it into a playable build

Everything from Tasks 1–6 assembled: a second `Units` crowd for enemies, two `Projectiles` pools, enemy spawning, both sides firing via `Volley`, hit resolution both ways, contact damage when an enemy reaches the squad, and `RunState` finally driven by a real fail condition.

**Files:**
- Modify: `scripts/game.gd`, `scenes/game.tscn`, `test/test_game_integration.gd`

**Interfaces:**
- Consumes: every unit above, plus phase 1's `Squad`, `SteerInput`, `TrackRunner`, `Corridor`, `Formation`, `UnitsView`, `CorridorView`, `ProjectileView`.
- Produces: a running game with combat.

**Do not touch `scripts/corridor.gd`, `scripts/formation.gd`, `scripts/steer_input.gd`, `scripts/track_runner.gd`, or their views.** Nothing about steering or scrolling changes in this phase.

- [ ] **Step 1: Write the failing integration tests**

`test/test_game_integration.gd` currently has two sections: a mirrored-simulation section (a `_simulate()` helper plus six tests, all pure logic with no scene) and a real-scene section below it (`_make_game`/`_press`/`_drag_to` helpers plus three tests that load the actual `game.tscn`).

**Replace only the mirrored-simulation section** — from the file's `extends GutTest` line down to (and including) the old `test_the_simulation_is_reproducible` — with the block below. **Leave the real-scene section below it completely untouched for now**; Step 1b afterward makes the one necessary change to it.

```gdscript
extends GutTest

const CONTACT_DEPTH := 0.0
const HIT_RADIUS := 0.5
const ENEMY_WEAPON_TIER := 0
const ENEMY_PROJECTILE_SPEED := 25.0

# step defaults to 1/60 for numerical fidelity on short tests. Longer tests
# pass a coarser step explicitly: resolve_hits is a naive O(units x
# projectiles) loop (deliberately, per spec -- deferred to Task 8's
# profiling), and this simulation's crowds only grow as a run escalates, so
# a 300-second run at 1/60 would be tens of thousands of increasingly
# expensive iterations. Phase 1 hit this exact problem with the same
# collision loop and fixed it the same way.
func _simulate(seconds: float, drag_pixels: float, rng_seed: int, step: float = 1.0 / 60.0) -> Dictionary:
    var squad := Squad.new()
    var steer := SteerInput.new()
    var runner := TrackRunner.new()
    var generator := TrackGenerator.new(rng_seed)
    var enemies := Units.new()
    var squad_weapon := Weapon.new()
    var enemy_weapon := Weapon.new()
    var squad_projectiles := Projectiles.new()
    var enemy_projectiles := Projectiles.new()
    var run := RunState.new()

    var elapsed := 0.0
    steer.steer_to_screen_delta(Vector2(drag_pixels, 0))
    while elapsed < seconds and not run.is_over:
        for pos in generator.tick(step, enemies.count):
            enemies.spawn(pos, Vector2(0, -generator.enemy_speed()), generator.enemy_health())

        runner.tick(step)
        steer.tick(step)
        squad.tick(step, steer.centre_x)
        enemies.tick(step, Vector2(0, -Corridor.scroll_speed_at(runner.elapsed)))

        var squad_shots := squad_weapon.tick(step, squad.weapon_tier)
        Volley.fire(squad.units, squad_projectiles, squad_shots,
            Weapon.projectiles_per_shot_at(squad.weapon_tier),
            Weapon.spread_degrees_at(squad.weapon_tier),
            Vector2(0, 1), squad_weapon.projectile_speed)

        var enemy_shots := enemy_weapon.tick(step, ENEMY_WEAPON_TIER)
        Volley.fire(enemies, enemy_projectiles, enemy_shots,
            Weapon.projectiles_per_shot_at(ENEMY_WEAPON_TIER),
            Weapon.spread_degrees_at(ENEMY_WEAPON_TIER),
            Vector2(0, -1), ENEMY_PROJECTILE_SPEED)

        squad_projectiles.tick(step, Corridor.SPAWN_DISTANCE + 5.0)
        enemy_projectiles.tick(step, Corridor.SPAWN_DISTANCE + 5.0)

        run.record_kills(squad_projectiles.resolve_hits(enemies, HIT_RADIUS,
            Weapon.damage_at(squad.weapon_tier)))
        enemy_projectiles.resolve_hits(squad.units, HIT_RADIUS,
            Weapon.damage_at(ENEMY_WEAPON_TIER))

        var contacts := enemies.remove_beyond(CONTACT_DEPTH)
        squad.set_count(max(squad.count() - contacts, 0))

        run.tick(step, runner.distance)
        if squad.is_wiped():
            run.end_run()
        elapsed += step

    return {"squad": squad, "enemies": enemies, "run": run, "runner": runner,
        "squad_projectiles": squad_projectiles, "enemy_projectiles": enemy_projectiles}

func test_enemies_actually_spawn_over_a_run():
    var result := _simulate(30.0, 0.0, 1)
    assert_gt(result["enemies"].count + result["run"].kills, 0,
        "either enemies are alive or some were killed -- either way, spawning happened")

func test_squad_fire_kills_enemies():
    # Seed and duration chosen so at least one enemy has time to spawn,
    # close, and be hit before the run ends -- confirmed by re-running
    # this seed's trace during implementation, not guessed.
    var result := _simulate(20.0, 0.0, 1)
    assert_gt(result["run"].kills, 0,
        "the squad's own fire must be capable of killing enemies")

func test_a_run_can_end_from_enemy_pressure():
    # A long enough run against a stationary squad (no steering to dodge,
    # no weapon upgrades yet) must eventually be overrun -- proves contact
    # damage and/or enemy fire actually hurts the squad rather than being
    # wired to nothing. Coarser step (see _simulate's own comment): 300
    # simulated seconds at 1/20 is 6000 iterations against a naive
    # collision loop, not 18000.
    var result := _simulate(300.0, 0.0, 3, 1.0 / 20.0)
    assert_true(result["run"].is_over,
        "an idle squad must eventually lose to escalating enemy pressure")

func test_kills_are_never_negative_and_distance_tracks_the_runner():
    var result := _simulate(15.0, 0.0, 5)
    assert_gte(result["run"].kills, 0)
    assert_almost_eq(result["run"].distance, result["runner"].distance, 0.001)

func test_enemies_never_cross_behind_the_contact_line():
    var result := _simulate(60.0, 0.0, 7)
    for i in result["enemies"].count:
        assert_gte(result["enemies"].positions[i].y, CONTACT_DEPTH - 0.001,
            "an enemy past the contact line should have been removed, not left behind it")

func test_the_simulation_is_reproducible():
    var a := _simulate(20.0, 100.0, 11)
    var b := _simulate(20.0, 100.0, 11)
    assert_almost_eq(a["run"].distance, b["run"].distance, 0.0001)
    assert_eq(a["run"].kills, b["run"].kills)
```

**Note on `test_squad_fire_kills_enemies` and `test_a_run_can_end_from_enemy_pressure`:** these depend on the placeholder balance numbers in `Weapon`/`TrackGenerator` actually producing kills and eventual defeat within the chosen durations. If either fails when first run, that is real information about the balance, not a broken test — investigate whether it's a wiring bug (nothing is actually colliding) or a balance issue (numbers need adjusting), and say which in your report. Do not loosen these tests to pass around a wiring bug.

- [ ] **Step 1b: Extend the restart-identity test for the objects `_restart()` now resets**

`_restart()` (rewritten in Step 3 below) resets six more objects than it did in phase 1: `generator`, `enemies`, `squad_weapon`, `enemy_weapon`, `squad_projectiles`, `enemy_projectiles`. The existing `test_restart_resets_state_without_reallocating_units` (in the real-scene section, untouched so far) only checks `squad`, `squad.units`, `steer`, `runner` — extended here so the identity-preservation guarantee actually covers everything `_restart()` touches, not just the phase 1 subset.

In `test/test_game_integration.gd`'s real-scene section, find `test_restart_resets_state_without_reallocating_units` and add these lines immediately after the existing four `_ref` variable declarations (`squad_ref`, `units_ref`, `steer_ref`, `runner_ref`):

```gdscript
    var generator_ref: TrackGenerator = game.generator
    var enemies_ref: Units = game.enemies
    var squad_weapon_ref: Weapon = game.squad_weapon
    var enemy_weapon_ref: Weapon = game.enemy_weapon
    var squad_projectiles_ref: Projectiles = game.squad_projectiles
    var enemy_projectiles_ref: Projectiles = game.enemy_projectiles
```

And add these assertions immediately after the existing four `assert_same` calls:

```gdscript
    assert_same(game.generator, generator_ref, "restart must reuse the existing TrackGenerator")
    assert_same(game.enemies, enemies_ref, "restart must reuse the existing enemy Units")
    assert_same(game.squad_weapon, squad_weapon_ref, "restart must reuse the existing squad Weapon")
    assert_same(game.enemy_weapon, enemy_weapon_ref, "restart must reuse the existing enemy Weapon")
    assert_same(game.squad_projectiles, squad_projectiles_ref, "restart must reuse the existing squad Projectiles")
    assert_same(game.enemy_projectiles, enemy_projectiles_ref, "restart must reuse the existing enemy Projectiles")
```

Leave every other test in the real-scene section untouched.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: RED. The mirrored-simulation tests fail because `TrackGenerator`/`Volley`/the new `Weapon`/`Units.tick`/`RunState` signatures are exercised together here for the first time. The extended restart test fails because `game.gd` doesn't yet expose `generator`/`enemies`/`squad_weapon`/`enemy_weapon`/`squad_projectiles`/`enemy_projectiles` — Step 3 adds them. If Tasks 1–6 are already committed and green individually, some assertions may partially pass already; that's fine, note it in your report rather than forcing an artificial red.

- [ ] **Step 3: Update `scripts/game.gd`**

Replace in full:

```gdscript
class_name Game extends Node3D

const CONTACT_DEPTH := 0.0
const HIT_RADIUS := 0.5
const ENEMY_WEAPON_TIER := 0
const ENEMY_PROJECTILE_SPEED := 25.0

@onready var units_view: UnitsView = $UnitsView
@onready var enemy_view: UnitsView = $EnemyView
@onready var corridor_view: CorridorView = $CorridorView
@onready var squad_projectile_view: ProjectileView = $SquadProjectileView
@onready var enemy_projectile_view: ProjectileView = $EnemyProjectileView
@onready var hud: Label = $HUD/DistanceLabel

var squad: Squad
var steer: SteerInput
var runner: TrackRunner
var generator: TrackGenerator
var enemies: Units
var squad_weapon: Weapon
var enemy_weapon: Weapon
var squad_projectiles: Projectiles
var enemy_projectiles: Projectiles
var run: RunState

var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_base := 0.0
var _time := 0.0

func _ready() -> void:
    squad = Squad.new()
    steer = SteerInput.new()
    runner = TrackRunner.new()
    generator = TrackGenerator.new(randi())
    enemies = Units.new()
    squad_weapon = Weapon.new()
    enemy_weapon = Weapon.new()
    squad_projectiles = Projectiles.new()
    enemy_projectiles = Projectiles.new()
    run = RunState.new()
    run.load_best()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
            _drag_base = steer.centre_x
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        var moved: float = _screen_delta_to_steer_delta(event.position.x - _drag_origin.x)
        steer.steer_to_screen_delta(
            Vector2(moved + _drag_base * SteerInput.PIXELS_PER_UNIT, 0))

# The Camera3D in game.tscn is yawed 180 degrees (rotation_degrees.y = 180)
# so it can look down +Z instead of Godot's default -Z -- this game's
# "forward" is +Z (see Corridor/Formation). That yaw flips the camera's
# local right vector relative to world +X: screen-right corresponds to
# world -X, not world +X. Feeding a raw screen-space drag straight into a
# world-space steer target therefore moves the squad opposite the finger.
static func _screen_delta_to_steer_delta(screen_delta_x: float) -> float:
    return -screen_delta_x

func _process(delta: float) -> void:
    _time += delta

    for pos in generator.tick(delta, enemies.count):
        enemies.spawn(pos, Vector2(0, -generator.enemy_speed()), generator.enemy_health())

    runner.tick(delta)
    steer.tick(delta)
    squad.tick(delta, steer.centre_x)
    enemies.tick(delta, Vector2(0, -Corridor.scroll_speed_at(runner.elapsed)))

    var squad_shots := squad_weapon.tick(delta, squad.weapon_tier)
    Volley.fire(squad.units, squad_projectiles, squad_shots,
        Weapon.projectiles_per_shot_at(squad.weapon_tier),
        Weapon.spread_degrees_at(squad.weapon_tier),
        Vector2(0, 1), squad_weapon.projectile_speed)

    var enemy_shots := enemy_weapon.tick(delta, ENEMY_WEAPON_TIER)
    Volley.fire(enemies, enemy_projectiles, enemy_shots,
        Weapon.projectiles_per_shot_at(ENEMY_WEAPON_TIER),
        Weapon.spread_degrees_at(ENEMY_WEAPON_TIER),
        Vector2(0, -1), ENEMY_PROJECTILE_SPEED)

    squad_projectiles.tick(delta, Corridor.SPAWN_DISTANCE + 5.0)
    enemy_projectiles.tick(delta, Corridor.SPAWN_DISTANCE + 5.0)

    run.record_kills(squad_projectiles.resolve_hits(enemies, HIT_RADIUS,
        Weapon.damage_at(squad.weapon_tier)))
    enemy_projectiles.resolve_hits(squad.units, HIT_RADIUS,
        Weapon.damage_at(ENEMY_WEAPON_TIER))

    var contacts := enemies.remove_beyond(CONTACT_DEPTH)
    squad.set_count(max(squad.count() - contacts, 0))

    run.tick(delta, runner.distance)
    if squad.is_wiped():
        _restart()

    units_view.render(squad.units, _time)
    enemy_view.render(enemies, _time)
    corridor_view.render(runner)
    squad_projectile_view.render(squad_projectiles)
    enemy_projectile_view.render(enemy_projectiles)
    hud.text = "%d m    %d kills" % [int(runner.distance), run.kills]

func _restart() -> void:
    run.end_run()
    run.save_best()
    run.reset()
    squad.reset()
    steer.reset()
    runner.reset()
    generator.reset()
    enemies.clear()
    squad_weapon.reset()
    enemy_weapon.reset()
    squad_projectiles.clear()
    enemy_projectiles.clear()
```

`_restart()` resets every stateful unit in place and reuses every object — no reallocation, matching the constraint every prior task in this project has upheld for the eventual continuous-audio requirement.

- [ ] **Step 4: Update `scenes/game.tscn`**

Add three nodes alongside the existing ones (do not change the `Camera3D`, `DirectionalLight3D`, `CorridorView`, or `HUD` nodes — those are unaffected by this phase):

```
Game            (Node3D)              → scripts/game.gd
├── Camera3D                          → UNCHANGED
├── DirectionalLight3D                → UNCHANGED
├── CorridorView   (Node3D)           → UNCHANGED
├── UnitsView      (MultiMeshInstance3D) → scripts/views/units_view.gd  [existing, squad's own]
├── EnemyView      (MultiMeshInstance3D) → scripts/views/units_view.gd  [NEW — same script, second instance]
├── SquadProjectileView (MultiMeshInstance3D) → scripts/views/projectile_view.gd  [NEW]
├── EnemyProjectileView (MultiMeshInstance3D) → scripts/views/projectile_view.gd  [NEW]
└── HUD            (CanvasLayer)      → UNCHANGED
    └── DistanceLabel (Label)
```

`EnemyView` and both `ProjectileView` instances reuse the exact same scripts as the squad's existing `UnitsView` node — no new view classes, per the spec's "generic container, used twice" design. Each needs its own `MultiMeshInstance3D` node so it owns its own `MultiMesh` resource (created in each instance's own `_ready()`), not a shared one.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: full suite PASS. Report the count with arithmetic and the runtime.

- [ ] **Step 6: Confirm the game runs**

Run: `godot --headless --quit-after 900`
Expected: starts, runs, exits 0, no script errors.

- [ ] **Step 7: Add an on-screen FPS readout for the device performance pass**

Extend the HUD line in `_process` to also show `Engine.get_frames_per_second()`, since Task 8 needs a way to read framerate on Aslam's actual phone without any extra tooling:

```gdscript
    hud.text = "%d m    %d kills    %d fps" % [int(runner.distance), run.kills, Engine.get_frames_per_second()]
```

- [ ] **Step 8: Verify the test-strength properties of the new integration tests**

For `test_a_run_can_end_from_enemy_pressure` and `test_squad_fire_kills_enemies`: confirm by deliberately breaking the wiring (e.g., temporarily skip the `run.record_kills(squad_projectiles.resolve_hits(...))` line, or skip the contact-damage lines) that the relevant test fails. Restore, confirm `git diff scripts/game.gd` is empty. Report which mutation you used and which test caught it.

- [ ] **Step 9: Commit**

```bash
git add scripts/game.gd scenes/game.tscn test/test_game_integration.gd
git commit -m "feat: wire weapon tiers, enemy crowds, and both projectile pools into the corridor"
```

---

### Task 8: Device performance pass — hand to Aslam, do not attempt

Phase 1's build order named this as its own step ("Android toolchain and a device performance pass at full caps") and it was implicitly deferred twice: once because phase 1 had nothing to stress yet, once because phase 1's own playtest took priority. Phase 2 is the first point where there is real simultaneous load to check — up to 256 squad units, 256 enemies, and 512 projectiles per pool, all MultiMesh-drawn at once.

**This step cannot be performed by an agent.** It requires Aslam's physical Android device.

- [ ] **Step 1: Build the debug APK**

From the project root:
```
godot --headless --export-debug "Android" builds/onrush-debug.apk
```

- [ ] **Step 2: Hand to Aslam with this checklist**

- Does the FPS readout (added in Task 7 Step 7) stay near 60 during normal play?
- Does it drop when many enemies are on screen at once? (Waiting near the end of a long run, once `TrackGenerator`'s group size has escalated, is the easiest way to see this.)
- Does firing at a high weapon tier (once tested manually by editing `squad.weapon_tier` — no gate exists yet to change it in normal play) cause a visible stutter?
- Does the game still feel responsive — steering, in particular — under heavy enemy load, or does frame-time growth make input feel laggy even though the accumulator logic itself stays frame-rate independent?

If FPS holds near 60 throughout, no further action needed here — the naive `O(units × projectiles)` collision loop in `Projectiles.resolve_hits` is fine as-is and the spec's deferred broadphase optimisation stays deferred. If it drops meaningfully under load, that is the signal to build the broadphase the spec has been holding open for exactly this moment — report the specific conditions (unit counts, projectile counts) that triggered it, since that becomes the next task's acceptance criterion.

## Self-review notes

**Spec coverage.** Covers build order step 4 (weapon tiers, both projectile pools, enemy crowds) in full, plus finally completing step 3 (the device performance pass, deferred twice already). Gates (step 5) and hazards (step 6) are explicitly out of scope — `Weapon`'s tier is settable data with no gate wired to change it yet, exactly mirroring how `Squad.weapon_tier` sits unused by anything except a future gate.

**Deliberate simplifications, recorded here rather than hidden:**

1. **Enemies reuse `Weapon` tier 0** rather than having their own stat block. A reasonable first pass; split out a dedicated enemy stat table later if enemies need independent balance.
2. **Contact damage is a flat "one contact removes one squad unit"** (via reusing `Units.remove_beyond`'s count), not scaled by the enemy's remaining health or type. Simplest rule that gives "letting enemies through" a real cost.
3. **All tier and `TrackGenerator` numbers are first-pass placeholders**, explicitly flagged as such in Task 1 and Task 4, in the same spirit as phase 1's `SMOOTHING`/`PIXELS_PER_UNIT` — expected to be retuned after playing, not treated as final balance.

**Known gap.** `test_squad_fire_kills_enemies` and `test_a_run_can_end_from_enemy_pressure` depend on the placeholder balance actually producing the described outcome within the chosen test durations. If the balance is badly wrong, these fail honestly — that is useful information, not a defect in the tests.
