extends GutTest

var units: Units
var projectiles: Projectiles

func before_each():
    units = Units.new()
    projectiles = Projectiles.new()

func test_zero_shots_fires_nothing():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 0, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 0)

func test_one_shot_one_unit_one_projectile_per_shot():
    units.spawn(Vector2(3, 4), Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 1)
    assert_eq(projectiles.positions[0], Vector2(3, 4),
        "the projectile must originate at the firing unit's own position")

func test_firepower_scales_with_unit_count():
    # This is the property the whole class exists for: N units at the same
    # tier must fire N times the projectiles of one unit, not a fixed
    # number from an abstract origin. An implementation that fires once
    # regardless of unit count would pass test_one_shot_one_unit... above
    # but fail this.
    for i in 5:
        units.spawn(Vector2(float(i), 0), Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 5)

func test_multiple_shots_multiply_the_count():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 3, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 3,
        "a long frame firing 3 trigger pulses must not silently collapse to 1")

func test_projectiles_per_shot_multiplies_the_count_too():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 4, 20.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 4)

func test_no_spread_fires_straight_along_forward():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_almost_eq(projectiles.positions[0].x, 0.0, 0.0001)

func test_spread_fans_symmetrically_around_forward():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 2, 20.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, 2)
    # Two projectiles at +-10 degrees off straight-ahead must have equal and
    # opposite lateral displacement after moving the same distance forward.
    # (Positions equal the origin -- Vector2.ZERO here -- until ticked, so a
    # tick is required to actually observe the fan; reading positions
    # straight off fire() would trivially compare 0.0 to -0.0.)
    projectiles.tick(1.0, 1000.0)
    var a := projectiles.positions[0]
    var b := projectiles.positions[1]
    assert_almost_eq(a.x, -b.x, 0.0001,
        "an even projectile count must fan symmetrically, not lean to one side")
    assert_gt(abs(a.x), 0.001, "some spread must actually be applied")

func test_direction_reverses_for_the_opposite_side():
    # Proves the same call works unmodified for enemies firing the other
    # way -- the only difference from the squad's own call is this vector.
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, -1), 10.0)
    for i in 60:
        projectiles.tick(1.0 / 60.0, 1000.0)
    assert_lt(projectiles.positions[0].y, 0.0,
        "firing with forward=(0,-1) must send the projectile toward negative y")

func test_speed_is_honoured():
    units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    projectiles.tick(1.0, 1000.0)
    assert_almost_eq(projectiles.positions[0].y, 10.0, 0.01)

func test_stops_firing_once_the_projectile_pool_is_full():
    for i in 3:
        units.spawn(Vector2.ZERO, Vector2.ZERO, 1.0)
    # Fill the pool to exactly one slot short of capacity, then fire from
    # 3 units -- only one of the three can possibly land.
    for i in Projectiles.MAX_PROJECTILES - 1:
        projectiles.fire(Vector2.ZERO, Vector2(0, 1), 1.0)
    Volley.fire(units, projectiles, 1, 1, 0.0, Vector2(0, 1), 10.0)
    assert_eq(projectiles.count, Projectiles.MAX_PROJECTILES,
        "must cap at the pool size rather than overflow or crash")
