# Onrush Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gate pairs — Count, Weapon tier, and Formation families — to the corridor, so steering
has stakes beyond dodging fire: every pair is a choice between a better and a worse (or neutral)
outcome, resolved by which side the squad's centre is on when it crosses the line.

**Architecture:** Four new pure-logic classes (`Gate`, `GatePair`, `Gates`, plus generation logic
folded into `TrackGenerator`) extend the existing corridor/spawn/tick pipeline without touching
tested behaviour in `Squad`, `Weapon`, or `TrackRunner` beyond adding new methods. `Gates` owns the
list of pairs currently on-track and resolves them exactly like `Units.remove_beyond` recycles
enemies — cross a threshold, act, remove — but gates additionally need to know *which side* the
squad was on, which neither `TrackRunner` nor `Units` has any concept of. Rendering is a new
`GateView` following `CorridorView`'s per-instance pooling (not `UnitsView`'s `MultiMesh` — gates
need per-instance `Label3D` text, which `MultiMesh` can't carry).

**Tech Stack:** Godot 4.7.1 Standard, GDScript, GUT 9.6.1. No new dependencies.

Source spec: `docs/specs/2026-08-06-onrush-gates-design.md` (this plan implements it task-by-task);
`docs/specs/2026-08-02-onrush-design.md` `## Gates` for the original family/tension rationale.

## Global Constraints

- **Logic is 2D.** `Vector2(x, y)`, `x` lateral, `y` forward. Views map to `Vector3(x, 0, y)`. No rule
  unit may reference a 3D type.
- **Rule units extend `RefCounted`, never `Node`.**
- **No Godot physics anywhere.** Gate/squad overlap is arithmetic (`abs(x - x_centre) <= HALF_WIDTH`),
  never `Area3D`.
- **Corrected gate geometry, not the original spec text's numbers:** `Gate.SIDE_OFFSET := 2.4`,
  `Gate.HALF_WIDTH := 1.0`. See `docs/specs/2026-08-06-onrush-gates-design.md`'s "Geometry
  correction" section for why the original `x=±3, half-width 1.2` doesn't fit
  `SteerInput.MAX_CENTRE = 3.75`.
- **Bad Count gates floor the squad at 1, never 0.** A gate must never itself end a run; only combat
  contact may reach zero (`Squad.set_count` already floors combat losses at 0 — that path is
  untouched).
- **`Squad` owns the rules for applying a gate**, per the original spec's own words. `Gate.apply`
  only dispatches to `Squad` methods; no clamping or floor logic lives in `Gate` itself.
- **Gate value generation uses its own RNG stream and its own spawn clock inside `TrackGenerator`**,
  entirely separate from the existing enemy-spawn `_rng`/`_spawn_clock`. This is not a style
  preference — the existing `test_track_generator.gd` determinism tests assert an exact enemy-spawn
  sequence for a given seed, and adding gate spawning must not perturb it.
- **A test a broken implementation would pass is not a test.** Every new test below is written to
  fail against at least one plausible wrong implementation, and several call that out explicitly.

---

### Task 1: Squad — gate-application rules

**Files:**
- Modify: `scripts/squad.gd`
- Modify: `test/test_squad.gd`

**Interfaces:**
- Consumes: `Weapon.TIER_COUNT` (already exists, `scripts/weapon.gd:3`).
- Produces:
  - `Squad.add_count(delta: int) -> void`
  - `Squad.mul_count(factor: float) -> void`
  - `Squad.step_weapon_tier(delta: int) -> void`
  - `Squad.set_formation(kind: int) -> void`

These four are what `Gate.apply` (Task 2) calls into. None of them exist yet — `squad.gd` currently
only exposes `set_count`, and `weapon_tier`/`formation` are bare public vars anyone can write
unclamped.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_squad.gd`:

```gdscript
func test_add_count_increases():
    squad.set_count(10)
    squad.add_count(5)
    assert_eq(squad.count(), 15)

func test_add_count_floors_at_one():
    squad.set_count(1)
    squad.add_count(-50)
    assert_eq(squad.count(), 1,
        "a gate must never be able to wipe the squad -- only combat may reach zero")

func test_add_count_still_clamps_to_the_cap():
    squad.set_count(Units.MAX_UNITS - 2)
    squad.add_count(100)
    assert_eq(squad.count(), Units.MAX_UNITS)

func test_mul_count_scales():
    squad.set_count(10)
    squad.mul_count(2.0)
    assert_eq(squad.count(), 20)

func test_mul_count_floors_at_one():
    squad.set_count(1)
    squad.mul_count(0.5)
    assert_eq(squad.count(), 1,
        "a halving gate on a single-unit squad must not be able to reach zero")

func test_step_weapon_tier_increases():
    squad.step_weapon_tier(1)
    assert_eq(squad.weapon_tier, 1)

