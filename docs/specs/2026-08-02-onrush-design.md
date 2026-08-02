# Onrush — design

Design agreed with Aslam on 2026-08-02. Working title.

**This supersedes the fixed-position horde-defense design** in `2026-08-02-holdout-design.md`. That
spec is kept for its record of decisions and for the units this one inherits. Read the "What this
replaces" section below before treating anything in the older document as current.

## In plain English

Skip the rest if you just need the gist.

Onrush is a free mobile game with no ads and no in-app purchases. A squad of little soldiers runs
forward down a corridor on its own, firing ahead on its own. You drag left and right to steer them.

Gates come at you in pairs, one on each side, and you pick one by steering into it. Some change how
many soldiers you have — `+11`, `×2`, `−5`. Some change the gun everyone is carrying. Some change
the shape of the squad: spread wide, or squeeze into a column. Wide covers more of the corridor with
gunfire but catches more incoming; a column hits harder in one place but funnels straight into
whatever is in the way.

Enemy crowds come the other way and shoot back, and there are obstacles to steer around. When your
last soldier dies the run ends, you see how far you got, and you are straight back in.

It runs forever and gets harder as you go. Built in Godot 4 for Android.

## Goal and constraints

Build a game Aslam wants to play, get it onto his phone, and enjoy making it.

**It earns nothing, deliberately.** No ads, no IAP, no store listing needed. That is a creative
choice, not an oversight, and nothing here should be traded away for monetisation. It also removes
an ad SDK, a consent flow, a privacy policy, advertising-ID handling and a Play Console account.

**Success:** a build on Aslam's phone that he opens again without deciding to.

Constraints carried forward unchanged:

- **Time is binding.** Aslam works full time. Prefer less work over more, and front-load whatever
  could invalidate the rest.
- **Godot 4.7.1**, Standard build, already installed. Read the version from `CLAUDE.md`, never assume.
- **Android only.** iOS needs a Mac and USD 99/year.
- **Solo, no art skills.** Every visual decision must be reachable with flat colours and primitives.

## What this replaces, and why

The project began as "playable ads are fun for forty seconds then lie about the game — build one
that holds up." It moved through a crowd runner, a calming endless game, and a fixed-position horde
defense, which was built to a working state before Aslam identified the actual target: the crowd
runner with auto-fire seen in Army Clash / Crowd Evolution style ads. A squad running a corridor,
gates that grow it, enemy crowds ahead.

**Phase 1 of the old design is merged to `main` and is not wasted.** Seven pure-logic units passed
review with 84 tests green. What survives, and in what condition:

| Unit | Condition |
|---|---|
| `Projectiles` | **Ports unchanged.** Instantiated twice here — the squad's and the enemies'. |
| `RunState` | **Ports unchanged.** Wave counter becomes distance. |
| `HordeView`, `ProjectileView` | **Port unchanged.** MultiMesh, unskinned, procedural bob. |
| `Horde` → `Units` | **Modified.** Storage, swap-remove, `spawn`, `damage_at` and `clear` are untouched; `tick` currently walks everything toward the origin, which is fixed-position logic. It gains a `velocities` array and integrates instead. Not a free port. |
| `AimInput` → `SteerInput` | **Modified.** The frame-independent `1 - exp(-k·dt)` smoothing and the clamp port directly; the clamp bound becomes corridor width rather than an angle. |
| `WaveDirector` → `TrackGenerator` | **Modified.** Seeded determinism, escalation curve and concurrency throttling all survive; it emits track events instead of spawn positions. |
| `Weapon` | **Extended.** The frame-rate-independent accumulator is untouched; it gains tiers. |
| `BarricadeSet`, `BarricadeView` | **Deleted.** Only meaningful standing still. |
| `game.gd`, `game.tscn`, `test_game_integration.gd` | **Deleted.** Rewritten for the new shape. |

**One inherited defect dies with the old scene.** The phase 1 `Camera3D` could not show the
180-degree arc it was required to show: `project.godot` sets a portrait viewport, Godot's `fov` is
vertical by default, and flank spawns sat ~68 degrees off the camera axis behind a ~23 degree
horizontal half-angle. A corridor puts every threat ahead in a narrow lane, so the problem does not
recur — but see "Camera" below, because the lesson does.

## World model

**The squad does not move forward. The world moves toward it.**

