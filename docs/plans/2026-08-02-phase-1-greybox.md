# Holdout Phase 1 — Grey-Box Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable untextured desktop build of Holdout — aim, auto-fire, three barricade sections, escalating zombie waves — to answer one question: does the shooting feel good?

**Architecture:** Seven pure-logic units with no Godot node dependencies, three view units that only read and draw, and one scene script that wires them together. All game logic runs in **2D on the XZ plane**; only the views know about 3D. Every rule unit is tested headlessly with GUT.

**Tech Stack:** Godot 4.x (latest stable), GDScript, GUT for tests. No addons beyond GUT. No physics engine, no `Area3D`, no `RigidBody3D`.

Source spec: `Repo/Projects/Planner/Holdout/specs/2026-08-02-holdout-design.md`

## Test strength

Added during execution, after reviews of Tasks 1 and 2 found three tests whose names promised
more than their assertions checked — `test_spawns_only_up_to_remaining_headroom` asserting merely
`<= 3`, `test_reset_returns_to_wave_one` checking only the counter and not the replay, and no test
at all covering multiple kills in one `damage_at` call. All three were defects in this plan's test
code, not in anyone's implementation. Every one would have passed against a broken unit.

**A test that a broken implementation would pass is not a test.** For each test written from this
plan, ask what specific wrong implementation it rules out. If the answer is "none", strengthen the
assertion. Where a test guards logic the plan calls load-bearing, verify it bites: deliberately
break the implementation in the way the test is meant to catch, confirm the test fails, restore the
code, and confirm `git diff` on the implementation file comes back empty.

## Global Constraints

- **Logic is 2D.** All positions, velocities and collision use `Vector2`, where `x` is right and `y` is forward (world Z). Views map `Vector2(x, y)` to `Vector3(x, 0, y)`. Nothing in a rule unit may reference a 3D type.
- **No Godot physics anywhere.** No `Area3D`, `RigidBody3D`, `CharacterBody3D`, `PhysicsServer`. Collision is arithmetic over flat arrays.
- **Rule units extend `RefCounted`, never `Node`.** They must be constructible in a test with no scene tree.
- **Views never write.** A view exposes `render(state)` and mutates only its own meshes.
- **Play space:** player at origin. Zombies spawn at radius `30.0`, stop and attack at radius `4.0`. The arc spans angles `-PI/2` (hard left) to `+PI/2` (hard right), where angle `0` is straight ahead. Angle of a point is `atan2(pos.x, pos.y)`.
- **Caps:** 256 concurrent zombies, 512 concurrent projectiles. Fixed-size arrays, swap-remove, zero allocation in the hot path.
- **Godot version is pinned, not assumed.** Whatever version Task 0 installs gets written into the repo's `CLAUDE.md`, and every later task reads it from there.
- **No art, no audio, no Android in this phase.** Capsules and boxes only.

---

### Task 0: Repository, engine, and a test harness that runs

**Files:**
- Create: `Holdout/project.godot`
- Create: `Holdout/CLAUDE.md`
- Create: `Holdout/.gitignore`
- Create: `Holdout/test/test_harness.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: a Godot project where `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit` runs and reports passing tests. Every later task depends on this command working.

- [ ] **Step 1: Install Godot and record the exact version**

Download the latest stable Godot 4.x **Standard** build (not .NET — this project uses GDScript only) from https://godotengine.org/download/windows/ and unzip it to `C:\Users\aslam\Tools\Godot\`.

Then capture the version — this exact string goes into `CLAUDE.md` in Step 4 and must not be guessed:

```powershell
& "C:\Users\aslam\Tools\Godot\Godot_v4.x-stable_win64.exe" --version
```

- [ ] **Step 2: Create the GitHub repo and clone it**

```bash
gh repo create aslamfq/Holdout --private --clone
```

If `gh` is not installed, create the repo through the GitHub MCP server's `create_repository` tool instead, then:

```bash
git clone https://github.com/aslamfq/Holdout.git "C:/Users/aslam/Documents/Repo/Projects/Holdout"
```

- [ ] **Step 3: Create the Godot project file**

Create `Holdout/project.godot`:

```ini
config_version=5

[application]

config/name="Holdout"
run/main_scene="res://scenes/game.tscn"
config/features=PackedStringArray("4.4", "Forward Plus")

[display]

window/size/viewport_width=1080
window/size/viewport_height=1920
window/stretch/mode="canvas_items"
window/handheld/orientation=1

[rendering]

renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

Set `config/features` to the actual major.minor from Step 1. `rendering_method="mobile"` is set now, not later, so desktop rendering matches what Android will do and phase 3's profiling is not measuring a different renderer.

- [ ] **Step 4: Write the repo CLAUDE.md**

Create `Holdout/CLAUDE.md`, substituting the real version from Step 1:

```markdown
@../../CLAUDE.md

# Holdout

Fixed-position endless horde-defense game. Godot 4, GDScript, Android target.

Design spec: `../Planner/Holdout/specs/2026-08-02-holdout-design.md`
(move into `docs/specs/` here and delete `Planner/Holdout/` — see the spec's Placement section)

## Engine

Godot **<exact version from Step 1>**, Standard build (not .NET), at
`C:\Users\aslam\Tools\Godot\`. Read this line rather than assuming a version.

## Build/test

Run all tests headlessly:

    godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit

Run the game:

    godot

## Architecture

Rule units in `scripts/` extend `RefCounted` and hold no Godot node references, so
every rule is testable without a scene tree. Views in `scripts/views/` read state and
draw; they never write. All logic is 2D on the XZ plane — `Vector2(x, y)` maps to
`Vector3(x, 0, y)` at render time only.

No Godot physics anywhere: no `Area3D`, no `RigidBody3D`, no `CharacterBody3D`.
Collision is arithmetic over flat arrays.
```

- [ ] **Step 5: Add .gitignore**

Create `Holdout/.gitignore`:

```gitignore
.godot/
.import/
export.cfg
export_presets.cfg
*.translation
android/
```

- [ ] **Step 6: Install GUT without the editor**

The AssetLib route needs the Godot GUI. Download and extract instead, which is scriptable and gives you a pinned version:

```powershell
$release = Invoke-RestMethod "https://api.github.com/repos/bitwes/Gut/releases/latest"
$zipUrl = ($release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1).browser_download_url
if (-not $zipUrl) { $zipUrl = $release.zipball_url }
Invoke-WebRequest $zipUrl -OutFile "$env:TEMP\gut.zip"
Expand-Archive "$env:TEMP\gut.zip" -DestinationPath "$env:TEMP\gut" -Force
```

Find the `addons/gut` directory inside the extracted tree and copy it to `Holdout/addons/gut`. Record the release tag in `CLAUDE.md` next to the Godot version.

