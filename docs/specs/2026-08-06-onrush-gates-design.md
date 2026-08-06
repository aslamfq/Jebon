# Onrush Gates — Design

Build-order step 5, following `docs/specs/2026-08-02-onrush-design.md`'s `## Gates` section. That
section is still authoritative for *why* gates exist and the three families; this doc is the
implementation-level design for *how*, including one correction the original numbers needed once
checked against the shipped `SteerInput` clamp.

## Geometry correction

The original spec text says gates sit at `x = ±3`, each 2.4 wide (half-width 1.2), so a pair spans
`[1.8, 4.2]` on each side. But `SteerInput.MAX_CENTRE` — tuned during phase 1 playtesting — caps
`centre_x` at `Corridor.HALF_WIDTH - Formation.WIDE_HALF_SPAN = 3.75`. The squad's centre can never
reach 4.2, so the outer "skip both gates" lane the spec explicitly wants would be unreachable in the
shipped game.

Fix: `Gate.SIDE_OFFSET := 2.4`, `Gate.HALF_WIDTH := 1.0`. A pair then spans `[1.4, 3.4]` on each
side — inside the reachable range, with room both for the skip lane beyond 3.4 and the centre
channel below 1.4 (design intent: `1.4/2.4 ≈ 58%` of full deflection reaches a gate at all, close
enough to the original's `1.8/3.75 ≈ 48%` that the "both bad, refuse both" option stays meaningfully
available without being the default outcome).

## Architecture

**`Gate`** (new, `RefCounted`) — one side of one pair.
- `op: Op` enum — `ADD`, `MUL`, `TIER_STEP`, `SET_FORMATION`. Flat rather than family-plus-op, so
  nothing needs to interpret a value differently depending on family.
- `value: float` — meaning depends on `op` (delta for `ADD`, factor for `MUL`, ±1 for `TIER_STEP`,
  `Formation.Kind` for `SET_FORMATION`).
- `x_centre: float` — world x this gate occupies. No separate `side` field; `x_centre`'s sign is the
  side.
- `apply(squad: Squad) -> void`.

**`GatePair`** (new, `RefCounted`) — `left: Gate`, `right: Gate`, `y: float`. No `triggered` flag —
a pair is removed from `Gates` the instant it resolves, so nothing needs to remember it happened.

**`Gates`** (new, `RefCounted`) — owns `Array[GatePair]`.
- `tick(delta: float, scroll_speed: float, squad: Squad) -> void` — advances every pair's `y` by
  `scroll_speed * delta`; for any pair whose `y` crosses `<= 0` this tick, reads `squad.centre_x`
  *after* the position update (a gate is a plane at `y=0`, not a volume, so post-update is simply
  correct — no separate ordering concern), determines which `Gate` (if any) contains that x, calls
  `apply(squad)` if one does, and removes the pair either way.
- `reset() -> void` — clears all pairs. Wired into `Game._restart()` alongside every other system's
  `reset()`.

**`TrackGenerator`** (extend) — gate spawning is a second, independent stream from enemy spawning:
- Own spawn clock (`_gate_spawn_clock`), separate from `_spawn_clock`. Fixed interval, not decaying
  — the spec escalates *severity* with distance, not frequency, unlike enemy group cadence.
- Own `RandomNumberGenerator` (`_gate_rng`, seeded `_seed` XORed with a distinct constant, reseeded
  in `reset()`), so drawing gate values never perturbs the enemy-spawn RNG stream that
  `test_track_generator.gd` already asserts against.
- `tick_gates(delta: float) -> Array[GatePair]` — at most **one** pair per call, even if multiple
  intervals elapsed in one frame (caps `MAX_DELTA`-driven catch-up from ever emitting two pairs at
  the same `y`, which would make trigger resolution ambiguous). Spawns at `y = Corridor.SPAWN_DISTANCE`.
- `reset()` gains: zero `_gate_spawn_clock`, reseed `_gate_rng`.
- `count_delta_range(elapsed) -> Vector2` — same `1 - exp(-elapsed/ramp)` escalation shape as
  `enemy_health()`/`enemy_speed()`, widening the `ADD` magnitude sampled for Count gates as distance
  grows.

**Pair generation** (in `TrackGenerator`, using `_gate_rng`):
1. Pick two distinct families from `{COUNT, WEAPON, FORMATION}` for left/right.
2. If `FORMATION` is one of the two picks, it is never the deliberately-bad side — the other family
   gets the good/bad roll, Formation is offered as a neutral alternative, not a punishment.
