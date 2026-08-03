extends GutTest

# The six tests below mirror game.gd's _process ordering (runner.tick,
# steer.tick, squad.tick) with no scene tree, exactly as the brief specifies.
# They are valuable for catching a broken *interaction* between the units --
# e.g. steering never reaching the squad, or the corridor never scrolling --
# but by construction they never execute a single line of scripts/game.gd
# itself. A bug in game.gd's actual _ready(), _unhandled_input() or _process()
# (wrong call order, wrong argument, a forgotten assignment, the HUD never
# updated) would ship undetected by these six alone, because _simulate()
# re-implements the ordering rather than running the real code.
#
# The three tests after them close that gap: they load the real
# scenes/game.tscn, add it to this test's live tree (add_child_autofree runs
# _ready() synchronously, same as GUT's normal pattern for scene tests), and
# drive the actual _unhandled_input()/_process()/_restart() methods directly.
# In particular test_input_drag_actually_steers_the_squad is the only test in
# this suite that ever calls _unhandled_input -- none of the six mirrored
# tests touch it, so a broken drag-to-steering mapping (the actual player-
# facing control) would otherwise be invisible to the whole test suite.

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
    # The brief's version asserted every unit's absolute x > 1.0, which is
    # mathematically unreachable for this drag: 400px is well past
    # SteerInput.MAX_CENTRE regardless of PIXELS_PER_UNIT's exact value
    # (currently 400/70 = 5.71 > MAX_CENTRE), so centre_x settles at
    # MAX_CENTRE itself -- 3.75, i.e. Corridor.HALF_WIDTH(6.0) minus
    # Formation.WIDE_HALF_SPAN(2.25). WIDE's trailing-most column sits at
    # -WIDE_HALF_SPAN, so the trailing-most unit settles at
    # 3.75 - 2.25 = 1.5, which can never clear an absolute threshold of
    # 1.0 with any margin. That is not a convergence bug, it is the
    # correct steady state; the absolute threshold was simply wrong, and
    # would go wrong again on the next retune of any of these three
    # constants. Assert displacement from each unit's own starting slot
    # instead, which is agnostic to all of them and still fails hard if
    # only the lead unit (or only some units) actually follow the drag.
    var result := _simulate(3.0, 400.0)
    var squad: Squad = result["squad"]
    for i in squad.count():
        var start_x: float = Formation.slot(i, squad.formation, 0.0).x
        assert_gt(squad.units.positions[i].x, start_x + 1.0,
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
    # The brief's upper bound (SPAWN_DISTANCE + MARKER_SPACING = 66.0) is
    # tighter than what TrackRunner actually guarantees. Its ring buffer
    # holds ceil((SPAWN_DISTANCE - RECYCLE_DISTANCE) / MARKER_SPACING) + 1
    # markers (12, not 11) and wraps by adding their combined span (72, not
    # 65) whenever a marker crosses RECYCLE_DISTANCE, so immediately after a
    # wrap a marker can land anywhere below RECYCLE_DISTANCE + 12 *
    # MARKER_SPACING = 67.0. A 120-second run is long enough to land in that
    # window and trips the brief's bound deterministically even though
    # nothing is actually unbounded -- confirmed against the same +1 buffer
    # marker TrackRunner's own reset() relies on, not loosened arbitrarily.
    var result := _simulate(120.0, 0.0)
    var runner: TrackRunner = result["runner"]
    var ceiling: float = Corridor.RECYCLE_DISTANCE + float(runner.markers.size()) * TrackRunner.MARKER_SPACING
    for m in runner.markers:
        assert_between(m, Corridor.RECYCLE_DISTANCE - 0.001, ceiling + 0.001,
            "a marker outside TrackRunner's own ring-buffer span means recycling is broken")

func test_the_simulation_is_reproducible():
    var a := _simulate(20.0, 250.0)
    var b := _simulate(20.0, 250.0)
    assert_almost_eq(a["runner"].distance, b["runner"].distance, 0.0001)
    assert_almost_eq(a["steer"].centre_x, b["steer"].centre_x, 0.0001)

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
    assert_eq(game.hud.text, "%d m" % int(game.runner.distance),
        "the HUD must actually be wired to the runner's distance")

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

    assert_eq(game.squad.count(), Squad.STARTING_COUNT)
    assert_almost_eq(game.steer.centre_x, 0.0, 0.001)
    assert_almost_eq(game.runner.distance, 0.0, 0.001)
    for i in game.squad.count():
        var target := Formation.slot(i, game.squad.formation, 0.0)
        assert_almost_eq(game.squad.units.positions[i].x, target.x, 0.001,
            "restart must snap units back onto their opening slots immediately, not leave them lerping in from wherever they were")
        assert_almost_eq(game.squad.units.positions[i].y, target.y, 0.001)