**Enabling the plugin is not required for headless test runs.** `gut_cmdln.gd` runs standalone, so the command-line suite works from the extracted files alone. Enable the plugin in Project Settings → Plugins only if you want the editor's GUT panel.

GUT's base class name changed across versions. Confirm which applies before writing any test — check whether `addons/gut/test.gd` declares `class_name GutTest`:

```powershell
Select-String -Path "Holdout\addons\gut\test.gd" -Pattern "class_name"
```

If it declares `GutTest`, use `extends GutTest`. If not, use `extends "res://addons/gut/test.gd"`. Use the same form in every later task, and record which one in `CLAUDE.md`.

- [ ] **Step 7: Write a harness test that proves the runner works**

Create `Holdout/test/test_harness.gd`:

```gdscript
extends GutTest

func test_harness_runs():
    assert_eq(2 + 2, 4, "arithmetic works, so GUT is wired up correctly")
```

- [ ] **Step 8: Run it and confirm it passes**

Run:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Expected: 1 test, 1 passing, 0 failing, exit code 0.

If the runner cannot find `gut_cmdln.gd`, the addon path differs in your GUT version — locate the actual command-line script under `addons/gut/` and record the corrected command in `CLAUDE.md`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold Godot project with GUT test harness"
```

---

### Task 1: Horde

The zombie population. Flat parallel arrays with swap-remove, so no allocation happens while the game runs.

**Files:**
- Create: `Holdout/scripts/horde.gd`
- Test: `Holdout/test/test_horde.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Horde.MAX_ZOMBIES: int` = 256
  - `Horde.new() -> Horde`
  - `horde.count: int` — living zombies occupy indices `[0, count)`
  - `horde.positions: PackedVector2Array`, `horde.healths: PackedFloat32Array`, `horde.speeds: PackedFloat32Array`
  - `horde.spawn(pos: Vector2, health: float, speed: float) -> bool`
  - `horde.tick(delta: float, stop_radius: float) -> void`
  - `horde.attackers(stop_radius: float) -> PackedInt32Array`
  - `horde.damage_at(point: Vector2, radius: float, amount: float) -> int`
  - `horde.angle_of(i: int) -> float`
  - `horde.clear() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_horde.gd`:

```gdscript
extends GutTest

var horde: Horde

func before_each():
    horde = Horde.new()

func test_spawn_increases_count():
    assert_true(horde.spawn(Vector2(0, 30), 10.0, 2.0))
    assert_eq(horde.count, 1)

func test_spawn_fails_when_full():
    for i in Horde.MAX_ZOMBIES:
        assert_true(horde.spawn(Vector2(0, 30), 10.0, 2.0))
    assert_false(horde.spawn(Vector2(0, 30), 10.0, 2.0), "cap must be enforced")
    assert_eq(horde.count, Horde.MAX_ZOMBIES)

func test_tick_moves_toward_origin():
    horde.spawn(Vector2(0, 30), 10.0, 2.0)
    horde.tick(1.0, 4.0)
    assert_almost_eq(horde.positions[0].y, 28.0, 0.001)

func test_tick_stops_at_stop_radius():
    horde.spawn(Vector2(0, 5), 10.0, 2.0)
    horde.tick(1.0, 4.0)
    assert_almost_eq(horde.positions[0].length(), 4.0, 0.001,
        "must clamp to the barricade, never walk past it")

func test_attackers_lists_only_those_at_the_barricade():
    horde.spawn(Vector2(0, 30), 10.0, 2.0)   # far
    horde.spawn(Vector2(0, 4), 10.0, 2.0)    # at the barricade
    var at := horde.attackers(4.0)
    assert_eq(at.size(), 1)
    assert_eq(at[0], 1)

func test_damage_at_kills_and_reports():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    var kills := horde.damage_at(Vector2(0, 10), 1.0, 10.0)
    assert_eq(kills, 1)
    assert_eq(horde.count, 0)

func test_damage_at_wounds_without_killing():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    var kills := horde.damage_at(Vector2(0, 10), 1.0, 4.0)
    assert_eq(kills, 0)
    assert_eq(horde.count, 1)
    assert_almost_eq(horde.healths[0], 6.0, 0.001)

func test_damage_at_misses_outside_radius():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    assert_eq(horde.damage_at(Vector2(0, 20), 1.0, 10.0), 0)
    assert_eq(horde.count, 1)

func test_swap_remove_keeps_survivors_intact():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)   # index 0, will die
    horde.spawn(Vector2(5, 5), 10.0, 3.0)    # index 1, must survive intact
    horde.damage_at(Vector2(0, 10), 1.0, 10.0)
    assert_eq(horde.count, 1)
    assert_eq(horde.positions[0], Vector2(5, 5))
    assert_almost_eq(horde.speeds[0], 3.0, 0.001)

func test_angle_of_is_zero_straight_ahead():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    assert_almost_eq(horde.angle_of(0), 0.0, 0.001)

