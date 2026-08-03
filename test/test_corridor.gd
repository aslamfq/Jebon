extends GutTest

func test_recycle_line_is_behind_the_squad():
    assert_lt(Corridor.RECYCLE_DISTANCE, 0.0,
        "content must only be recycled after it has passed the squad at y=0")

func test_spawn_distance_is_well_ahead():
    assert_gt(Corridor.SPAWN_DISTANCE, 0.0)
    assert_gt(Corridor.SPAWN_DISTANCE, Corridor.MAX_SCROLL_SPEED * 2.0,
        "a player must get at least two seconds of warning at top speed")

func test_scroll_starts_at_base_speed():
    assert_almost_eq(Corridor.scroll_speed_at(0.0), Corridor.BASE_SCROLL_SPEED, 0.001)

func test_scroll_accelerates():
    assert_gt(Corridor.scroll_speed_at(30.0), Corridor.scroll_speed_at(0.0))

func test_scroll_plateaus_and_never_exceeds_the_maximum():
    for seconds in [0.0, 60.0, 300.0, 3600.0, 100000.0]:
        assert_lte(Corridor.scroll_speed_at(seconds), Corridor.MAX_SCROLL_SPEED + 0.001,
            "an endless game that ramps forever becomes a countdown, not a game")

func test_scroll_is_close_to_maximum_after_the_ramp():
    var late := Corridor.scroll_speed_at(Corridor.SCROLL_RAMP_SECONDS * 4.0)
    assert_gt(late, Corridor.MAX_SCROLL_SPEED * 0.9,
        "the ramp must actually arrive, not creep forever")

func test_scroll_is_monotonic():
    var previous := 0.0
    for i in 200:
        var current := Corridor.scroll_speed_at(float(i) * 5.0)
        assert_gte(current, previous - 0.001, "speed must never drop mid-run")
        previous = current