3. If `FORMATION` isn't picked, one side is forced-good, the other forced-bad:
   - **Count good:** `ADD` with `value = +N` or `MUL` with `value = 2.0`.
   - **Count bad:** `ADD` with `value = -N` (floored so the applied result never drops the squad
     below 1 — see Squad rules below) or `MUL` with `value = 0.5`. `N` sampled from
     `count_delta_range(elapsed)`.
   - **Weapon good:** `TIER_STEP` with `value = +1`.
   - **Weapon bad:** `TIER_STEP` with `value = -1`. Fixed magnitude — 5 tiers total, nothing to
     escalate.
4. Formation's own value: `SET_FORMATION` with a `Formation.Kind` chosen uniformly at random,
   excluding the squad's *current* formation (offering what the squad already has is a wasted gate).

## Squad rules

`Gate.apply` calls into `Squad`, which — per the original spec's "`Squad`… owns the rules for
applying a gate" — is where clamping lives, not `Gate`:
- `Squad.add_count(delta: int) -> void` — calls `set_count(count() + delta)` but first floors the
  result at 1. A bad Count gate can shrink the squad hard; it must never be what ends the run. Only
  combat contact should be able to reach zero.
- `Squad.mul_count(factor: float) -> void` — same floor.
- `Squad.step_weapon_tier(delta: int) -> void` — `weapon_tier = clampi(weapon_tier + delta,
  0, Weapon.TIER_COUNT - 1)`. Needed because `weapon_tier` is currently a bare, unclamped var
  (`scripts/squad.gd:9`); without this, repeated bad gates could drive it negative, and later good
  gates would silently do nothing until it climbed back to 0.
- `Squad.set_formation(kind: int) -> void` — thin setter; formation itself has no invalid states.

`Gate.apply` dispatches on `op` to whichever of these four it calls.

## Data flow

In `Game._process`, after `runner.tick(delta)` (so this frame's `scroll_speed` is known) and after
`squad.tick(...)` (so `centre_x` is current):

```
for pair in generator.tick_gates(delta):
    gates.pairs.append(pair)
gates.tick(delta, Corridor.scroll_speed_at(runner.elapsed), squad)
gate_view.render(gates)
```

Reusing the same `Corridor.scroll_speed_at(runner.elapsed)` value the enemy-motion line already
computes, rather than `Gates` computing its own, keeps gates and enemies moving at literally the
same rate — no separate source that could drift from it.

`Game._restart()` gains `gates.reset()` alongside every other system already reset there.

## Visuals

Grey-box, per the project's established phase style (real art is a later build-order step, done
once for the whole game rather than piecemeal per feature). Each `Gate` renders as a flat-colored
vertical panel plus a `Label3D` showing its effect (`+15`, `WEAPON −1`, `WEDGE`) — green-tinted for
good, red-tinted for bad, grey for Formation/neutral.

**`GateView`** (new) — follows `CorridorView`'s pooling pattern (`_ensure_*`, grow-once-never-free),
not `UnitsView`/`ProjectileView`'s `MultiMesh` pattern: `Label3D` text can't go through `MultiMesh`,
and the live gate count is always small (at most a handful of pairs on-track at once), so per-pair
`Node3D` instances pooled and repositioned each frame are simple and cheap enough. Nodes beyond the
current pair count are hidden, not freed, matching how `CorridorView` already handles variable prop
counts.

## Testing

Pure-logic coverage, no scene tree, matching every existing test file's style:
- `test_gate.gd` — each `op` applies correctly to a `Squad`; `x_centre` containment math for the
  corrected `SIDE_OFFSET`/`HALF_WIDTH`.
- `test_gate_pair.gd` / `test_gates.gd` — crossing detection at `y <= 0`; the "outside both gates
  skips both" rule reachable at `SteerInput.MAX_CENTRE`; a pair whose `y` jumps past 0 in one
  `MAX_DELTA`-capped frame still resolves exactly once; removed pairs don't reappear; `reset()`
  clears pairs.
- `test_track_generator.gd` additions — gate spawn cadence is independent of and doesn't perturb the
  existing enemy-spawn assertions (separate RNG stream verified by asserting enemy-spawn sequence is
  unchanged before/after adding gate calls); `tick_gates` never returns more than one pair per call
  even across a large `delta`; good/bad/neutral family distribution over many seeded draws; Formation
  never lands on the deliberately-bad side; `count_delta_range` widens with elapsed time.
- `test_squad.gd` additions — `add_count`/`mul_count` floor at 1; `step_weapon_tier` clamps to
  `[0, TIER_COUNT-1]` in both directions.

## Deferred

Hazards (build-order step 6) and real art (step 7) are explicitly out of scope for this pass, per
the same separation phase 2's plan drew around gates and hazards.