func test_angle_of_is_positive_to_the_right():
    horde.spawn(Vector2(10, 0), 10.0, 2.0)
    assert_almost_eq(horde.angle_of(0), PI / 2.0, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Horde` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/horde.gd`:

```gdscript
class_name Horde extends RefCounted

const MAX_ZOMBIES := 256

var positions := PackedVector2Array()
var healths := PackedFloat32Array()
var speeds := PackedFloat32Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_ZOMBIES)
    healths.resize(MAX_ZOMBIES)
    speeds.resize(MAX_ZOMBIES)

func spawn(pos: Vector2, health: float, speed: float) -> bool:
    if count >= MAX_ZOMBIES:
        return false
    positions[count] = pos
    healths[count] = health
    speeds[count] = speed
    count += 1
    return true

func tick(delta: float, stop_radius: float) -> void:
    for i in count:
        var pos := positions[i]
        var dist := pos.length()
        if dist <= stop_radius:
            continue
        var step: float = min(speeds[i] * delta, dist - stop_radius)
        positions[i] = pos - pos.normalized() * step

func attackers(stop_radius: float) -> PackedInt32Array:
    var result := PackedInt32Array()
    for i in count:
        if positions[i].length() <= stop_radius + 0.001:
            result.append(i)
    return result

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
                continue   # index i now holds a different zombie; re-check it
        i += 1
    return kills

func angle_of(i: int) -> float:
    return atan2(positions[i].x, positions[i].y)

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    healths[i] = healths[last]
    speeds[i] = speeds[last]
    count = last
```

The `continue` after `_remove_at` without incrementing `i` is deliberate: swap-remove moves the last zombie into slot `i`, and that zombie has not been tested yet. Incrementing there would silently skip it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Horde tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/horde.gd test/test_horde.gd
git commit -m "feat: add Horde with flat-array storage and swap-remove"
```

---

### Task 2: WaveDirector

Decides what spawns and when, and escalates forever. Seeded so a run is reproducible.

**Files:**
- Create: `Holdout/scripts/wave_director.gd`
- Test: `Holdout/test/test_wave_director.gd`

**Interfaces:**
- Consumes: `Horde.MAX_ZOMBIES` (for the concurrency cap).
- Produces:
  - `WaveDirector.SECONDS_PER_WAVE: float` = 20.0
  - `WaveDirector.SPAWN_RADIUS: float` = 30.0
  - `WaveDirector.new(rng_seed: int) -> WaveDirector`
  - `director.wave: int` — starts at 1
  - `director.tick(delta: float, live_count: int) -> PackedVector2Array`
  - `director.zombie_health() -> float`
  - `director.zombie_speed() -> float`
  - `director.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_wave_director.gd`:

```gdscript
extends GutTest

func test_starts_at_wave_one():
    var d := WaveDirector.new(42)
    assert_eq(d.wave, 1)

func test_wave_advances_on_the_timer():
    var d := WaveDirector.new(42)
    d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_eq(d.wave, 2)

func test_spawns_land_on_the_spawn_radius():
    var d := WaveDirector.new(42)
    var spawns := d.tick(5.0, 0)
    assert_gt(spawns.size(), 0, "five seconds must produce at least one spawn")
    for p in spawns:
        assert_almost_eq(p.length(), WaveDirector.SPAWN_RADIUS, 0.001)

func test_spawns_stay_inside_the_frontal_arc():
    var d := WaveDirector.new(42)
    var spawns := d.tick(30.0, 0)
    for p in spawns:
        var angle := atan2(p.x, p.y)
        assert_between(angle, -PI / 2.0, PI / 2.0,
            "nothing may spawn behind the player")

func test_is_deterministic_for_a_given_seed():
    var a := WaveDirector.new(7)
    var b := WaveDirector.new(7)
    for i in 20:
        assert_eq(a.tick(1.0, 0), b.tick(1.0, 0),
            "same seed must produce an identical run")

func test_different_seeds_diverge():
    var a := WaveDirector.new(1)
    var b := WaveDirector.new(2)
    var same := true
    for i in 20:
        if a.tick(1.0, 0) != b.tick(1.0, 0):
            same = false
    assert_false(same, "different seeds must produce different runs")

func test_respects_the_concurrency_cap():
    var d := WaveDirector.new(42)
    var spawns := d.tick(60.0, Horde.MAX_ZOMBIES)
    assert_eq(spawns.size(), 0, "must not spawn past the cap")

func test_spawns_only_up_to_remaining_headroom():
    var d := WaveDirector.new(42)
    var spawns := d.tick(60.0, Horde.MAX_ZOMBIES - 3)
    assert_lte(spawns.size(), 3)

func test_difficulty_escalates():
    var d := WaveDirector.new(42)
    var early_health := d.zombie_health()
    var early_speed := d.zombie_speed()
    for i in 10:
        d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_gt(d.zombie_health(), early_health, "later waves must be tougher")
    assert_gt(d.zombie_speed(), early_speed, "later waves must be faster")

func test_speed_plateaus_so_it_stays_playable():
    var d := WaveDirector.new(42)
    for i in 500:
        d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_lte(d.zombie_speed(), 8.0,
        "speed must converge, or late waves become unreadable")

func test_reset_returns_to_wave_one():
    var d := WaveDirector.new(42)
    d.tick(100.0, 0)
    d.reset()
    assert_eq(d.wave, 1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `WaveDirector` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/wave_director.gd`:

```gdscript
class_name WaveDirector extends RefCounted

const SECONDS_PER_WAVE := 20.0
const SPAWN_RADIUS := 30.0

const BASE_SPAWN_INTERVAL := 1.2
const MIN_SPAWN_INTERVAL := 0.12
const BASE_HEALTH := 10.0
const HEALTH_PER_WAVE := 3.0
const BASE_SPEED := 1.8
const MAX_SPEED := 6.0
const SPEED_APPROACH := 0.12

var wave := 1

var _rng := RandomNumberGenerator.new()
var _seed: int
var _wave_clock := 0.0
var _spawn_clock := 0.0

func _init(rng_seed: int) -> void:
    _seed = rng_seed
    _rng.seed = rng_seed

func tick(delta: float, live_count: int) -> PackedVector2Array:
    _wave_clock += delta
    while _wave_clock >= SECONDS_PER_WAVE:
        _wave_clock -= SECONDS_PER_WAVE
        wave += 1

    var spawns := PackedVector2Array()
    var headroom := Horde.MAX_ZOMBIES - live_count
    var interval := _spawn_interval()

    _spawn_clock += delta
    while _spawn_clock >= interval:
        _spawn_clock -= interval
        if spawns.size() >= headroom:
            continue
        var angle := _rng.randf_range(-PI / 2.0, PI / 2.0)
        spawns.append(Vector2(sin(angle), cos(angle)) * SPAWN_RADIUS)
    return spawns

func zombie_health() -> float:
    return BASE_HEALTH + HEALTH_PER_WAVE * float(wave - 1)

func zombie_speed() -> float:
    # Approaches MAX_SPEED asymptotically and never exceeds it, so late waves
    # get denser rather than unreadably fast.
    var t := 1.0 - exp(-SPEED_APPROACH * float(wave - 1))
    return BASE_SPEED + (MAX_SPEED - BASE_SPEED) * t

func reset() -> void:
    wave = 1
    _wave_clock = 0.0
    _spawn_clock = 0.0
    _rng.seed = _seed

func _spawn_interval() -> float:
    var scaled := BASE_SPAWN_INTERVAL * pow(0.93, float(wave - 1))
    return max(scaled, MIN_SPAWN_INTERVAL)
```

The `continue` inside the spawn loop rather than `break` matters: the clock still drains at the capped rate, so a run that sits at the cap does not bank spawn credit and then dump it the instant space appears.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all WaveDirector tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/wave_director.gd test/test_wave_director.gd
git commit -m "feat: add seeded WaveDirector with plateauing difficulty"
```

---

### Task 3: BarricadeSet

Three independent sections. This is what makes threat direction matter.

**Files:**
- Create: `Holdout/scripts/barricade_set.gd`
- Test: `Holdout/test/test_barricade_set.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `BarricadeSet.Section` enum: `LEFT = 0`, `CENTRE = 1`, `RIGHT = 2`
  - `BarricadeSet.SECTION_MAX_HEALTH: float` = 100.0
  - `BarricadeSet.RADIUS: float` = 4.0
  - `BarricadeSet.section_for_angle(angle: float) -> int` (static)
  - `BarricadeSet.new() -> BarricadeSet`
  - `barricades.healths: PackedFloat32Array` — size 3
  - `barricades.damage(section: int, amount: float) -> void`
  - `barricades.is_broken() -> bool`
  - `barricades.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_barricade_set.gd`:

```gdscript
extends GutTest

var barricades: BarricadeSet

func before_each():
    barricades = BarricadeSet.new()

func test_starts_at_full_health():
    for i in 3:
        assert_almost_eq(barricades.healths[i], BarricadeSet.SECTION_MAX_HEALTH, 0.001)

func test_straight_ahead_is_centre():
    assert_eq(BarricadeSet.section_for_angle(0.0), BarricadeSet.Section.CENTRE)

func test_hard_left_is_left():
    assert_eq(BarricadeSet.section_for_angle(-PI / 2.0), BarricadeSet.Section.LEFT)

func test_hard_right_is_right():
    assert_eq(BarricadeSet.section_for_angle(PI / 2.0), BarricadeSet.Section.RIGHT)

func test_boundaries_land_predictably():
    assert_eq(BarricadeSet.section_for_angle(-PI / 5.0), BarricadeSet.Section.LEFT)
    assert_eq(BarricadeSet.section_for_angle(-PI / 7.0), BarricadeSet.Section.CENTRE)
    assert_eq(BarricadeSet.section_for_angle(PI / 7.0), BarricadeSet.Section.CENTRE)
    assert_eq(BarricadeSet.section_for_angle(PI / 5.0), BarricadeSet.Section.RIGHT)

func test_damage_affects_only_its_own_section():
    barricades.damage(BarricadeSet.Section.LEFT, 30.0)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.LEFT], 70.0, 0.001)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.CENTRE],
        BarricadeSet.SECTION_MAX_HEALTH, 0.001)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.RIGHT],
        BarricadeSet.SECTION_MAX_HEALTH, 0.001)