- Logic stays 2D: `Vector2(x, y)`, `x` lateral, `y` forward. Views map to `Vector3(x, 0, y)`, and
  only views do that mapping. This is the same convention every inherited unit already assumes.
- The squad's centre sits at `y = 0`, with `x` steerable within `±CORRIDOR_HALF_WIDTH` (6.0).
- Track content spawns at `y = SPAWN_DISTANCE` (60.0) and moves toward `y = 0` at the scroll speed.
  Content below `y = -5` is recycled.
- **Distance travelled is accumulated scroll.** This keeps every coordinate small and bounded,
  makes recycling trivial, and means no unit ever needs to know about a moving origin.
- Scroll speed ramps for roughly the first two minutes then plateaus. Endless games that ramp
  forever become a countdown to failure; a plateau lets skill rather than clock decide the run.

## Core loop

1. `TrackGenerator` emits events ahead — gate pairs, enemy groups, hazards — on an escalating schedule.
2. `TrackRunner` scrolls everything toward `y = 0` and recycles what passes.
3. You drag to steer; `SteerInput` smooths it into a lateral centre.
4. `Formation` lays out squad slots from the count, formation type and centre; units lerp toward them.
5. `Weapon` converts elapsed time into shots; projectiles fly forward.
6. Enemy units advance and fire back; their projectiles fly toward you.
7. Hit resolution both ways. Hazards damage any squad unit overlapping them.
8. A gate reaching `y = 0` applies to the squad.
9. Squad count reaching zero ends the run. Distance shows, and the next run starts at once.

## Gates

Gates arrive in pairs at the same `y`, one centred at `x = -3`, one at `x = +3`, each 2.4 wide.

**The squad's centre decides which gate applies, and it applies to the whole squad.** With a wide
formation some units would otherwise clip both gates, which is unreadable and produces arguments
with the player. One centre, one gate, whole squad — deterministic and legible.

**Passing outside both gates is legal and applies nothing.** The corridor is wider than the gate
pair, so steering to an outer edge skips the pair entirely. This is deliberate: when both options
are bad, refusing both should be available, and it gives the corridor's full width a purpose.

Three families:

**Count** — `+N`, `−N`, `×N`, `÷N`. The archetype's bread and butter.

**Weapon tier** — five tiers, 0 through 4, each with its own fire interval, damage, projectiles per
shot and spread. Gates step one tier up or down.

**Formation** — `WIDE` (units spread across the corridor), `COLUMN` (narrow, ~±0.8), `WEDGE` (a
triangle). Formation is a real trade-off rather than decoration: width determines how much of the
corridor your fire covers and how much incoming fire you catch, and how likely you are to clip a
hazard.

**The tension worth building is weapon versus count.** Twenty units with pistols against six with
shotguns is a choice a player can be genuinely wrong about, and being wrong in an interesting way is
what makes a run worth repeating. A pair offering `+15` against `weapon +1` is the game.

## Threats

**Enemy crowds** spawn ahead in groups and fire back. They use the same `Units` container and the
same `Projectiles` pool type as the squad — the only asymmetry is which direction things travel and
who owns which pool.

**Enemy motion is scroll plus their own velocity, and both are real.** Every piece of track content
moves toward `y = 0` at the scroll speed; enemy units additionally carry a negative-`y` velocity of
their own, so they close faster than the corridor does. Enemies that stand still relative to the
track are simply given zero velocity. Keeping these two motions separate rather than folding them
together means the scroll speed can be retuned without silently changing how aggressive enemies feel.

**Hazards** are static obstacles occupying an `x` range: any squad unit overlapping one takes
damage. They exist so the gaps between gates are not dead time, and so formation width carries a
cost as well as a benefit.

Escalation scales enemy group size, enemy health, hazard density and the severity of negative gate
options with distance — then plateaus.

## Architecture

Pure-logic units hold no Godot node references and are testable with no scene tree. Views read and
draw and never write. Data flows one way per edge; the loop as a whole is a cycle, which is what a
game loop is.

**`Units`** — generic flat-array container. `positions`, `velocities`, `healths`, `count`, with
swap-remove. Used twice: squad and enemies.

**`Formation`** — pure function of count, type and lateral centre to target slots. No state.

**`Squad`** — the player's `Units`, plus weapon tier, formation type and lateral centre. Owns the
rules for applying a gate.

**`SteerInput`** — drag to lateral centre, exponentially smoothed, clamped to the corridor.

**`Weapon`** — tier table plus the inherited frame-rate-independent accumulator.

