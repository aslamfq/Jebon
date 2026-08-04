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

        # Mirrors game.gd's own per-frame clears, which this helper was
        # missing entirely: Projectiles.tick()/resolve_hits() only append to
        # the removal reports (clearing is the caller's job, once per frame
        # per pool), so without these every removal across the whole
        # simulated run accumulated in both arrays -- tens of thousands of
        # entries on the 300-second test below, none of them ever read.
        # Projectiles.clear() now empties them too, but that only fires on
        # restart; a frame-driving caller still owns the per-frame clear.
        squad_projectiles.removed_positions.clear()
        squad_projectiles.removed_previous_positions.clear()
        squad_projectiles.tick(step, Corridor.SPAWN_DISTANCE + 5.0)

        enemy_projectiles.removed_positions.clear()
        enemy_projectiles.removed_previous_positions.clear()
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

func test_a_simulated_run_does_not_accumulate_removal_reports_forever():
    # Regression guard on _simulate()'s per-frame clears above. Both removal
    # reports are append-only within a frame and cleared by the frame driver,
    # so at the end of a run they must hold at most the final frame's
    # removals -- not every removal the whole run ever produced. Without the
    # clears this run left thousands of entries behind.
    var result := _simulate(30.0, 0.0, 1)
    var squad_projectiles: Projectiles = result["squad_projectiles"]
    assert_lt(squad_projectiles.removed_positions.size(), 32,
        "the removal report must hold one frame's removals, not the whole run's")
    assert_eq(squad_projectiles.removed_previous_positions.size(),
        squad_projectiles.removed_positions.size(),
        "the two reports must stay index-parallel across a whole run")

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

# ---- tests that run the real scripts/game.gd, not a mirrored simulation ----

func _make_game() -> Node3D:
    var scene: PackedScene = load("res://scenes/game.tscn")
    var game := scene.instantiate()
    add_child_autofree(game)
    return game