func test_health_floors_at_zero():
    barricades.damage(BarricadeSet.Section.CENTRE, 500.0)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.CENTRE], 0.0, 0.001)

func test_intact_set_is_not_broken():
    barricades.damage(BarricadeSet.Section.LEFT, 99.0)
    assert_false(barricades.is_broken())

func test_any_single_section_falling_ends_the_run():
    barricades.damage(BarricadeSet.Section.RIGHT, BarricadeSet.SECTION_MAX_HEALTH)
    assert_true(barricades.is_broken(),
        "one section is enough — the run ends on the first breach")

func test_reset_restores_every_section():
    barricades.damage(BarricadeSet.Section.LEFT, 500.0)
    barricades.reset()
    assert_false(barricades.is_broken())
    for i in 3:
        assert_almost_eq(barricades.healths[i], BarricadeSet.SECTION_MAX_HEALTH, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `BarricadeSet` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/barricade_set.gd`:

```gdscript
class_name BarricadeSet extends RefCounted

enum Section { LEFT = 0, CENTRE = 1, RIGHT = 2 }

const SECTION_MAX_HEALTH := 100.0
const RADIUS := 4.0
const CENTRE_HALF_WIDTH := PI / 6.0   # three equal 60-degree sections across 180

var healths := PackedFloat32Array()

func _init() -> void:
    healths.resize(3)
    reset()

static func section_for_angle(angle: float) -> int:
    if angle < -CENTRE_HALF_WIDTH:
        return Section.LEFT
    if angle > CENTRE_HALF_WIDTH:
        return Section.RIGHT
    return Section.CENTRE

func damage(section: int, amount: float) -> void:
    healths[section] = max(healths[section] - amount, 0.0)

func is_broken() -> bool:
    for i in 3:
        if healths[i] <= 0.0:
            return true
    return false

func reset() -> void:
    for i in 3:
        healths[i] = SECTION_MAX_HEALTH
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all BarricadeSet tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/barricade_set.gd test/test_barricade_set.gd
git commit -m "feat: add BarricadeSet with three independent sections"
```

---

### Task 4: Weapon

Turns elapsed time into a number of shots. Accumulator-based so the fire rate is identical at 30fps and 144fps.

**Files:**
- Create: `Holdout/scripts/weapon.gd`
- Test: `Holdout/test/test_weapon.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Weapon.new() -> Weapon`
  - `weapon.fire_interval: float` = 0.12
  - `weapon.damage: float` = 5.0
  - `weapon.projectile_speed: float` = 45.0
  - `weapon.tick(delta: float) -> int`
  - `weapon.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_weapon.gd`:

```gdscript
extends GutTest

var weapon: Weapon

func before_each():
    weapon = Weapon.new()

func test_no_shots_before_the_interval_elapses():
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 0)

func test_one_shot_per_interval():
    assert_eq(weapon.tick(weapon.fire_interval), 1)

func test_a_long_frame_fires_the_whole_backlog():
    assert_eq(weapon.tick(weapon.fire_interval * 3.0), 3,
        "a stutter must not silently swallow shots")

func test_remainder_carries_into_the_next_frame():
    weapon.tick(weapon.fire_interval * 0.75)
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 1,
        "0.75 + 0.5 = 1.25 intervals, so exactly one shot")

func test_rate_is_frame_independent():
    var coarse := Weapon.new()
    var fine := Weapon.new()
    var coarse_shots := 0
    var fine_shots := 0
    for i in 60:
        coarse_shots += coarse.tick(1.0 / 60.0)
    for i in 240:
        fine_shots += fine.tick(1.0 / 240.0)
    assert_eq(coarse_shots, fine_shots,
        "one second of fire must be the same at any frame rate")

func test_reset_clears_the_accumulator():
    weapon.tick(weapon.fire_interval * 0.9)
    weapon.reset()
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Weapon` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/weapon.gd`:

```gdscript
class_name Weapon extends RefCounted

var fire_interval := 0.12
var damage := 5.0
var projectile_speed := 45.0

var _accumulator := 0.0

func tick(delta: float) -> int:
    _accumulator += delta
    var shots := int(_accumulator / fire_interval)
    _accumulator -= float(shots) * fire_interval
    return shots

func reset() -> void:
    _accumulator = 0.0
```

