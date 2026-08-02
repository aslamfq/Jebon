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

# Strengthens the brief's sign-only check: 120 frames at 1/60s is 2 seconds, ~28 time
# constants past SMOOTHING's decay, so the aim should have converged on the exact angle
# PIXELS_PER_RADIAN implies, not merely landed somewhere positive. An implementation with
# the wrong pixel-to-radian scale, or one that only partially applies the drag, would still
# pass a bare assert_gt but fails the almost_eq below.
func test_dragging_right_aims_right():
    aim_input.aim_at_screen_delta(Vector2(200, 0))
    for i in 120:
        aim_input.tick(1.0 / 60.0)
    assert_gt(aim_input.aim.x, 0.0)
    var expected_angle: float = 200.0 / AimInput.PIXELS_PER_RADIAN
    assert_almost_eq(aim_input.aim.x, sin(expected_angle), 0.001)
    assert_almost_eq(aim_input.aim.y, cos(expected_angle), 0.001)

func test_dragging_left_aims_left():
    aim_input.aim_at_screen_delta(Vector2(-200, 0))
    for i in 120:
        aim_input.tick(1.0 / 60.0)
    assert_lt(aim_input.aim.x, 0.0)
    var expected_angle: float = -200.0 / AimInput.PIXELS_PER_RADIAN
    assert_almost_eq(aim_input.aim.x, sin(expected_angle), 0.001)
    assert_almost_eq(aim_input.aim.y, cos(expected_angle), 0.001)

func test_aim_never_leaves_the_frontal_arc():
    aim_input.aim_at_screen_delta(Vector2(100000, 0))
    for i in 300:
        aim_input.tick(1.0 / 60.0)
    var angle := atan2(aim_input.aim.x, aim_input.aim.y)
    assert_lte(angle, AimInput.MAX_ANGLE + 0.001,
        "the player must never aim behind themselves")

# Mirrors the brief's arc-clamp test on the other side. The brief only ever drags right, so
# an implementation that clamps the target angle asymmetrically (e.g. min(angle, MAX_ANGLE)
# with no lower bound) would pass every test above while still letting a hard-left drag put
# the player's aim behind themselves.
#
# Both bounds are checked, not just the lower one: an unclamped target angle of roughly
# -312.5 rad (from -100000 / PIXELS_PER_RADIAN with no lower clamp) still gets fed through
# sin()/cos(), and that periodicity wraps it to an equivalent angle of about +1.66 rad —
# past MAX_ANGLE on the *positive* side, not negative. A check of only the lower bound would
# have missed exactly the asymmetric-clamp bug this test exists to catch, because the wrapped
# angle trivially satisfies "angle >= -MAX_ANGLE" while still being outside the frontal arc.
func test_aim_never_leaves_the_frontal_arc_on_the_left():
    aim_input.aim_at_screen_delta(Vector2(-100000, 0))
    for i in 300:
        aim_input.tick(1.0 / 60.0)
    var angle := atan2(aim_input.aim.x, aim_input.aim.y)
    assert_gte(angle, -AimInput.MAX_ANGLE - 0.001,
        "the player must never aim behind themselves")
    assert_lte(angle, AimInput.MAX_ANGLE + 0.001,
        "the player must never aim behind themselves")

# Strengthens the brief's smoothed-not-instant check with the exact value the exp() formula
# predicts for one frame at 1/60s. A raw lerp(a, b, SMOOTHING * delta) produces a noticeably
# different angle here (0.2917 rad vs ~0.2604 rad) and would still pass the brief's loose
# "< MAX_ANGLE * 0.9" bound, so that bound alone does not prove the exp() form is in use.
func test_aim_is_smoothed_not_instant():
    aim_input.aim_at_screen_delta(Vector2(400, 0))
    aim_input.tick(1.0 / 60.0)
    var angle := atan2(aim_input.aim.x, aim_input.aim.y)
    assert_lt(angle, AimInput.MAX_ANGLE * 0.9,
        "one frame must not snap all the way across")
    var target_angle: float = 400.0 / AimInput.PIXELS_PER_RADIAN
    var t: float = 1.0 - exp(-AimInput.SMOOTHING * (1.0 / 60.0))
    var expected_angle: float = target_angle * t
    assert_almost_eq(angle, expected_angle, 0.001,
        "smoothing must follow 1 - exp(-k*dt), not a raw lerp")

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
    assert_almost_eq(aim_input.aim.x, 0.0, 0.001)
    assert_almost_eq(aim_input.aim.y, 1.0, 0.001)

# Strengthens the reset test above: reset() must clear the pending target, not just the
# current aim. An implementation that resets `aim` and the internal angle but forgets the
# target angle would pass the single-frame check above yet drift straight back toward the
# old drag target on the very next tick.
func test_reset_clears_the_pending_target_too():
    aim_input.aim_at_screen_delta(Vector2(200, 0))
    for i in 60:
        aim_input.tick(1.0 / 60.0)
    aim_input.reset()
    aim_input.tick(1.0 / 60.0)
    assert_almost_eq(aim_input.aim.x, 0.0, 0.001,
        "a leftover target must not pull aim away from forward after reset")
    assert_almost_eq(aim_input.aim.y, 1.0, 0.001)

# The property the exp() form exists for: total elapsed time determines the angle, not how
# it was chopped into frames. Drives the same 1/6 second of elapsed time as 10 frames at
# 60fps versus 100 frames at 600fps and asserts the results agree tightly. This elapsed time
# is deliberately short enough that the smoothing has not fully settled, which is what makes
# the test discriminating: a raw lerp(a, b, SMOOTHING * delta) is NOT frame-rate independent
# and diverges by roughly 0.015 rad between these two step sizes at this elapsed time, far
# outside the tolerance below, while the correct exp() form is frame-rate independent to
# floating-point precision. Nothing in the brief's own tests checks this even though the
# whole design rationale for choosing exp() over lerp is built on it.
func test_smoothing_is_frame_rate_independent():
    var coarse := AimInput.new()
    var fine := AimInput.new()
    coarse.aim_at_screen_delta(Vector2(200, 0))
    fine.aim_at_screen_delta(Vector2(200, 0))
    for i in 10:
        coarse.tick(1.0 / 60.0)
    for i in 100:
        fine.tick(1.0 / 600.0)
    var coarse_angle := atan2(coarse.aim.x, coarse.aim.y)
    var fine_angle := atan2(fine.aim.x, fine.aim.y)
    assert_almost_eq(coarse_angle, fine_angle, 0.001,
        "the same elapsed time must produce the same angle at any frame rate")
