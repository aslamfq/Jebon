extends GutTest

var runner: TrackRunner

func before_each():
    runner = TrackRunner.new()

func test_starts_at_zero_distance():
    assert_almost_eq(runner.distance, 0.0, 0.001)

func test_distance_accumulates():
    runner.tick(1.0)
    assert_gt(runner.distance, 0.0)

func test_distance_matches_the_scroll_speed():
    runner.tick(1.0)
    assert_almost_eq(runner.distance, Corridor.scroll_speed_at(0.0), 0.5,
        "distance is accumulated scroll, so the two must agree")

func test_distance_never_decreases():
    var previous := 0.0
    for i in 300:
        runner.tick(1.0 / 60.0)
        assert_gte(runner.distance, previous)
        previous = runner.distance

# The brief's version only checks markers[0], which a broken implementation
# that updates index 0 and leaves the rest untouched would still pass. It also
# only checked direction, not magnitude. Marker 0 starts exactly on the
# recycle line, so even this very first tick wraps it -- the test must account
# for that rather than assume no marker wraps. Compute each marker's expected
# position independently (its own pre-tick value minus the scroll step,
# wrapped through the correct span) and require every marker to match, which
# also catches a wrong span (e.g. off by one marker) on the very first tick.
func test_markers_move_toward_the_squad():
    var before := PackedFloat32Array(runner.markers)
    runner.tick(0.25)
    var step: float = Corridor.scroll_speed_at(runner.elapsed) * 0.25
    var span: float = float(runner.markers.size()) * TrackRunner.MARKER_SPACING
    for i in runner.markers.size():
        var expected: float = before[i] - step
        while expected < Corridor.RECYCLE_DISTANCE:
            expected += span
        assert_almost_eq(runner.markers[i], expected, 0.001,
            "every marker must advance by the tick's scroll step, wrapping through the recycle line as needed")

func test_markers_recycle_instead_of_running_out():
    for i in 6000:
        runner.tick(1.0 / 60.0)
    assert_gt(runner.markers.size(), 0)
    for m in runner.markers:
        assert_between(m, Corridor.RECYCLE_DISTANCE - 0.001,
            Corridor.SPAWN_DISTANCE + TrackRunner.MARKER_SPACING + 0.001,
            "a marker outside the corridor means recycling is broken")

func test_marker_count_stays_constant():
    var initial := runner.markers.size()
    for i in 6000:
        runner.tick(1.0 / 60.0)
    assert_eq(runner.markers.size(), initial,
        "markers must be recycled, never allocated per frame")

func test_markers_stay_evenly_spaced():
    for i in 500:
        runner.tick(1.0 / 60.0)
    var sorted := Array(runner.markers)
    sorted.sort()
    for i in range(1, sorted.size()):
        assert_almost_eq(sorted[i] - sorted[i - 1], TrackRunner.MARKER_SPACING, 0.001,
            "uneven spacing would read as stuttering ground")

func test_scroll_accelerates_over_a_run():
    var early := runner.distance
    runner.tick(1.0)
    var first_second := runner.distance - early
    for i in 6000:
        runner.tick(1.0 / 60.0)
    var later := runner.distance
    runner.tick(1.0)
    assert_gt(runner.distance - later, first_second,
        "the run must speed up, or the ramp does nothing")

# The brief's version only checks distance and elapsed, which a reset() that
# forgot to restore markers would still pass -- and a run resumed with stale
# marker positions would show ground that visibly jumps on restart. Assert
# every marker lands back on its exact opening-state formula.
func test_reset_returns_to_the_start():
    for i in 600:
        runner.tick(1.0 / 60.0)
    runner.reset()
    assert_almost_eq(runner.distance, 0.0, 0.001)
    assert_almost_eq(runner.elapsed, 0.0, 0.001)
    for i in runner.markers.size():
        assert_almost_eq(runner.markers[i],
            Corridor.RECYCLE_DISTANCE + float(i) * TrackRunner.MARKER_SPACING, 0.001,
            "reset must also restore marker positions, not just distance and elapsed")