func _press(game: Node3D, at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = at
    game._unhandled_input(event)

func _drag_to(game: Node3D, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    game._unhandled_input(event)

func test_the_scene_wires_up_its_dependencies():
    var game := _make_game()
    assert_not_null(game.squad, "Game must construct its own Squad in _ready")
    assert_not_null(game.steer, "Game must construct its own SteerInput in _ready")
    assert_not_null(game.runner, "Game must construct its own TrackRunner in _ready")
    assert_eq(game.squad.count(), Squad.STARTING_COUNT)

func test_ready_pins_max_fps_so_the_display_cannot_chase_a_variable_refresh_rate():
    # Found on Aslam's real device: repeatedly minimizing and reopening the
    # app made the FPS readout oscillate (120, then 20-30, then 100+)
    # across successive cycles, distinct from the backgrounding stutter
    # Game.MAX_DELTA already fixes (that one is about simulated game time
    # per frame; this one is about the actual render rate). project.godot
    # has never set vsync/max_fps -- everything before this was Godot's
    # default, which lets the engine simply follow whatever refresh rate
    # the display negotiates. Modern phones with adaptive/variable refresh
    # panels (90Hz/120Hz) renegotiate that rate on each resume from the
    # background, which is consistent with an oscillating readout across
    # repeated minimize/reopen cycles rather than a single stable value.
    # Pinning Engine.max_fps removes that dependency: the engine targets a
    # fixed rate regardless of what the display does around a resume.
    _make_game()
    assert_eq(Engine.max_fps, 60,
        "Game._ready() must pin a fixed max_fps so render rate can't drift with the display's own adaptive refresh negotiation")

func test_input_drag_actually_steers_the_squad():
    # CORRECTED after real phone play found the controls felt backwards.
    # This test originally asserted centre_x > 1.0 here -- i.e. that a
    # rightward finger drag increases centre_x -- and passed, because that
    # is exactly what the code did at the time. Nobody had checked that
    # assertion against the actual camera: game.tscn's Camera3D is yawed
    # 180 degrees (see Game._screen_delta_to_steer_delta's comment), which
    # makes screen-right correspond to world -X. So "centre_x increases on
    # a rightward drag" was the wrong requirement, not just an unproven one
    # -- the test enshrined the bug as correct. The fix negates the screen
    # delta in Game._screen_delta_to_steer_delta; this test now asserts the
    # requirement that actually matches what the player sees on screen.
    var game := _make_game()
    _press(game, Vector2(500, 900))
    _drag_to(game, Vector2(900, 900))  # dragged 400px right on screen

    var step := 1.0 / 60.0
    for i in 180:
        game._process(step)

    assert_lt(game.steer.centre_x, -1.0,
        "a rightward screen drag must steer the squad toward the camera's screen-right, which is world -X given the 180-degree camera yaw")
    # Displacement from each unit's own starting slot, not an absolute x
    # threshold -- see test_steering_moves_the_whole_squad for why an
    # absolute threshold is formation-width-dependent and wrong here too.
    for i in game.squad.count():
        var start_x: float = Formation.slot(i, game.squad.formation, 0.0).x
        assert_lt(game.squad.units.positions[i].x, start_x - 1.0,
            "the whole squad must follow a real drag routed through _unhandled_input, not just steer's internal state")
    # Exact equality against "%d m" no longer holds: Task 7 extends the HUD
    # line to also show kills and fps (scripts/game.gd's _process). fps is
    # an engine metric read live via Engine.get_frames_per_second(), not
    # reproducible from this test, so match the distance+kills prefix only
    # -- still enough to prove the HUD is wired to both runner.distance and
    # run.kills, not just the pre-Task-7 distance-only subset.
    assert_true(game.hud.text.begins_with("%d m    %d kills" % [int(game.runner.distance), game.run.kills]),
        "the HUD must actually be wired to the runner's distance and kill count")

func test_screen_delta_to_steer_delta_inverts_because_camera_is_yawed_180():
    # The camera looks down +Z via a 180-degree yaw, so screen-right is
    # world -X. A rightward (positive) screen delta must produce a negative
    # steer delta, or the squad visually moves opposite the player's finger.
    assert_lt(Game._screen_delta_to_steer_delta(100.0), 0.0)
    assert_gt(Game._screen_delta_to_steer_delta(-100.0), 0.0)
    assert_almost_eq(Game._screen_delta_to_steer_delta(50.0), -50.0, 0.001)

func test_restart_resets_state_without_reallocating_units():
    var game := _make_game()
    var squad_ref: Squad = game.squad
    var units_ref: Units = game.squad.units
    var steer_ref: SteerInput = game.steer
    var runner_ref: TrackRunner = game.runner
    var generator_ref: TrackGenerator = game.generator
    var enemies_ref: Units = game.enemies
    var squad_weapon_ref: Weapon = game.squad_weapon
    var enemy_weapon_ref: Weapon = game.enemy_weapon
    var squad_projectiles_ref: Projectiles = game.squad_projectiles
    var enemy_projectiles_ref: Projectiles = game.enemy_projectiles

    _press(game, Vector2(500, 900))
    _drag_to(game, Vector2(900, 900))
    var step := 1.0 / 60.0
    for i in 300:
        game._process(step)

    assert_gt(game.runner.distance, 0.0,
        "sanity check: the run must have progressed before restart is meaningful")

    game._restart()

    assert_same(game.squad, squad_ref,
        "restart must reuse the existing Squad, never rebuild it (required for a later phase's continuous audio to survive a restart)")
    assert_same(game.squad.units, units_ref,
        "restart must reuse the existing Units array, never rebuild it")
    assert_same(game.steer, steer_ref, "restart must reuse the existing SteerInput")
    assert_same(game.runner, runner_ref, "restart must reuse the existing TrackRunner")
    assert_same(game.generator, generator_ref, "restart must reuse the existing TrackGenerator")
    assert_same(game.enemies, enemies_ref, "restart must reuse the existing enemy Units")
    assert_same(game.squad_weapon, squad_weapon_ref, "restart must reuse the existing squad Weapon")
    assert_same(game.enemy_weapon, enemy_weapon_ref, "restart must reuse the existing enemy Weapon")
    assert_same(game.squad_projectiles, squad_projectiles_ref, "restart must reuse the existing squad Projectiles")
    assert_same(game.enemy_projectiles, enemy_projectiles_ref, "restart must reuse the existing enemy Projectiles")

    assert_eq(game.squad.count(), Squad.STARTING_COUNT)
    # _restart() happens mid-frame, before this frame's render() calls. A
    # removal report left populated across the restart lets the wiped run's
    # last removals still play impact bursts on the fresh run's first
    # rendered frame.
    assert_eq(game.squad_projectiles.removed_positions.size(), 0,
        "restart must leave no pre-restart removals for render() to burst on")
    assert_eq(game.squad_projectiles.removed_previous_positions.size(), 0)
    assert_eq(game.enemy_projectiles.removed_positions.size(), 0)
    assert_eq(game.enemy_projectiles.removed_previous_positions.size(), 0)
    assert_almost_eq(game.steer.centre_x, 0.0, 0.001)
    assert_almost_eq(game.runner.distance, 0.0, 0.001)
    for i in game.squad.count():
        var target := Formation.slot(i, game.squad.formation, 0.0)
        assert_almost_eq(game.squad.units.positions[i].x, target.x, 0.001,
            "restart must snap units back onto their opening slots immediately, not leave them lerping in from wherever they were")
        assert_almost_eq(game.squad.units.positions[i].y, target.y, 0.001)

func test_real_scene_combat_produces_a_kill():
    # Closes a gap the mirrored _simulate() tests cannot: they prove the
    # combat pattern works, but by construction never execute a single line
    # of the real Game._process() (see this file's own header comment,
    # untouched above). Phase 1 treated the equivalent gap for steering as
    # mandatory to close with a real-scene test
    # (test_input_drag_actually_steers_the_squad) rather than deferring it;
    # this is that same closure for combat -- confirmed via Task 7's own
    # break-check, which found that mutating game.gd's real
    # run.record_kills(...) line was caught by nothing in the suite before
    # this test existed.
    #
    # Game._ready() seeds its TrackGenerator with randi() -- an
    # uncontrolled seed -- so override it with a seeded one before ticking.
    # Game._process() runs the identical order of operations as _simulate()
    # (generator tick, runner/steer/squad tick, both Volley.fire calls, both
    # Projectiles.tick calls, both resolve_hits calls, contact damage), and
    # TrackGenerator's RNG is consumed only as a function of elapsed time
    # and group size, not of anything that could differ between the two
    # paths here (no steering input, same starting squad/weapon/generator
    # state), so the same seed against the same step schedule reproduces
    # the same spawn sequence.
    #
    # 900 frames (15s), not test_squad_fire_kills_enemies's 20s: that test's
    # _simulate() halts the instant the squad is wiped and returns the kill
    # count as of that instant, but Game._process() has no such halt -- on
    # wipe it calls _restart() in the same frame, and RunState.reset()
    # zeroes kills. Traced this seed empirically with a standalone probe
    # mirroring _process() exactly: seed 1's squad wipes at frame 1162
    # (~19.37s), so ticking to 1200 frames (20s) hits the post-restart
    # window and reads back kills=0 even though 7 kills happened first --
    # not a bug in Game, just the wrong duration for this assertion. The
    # same probe showed the first kill at frame 180 (3.0s) and 6 kills
    # accumulated by frame 808 (13.47s), so 900 frames lands comfortably
    # after the first kill and comfortably before the wipe.
    var game := _make_game()
    game.generator = TrackGenerator.new(1)

    var step := 1.0 / 60.0
    for i in 900:
        game._process(step)

    assert_gt(game.run.kills, 0,
        "the squad's fire must actually kill enemies through the real Game._process(), not just the mirrored _simulate() reimplementation")
    # The other half of the same gap: this test previously only proved the
    # squad's OWN fire is wired through the real Game node, not that damage
    # flows the other way. Deleting enemy_projectiles.resolve_hits(squad.units,
    # ...) and both contact-damage lines in game.gd left the whole suite
    # green -- the final whole-branch review's deferred-item finding, since
    # nothing else drives the real Game node this far into a run. 900 frames
    # is already well past where enemy pressure starts costing squad units
    # (confirmed by the same review), so the squad must have taken losses by
    # here.
    assert_lt(game.squad.count(), Squad.STARTING_COUNT,
        "enemy fire and/or contact damage must actually cost the squad units through the real Game._process(), not just the mirrored _simulate() reimplementation")

func test_process_clamps_a_huge_delta_after_the_app_resumes_from_background():
    # Found on Aslam's real device: minimizing the app then reopening it
    # produced a severe FPS drop followed by an erratic spike. Root cause --
    # Android suspends rendering while the app is backgrounded, but Godot's
    # own clock keeps running, so the first _process() call after resume
    # receives one huge delta representing the entire backgrounded
    # duration. Nothing downstream clamps it: TrackGenerator.tick's spawn
    # catch-up loop, Units.tick's per-unit movement, and
    # Projectiles.resolve_hits's O(units x projectiles) loop all scale
    # directly with delta, so one call tries to simulate the whole missed
    # interval (and every enemy it would have spawned) in a single frame --
    # the stutter Aslam saw. Regression-proofs the clamp with a delta far
    # larger than any real background gap this bug report could plausibly
    # represent, so a future accidental removal of the clamp can't
    # coincidentally still pass at a smaller value.
    var game := _make_game()
    game._process(3600.0)
    assert_almost_eq(game.runner.elapsed, Game.MAX_DELTA, 0.0001,
        "a single frame must never simulate more than Game.MAX_DELTA of game time, however large the real elapsed time was")