`fire_interval` and `damage` are plain variables rather than constants because phase 3's `UpgradeDraft` writes to them. Nothing else may.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Weapon tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapon.gd test/test_weapon.gd
git commit -m "feat: add Weapon with frame-rate-independent fire rate"
```

---

### Task 5: Projectiles

Pooled bullets and the hit resolution against the horde.

**Collision is deliberately naive here** — a nested loop over live projectiles and live zombies. The spec's radial-bucket broadphase belongs to phase 3, after profiling proves it is needed. Building it now would be optimising before measuring. The signature of `resolve_hits` will not change when the broadphase replaces the inner loop, and the tests written here will guard that replacement.

**Files:**
- Create: `Holdout/scripts/projectiles.gd`
- Test: `Holdout/test/test_projectiles.gd`

**Interfaces:**
- Consumes: `Horde` (Task 1).
- Produces:
  - `Projectiles.MAX_PROJECTILES: int` = 512
  - `Projectiles.new() -> Projectiles`
  - `projectiles.count: int`
  - `projectiles.positions: PackedVector2Array`
  - `projectiles.fire(origin: Vector2, direction: Vector2, speed: float) -> bool`
  - `projectiles.tick(delta: float, despawn_radius: float) -> void`
  - `projectiles.resolve_hits(horde: Horde, hit_radius: float, damage: float) -> int`
  - `projectiles.clear() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_projectiles.gd`:

```gdscript
extends GutTest

var projectiles: Projectiles
var horde: Horde

func before_each():
    projectiles = Projectiles.new()
    horde = Horde.new()

func test_fire_increases_count():
    assert_true(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0))
    assert_eq(projectiles.count, 1)

func test_fire_fails_when_pool_is_full():
    for i in Projectiles.MAX_PROJECTILES:
        assert_true(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0))
    assert_false(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0))

func test_direction_is_normalised_before_use():
    projectiles.fire(Vector2.ZERO, Vector2(0, 5), 10.0)
    projectiles.tick(1.0, 100.0)
    assert_almost_eq(projectiles.positions[0].y, 10.0, 0.001,
        "an unnormalised direction must not multiply the speed")

func test_tick_moves_along_the_velocity():
    projectiles.fire(Vector2.ZERO, Vector2(1, 0), 10.0)
    projectiles.tick(0.5, 100.0)
    assert_almost_eq(projectiles.positions[0].x, 5.0, 0.001)

func test_projectiles_despawn_past_the_radius():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0, "bullets must not accumulate off-screen forever")

func test_hit_damages_the_zombie_and_consumes_the_bullet():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    var kills := projectiles.resolve_hits(horde, 0.5, 4.0)
    assert_eq(kills, 0)
    assert_eq(projectiles.count, 0, "the bullet is spent")
    assert_almost_eq(horde.healths[0], 6.0, 0.001)

func test_a_lethal_hit_is_reported_as_a_kill():
    horde.spawn(Vector2(0, 10), 4.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 0.5, 4.0), 1)
    assert_eq(horde.count, 0)

func test_a_miss_leaves_both_sides_alone():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    projectiles.fire(Vector2(20, 0), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 0.5, 4.0), 0)
    assert_eq(projectiles.count, 1)
    assert_eq(horde.count, 1)

func test_one_bullet_hits_only_one_zombie():
    horde.spawn(Vector2(0, 10), 4.0, 2.0)
    horde.spawn(Vector2(0.1, 10), 4.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 1.0, 4.0), 1,
        "no accidental piercing — that is an upgrade, not a default")
    assert_eq(horde.count, 1)

func test_clear_empties_the_pool():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0)
    projectiles.clear()
    assert_eq(projectiles.count, 0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `Projectiles` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/projectiles.gd`:

```gdscript
class_name Projectiles extends RefCounted

const MAX_PROJECTILES := 512

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_PROJECTILES)
    velocities.resize(MAX_PROJECTILES)

func fire(origin: Vector2, direction: Vector2, speed: float) -> bool:
    if count >= MAX_PROJECTILES:
        return false
    positions[count] = origin
    velocities[count] = direction.normalized() * speed
    count += 1
    return true

func tick(delta: float, despawn_radius: float) -> void:
    var radius_sq := despawn_radius * despawn_radius
    var i := 0
    while i < count:
        positions[i] += velocities[i] * delta
        if positions[i].length_squared() > radius_sq:
            _remove_at(i)
            continue
        i += 1

# Naive nested loop by design. Phase 3 replaces the inner scan with a radial
# broadphase behind this same signature, guarded by these tests.
func resolve_hits(horde: Horde, hit_radius: float, damage: float) -> int:
    var kills := 0
    var radius_sq := hit_radius * hit_radius
    var i := 0
    while i < count:
        var hit_index := -1
        for j in horde.count:
            if positions[i].distance_squared_to(horde.positions[j]) <= radius_sq:
                hit_index = j
                break
        if hit_index >= 0:
            kills += horde.damage_at(horde.positions[hit_index], 0.001, damage)
            _remove_at(i)
            continue
        i += 1
    return kills

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    velocities[i] = velocities[last]
    count = last
```

`damage_at` is called with a near-zero radius at the struck zombie's exact position, so a bullet damages precisely one zombie. Widening that radius is how a splash-damage upgrade will work in phase 3.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all Projectiles tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/projectiles.gd test/test_projectiles.gd
git commit -m "feat: add pooled Projectiles with naive hit resolution"
```

---

### Task 6: AimInput

Turns a screen drag into a smoothed aim vector, clamped to the frontal arc. This is the entire skill layer, so it lives alone and gets tuned alone.

**Files:**
- Create: `Holdout/scripts/aim_input.gd`
- Test: `Holdout/test/test_aim_input.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `AimInput.SMOOTHING: float` = 14.0
  - `AimInput.MAX_ANGLE: float` = `PI / 2.0`
  - `AimInput.new() -> AimInput`
  - `aim_input.aim: Vector2` — unit vector, starts at `Vector2(0, 1)`
  - `aim_input.aim_at_screen_delta(delta_pixels: Vector2) -> void`
  - `aim_input.tick(delta: float) -> void`
  - `aim_input.reset() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_aim_input.gd`:

```gdscript
extends GutTest

var aim_input: AimInput

func before_each():
    aim_input = AimInput.new()

func test_starts_pointing_straight_ahead():
    assert_almost_eq(aim_input.aim.x, 0.0, 0.001)
    assert_almost_eq(aim_input.aim.y, 1.0, 0.001)

func test_aim_stays_a_unit_vector():
    aim_input.aim_at_screen_delta(Vector2(300, 0))
    for i in 60:
        aim_input.tick(1.0 / 60.0)
    assert_almost_eq(aim_input.aim.length(), 1.0, 0.001)

func test_dragging_right_aims_right():
    aim_input.aim_at_screen_delta(Vector2(200, 0))
    for i in 120:
        aim_input.tick(1.0 / 60.0)
    assert_gt(aim_input.aim.x, 0.0)

func test_dragging_left_aims_left():
    aim_input.aim_at_screen_delta(Vector2(-200, 0))
    for i in 120:
        aim_input.tick(1.0 / 60.0)
    assert_lt(aim_input.aim.x, 0.0)

