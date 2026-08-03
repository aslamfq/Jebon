extends GutTest

var units: Units

func before_each():
    units = Units.new()

func test_spawn_increases_count():
    assert_true(units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0))
    assert_eq(units.count, 1)

func test_spawn_fails_when_full_and_count_stays_at_the_cap():
    for i in Units.MAX_UNITS:
        assert_true(units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0))
    assert_false(units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0))
    assert_eq(units.count, Units.MAX_UNITS)

func test_tick_integrates_velocity():
    units.spawn(Vector2(0, 10), Vector2(2, -3), 10.0)
    units.tick(0.5)
    assert_almost_eq(units.positions[0].x, 1.0, 0.001)
    assert_almost_eq(units.positions[0].y, 8.5, 0.001)

func test_a_stationary_unit_does_not_move():
    units.spawn(Vector2(4, 4), Vector2.ZERO, 10.0)
    units.tick(1.0)
    assert_almost_eq(units.positions[0].x, 4.0, 0.001)
    assert_almost_eq(units.positions[0].y, 4.0, 0.001)

func test_tick_is_frame_rate_independent():
    var coarse := Units.new()
    var fine := Units.new()
    coarse.spawn(Vector2.ZERO, Vector2(0, 10), 1.0)
    fine.spawn(Vector2.ZERO, Vector2(0, 10), 1.0)
    for i in 10:
        coarse.tick(0.1)
    for i in 100:
        fine.tick(0.01)
    assert_almost_eq(coarse.positions[0].y, fine.positions[0].y, 0.001)

func test_damage_at_kills_and_reports():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 10.0), 1)
    assert_eq(units.count, 0)

func test_damage_at_wounds_without_killing():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 4.0), 0)
    assert_almost_eq(units.healths[0], 6.0, 0.001)

func test_damage_at_misses_outside_radius():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    assert_eq(units.damage_at(Vector2(0, 20), 1.0, 10.0), 0)
    assert_eq(units.count, 1)

func test_damage_at_kills_every_clustered_unit_in_one_call():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(0.2, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(-0.2, 10), Vector2.ZERO, 1.0)
    assert_eq(units.damage_at(Vector2(0, 10), 1.0, 5.0), 3,
        "swap-remove must re-test the unit swapped into the vacated slot")
    assert_eq(units.count, 0)

func test_swap_remove_keeps_survivors_intact():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(5, 5), Vector2(1, 2), 7.0)
    units.damage_at(Vector2(0, 10), 0.5, 5.0)
    assert_eq(units.count, 1)
    assert_eq(units.positions[0], Vector2(5, 5))
    assert_eq(units.velocities[0], Vector2(1, 2))
    assert_almost_eq(units.healths[0], 7.0, 0.001)

func test_remove_beyond_drops_only_what_has_passed():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 1.0)
    units.spawn(Vector2(0, -10), Vector2.ZERO, 1.0)
    assert_eq(units.remove_beyond(-5.0), 1)
    assert_eq(units.count, 1)
    assert_almost_eq(units.positions[0].y, 10.0, 0.001)

func test_remove_beyond_handles_every_unit_passing_at_once():
    for i in 5:
        units.spawn(Vector2(0, -10.0 - float(i)), Vector2.ZERO, 1.0)
    assert_eq(units.remove_beyond(-5.0), 5)
    assert_eq(units.count, 0)

func test_remove_last_shrinks_from_the_end():
    for i in 5:
        units.spawn(Vector2(float(i), 0), Vector2.ZERO, 1.0)
    units.remove_last(2)
    assert_eq(units.count, 3)
    assert_almost_eq(units.positions[0].x, 0.0, 0.001)

func test_remove_last_cannot_go_negative():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    units.remove_last(50)
    assert_eq(units.count, 0)

func test_clear_empties():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    units.clear()
    assert_eq(units.count, 0)
