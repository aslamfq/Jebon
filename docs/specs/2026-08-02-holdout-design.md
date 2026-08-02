# Holdout — design

> **SUPERSEDED on 2026-08-02 by `2026-08-02-onrush-design.md`.** The game pivoted from this
> fixed-position horde defense to a crowd runner with auto-fire. This document is kept for its
> record of decisions and because the current design inherits seven of its units. Do not treat
> anything below as current: in particular the barricade, the 180-degree arc, the fixed camera and
> the manual-aim skill layer are all gone. See the successor's "What this replaces" section for
> exactly what survived and in what condition.

Design agreed with Aslam on 2026-08-02. Working title; rename before the repo is created if a better
one lands.

First game project in the workspace. Unrelated to `SAIL-revamp`.

## In plain English

Skip the rest if you just need the gist.

Holdout is a free mobile game with no ads and no in-app purchases. You stand behind a barricade of
three sections while zombies walk at you through a wide arc. You drag your thumb to aim; the gun fires
by itself. Because each section has its own health, where the zombies are matters as much as how many
there are. Killing zombies fills a bar, and each time it fills the game slows down and offers you
three upgrades — pick one and keep going. The waves get bigger and nastier forever. When any section
falls you see which wave you reached and you are straight back in, with the music still playing.

It is built in Godot 4 and runs on Android. It looks like soft pastel low-poly clay figures rather
than gore.

The idea started as "playable ads are fun for forty seconds and then lie about the game" — so build
one of those mechanics as a game that holds up.

## Goal

Build a game Aslam wants to play, ship it to his own phone, and enjoy making it.

**This earns no money and that is deliberate.** No ads, no IAP, no store listing required. Aslam chose
this as a creative project rather than an income play, so nothing in this spec should be traded away
for monetisation. The absence of ads also removes an ad SDK, a consent flow, a privacy policy,
advertising-ID handling and a Play Console account — real engineering savings, not just a preference.

**Success:** a build on Aslam's phone that he opens again without deciding to.

## Constraints

- **Time is the binding constraint.** Aslam works full time. Every decision below favours less work
  over more, and the build order front-loads the parts that could invalidate the rest.
- **The machine is an older MSI laptop.** Godot 4 opens in seconds on it; Unity and Unreal do not.
- **Pin the exact Godot version.** Install a specific 4.x, record it in the `Holdout` repo's
  `CLAUDE.md`, and read it there rather than assuming. Point releases differ in rendering and export
  behaviour, and this workspace already learned that lesson the expensive way across Unreal 4.19
  through 5.4.
- **Android only.** iOS needs a Mac and USD 99 a year. Godot's web export could reach iPhones later,
  but its mobile browser support is uneven, so treat that as an experiment rather than a plan.
- **Solo, with no art skills.** Every visual decision must be achievable with flat colours and
  primitives.

## Decisions and how we got here

The design moved a long way during brainstorming. Recording the path matters, because each rejection
still constrains the current design.

| Decision | Outcome | Why |
|---|---|---|
| Purpose | Creative project, not income | Aslam's call. Hypercasual-with-ads was separately ruled out on 2026-07-25: solo-dev median USD 3–20/day, SEA rewarded-video eCPM ~USD 2 against USD 15–30 tier-1. |
| Engine | **Godot 4** | Free, ~130MB, no account, opens instantly on the MSI, real 3D editor, one-click APK. Unity means multi-GB install and a slow editor loop on this machine; Unreal is outright overkill. |
| Genre, first pass | Crowd runner with gates — **rejected** | Chosen, then abandoned once the endless-waves idea arrived. |
| Tone, first pass | "Calming" — **rejected** | Aslam: "you're holding on the calming too much, it still has to be interesting to play." Calm survives as palette and audio only, never as a reason to remove stakes. |
| Boss fight | **Cut** | Aslam's call. Endless play has no end to put a boss at. |
| Shape | **Fixed position, horde defense** | Deletes four subsystems outright: player movement, camera rig, level streaming, procedural track generation. Cheapest path to something playable. |
| Camera | **Fixed 3D, frontal ~180° arc** | Keeps the low-poly look. Costs meshes and lighting against a 2D build, and Aslam chose it knowingly. |
| Aim | **Manual aim, automatic fire** | One thumb, no fire button, and skill expression in every second of play. |
| Fail state | **Run ends, instant restart** | Flagged as the choice that raises tension; Aslam took it deliberately. Handled through presentation — see below. |
| Art | **Soft low-poly pastel** | Flat colour, no textures, no art skill needed. |
| Barricade | **Three independent sections** | Added on review. A single hit-point pool would make threat direction meaningless and collapse one of the four depth layers this design rests on. |

### Why a fixed position still works

Removing player movement removes the usual source of depth in this genre. Four layers replace it:

1. **Manual aim** gives moment-to-moment skill — leading targets, sweeping efficiently, choosing where
   the stream of fire sits while threats converge from several directions at once.
2. **Threat prioritisation** gives tactics. Zombies arrive from several angles at different speeds and
   toughness, and you cannot cover everything, so every few seconds you choose what to shoot first.
3. **A segmented barricade** makes direction matter concretely. The slow zombie chewing the left
   section may outrank the fast one in front of you.
4. **The upgrade draft** gives the run-to-run reason to play again.

Layer 3 only works if the barricade has independent sections. **A single pool would make position
irrelevant and collapse the layer into "shoot whatever is closest"** — so the barricade is specified
below as three sections with separate hit points, and the run ends when any one of them breaks.

### Why the draft is the heart

In this genre the shooting is automatic and the player barely touches it. The engagement engine is the
draft: three options at every level-up, and a run you are assembling out of them. Piercing shot or an
extra orbital, crit or area. That loop is what separates a horde shooter people return to from one they
delete. **`UpgradeDraft` is therefore built as a first-class unit with its own tests, not as logic
scattered through the weapon code.**

### Making a fail state feel unhurried

Aslam chose a real fail state, so presentation carries the tone:

- The music never stops. One audio bus survives the restart, so failure never sounds like a rupture.
- No "GAME OVER", no red flash, no screen shake on death, no menu, no restart tap.
- The wave number appears small. No leaderboard, no streak, nothing to break.
- Best wave persists locally and never appears as a taunt.

## Core loop

**Waves are continuous, not discrete.** Pressure never drops to zero and no break separates one wave
from the next. "Wave" is a counter that advances on a timer, naming the current difficulty band and
giving the run an end-screen number. The only pause in the whole game is the level-up draft.

1. `WaveDirector` spawns zombies into the arc on a schedule that escalates forever.
2. Zombies walk toward the barricade. You drag to aim; the weapon fires on its own.
3. Kills award XP. A filled XP bar slows time and offers three upgrades; you pick one.
4. Zombies reaching a barricade section attack it.
5. Any section reaching zero ends the run. The wave number shows, and the next run starts at once.

## Architecture

Ten units: seven that hold rules, three that only draw.

The rule units form a **feedback cycle**, which is what a game loop is — claiming one-way flow here
would be a lie. The real invariant is narrower and more useful: **every edge below runs in exactly one
direction, and no view ever writes.**

```
AimInput ──aim vector──> Weapon ──fire requests──> Projectiles
                            ▲                           │
              modifiers     │                           │ damage
                            │                           ▼
                     UpgradeDraft                     Horde <──spawns── WaveDirector
                            ▲                        │      │
        offers 3 on level-up│               XP on kill│      │contact
                            │                        ▼      ▼
                          RunState <───run ends─── BarricadeSet

Views:  HordeView → reads Horde        ProjectileView → reads Projectiles
        BarricadeView → reads BarricadeSet
```

`RunState` owns XP and the level threshold, so it — not `UpgradeDraft` — decides when a level-up
happens. `UpgradeDraft` only answers "offer me three" and "apply this one." Keeping the trigger and
the offer in separate units means the level curve can be retuned without touching the upgrade pool.

**`Horde`** — pure logic, no Godot nodes. Flat arrays of zombie state: position, hit points, type,
speed. Exposes `spawn()`, `tick(dt)` and `damage_at()`. Every enemy rule lives here and nowhere else,
so the entire ruleset runs headlessly in tests.

**`HordeView`** — one `MultiMeshInstance3D` per zombie type, writing transforms from `Horde` each
frame. Meshes are low-poly and **unskinned**, animated by procedural bob and squash. Skinned-mesh
instancing is the one genuinely hard problem in drawing a crowd on a phone, and unskinned meshes
delete it. It also suits the clay-figure look.

**`WaveDirector`** — **seeded and deterministic.** Owns the escalation curve and the spawn tables:
which types, how many, what cadence, from which angles, at which wave. Also throttles spawning to
respect the concurrency cap. Determinism makes a run reproducible, which turns "that felt wrong"
into a test.

**`Weapon`** — fire rate, damage, projectile specification, and the modifier stack that upgrades write
into. Pure logic; emits fire requests rather than spawning anything.

**`Projectiles`** — pooled, drawn through a `MultiMeshInstance3D`. **Collision uses a hand-rolled
broadphase, never Godot physics.** Radial buckets across the arc, since every threat approaches from a
known direction. Hundreds of projectiles against hundreds of zombies would collapse under `Area3D` and
physics bodies. This is the most important technical decision in the build.

**`UpgradeDraft`** — the upgrade pool, its weighting, the three-choice offer, and application to
`Weapon` and player stats. Pure logic, fully testable.

