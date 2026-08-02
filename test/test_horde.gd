extends GutTest

var horde: Horde

func before_each():
    horde = Horde.new()

func test_spawn_increases_count():
    assert_true(horde.spawn(Vector2(0, 30), 10.0, 2.0))
    assert_eq(horde.count, 1)

func test_spawn_fails_when_full():
    for i in Horde.MAX_ZOMBIES:
        assert_true(horde.spawn(Vector2(0, 30), 10.0, 2.0))
    assert_false(horde.spawn(Vector2(0, 30), 10.0, 2.0), "cap must be enforced")
    assert_eq(horde.count, Horde.MAX_ZOMBIES)

func test_tick_moves_toward_origin():
    horde.spawn(Vector2(0, 30), 10.0, 2.0)
    horde.tick(1.0, 4.0)
    assert_almost_eq(horde.positions[0].y, 28.0, 0.001)

func test_tick_stops_at_stop_radius():
    horde.spawn(Vector2(0, 5), 10.0, 2.0)
    horde.tick(1.0, 4.0)
    assert_almost_eq(horde.positions[0].length(), 4.0, 0.001,
        "must clamp to the barricade, never walk past it")

func test_attackers_lists_only_those_at_the_barricade():
    horde.spawn(Vector2(0, 30), 10.0, 2.0)   # far
    horde.spawn(Vector2(0, 4), 10.0, 2.0)    # at the barricade
    var at := horde.attackers(4.0)
    assert_eq(at.size(), 1)
    assert_eq(at[0], 1)

func test_damage_at_kills_and_reports():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    var kills := horde.damage_at(Vector2(0, 10), 1.0, 10.0)
    assert_eq(kills, 1)
    assert_eq(horde.count, 0)

func test_damage_at_wounds_without_killing():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    var kills := horde.damage_at(Vector2(0, 10), 1.0, 4.0)
    assert_eq(kills, 0)
    assert_eq(horde.count, 1)
    assert_almost_eq(horde.healths[0], 6.0, 0.001)

func test_damage_at_misses_outside_radius():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    assert_eq(horde.damage_at(Vector2(0, 20), 1.0, 10.0), 0)
    assert_eq(horde.count, 1)

func test_swap_remove_keeps_survivors_intact():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)   # index 0, will die
    horde.spawn(Vector2(5, 5), 10.0, 3.0)    # index 1, must survive intact
    horde.damage_at(Vector2(0, 10), 1.0, 10.0)
    assert_eq(horde.count, 1)
    assert_eq(horde.positions[0], Vector2(5, 5))
    assert_almost_eq(horde.speeds[0], 3.0, 0.001)

func test_angle_of_is_zero_straight_ahead():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    assert_almost_eq(horde.angle_of(0), 0.0, 0.001)

func test_angle_of_is_positive_to_the_right():
    horde.spawn(Vector2(10, 0), 10.0, 2.0)
    assert_almost_eq(horde.angle_of(0), PI / 2.0, 0.001)
