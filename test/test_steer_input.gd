extends GutTest

var steer: SteerInput

func before_each():
    steer = SteerInput.new()

func test_starts_centred():
    assert_almost_eq(steer.centre_x, 0.0, 0.001)

# Strengthens the brief's sign-only check: 120 frames at 1/60s is 2 seconds, ~28 time
# constants past SMOOTHING's decay (exp(-14*2) ~= 6.9e-13), so centre_x should have
# converged on the exact position PIXELS_PER_UNIT implies, not merely landed somewhere
# positive. An implementation with the wrong pixel-to-unit scale, or one that only
# partially applies the drag, would still pass a bare assert_gt but fails the almost_eq
# below. Drag magnitude (90px) is fixed rather than derived from PIXELS_PER_UNIT itself
# so a future retune of that constant can't silently make this drag land exactly on
# SteerInput.MAX_CENTRE's wall clamp -- 90 / SteerInput.PIXELS_PER_UNIT must stay well
# inside MAX_CENTRE for this test to measure the pixel-to-unit conversion rather than
# the clamp, which gets its own test below.
func test_dragging_right_moves_right():
    steer.steer_to_screen_delta(Vector2(90, 0))
    for i in 120:
        steer.tick(1.0 / 60.0)
    assert_gt(steer.centre_x, 0.0)
    assert_almost_eq(steer.centre_x, 90.0 / SteerInput.PIXELS_PER_UNIT, 0.001)

# Mirrors the strengthening above on the other side.
func test_dragging_left_moves_left():
    steer.steer_to_screen_delta(Vector2(-90, 0))
    for i in 120:
        steer.tick(1.0 / 60.0)
    assert_lt(steer.centre_x, 0.0)
    assert_almost_eq(steer.centre_x, -90.0 / SteerInput.PIXELS_PER_UNIT, 0.001)

func test_vertical_drag_is_ignored():
    steer.steer_to_screen_delta(Vector2(0, 500))
    for i in 60:
        steer.tick(1.0 / 60.0)
    assert_almost_eq(steer.centre_x, 0.0, 0.001,
        "this game steers on one axis only")

# Both directions in one test: an implementation that clamps the target asymmetrically
# (e.g. min(x, HALF_WIDTH) with no lower bound) would pass a right-only drag test while
# still letting a hard-left drag push the squad through the left wall.
func test_never_leaves_the_corridor_in_either_direction():
    for pixels in [100000.0, -100000.0]:
        var s := SteerInput.new()
        s.steer_to_screen_delta(Vector2(pixels, 0))
        for i in 600:
            s.tick(1.0 / 60.0)
        assert_between(s.centre_x,
            -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001,
            "the squad must never leave the corridor, however hard you drag")

# Strengthens the brief's loose "< HALF_WIDTH * 0.9" bound with the exact value the
# exp() formula predicts for one frame at 1/60s. A raw lerp(a, b, SMOOTHING * delta)
# produces a noticeably different position here and would still pass the brief's loose
# bound, so that bound alone does not prove the exp() form is in use.
func test_movement_is_smoothed_not_instant():
    steer.steer_to_screen_delta(Vector2(100000, 0))
    steer.tick(1.0 / 60.0)
    assert_lt(steer.centre_x, Corridor.HALF_WIDTH * 0.9,
        "one frame must not teleport the squad across the corridor")
    # A huge drag clamps to SteerInput.MAX_CENTRE, not the raw corridor wall --
    # MAX_CENTRE reserves room for the WIDE formation's half-span so its outer
    # slots never need Formation.slot's own clamp during ordinary play.
    var target_x: float = SteerInput.MAX_CENTRE
    var t: float = 1.0 - exp(-SteerInput.SMOOTHING * (1.0 / 60.0))
    var expected_x: float = target_x * t
    assert_almost_eq(steer.centre_x, expected_x, 0.001,
        "smoothing must follow 1 - exp(-k*dt), not a raw lerp")

# The property the exp() form exists for: total elapsed time determines position, not
# how it was chopped into frames. Drives the same 1/6 second of elapsed time as 10
# frames at 60fps versus 100 frames at 600fps. Verified this is discriminating: at these
# values a raw lerp(a, b, SMOOTHING * delta) diverges between the two step sizes by
# ~0.08 units, far outside the 0.001 tolerance below, while the correct exp() form
# agrees to floating-point precision.
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

# The regression test for the actual finding: at full deflection, centre_x
# alone staying inside +-Corridor.HALF_WIDTH (as every test above checks) is
# not enough. Formation.slot adds up to +-Formation.WIDE_HALF_SPAN on top of
# centre_x and clamps that sum to the same corridor edge, so if centre_x is
# allowed to reach the wall itself, every row-0 WIDE column whose offset is
# positive (or negative, on the other side) gets clamped to the identical
# wall value AND the identical row -- several distinct starting units
# collapse onto one exact point, which is exactly what the human playtester
# saw first. (Checking x alone is not the right property: unit 0, column 0
# row 0, and unit 6, column 0 row 1 (WIDE_COLUMNS is 6), legitimately share
# an x because they are stacked in the same column -- that is ordinary grid
# layout, not the bug. The bug is two units sharing a full position.) Drives
# the real Squad/SteerInput pair the way game.gd does (steer.tick then
# squad.tick each frame) to full deflection in both directions, lets
# slot-lerp settle, and asserts no two live units occupy the same point. A
# reverted fix (clamping centre_x to the bare Corridor.HALF_WIDTH) fails
# this: three of WIDE's six row-0 columns have a positive offset (see
# Formation.WIDE_HALF_SPAN), so three per side land on the identical
# clamped point.
func test_full_deflection_never_stacks_two_wide_units_on_the_same_point():
    for drag_pixels in [100000.0, -100000.0]:
        var squad := Squad.new()
        var s := SteerInput.new()
        s.steer_to_screen_delta(Vector2(drag_pixels, 0))
        for i in 600:
            s.tick(1.0 / 60.0)
            squad.tick(1.0 / 60.0, s.centre_x)
        assert_eq(squad.formation, Formation.Kind.WIDE,
            "this regression is specific to the WIDE starting formation")
        var seen_points := {}
        for i in squad.count():
            var p: Vector2 = squad.units.positions[i].snapped(Vector2(0.0001, 0.0001))
            assert_false(seen_points.has(p),
                "units %s and %d both landed on %s at full deflection (drag=%s)"
                    % [seen_points.get(p), i, p, drag_pixels])
            seen_points[p] = i