func test_step_weapon_tier_clamps_at_the_top():
    squad.weapon_tier = Weapon.TIER_COUNT - 1
    squad.step_weapon_tier(1)
    assert_eq(squad.weapon_tier, Weapon.TIER_COUNT - 1,
        "stepping past the top tier must clamp, not overflow silently")

func test_step_weapon_tier_clamps_at_the_bottom():
    squad.step_weapon_tier(-1)
    assert_eq(squad.weapon_tier, 0,
        "stepping below tier 0 must clamp, or a later good gate could silently do nothing while the squad 'climbs back' through negative tiers")

func test_set_formation_changes_formation():
    squad.set_formation(Formation.Kind.WEDGE)
    assert_eq(squad.formation, Formation.Kind.WEDGE)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: the seven new tests FAIL (methods don't exist yet); all pre-existing tests still PASS.

- [ ] **Step 3: Implement**

In `scripts/squad.gd`, add these methods (placement: after `set_count`, before `tick`):

```gdscript
func add_count(delta: int) -> void:
    set_count(max(count() + delta, 1))

func mul_count(factor: float) -> void:
    set_count(max(int(round(count() * factor)), 1))

func step_weapon_tier(delta: int) -> void:
    weapon_tier = clampi(weapon_tier + delta, 0, Weapon.TIER_COUNT - 1)

func set_formation(kind: int) -> void:
    formation = kind
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/squad.gd test/test_squad.gd
git commit -m "feat: add gate-application rules to Squad (count, weapon tier, formation)"
```

---

### Task 2: Gate — pure-logic gate unit

**Files:**
- Create: `scripts/gate.gd`
- Create: `test/test_gate.gd`

**Interfaces:**
- Consumes: `Squad.add_count`, `Squad.mul_count`, `Squad.step_weapon_tier`, `Squad.set_formation`
  (Task 1).
- Produces:
  - `Gate.SIDE_OFFSET: float` = 2.4 (const)
  - `Gate.HALF_WIDTH: float` = 1.0 (const)
  - `Gate.Op` enum — `ADD`, `MUL`, `TIER_STEP`, `SET_FORMATION`
  - `Gate.new(op: Gate.Op, value: float, x_centre: float) -> Gate`
  - `gate.op: Gate.Op`, `gate.value: float`, `gate.x_centre: float` (public, read directly — same
    style as `Weapon`'s public tier tables, no getters where nothing needs them)
  - `gate.contains(x: float) -> bool`
  - `gate.apply(squad: Squad) -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_gate.gd`:

```gdscript
extends GutTest

var squad: Squad

func before_each():
    squad = Squad.new()

func test_add_applies_to_squad_count():
    squad.set_count(10)
    var gate := Gate.new(Gate.Op.ADD, 5.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.count(), 15)

func test_mul_applies_to_squad_count():
    squad.set_count(10)
    var gate := Gate.new(Gate.Op.MUL, 2.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.count(), 20)

func test_tier_step_applies_to_weapon_tier():
    var gate := Gate.new(Gate.Op.TIER_STEP, 1.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.weapon_tier, 1)

func test_tier_step_negative_clamps_at_zero():
    var gate := Gate.new(Gate.Op.TIER_STEP, -1.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.weapon_tier, 0,
        "Gate must go through Squad's clamped setter, not write weapon_tier directly")

func test_set_formation_applies_to_squad_formation():
    var gate := Gate.new(Gate.Op.SET_FORMATION, float(Formation.Kind.COLUMN), 0.0)
    gate.apply(squad)
    assert_eq(squad.formation, Formation.Kind.COLUMN)

func test_contains_true_inside_half_width():
    var gate := Gate.new(Gate.Op.ADD, 0.0, 2.4)
    assert_true(gate.contains(2.4))
    assert_true(gate.contains(1.4))
    assert_true(gate.contains(3.4))

func test_contains_false_outside_half_width():
    var gate := Gate.new(Gate.Op.ADD, 0.0, 2.4)
    assert_false(gate.contains(1.39))
    assert_false(gate.contains(3.41))

func test_contains_false_on_the_opposite_side():
    var gate := Gate.new(Gate.Op.ADD, 0.0, -2.4)
    assert_false(gate.contains(2.4),
        "a gate centred on the left must not claim a point on the right")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL with "Gate not declared" (class doesn't exist yet).

- [ ] **Step 3: Implement**

Create `scripts/gate.gd`:

```gdscript
class_name Gate extends RefCounted

# Corrected from the original design doc's x=+/-3, half-width 1.2: that footprint
# (spanning [1.8, 4.2]) sits partly outside SteerInput.MAX_CENTRE (3.75), which would
# make the "skip both gates" lane unreachable. This footprint ([1.4, 3.4]) fits inside
# it. See docs/specs/2026-08-06-onrush-gates-design.md.
const SIDE_OFFSET := 2.4
const HALF_WIDTH := 1.0

enum Op { ADD, MUL, TIER_STEP, SET_FORMATION }

var op: Op
var value: float
var x_centre: float

func _init(p_op: Op, p_value: float, p_x_centre: float) -> void:
    op = p_op
    value = p_value
    x_centre = p_x_centre

func contains(x: float) -> bool:
    return abs(x - x_centre) <= HALF_WIDTH

func apply(squad: Squad) -> void:
    match op:
        Op.ADD:
            squad.add_count(int(value))
        Op.MUL:
            squad.mul_count(value)
        Op.TIER_STEP:
            squad.step_weapon_tier(int(value))
        Op.SET_FORMATION:
            squad.set_formation(int(value))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/gate.gd test/test_gate.gd
git commit -m "feat: add Gate, a pure-logic single-side gate effect"
```

---

### Task 3: GatePair — two gates, one crossing

**Files:**
- Create: `scripts/gate_pair.gd`
- Create: `test/test_gate_pair.gd`

**Interfaces:**
- Consumes: `Gate.contains` (Task 2).
- Produces:
  - `GatePair.new(left: Gate, right: Gate, y: float) -> GatePair`
  - `gate_pair.left: Gate`, `gate_pair.right: Gate`, `gate_pair.y: float` (public)
  - `gate_pair.resolve(squad_centre_x: float) -> Gate` (returns `null` if the centre is in neither
    gate's span — the "skip both" case)

- [ ] **Step 1: Write the failing tests**

Create `test/test_gate_pair.gd`:

```gdscript
extends GutTest

var pair: GatePair

func before_each():
    var left := Gate.new(Gate.Op.ADD, -5.0, -Gate.SIDE_OFFSET)
    var right := Gate.new(Gate.Op.ADD, 5.0, Gate.SIDE_OFFSET)
    pair = GatePair.new(left, right, 10.0)

func test_resolve_picks_left_when_centre_is_inside_the_left_gate():
    assert_eq(pair.resolve(-Gate.SIDE_OFFSET), pair.left)

func test_resolve_picks_right_when_centre_is_inside_the_right_gate():
    assert_eq(pair.resolve(Gate.SIDE_OFFSET), pair.right)

func test_resolve_returns_null_in_the_centre_channel():
    # Midway between the two gates -- inside neither's HALF_WIDTH.
    assert_null(pair.resolve(0.0),
        "the corridor's centre channel must let the squad skip both gates")

func test_resolve_returns_null_beyond_the_outer_edge():
    # Just past the right gate's outer edge but still within SteerInput.MAX_CENTRE (3.75).
    assert_null(pair.resolve(Gate.SIDE_OFFSET + Gate.HALF_WIDTH + 0.3),
        "steering past a gate's outer edge must also skip it -- the whole point of the corridor being wider than the gate pair")

func test_resolve_boundary_is_inclusive():
    # Exactly on the gate's inner/outer edge must still count as inside it --
    # matches Gate.contains's own <= semantics, tested separately in test_gate.gd.
    assert_eq(pair.resolve(Gate.SIDE_OFFSET - Gate.HALF_WIDTH), pair.right)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL with "GatePair not declared".

- [ ] **Step 3: Implement**

Create `scripts/gate_pair.gd`:

```gdscript
class_name GatePair extends RefCounted

var left: Gate
var right: Gate
var y: float

func _init(p_left: Gate, p_right: Gate, p_y: float) -> void:
    left = p_left
    right = p_right
    y = p_y

func resolve(squad_centre_x: float) -> Gate:
    if left.contains(squad_centre_x):
        return left
    if right.contains(squad_centre_x):
        return right
    return null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/gate_pair.gd test/test_gate_pair.gd
git commit -m "feat: add GatePair, resolving which gate (if any) a centre-x crossed"
```

---

### Task 4: Gates — the container that scrolls, triggers, and recycles pairs

**Files:**
- Create: `scripts/gates.gd`
- Create: `test/test_gates.gd`

**Interfaces:**
- Consumes: `GatePair.resolve` (Task 3), `Gate.apply` (Task 2), `Squad.centre_x` (existing public
  field, `scripts/squad.gd:10`).
- Produces:
  - `Gates.new() -> Gates`
  - `gates.pairs: Array[GatePair]` (public, mutated externally by `TrackGenerator`'s spawns in
    Task 6 — same shape as how `Game._process` currently appends straight into `enemies`)
  - `gates.tick(delta: float, scroll_speed: float, squad: Squad) -> void`
  - `gates.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `test/test_gates.gd`:

```gdscript
extends GutTest

var gates: Gates
var squad: Squad

func before_each():
    gates = Gates.new()
    squad = Squad.new()

func _pair(left_value: float, right_value: float, y: float) -> GatePair:
    var left := Gate.new(Gate.Op.ADD, left_value, -Gate.SIDE_OFFSET)
    var right := Gate.new(Gate.Op.ADD, right_value, Gate.SIDE_OFFSET)
    return GatePair.new(left, right, y)

func test_pairs_move_toward_zero_each_tick():
    var pair := _pair(0.0, 0.0, 10.0)
    gates.pairs.append(pair)
    gates.tick(1.0, 4.0, squad)
    assert_almost_eq(pair.y, 6.0, 0.001)

func test_a_pair_that_crosses_zero_is_removed():
    gates.pairs.append(_pair(0.0, 0.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(gates.pairs.size(), 0)

func test_a_pair_that_has_not_crossed_yet_survives():
    gates.pairs.append(_pair(0.0, 0.0, 10.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(gates.pairs.size(), 1)

func test_crossing_applies_the_right_gate_when_centre_is_on_the_right():
    squad.centre_x = Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(-100.0, 7.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 17,
        "the RIGHT gate's value must apply when the squad's centre is on the right")

func test_crossing_applies_the_left_gate_when_centre_is_on_the_left():
    squad.centre_x = -Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(7.0, -100.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 17,
        "the LEFT gate's value must apply when the squad's centre is on the left")

func test_crossing_in_the_centre_channel_applies_neither_gate():
    squad.centre_x = 0.0
    squad.set_count(10)
    gates.pairs.append(_pair(50.0, 50.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 10,
        "steering between both gates must apply nothing, even though both would otherwise help")

func test_a_pair_resolves_exactly_once_even_when_a_large_delta_jumps_past_zero():
    squad.centre_x = Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(0.0, 7.0, 0.5))
    # A single MAX_DELTA-sized (0.1s) frame at a plausible scroll speed easily
    # covers more than 0.5 world units, jumping y from +0.5 to well past 0 in
    # one tick -- must still apply the gate exactly once, not zero or twice.
    gates.tick(0.1, 14.0, squad)
    assert_eq(squad.count(), 17)
    gates.tick(0.1, 14.0, squad)
    assert_eq(squad.count(), 17,
        "a pair already removed must not somehow apply again on a later tick")

func test_reset_clears_all_pairs():
    gates.pairs.append(_pair(0.0, 0.0, 10.0))
    gates.pairs.append(_pair(0.0, 0.0, 20.0))
    gates.reset()
    assert_eq(gates.pairs.size(), 0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL with "Gates not declared".

- [ ] **Step 3: Implement**

Create `scripts/gates.gd`:

```gdscript
class_name Gates extends RefCounted

var pairs: Array[GatePair] = []

func tick(delta: float, scroll_speed: float, squad: Squad) -> void:
    var step := scroll_speed * delta
    var remaining: Array[GatePair] = []
    for pair in pairs:
        pair.y -= step
        if pair.y <= 0.0:
            var gate := pair.resolve(squad.centre_x)
            if gate != null:
                gate.apply(squad)
            continue
        remaining.append(pair)
    pairs = remaining

func reset() -> void:
    pairs.clear()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/gates.gd test/test_gates.gd
git commit -m "feat: add Gates container -- scrolls, triggers, and recycles gate pairs"
```

---

### Task 5: TrackGenerator — gate pair spawning and value generation

**Files:**
- Modify: `scripts/track_generator.gd`
- Modify: `test/test_track_generator.gd`

**Interfaces:**
- Consumes: `Gate.new`, `Gate.SIDE_OFFSET` (Task 2), `GatePair.new` (Task 3), `Formation.Kind`
  (existing, `scripts/formation.gd:3`), `Corridor.SPAWN_DISTANCE` (existing).
- Produces:
  - `TrackGenerator.tick_gates(delta: float, current_formation: int) -> Array[GatePair]` — emits at
    most one pair per call, at `y = Corridor.SPAWN_DISTANCE`.
  - `TrackGenerator.count_delta_range() -> Vector2` — `.x` = current min magnitude, `.y` = current
    max magnitude for a Count `ADD` gate, escalating with elapsed time.
  - `reset()` (existing method, extended) also zeroes the gate spawn clock and reseeds the gate RNG.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_track_generator.gd`. `_family_of` is a small test-only helper mapping a
resolved `Gate.op` back to which family produced it, since `Gate` itself doesn't store a family
(Task 2's design note: family is derivable from `op`, so it isn't stored twice).

```gdscript
enum _Family { COUNT, WEAPON, FORMATION }

func _family_of(gate: Gate) -> int:
    match gate.op:
        Gate.Op.ADD, Gate.Op.MUL:
            return _Family.COUNT
        Gate.Op.TIER_STEP:
            return _Family.WEAPON
        _:
            return _Family.FORMATION

func test_tick_gates_produces_nothing_before_the_interval_elapses():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(0.5, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 0)

func test_tick_gates_spawns_a_pair_at_the_spawn_distance_once_the_interval_elapses():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 1)
    assert_almost_eq(spawns[0].y, Corridor.SPAWN_DISTANCE, 0.001)

func test_tick_gates_never_returns_more_than_one_pair_per_call():
    var g := TrackGenerator.new(42)
    # Five intervals' worth of delta in a single call -- a real backgrounded-app
    # catch-up frame could plausibly do this before Game.MAX_DELTA clamps it.
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL * 5.0, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 1,
        "at most one pair per call, or two pairs could land at the identical y and make trigger resolution ambiguous")

func test_a_spawned_pair_has_gates_on_opposite_sides():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
    var pair: GatePair = spawns[0]
    assert_almost_eq(pair.left.x_centre, -Gate.SIDE_OFFSET, 0.001)
    assert_almost_eq(pair.right.x_centre, Gate.SIDE_OFFSET, 0.001)

func test_pairs_are_cross_family_never_the_same_family_on_both_sides():
    var g := TrackGenerator.new(42)
    for i in 40:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        assert_ne(_family_of(pair.left), _family_of(pair.right),
            "a pair must always offer two different families, never the same family on both sides")

func test_formation_gate_never_offers_the_squads_current_formation():
    var g := TrackGenerator.new(42)
    var found_formation_gate := false
    for i in 200:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        for gate in [pair.left, pair.right]:
            if gate.op == Gate.Op.SET_FORMATION:
                found_formation_gate = true
                assert_ne(int(gate.value), Formation.Kind.WIDE,
                    "a Formation gate must never offer the formation the squad is already in")
    assert_true(found_formation_gate,
        "test setup problem: 200 pairs produced no Formation gate at all to check")

func test_non_formation_pairs_are_one_good_one_bad():
    # When neither side is Formation, Count/Weapon must split good/bad -- never
    # both positive or both negative, per the design's cross-family tension rule.
    var g := TrackGenerator.new(42)
    var checked := 0
    for i in 60:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        if pair.left.op == Gate.Op.SET_FORMATION or pair.right.op == Gate.Op.SET_FORMATION:
            continue
        checked += 1
        var left_good: bool = (pair.left.op == Gate.Op.ADD and pair.left.value > 0.0) \
            or (pair.left.op == Gate.Op.MUL and pair.left.value > 1.0) \
            or (pair.left.op == Gate.Op.TIER_STEP and pair.left.value > 0.0)
        var right_good: bool = (pair.right.op == Gate.Op.ADD and pair.right.value > 0.0) \
            or (pair.right.op == Gate.Op.MUL and pair.right.value > 1.0) \
            or (pair.right.op == Gate.Op.TIER_STEP and pair.right.value > 0.0)
        assert_ne(left_good, right_good,
            "exactly one side of a non-Formation pair must be good and the other bad")
    assert_gt(checked, 0, "test setup problem: no non-Formation pair appeared to check")

func test_count_delta_range_widens_with_elapsed_time():
    var g := TrackGenerator.new(42)
    var early := g.count_delta_range()
    for i in 36000:  # 600s at 1/60, well past every ramp constant in this file
        g.tick(1.0 / 60.0, 0)
        g.tick_gates(1.0 / 60.0, Formation.Kind.WIDE)
    var late := g.count_delta_range()
    assert_gt(late.y, early.y,
        "the maximum Count delta must grow with distance, or later gates never feel more severe")

func test_gate_spawning_does_not_perturb_the_enemy_spawn_sequence():
    # Gate values must be drawn from a separate RNG stream. If they shared
    # _rng with enemy spawning, interleaving tick_gates() calls would change
    # the enemy spawn sequence for a fixed seed -- silently breaking every
    # existing determinism test above the moment gates were added.
    var without_gates := TrackGenerator.new(7)
    var with_gates := TrackGenerator.new(7)
    for i in 100:
        var a := without_gates.tick(1.0, 0)
        with_gates.tick_gates(1.0, Formation.Kind.WIDE)
        var b := with_gates.tick(1.0, 0)
        assert_eq(a, b, "enemy spawns must be identical whether or not tick_gates was ever called")

func test_reset_replays_the_same_gate_sequence():
    var g := TrackGenerator.new(42)
    var first: Array[bool] = []
    for i in 50:
        first.append(g.tick_gates(1.0, Formation.Kind.WIDE).size() > 0)
    g.reset()
    var second: Array[bool] = []
    for i in 50:
        second.append(g.tick_gates(1.0, Formation.Kind.WIDE).size() > 0)
    assert_eq(first, second)

func test_reset_zeroes_the_gate_spawn_clock():
    var g := TrackGenerator.new(42)
    g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL - 0.1, Formation.Kind.WIDE)
    g.reset()
    var spawns := g.tick_gates(0.5, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 0,
        "reset must zero the gate clock -- otherwise a run that reset just before a spawn would spawn immediately on the new run's very first tick")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `tick_gates`/`count_delta_range`/`GATE_SPAWN_INTERVAL` don't exist yet.

- [ ] **Step 3: Implement**

In `scripts/track_generator.gd`, add near the top (after the existing consts):

```gdscript
# Gate cadence is fixed, not decaying like GROUP_INTERVAL -- the spec escalates
# gate SEVERITY with distance, not how often gates appear.
const GATE_SPAWN_INTERVAL := 6.0

# XORed into the constructor seed so the gate RNG stream is fully independent of
# _rng (enemy spawning). Any fixed nonzero constant works; this one just needs to
# never collide with a real seed in practice.
const GATE_RNG_SEED_XOR := 0x5bd1e995

const COUNT_DELTA_BASE_MIN := 3.0
const COUNT_DELTA_BASE_MAX := 6.0
const COUNT_DELTA_MAX_MIN := 8.0
const COUNT_DELTA_MAX_MAX := 20.0
const COUNT_DELTA_RAMP_SECONDS := 120.0

enum _Family { COUNT, WEAPON, FORMATION }
```

Add new instance vars next to the existing `_rng`/`_seed`/`_elapsed`/`_spawn_clock`:

```gdscript
var _gate_rng := RandomNumberGenerator.new()
var _gate_spawn_clock := 0.0
```

In `_init`, after `_rng.seed = rng_seed`:

```gdscript
    _gate_rng.seed = rng_seed ^ GATE_RNG_SEED_XOR
```

In `reset()`, after `_rng.seed = _seed`:

```gdscript
    _gate_spawn_clock = 0.0
    _gate_rng.seed = _seed ^ GATE_RNG_SEED_XOR
```

Add the new public methods (placement: after `enemy_speed()`, before `reset()`):

```gdscript
func count_delta_range() -> Vector2:
    var t := 1.0 - exp(-_elapsed / COUNT_DELTA_RAMP_SECONDS)
    var lo := COUNT_DELTA_BASE_MIN + (COUNT_DELTA_MAX_MIN - COUNT_DELTA_BASE_MIN) * t
    var hi := COUNT_DELTA_BASE_MAX + (COUNT_DELTA_MAX_MAX - COUNT_DELTA_BASE_MAX) * t
    return Vector2(lo, hi)

func tick_gates(delta: float, current_formation: int) -> Array[GatePair]:
    _gate_spawn_clock += delta
    if _gate_spawn_clock < GATE_SPAWN_INTERVAL:
        return []
    # Reset rather than subtract-and-carry: caps this at exactly one pair per
    # call even if delta covered several intervals (see the "never more than
    # one pair" test). A frame that large is already an edge case Game.MAX_DELTA
    # exists to prevent; losing the small remainder here is not worth the
    # complexity of a carry-and-loop.
    _gate_spawn_clock = 0.0
    return [_spawn_gate_pair(current_formation)]

func _spawn_gate_pair(current_formation: int) -> GatePair:
    var first: int = _gate_rng.randi_range(0, 2)
    var second: int = _gate_rng.randi_range(0, 2)
    while second == first:
        second = _gate_rng.randi_range(0, 2)
    var left_family: int
    var right_family: int
    if _gate_rng.randf() < 0.5:
        left_family = first
        right_family = second
    else:
        left_family = second
        right_family = first

    var left_good := _gate_rng.randf() < 0.5
    var left := _gate_for_family(left_family, left_good, -Gate.SIDE_OFFSET, current_formation)
    var right := _gate_for_family(right_family, not left_good, Gate.SIDE_OFFSET, current_formation)
    return GatePair.new(left, right, Corridor.SPAWN_DISTANCE)

func _gate_for_family(family: int, is_good: bool, x_centre: float, current_formation: int) -> Gate:
    match family:
        _Family.COUNT:
            return _count_gate(is_good, x_centre)
        _Family.WEAPON:
            return Gate.new(Gate.Op.TIER_STEP, 1.0 if is_good else -1.0, x_centre)
        _:
            return Gate.new(Gate.Op.SET_FORMATION,
                float(_random_formation_excluding(current_formation)), x_centre)

func _count_gate(is_good: bool, x_centre: float) -> Gate:
    var range := count_delta_range()
    var n := _gate_rng.randf_range(range.x, range.y)
    if _gate_rng.randf() < 0.5:
        return Gate.new(Gate.Op.MUL, 2.0 if is_good else 0.5, x_centre)
    return Gate.new(Gate.Op.ADD, n if is_good else -n, x_centre)

func _random_formation_excluding(current: int) -> int:
    var options: Array[int] = []
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        if kind != current:
            options.append(kind)
    return options[_gate_rng.randi_range(0, options.size() - 1)]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green. If `test_formation_gate_never_offers_the_squads_current_formation`
or `test_non_formation_pairs_are_one_good_one_bad` report their own "test setup problem" assertion
failing (not enough qualifying pairs appeared in the sampled range), that means seed `42` at
`GATE_SPAWN_INTERVAL` cadence doesn't produce one within the loop count used — raise the loop count
in that test rather than changing the implementation.

- [ ] **Step 5: Commit**

```bash
git add scripts/track_generator.gd test/test_track_generator.gd
git commit -m "feat: TrackGenerator spawns gate pairs on their own clock and RNG stream"
```

---

### Task 6: Game.gd — wire Gates into the real game loop

**Files:**
- Modify: `scripts/game.gd`
- Modify: `test/test_game_integration.gd`

**Interfaces:**
- Consumes: `Gates.new`, `Gates.tick`, `Gates.reset` (Task 4), `TrackGenerator.tick_gates` (Task 5).
- Produces: `game.gates: Gates` (public field, mirrors `game.enemies`/`game.squad` — later needed by
  Task 7's `GateView.render(gates)`).

- [ ] **Step 1: Write the failing tests**

Append to `test/test_game_integration.gd`:

```gdscript
func test_gates_are_wired_into_the_scene():
    var game := _make_game()
    assert_not_null(game.gates, "Game must construct its own Gates in _ready")

func test_restart_reuses_gates_and_clears_pending_pairs():
    var game := _make_game()
    var gates_ref: Gates = game.gates
    game.gates.pairs.append(GatePair.new(
        Gate.new(Gate.Op.ADD, 1.0, -Gate.SIDE_OFFSET),
        Gate.new(Gate.Op.ADD, 1.0, Gate.SIDE_OFFSET), 30.0))

    game._restart()

    assert_same(game.gates, gates_ref, "restart must reuse the existing Gates, never rebuild it")
    assert_eq(game.gates.pairs.size(), 0,
        "restart must clear any pairs still on-track from the previous run")

func test_a_gate_injected_into_the_real_scene_reaches_squad_through_process():
    # Closes the same kind of gap test_real_scene_combat_produces_a_kill closes for
    # combat: proves gates actually flow through the real Game._process(), not just
    # the isolated Gate/GatePair/Gates unit tests. Values are constructed directly
    # rather than relying on TrackGenerator's random family selection, so this test
    # is deterministic without needing a seed search.
    var game := _make_game()
    game.generator = TrackGenerator.new(1)

    # Steer fully onto the right gate's centre and let SteerInput's exponential
    # smoothing settle there before any gate is on the track, so the squad's
    # centre_x is already stable when the injected pair arrives.
    game.steer.steer_to_screen_delta(Vector2(Gate.SIDE_OFFSET * SteerInput.PIXELS_PER_UNIT, 0))
    var step := 1.0 / 60.0
    for i in 60:
        game._process(step)
    assert_almost_eq(game.squad.centre_x, Gate.SIDE_OFFSET, 0.05,
        "test setup problem: steering did not settle where this test needs it")

    var count_before := game.squad.count()
    var harmless_left := Gate.new(Gate.Op.ADD, 0.0, -Gate.SIDE_OFFSET)
    var real_right := Gate.new(Gate.Op.ADD, 25.0, Gate.SIDE_OFFSET)
    game.gates.pairs.append(GatePair.new(harmless_left, real_right, 3.0))

    for i in 60:
        game._process(step)

    assert_eq(game.squad.count(), count_before + 25,
        "a gate pair placed directly on Game.gates must actually apply through the real _process() loop")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `game.gates` doesn't exist yet.

- [ ] **Step 3: Implement**

In `scripts/game.gd`:

Add to the var block (after `var run: RunState`):

```gdscript
var gates: Gates
```

In `_ready()`, after `run.load_best()`:

```gdscript
    gates = Gates.new()
```

In `_process(delta)`, after the existing `squad.tick(delta, steer.centre_x)` line and before the
`enemies.tick(...)` line, insert:

```gdscript
    for pair in generator.tick_gates(delta, squad.formation):
        gates.pairs.append(pair)
    gates.tick(delta, Corridor.scroll_speed_at(runner.elapsed), squad)
```

Placed here (not later in `_process`) because `squad.centre_x` must already reflect this frame's
steering before `gates.tick` reads it, and `Corridor.scroll_speed_at(runner.elapsed)` needs
`runner.tick(delta)` to have already run this frame — both are already true by this point in the
existing function.

In `_restart()`, after `generator.reset()`:

```gdscript
    gates.reset()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green, including every pre-existing `test_game_integration.gd` test.

If `test_real_scene_combat_produces_a_kill` (pre-existing) now fails: that test never steers (holds
`centre_x` at 0 throughout, the corridor's centre channel), so every gate spawned during it should
resolve to `null` and apply nothing — investigate `Gates.tick`/`GatePair.resolve` for a boundary bug
before assuming the test itself needs changing.

- [ ] **Step 5: Commit**

```bash
git add scripts/game.gd test/test_game_integration.gd
git commit -m "feat: wire Gates into Game's real per-frame loop and restart"
```

---

### Task 7: GateView — grey-box rendering

**Files:**
- Create: `scripts/views/gate_view.gd`
- Modify: `scenes/game.tscn`
- Modify: `scripts/game.gd`

**Interfaces:**
- Consumes: `Gates.pairs`, `GatePair.left/right/y`, `Gate.op/value/x_centre` (Tasks 2-4).
- Produces: `GateView.render(gates: Gates) -> void`. No new tests — this codebase has no existing
  test files for any `*_view.gd` (`UnitsView`, `ProjectileView`, `CorridorView` are all untested;
  views read and draw only, verified by running the game, not GUT). Verified manually in Step 3
  below instead.

- [ ] **Step 1: Implement GateView**

Create `scripts/views/gate_view.gd`:

```gdscript
class_name GateView extends Node3D

const PANEL_WIDTH := Gate.HALF_WIDTH * 2.0
const PANEL_HEIGHT := 2.0
const PANEL_THICKNESS := 0.1
const LABEL_HEIGHT := PANEL_HEIGHT + 0.3

const GOOD_COLOR := Color(0.25, 0.75, 0.3)
const BAD_COLOR := Color(0.8, 0.25, 0.25)
const NEUTRAL_COLOR := Color(0.55, 0.55, 0.6)

var _panels: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _mesh: BoxMesh

func _ready() -> void:
    _mesh = BoxMesh.new()
    _mesh.size = Vector3(PANEL_WIDTH, PANEL_HEIGHT, PANEL_THICKNESS)

func render(gates: Gates) -> void:
    _ensure(gates.pairs.size() * 2)
    var i := 0
    for pair in gates.pairs:
        _place(i, pair.left, pair.y)
        i += 1
        _place(i, pair.right, pair.y)
        i += 1
    for j in range(i, _panels.size()):
        _panels[j].visible = false
        _labels[j].visible = false

func _place(i: int, gate: Gate, y: float) -> void:
    _panels[i].visible = true
    _labels[i].visible = true
    _panels[i].position = Vector3(gate.x_centre, PANEL_HEIGHT * 0.5, y)
    _labels[i].position = Vector3(gate.x_centre, LABEL_HEIGHT, y)
    _labels[i].text = _label_text(gate)
    var material := _panels[i].material_override as StandardMaterial3D
    material.albedo_color = _color_for(gate)

func _is_good(gate: Gate) -> bool:
    match gate.op:
        Gate.Op.MUL:
            return gate.value > 1.0
        _:
            return gate.value > 0.0

func _color_for(gate: Gate) -> Color:
    if gate.op == Gate.Op.SET_FORMATION:
        return NEUTRAL_COLOR
    return GOOD_COLOR if _is_good(gate) else BAD_COLOR

func _label_text(gate: Gate) -> String:
    match gate.op:
        Gate.Op.ADD:
            return "%+d" % int(gate.value)
        Gate.Op.MUL:
            return "x%.1f" % gate.value
        Gate.Op.TIER_STEP:
            return "WEAPON %+d" % int(gate.value)
        _:
            return Formation.Kind.keys()[int(gate.value)]

func _ensure(n: int) -> void:
    while _panels.size() < n:
        var material := StandardMaterial3D.new()
        var panel := MeshInstance3D.new()
        panel.mesh = _mesh
        panel.material_override = material
        add_child(panel)
        _panels.append(panel)

        var label := Label3D.new()
        label.font_size = 64
        label.pixel_size = 0.008
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        add_child(label)
        _labels.append(label)
```

- [ ] **Step 2: Add the node to the scene**

In `scenes/game.tscn`, add a new ext_resource line after the existing `4_projectile_view` one
(renumber nothing else — Godot resolves these by id string, not position):

```
[ext_resource type="Script" path="res://scripts/views/gate_view.gd" id="10_gate_view"]
```

Add a new node after the `EnemyProjectileView` node block:

```
[node name="GateView" type="Node3D" parent="."]
script = ExtResource("10_gate_view")
```

- [ ] **Step 3: Wire it into Game.gd and verify manually**

In `scripts/game.gd`, add to the `@onready` block:

```gdscript
@onready var gate_view: GateView = $GateView
```

In `_process`, after the existing `corridor_view.render(runner)` line:

```gdscript
    gate_view.render(gates)
```

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: PASS, full suite green (this task adds no new tests, but must not break existing ones —
`GateView` referencing `$GateView` before the node exists in the scene would fail every test that
instantiates `game.tscn`).

Then run the game and manually confirm gates are visible and readable:

Run: `godot`

Press Play, drag left and right as a gate pair approaches, and confirm: two colored panels with
readable labels appear ahead, steering into one applies its labelled effect (squad count, weapon
tier readout via existing behaviour, or formation shape visibly changes), and steering into the gap
between them or past the outer edge applies neither.

- [ ] **Step 4: Commit**

```bash
git add scripts/views/gate_view.gd scenes/game.tscn scripts/game.gd
git commit -m "feat: render gate pairs as grey-box panels with effect labels"
```

---

## Summary

After all seven tasks: `Gate`, `GatePair`, `Gates`, and `TrackGenerator`'s gate-spawning additions
are fully unit-tested pure logic; `Game` wires them into the real per-frame loop and restart cycle,
verified by an integration test that reaches `Squad` through the actual `_process()` path; `GateView`
renders them as grey-box panels. Real art, hazards, and audio remain deferred per the design doc's
build order.