**`Projectiles`** — pooled, MultiMesh-drawn, two instances. **Collision stays a naive nested loop**
until a profiling phase justifies a broadphase; building the optimisation before the measurement is
backwards, and the tests guard the eventual swap.

**`Gate`** — side, kind, operation, value; `apply(squad)`.

**`Hazard`** — lateral range, damage.

**`TrackGenerator`** — seeded and deterministic; emits gate pairs, enemy groups and hazards on an
escalating schedule. Same seed, same run.

**`TrackRunner`** — scrolls, triggers, recycles. Holds no rules.

**`RunState`** — distance, kills, best distance, run end, restart in place.

Views: `UnitsView` (twice), `ProjectileView` (twice), `GateView`, `HazardView`.

**Restart resets units in place and never reloads the scene.** Every unit therefore needs a
`reset()`. This is what lets a later audio phase keep the music running across a restart.

## Camera

The corridor is roughly twelve units wide at the squad's depth, which a portrait viewport handles
comfortably — this is a far easier problem than the one phase 1 failed.

**It must still be derived and verified by computation before the scene is committed.** Specifically:
set `Camera3D.keep_aspect` to `KEEP_WIDTH` so `fov` is horizontal rather than vertical, then prove
by calculation that both corridor edges at the squad's depth, and the full spawn distance, sit
inside the frustum with margin — and that a unit is wide enough in screen pixels to read at spawn
distance. Phase 1's camera was signed off as "verified" when only its facing direction had been
checked. Facing is not framing.

## Performance

Target 60fps on a mid-range Android phone.

- Caps: 256 squad units, 256 enemy units, 512 projectiles per pool.

**The squad cap is hard, and gates clamp against it.** Unlike phase 1's horde, every squad unit has
a position that matters — it decides what your fire covers and what a hazard clips — so there is no
honest way to let the model count exceed what is drawn. A `×2` at 200 units yields 256, not 400.

The design consequence must be respected in tuning: **at the cap, a `×N` gate is worth nothing**, and
a game where the squad sits pinned at 256 has silently deleted its own most exciting gate. Typical
counts should sit well below the cap, with the ceiling reachable only briefly and as a reward.
Multiplier gates and enemy lethality get balanced against each other with that in mind.
- `MultiMeshInstance3D` per type, one draw call each. Unskinned meshes, procedural bob.
- **No Godot physics anywhere** — no `Area3D`, `RigidBody3D`, `CharacterBody3D`. Positions are flat
  arrays; collision is arithmetic.
- Flat shading, no real-time shadows, no post-processing.

Proven on a real device before content is built, for the same reason as before: finding out late
wastes the time this project does not have.

## Testing

GUT, with every pure unit tested headlessly. The seeded generator allows a full run to be simulated
with no rendering and its outcome asserted.

**A test that a broken implementation would pass is not a test.** Phase 1 shipped three such tests
and needed two fix rounds to close them. For every test, name the wrong implementation it rules out;
if there is none, strengthen it. For load-bearing logic, deliberately break the implementation,
confirm the test fails, restore, and verify the restoration against a committed baseline.

## Build order

1. **Steering and scroll, grey-boxed.** `Units`, `Formation`, `Squad`, `SteerInput`, `TrackRunner`,
   a scrolling corridor and a squad you can steer. No guns, no gates, no enemies. Answers whether
   steering a crowd feels good, which nothing later can fix.
2. **Camera, derived and verified.** Early, because phase 1 proves this is where silent failure lives.
3. **Android toolchain and a device performance pass** at full caps. The technical risk, retired
   before content is built on top of it.
4. **Guns and enemies.** Weapon tiers, both projectile pools, enemy crowds.
5. **Gates.** All three families, and the tuning of pairs — the real design work.
6. **Hazards, and the escalation curve.**
7. **Art, then audio.** Continuous bed surviving restarts.

## Deferred

- **Boss encounters.** The screenshot shows oversized enemies; whether they are a distinct encounter
  type or just large units is unresolved and does not block anything.
- **Meta-progression between runs.** Absent by default. Add only if runs prove they need a longer arc.
- **Web export**, for a shareable link. Godot's mobile browser support is uneven; an experiment, not
  a commitment.
- **Store publication.** Not required to reach Aslam's own phone.
- **Renaming the repo** from `Holdout` to match the title. Cheap, cosmetic, whenever.
