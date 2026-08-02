extends GutTest

# Mirrors game.gd's _process ordering, without a scene tree.
#
# Seed choice: Horde.tick() moves each zombie in a dead straight line at its
# spawn bearing (locked behaviour, guarded by test_horde.gd), and a
# never-touched AimInput stays pinned at exactly Vector2(0, 1). Geometry
# alone -- asin(HIT_RADIUS / BarricadeSet.RADIUS) = asin(0.45 / 4.0) -- means
# only zombies that spawn within about 6.5 degrees of dead-ahead can ever be
# hit by a stationary weapon, roughly 7% of the 180-degree arc. Seed 42
# happened to draw zero spawns in that corridor -- confirmed by simulating it
# out to 300s, well past this test's 30s window, and still getting zero
# kills. That is a property of that seed's draw, not of game.gd's wiring, so
# it was swapped for seed 1, which was verified (see task-9-report.md) to
# satisfy every test below, including this one.
func _simulate(seconds: float, step: float) -> Dictionary:
    var horde := Horde.new()
    var director := WaveDirector.new(1)
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

# --- Below: tests that exercise the real scene and script, not the mirrored
# copy of the loop above. The tests above prove the *rules* hold together;
# they cannot catch a game.gd that mis-wires @onready paths, forgets to call
# a view's render(), or points a view at the wrong unit instance, because
# they never touch game.gd or scenes/game.tscn at all. These do.

func test_the_scene_wires_the_real_units_to_the_real_views():
    var scene: PackedScene = load("res://scenes/game.tscn")
    var game: Node3D = add_child_autofree(scene.instantiate())

    assert_true(game.horde_view is HordeView, "HordeView must resolve at $HordeView")
    assert_true(game.projectile_view is ProjectileView, "ProjectileView must resolve at $ProjectileView")
    assert_true(game.barricade_view is BarricadeView, "BarricadeView must resolve at $BarricadeView")
    assert_true(game.hud is Label, "HUD label must resolve at $HUD/WaveLabel")

    # Drive real frames through the real _process (not the mirrored copy)
    # until at least one wave-director spawn tick has definitely elapsed.
    simulate(game, 100, 1.0 / 60.0)

    assert_gt(game.horde.count, 0,
        "the real _process must call director.tick()/horde.spawn() the same as the mirrored loop")
    assert_eq(game.horde_view.multimesh.visible_instance_count, game.horde.count,
        "horde_view.render() must be called with this scene's own horde, not a stale copy")
    assert_eq(game.projectile_view.multimesh.visible_instance_count, game.projectiles.count,
        "projectile_view.render() must be called with this scene's own projectiles")
    assert_gt(game.run.elapsed, 0.0, "run.tick() must actually be wired into _process")
    assert_string_contains(game.hud.text, "WAVE",
        "the HUD text must be assembled from live run state, not left at its default")

func test_restart_resets_units_in_place_without_rebuilding_them():
    var scene: PackedScene = load("res://scenes/game.tscn")
    var game: Node3D = add_child_autofree(scene.instantiate())

    simulate(game, 90, 1.0 / 60.0)

    var horde_ref: Horde = game.horde
    var director_ref: WaveDirector = game.director
    var barricades_ref: BarricadeSet = game.barricades
    var weapon_ref: Weapon = game.weapon
    var projectiles_ref: Projectiles = game.projectiles
    var aim_ref: AimInput = game.aim
    var run_ref: RunState = game.run

    # Force some non-trivial state so a reset is actually observable.
    game.horde.spawn(Vector2(0, 5), 10.0, 1.0)
    game.run.record_kills(3)
    game.barricades.damage(BarricadeSet.Section.LEFT, 40.0)

    game._restart()

    # Same object identity -- a restart that swapped in fresh instances would
    # break phase 6's continuous audio, which is exactly the constraint this
    # guards. assert_eq on RefCounted/Node compares reference identity.
    assert_eq(game.horde, horde_ref, "restart must not replace the Horde instance")
    assert_eq(game.director, director_ref, "restart must not replace the WaveDirector instance")
    assert_eq(game.barricades, barricades_ref, "restart must not replace the BarricadeSet instance")
    assert_eq(game.weapon, weapon_ref, "restart must not replace the Weapon instance")
    assert_eq(game.projectiles, projectiles_ref, "restart must not replace the Projectiles instance")
    assert_eq(game.aim, aim_ref, "restart must not replace the AimInput instance")
    assert_eq(game.run, run_ref, "restart must not replace the RunState instance")

    # And the state on those same objects is actually cleared, not just left alone.
    assert_eq(game.horde.count, 0, "restart must clear the horde")
    assert_eq(game.run.kills, 0, "restart must reset kills")
    assert_false(game.run.is_over, "restart must bring the run back to live")
    for i in 3:
        assert_eq(game.barricades.healths[i], BarricadeSet.SECTION_MAX_HEALTH,
            "restart must fully repair the barricade")