func test_aim_never_leaves_the_frontal_arc():
    aim_input.aim_at_screen_delta(Vector2(100000, 0))
    for i in 300:
        aim_input.tick(1.0 / 60.0)
    var angle := atan2(aim_input.aim.x, aim_input.aim.y)
    assert_lte(angle, AimInput.MAX_ANGLE + 0.001,
        "the player must never aim behind themselves")

func test_aim_is_smoothed_not_instant():
    aim_input.aim_at_screen_delta(Vector2(400, 0))
    aim_input.tick(1.0 / 60.0)
    var angle := atan2(aim_input.aim.x, aim_input.aim.y)
    assert_lt(angle, AimInput.MAX_ANGLE * 0.9,
        "one frame must not snap all the way across")

func test_aim_converges_on_the_target():
    aim_input.aim_at_screen_delta(Vector2(150, 0))
    for i in 300:
        aim_input.tick(1.0 / 60.0)
    var settled := aim_input.aim
    aim_input.tick(1.0 / 60.0)
    assert_almost_eq(aim_input.aim.x, settled.x, 0.001, "it must settle, not drift")

func test_reset_returns_to_forward():
    aim_input.aim_at_screen_delta(Vector2(200, 0))
    for i in 60:
        aim_input.tick(1.0 / 60.0)
    aim_input.reset()
    assert_almost_eq(aim_input.aim.y, 1.0, 0.001)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `AimInput` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/aim_input.gd`:

```gdscript
class_name AimInput extends RefCounted

const SMOOTHING := 14.0
const MAX_ANGLE := PI / 2.0
const PIXELS_PER_RADIAN := 320.0

var aim := Vector2(0, 1)

var _target_angle := 0.0
var _angle := 0.0

func aim_at_screen_delta(delta_pixels: Vector2) -> void:
    _target_angle = clamp(delta_pixels.x / PIXELS_PER_RADIAN, -MAX_ANGLE, MAX_ANGLE)

func tick(delta: float) -> void:
    # Exponential smoothing, frame-rate independent.
    var t: float = 1.0 - exp(-SMOOTHING * delta)
    _angle += (_target_angle - _angle) * t
    aim = Vector2(sin(_angle), cos(_angle))

func reset() -> void:
    _angle = 0.0
    _target_angle = 0.0
    aim = Vector2(0, 1)
```

Smoothing uses `1 - exp(-k*dt)` rather than a raw `lerp(a, b, k*dt)`, because the raw form changes feel with frame rate and can overshoot on a long frame. Aim feel is the thing this whole phase exists to evaluate, so it must not vary with the machine it runs on.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all AimInput tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/aim_input.gd test/test_aim_input.gd
git commit -m "feat: add AimInput with frame-independent smoothing and arc clamp"
```

---

### Task 7: RunState

Wave counter, kills, run end, and best-wave persistence.

**No XP here.** XP and level thresholds arrive with `UpgradeDraft` in phase 3. Adding them now would mean tuning a progression curve against shooting that has not been proven yet.

**Files:**
- Create: `Holdout/scripts/run_state.gd`
- Test: `Holdout/test/test_run_state.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `RunState.SAVE_PATH: String` = `"user://holdout.cfg"`
  - `RunState.new() -> RunState`
  - `run_state.wave: int`, `run_state.kills: int`, `run_state.elapsed: float`
  - `run_state.best_wave: int`
  - `run_state.is_over: bool`
  - `run_state.tick(delta: float, current_wave: int) -> void`
  - `run_state.record_kills(n: int) -> void`
  - `run_state.end_run() -> void`
  - `run_state.reset() -> void`
  - `run_state.save_best() -> void`
  - `run_state.load_best() -> void`

- [ ] **Step 1: Write the failing tests**

Create `Holdout/test/test_run_state.gd`:

```gdscript
extends GutTest

var run_state: RunState

func before_each():
    run_state = RunState.new()

func after_all():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func test_starts_empty_and_live():
    assert_eq(run_state.kills, 0)
    assert_eq(run_state.wave, 1)
    assert_false(run_state.is_over)

func test_tick_accumulates_elapsed_time():
    run_state.tick(0.5, 1)
    run_state.tick(0.25, 1)
    assert_almost_eq(run_state.elapsed, 0.75, 0.001)

func test_tick_mirrors_the_directors_wave():
    run_state.tick(0.1, 7)
    assert_eq(run_state.wave, 7)

func test_kills_accumulate():
    run_state.record_kills(3)
    run_state.record_kills(2)
    assert_eq(run_state.kills, 5)

func test_end_run_marks_it_over():
    run_state.end_run()
    assert_true(run_state.is_over)

func test_end_run_promotes_a_new_best():
    run_state.tick(0.1, 9)
    run_state.end_run()
    assert_eq(run_state.best_wave, 9)

func test_end_run_does_not_demote_an_existing_best():
    run_state.best_wave = 20
    run_state.tick(0.1, 3)
    run_state.end_run()
    assert_eq(run_state.best_wave, 20, "a bad run must never erase a good one")

func test_reset_clears_the_run_but_keeps_the_best():
    run_state.tick(0.1, 9)
    run_state.record_kills(5)
    run_state.end_run()
    run_state.reset()
    assert_eq(run_state.kills, 0)
    assert_eq(run_state.wave, 1)
    assert_almost_eq(run_state.elapsed, 0.0, 0.001)
    assert_false(run_state.is_over)
    assert_eq(run_state.best_wave, 9)

func test_best_wave_survives_a_save_and_load():
    run_state.tick(0.1, 12)
    run_state.end_run()
    run_state.save_best()

    var reloaded := RunState.new()
    reloaded.load_best()
    assert_eq(reloaded.best_wave, 12)

func test_load_without_a_save_file_is_harmless():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
    var fresh := RunState.new()
    fresh.load_best()
    assert_eq(fresh.best_wave, 0, "a first launch must not crash or corrupt")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `RunState` is not a known class.

- [ ] **Step 3: Write the implementation**

Create `Holdout/scripts/run_state.gd`:

```gdscript
class_name RunState extends RefCounted

const SAVE_PATH := "user://holdout.cfg"

var wave := 1
var kills := 0
var elapsed := 0.0
var best_wave := 0
var is_over := false

func tick(delta: float, current_wave: int) -> void:
    elapsed += delta
    wave = current_wave

func record_kills(n: int) -> void:
    kills += n

func end_run() -> void:
    is_over = true
    if wave > best_wave:
        best_wave = wave

func reset() -> void:
    wave = 1
    kills = 0
    elapsed = 0.0
    is_over = false

func save_best() -> void:
    var config := ConfigFile.new()
    config.set_value("progress", "best_wave", best_wave)
    config.save(SAVE_PATH)

func load_best() -> void:
    var config := ConfigFile.new()
    if config.load(SAVE_PATH) != OK:
        best_wave = 0
        return
    best_wave = config.get_value("progress", "best_wave", 0)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: all RunState tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_state.gd test/test_run_state.gd
git commit -m "feat: add RunState with best-wave persistence"
```