**`AimInput`** — turns a drag into an aim vector, with the smoothing and dead zone that make aiming
feel good rather than twitchy. Isolated because aim is the whole skill layer of this game, and it will
need tuning passes that must not touch anything else.

**`BarricadeSet`** — three sections spanning the arc, each with independent hit points. Maps an
attacking zombie's angle to a section, applies damage, and signals the run's end when any section
breaks. Segmentation is what makes threat direction matter, so it is load-bearing rather than
decorative.

**`RunState`** — wave counter, kills, XP and the level threshold, best-wave persistence, and restart.
Owns the level-up decision. Restarts without touching the audio bus.

**`ProjectileView` and `BarricadeView`** — read their unit's state each frame and draw it, like
`HordeView` above. No rules, no writes.

### Why this shape

Every rule sits in a unit with no rendering dependency, so the whole game is testable without drawing
a frame. Views hold no rules, so changing how something looks cannot change how it behaves. This
structure already survived one total genre pivot intact, which is the strongest evidence available
that the boundaries are in the right places.

## Performance plan

The target is 60fps on a mid-range Android phone with roughly 250 concurrent zombies and several
hundred projectiles.

- `MultiMeshInstance3D` for zombies and projectiles. One draw call per type.
- **No `RigidBody3D`, `CharacterBody3D` or `Area3D` anywhere in the hot path.** Positions are plain
  arrays; collision is the radial-bucket broadphase.
- `WaveDirector` enforces a hard concurrency cap and throttles spawns to hold it.
- Flat shading, no real-time shadows, no post-processing.

**This gets proven before content is built.** If a phone cannot hold the target, the design changes,
and finding that out after twenty upgrades exist would waste the time this project does not have.

## Testing

GUT (the standard Godot unit-test addon) against `Horde`, `WaveDirector`, `Weapon` and `UpgradeDraft`.
All four are pure, so no test renders anything.

The seeded director enables the test that matters most: **simulate an entire run headlessly and assert
the outcome.** For example, seed 42 taking only crit upgrades survives to wave 20. Balance regressions
are otherwise findable only by playing for twenty minutes, which nobody does before every commit.

## Build order

Ordered so the risky and the unfun come first.

1. **Grey-box on desktop.** One weapon, one zombie type, aim, automatic fire, three barricade sections,
   escalating waves. Untextured capsules, no audio, no Android. One sitting. If the shooting feels bad
   grey, no amount of art rescues it.
2. **Android toolchain.** JDK 17 and the Android SDK, neither of which this machine has, plus a
   working APK export of the grey-box build.
3. **Performance pass.** MultiMesh plus broadphase at full target counts, profiled **on a real phone**.
   Deliberately ahead of content: this is the technical risk of the whole project.
4. **Upgrade draft and pool** — roughly 20 upgrades. The real design work, and the reason anyone
   replays.
5. **Zombie variety and wave curve tuning.** Types that force different responses, not just larger
   numbers.
6. **Art pass.** Pastel palette, flat shading, clay figures.
7. **Audio.** Continuous bed surviving restarts, chimes on level-up.

**On why the toolchain moved to second.** An earlier draft put it last, reasoning that installing it
is a chore with no gameplay payoff. That was wrong: step 3 exists to prove mobile performance, and
desktop figures say almost nothing about a mobile GPU. Profiling on a phone requires the toolchain, so
deferring it would have deferred the one risk this build order exists to retire early. The chore is
paid once, immediately after there is something worth putting on the phone.

## Placement

| What | Where |
|---|---|
| Code | `Repo/Projects/Holdout` — new repo `aslamfq/Holdout`, private |
| This spec, eventually | `Repo/Projects/Holdout/docs/specs/` |
| This spec, for now | `Repo/Projects/Planner/Holdout/specs/` |

A new product means a new repo under `Projects/`, never a subdirectory of an existing one.

**This document currently sits in the wrong place, knowingly.** Workspace convention is explicit that
plans belonging to one project live in that project's repo beside the code they describe, and that
`Planner` holds only what spans projects. This spec belongs to one project. It lives in `Planner`
solely because the `Holdout` repo does not exist yet and the spec needed somewhere to be committed.
**Move it into `Holdout` as the first commit after the repo is created, and delete
`Planner/Holdout/`.**

## Deferred

Named here so they stay decisions rather than drift:

- **Web export.** Would make the game shareable by link. Godot's mobile browser support is uneven, so
  it is an experiment after the Android build works, not a commitment.
- **A second weapon archetype.** The draft has more room with two base weapons, but one must feel good
  first.
- **Meta-progression between runs.** Deliberately absent from v1. Add only if the draft proves it
  needs a longer arc.
- **Store publication.** Not required to reach Aslam's own phone.