---

### Task 8: Views

Three read-only renderers. They have no tests — they contain no rules, and asserting on transform buffers would test Godot rather than the game. Everything worth testing already lives in Tasks 1–7.

**Files:**
- Create: `Holdout/scripts/views/horde_view.gd`
- Create: `Holdout/scripts/views/projectile_view.gd`
- Create: `Holdout/scripts/views/barricade_view.gd`

**Interfaces:**
- Consumes: `Horde`, `Projectiles`, `BarricadeSet`.
- Produces:
  - `HordeView.render(horde: Horde, time: float) -> void`
  - `ProjectileView.render(projectiles: Projectiles) -> void`
  - `BarricadeView.render(barricades: BarricadeSet) -> void`

- [ ] **Step 1: Write HordeView**

Create `Holdout/scripts/views/horde_view.gd`:

```gdscript
class_name HordeView extends MultiMeshInstance3D

const BOB_HEIGHT := 0.12
const BOB_SPEED := 9.0

func _ready() -> void:
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.25
    mesh.height = 1.4

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Horde.MAX_ZOMBIES
    multimesh.visible_instance_count = 0

func render(horde: Horde, time: float) -> void:
    multimesh.visible_instance_count = horde.count
    for i in horde.count:
        var pos := horde.positions[i]
        # Phase offset per index so the crowd does not bob in lockstep.
        var bob: float = sin(time * BOB_SPEED + float(i) * 0.7) * BOB_HEIGHT
        var basis := Basis().rotated(Vector3.UP, atan2(pos.x, pos.y))
        multimesh.set_instance_transform(i,
            Transform3D(basis, Vector3(pos.x, 0.7 + bob, pos.y)))
```

- [ ] **Step 2: Write ProjectileView**

Create `Holdout/scripts/views/projectile_view.gd`:

```gdscript
class_name ProjectileView extends MultiMeshInstance3D

func _ready() -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 0.08
    mesh.height = 0.16

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Projectiles.MAX_PROJECTILES
    multimesh.visible_instance_count = 0

func render(projectiles: Projectiles) -> void:
    multimesh.visible_instance_count = projectiles.count
    for i in projectiles.count:
        var pos := projectiles.positions[i]
        multimesh.set_instance_transform(i,
            Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))
```

- [ ] **Step 3: Write BarricadeView**

Create `Holdout/scripts/views/barricade_view.gd`:

```gdscript
class_name BarricadeView extends Node3D

const SECTION_ANGLES := [-PI / 3.0, 0.0, PI / 3.0]

var _sections: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(3.4, 1.0, 0.4)

    for i in 3:
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.6, 0.6, 0.6)

        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = material

        var angle: float = SECTION_ANGLES[i]
        var pos := Vector2(sin(angle), cos(angle)) * BarricadeSet.RADIUS
        instance.transform = Transform3D(
            Basis().rotated(Vector3.UP, angle),
            Vector3(pos.x, 0.5, pos.y))

        add_child(instance)
        _sections.append(instance)
        _materials.append(material)

func render(barricades: BarricadeSet) -> void:
    for i in 3:
        var ratio: float = barricades.healths[i] / BarricadeSet.SECTION_MAX_HEALTH
        # Grey-box damage readout: sinks into the ground as it is chewed away.
        var instance := _sections[i]
        var pos := instance.position
        pos.y = 0.5 - (1.0 - ratio) * 0.5
        instance.position = pos
        _materials[i].albedo_color = Color(0.6, 0.6, 0.6).lerp(
            Color(0.25, 0.25, 0.25), 1.0 - ratio)
```

- [ ] **Step 4: Verify the whole suite still passes**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: every test from Tasks 1–7 still PASSES. Adding views must not have touched any rule.

- [ ] **Step 5: Commit**

```bash
git add scripts/views/
git commit -m "feat: add MultiMesh views for horde, projectiles and barricades"
```

---

### Task 9: Wire it into a playable game

The scene script that owns every unit and drives them each frame. Also the point at which you finally answer the question this whole phase exists to answer.

**Files:**
- Create: `Holdout/scripts/game.gd`
- Create: `Holdout/scenes/game.tscn`
- Test: `Holdout/test/test_game_integration.gd`

**Interfaces:**
- Consumes: every unit from Tasks 1–8.
- Produces: a running game.

- [ ] **Step 1: Write the failing integration test**

This test drives the same rule units the scene drives, with no scene tree, and proves the loop holds together end to end.

Create `Holdout/test/test_game_integration.gd`:

```gdscript
extends GutTest

# Mirrors game.gd's _process ordering, without a scene tree.
func _simulate(seconds: float, step: float) -> Dictionary:
    var horde := Horde.new()
    var director := WaveDirector.new(42)
    var barricades := BarricadeSet.new()
    var weapon := Weapon.new()
    var projectiles := Projectiles.new()
    var aim := AimInput.new()
    var run := RunState.new()

    var elapsed := 0.0
    while elapsed < seconds and not run.is_over:
        for pos in director.tick(step, horde.count):
            horde.spawn(pos, director.zombie_health(), director.zombie_speed())

        aim.tick(step)
        horde.tick(step, BarricadeSet.RADIUS)

        for _shot in weapon.tick(step):
            projectiles.fire(Vector2.ZERO, aim.aim, weapon.projectile_speed)

        projectiles.tick(step, WaveDirector.SPAWN_RADIUS + 5.0)
        run.record_kills(projectiles.resolve_hits(horde, 0.45, weapon.damage))

        for i in horde.attackers(BarricadeSet.RADIUS):
            barricades.damage(BarricadeSet.section_for_angle(horde.angle_of(i)), 6.0 * step)

        run.tick(step, director.wave)
        if barricades.is_broken():
            run.end_run()
        elapsed += step

    return {"horde": horde, "run": run, "barricades": barricades}

# Long simulations use a 1/30 step, not 1/60. Task 5's hit resolution is a
# naive nested loop, so a 300-second run at 1/60 is roughly 18,000 frames of
# O(bullets x zombies) work and turns the suite into something nobody runs.
# These tests assert invariants, which a coarser step preserves.
const LONG_STEP := 1.0 / 30.0
const FRAME_STEP := 1.0 / 60.0

func test_a_run_ends_when_the_barricade_falls():
    var result := _simulate(300.0, LONG_STEP)
    assert_true(result["run"].is_over,
        "an idle player must eventually be overrun")

func test_the_player_kills_things_while_holding_still():
    var result := _simulate(30.0, FRAME_STEP)
    assert_gt(result["run"].kills, 0, "forward fire must connect")

func test_the_zombie_cap_is_never_exceeded():
    var result := _simulate(300.0, LONG_STEP)
    assert_lte(result["horde"].count, Horde.MAX_ZOMBIES)

func test_zombies_never_walk_through_the_barricade():
    var result := _simulate(120.0, LONG_STEP)
    var horde: Horde = result["horde"]
    for i in horde.count:
        assert_gte(horde.positions[i].length(), BarricadeSet.RADIUS - 0.01)

func test_a_run_survives_the_first_wave():
    var result := _simulate(20.0, FRAME_STEP)
    assert_false(result["run"].is_over,
        "wave 1 must not kill an idle player, or the opening is unplayably harsh")

func test_the_simulation_is_reproducible():
    var a := _simulate(60.0, FRAME_STEP)
    var b := _simulate(60.0, FRAME_STEP)
    assert_eq(a["run"].kills, b["run"].kills)
    assert_eq(a["run"].wave, b["run"].wave)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: FAIL — `game.gd` does not exist yet, though note these tests reference only Tasks 1–7, so they may fail on assertions rather than on missing classes. Either way they must be red before Step 3.

- [ ] **Step 3: Write the game script**

Create `Holdout/scripts/game.gd`:

```gdscript
extends Node3D

const HIT_RADIUS := 0.45
const ZOMBIE_DPS := 6.0
const DESPAWN_MARGIN := 5.0

@onready var horde_view: HordeView = $HordeView
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var barricade_view: BarricadeView = $BarricadeView
@onready var hud: Label = $HUD/WaveLabel

var horde: Horde
var director: WaveDirector
var barricades: BarricadeSet
var weapon: Weapon
var projectiles: Projectiles
var aim: AimInput
var run: RunState

var _dragging := false
var _drag_origin := Vector2.ZERO
var _time := 0.0

func _ready() -> void:
    horde = Horde.new()
    director = WaveDirector.new(randi())
    barricades = BarricadeSet.new()
    weapon = Weapon.new()
    projectiles = Projectiles.new()
    aim = AimInput.new()
    run = RunState.new()
    run.load_best()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        aim.aim_at_screen_delta(event.position - _drag_origin)

func _process(delta: float) -> void:
    _time += delta

    for pos in director.tick(delta, horde.count):
        horde.spawn(pos, director.zombie_health(), director.zombie_speed())

    aim.tick(delta)
    horde.tick(delta, BarricadeSet.RADIUS)

    for _shot in weapon.tick(delta):
        projectiles.fire(Vector2.ZERO, aim.aim, weapon.projectile_speed)

    projectiles.tick(delta, WaveDirector.SPAWN_RADIUS + DESPAWN_MARGIN)
    run.record_kills(projectiles.resolve_hits(horde, HIT_RADIUS, weapon.damage))

    for i in horde.attackers(BarricadeSet.RADIUS):
        barricades.damage(BarricadeSet.section_for_angle(horde.angle_of(i)), ZOMBIE_DPS * delta)

    run.tick(delta, director.wave)

    if barricades.is_broken():
        _restart()

    horde_view.render(horde, _time)
    projectile_view.render(projectiles)
    barricade_view.render(barricades)
    hud.text = "WAVE %d    KILLS %d    BEST %d" % [run.wave, run.kills, run.best_wave]

func _restart() -> void:
    run.end_run()
    run.save_best()
    run.reset()
    horde.clear()
    projectiles.clear()
    barricades.reset()
    director.reset()
    weapon.reset()
    aim.reset()
```

Restart rebuilds no objects and loads no scene — it resets the units in place. That is what lets the audio bus survive a restart untouched in phase 6, and it is why every unit above has a `reset()`.

- [ ] **Step 4: Build the scene**

Create `Holdout/scenes/game.tscn` in the Godot editor with this node tree:

```
Game                (Node3D)          → attach scripts/game.gd
├── Camera3D                          → position (0, 9, -8), rotation (-38, 180, 0)
├── DirectionalLight3D                → rotation (-50, -30, 0)
├── Ground           (MeshInstance3D) → PlaneMesh, size 80 × 80
├── HordeView        (MultiMeshInstance3D) → attach scripts/views/horde_view.gd
├── ProjectileView   (MultiMeshInstance3D) → attach scripts/views/projectile_view.gd
├── BarricadeView    (Node3D)         → attach scripts/views/barricade_view.gd
└── HUD              (CanvasLayer)
    └── WaveLabel    (Label)          → anchored top-left, 16px margin
```

The camera sits behind the origin looking forward down +Z, so the whole 180° arc is visible at once. Threat prioritisation is impossible if a section of the arc is off-screen — check every spawn angle is visible before moving on.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
Expected: the whole suite PASSES, integration tests included.

- [ ] **Step 6: Play it**

Run: `godot`

This is the deliverable. Play several runs and answer honestly:

- Does aiming feel responsive, or sluggish and disconnected?
- Can you see the whole arc, and tell which section is under threat?
- Do you ever have to choose between two threats, or is it always obvious?
- Does wave 1 bore you before wave 5 arrives?
- Do you want another run?

Write the answers into the spec's Deferred section as findings. **If aiming feels bad, stop and tune `AimInput.SMOOTHING` and `PIXELS_PER_RADIAN` before building anything else** — every later phase compounds on this feel, and no upgrade pool rescues shooting that is unpleasant.

- [ ] **Step 7: Commit**

```bash
git add scripts/game.gd scenes/game.tscn test/test_game_integration.gd
git commit -m "feat: wire units into a playable grey-box game"
```

---

## Self-review notes

**Spec coverage.** Phase 1 of the build order is covered task by task: one weapon (Task 4), one zombie type (Tasks 1–2), aim (Task 6), automatic fire (Tasks 4–5), three barricade sections (Task 3), escalating waves (Task 2), untextured (Task 8), no audio, no Android. `UpgradeDraft` and XP are deliberately excluded and belong to phase 3; the spec's build order agrees.

**Deliberate deviations from the spec, both recorded above:**

1. The radial-bucket broadphase is *not* built. Task 5 uses a naive nested loop behind the final signature. The spec names the broadphase as the most important technical decision, and it remains phase 3's job — after profiling justifies it. Building it now would optimise before measuring, and the Task 5 tests exist to guard the swap.
2. `RunState` carries no XP. It arrives with the draft.

**Known gap.** The spec targets 60fps at 250 concurrent zombies on a mid-range phone. Nothing in this plan measures that — by design, since it is phase 3's entire purpose. What phase 1 delivers is a build worth measuring.
