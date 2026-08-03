extends GutTest

var weapon: Weapon

func before_each():
    weapon = Weapon.new()

func test_tier_count_matches_the_tables():
    assert_eq(Weapon.TIER_COUNT, 5)

func test_tier_tables_are_monotonically_increasing_in_damage():
    # Not a strict requirement of the design, but a sanity check on the
    # placeholder numbers below: a "higher tier" that hits softer than a
    # lower one would be a data-entry bug, not a balance choice.
    var previous := 0.0
    for tier in Weapon.TIER_COUNT:
        var damage := Weapon.damage_at(tier)
        assert_gt(damage, previous, "tier %d must hit harder than tier %d" % [tier, tier - 1])
        previous = damage

func test_no_shots_before_the_interval_elapses():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 0)

func test_one_shot_per_interval():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0], 0), 1)

func test_a_long_frame_fires_the_whole_backlog():
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 3.0, 0), 3,
        "a stutter must not silently swallow shots")

func test_remainder_carries_into_the_next_frame():
    weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.75, 0)
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 1,
        "0.75 + 0.5 = 1.25 intervals, so exactly one shot")

func test_rate_is_frame_independent():
    var coarse := Weapon.new()
    var fine := Weapon.new()
    var coarse_shots := 0
    var fine_shots := 0
    for i in 60:
        coarse_shots += coarse.tick(1.0 / 60.0, 0)
    for i in 240:
        fine_shots += fine.tick(1.0 / 240.0, 0)
    assert_eq(coarse_shots, fine_shots,
        "one second of fire must be the same at any frame rate")

func test_higher_tier_fires_faster():
    # Tier 4's interval must be strictly shorter than tier 0's, and the
    # accumulator must actually use the tier passed to THIS call, not one
    # baked in earlier -- ticking the same weapon at different tiers on
    # consecutive calls must change its rate immediately.
    assert_lt(Weapon.TIER_FIRE_INTERVAL[4], Weapon.TIER_FIRE_INTERVAL[0])
    var w := Weapon.new()
    var one_second_tier0 := 0
    var one_second_tier4 := 0
    for i in 60:
        one_second_tier0 += w.tick(1.0 / 60.0, 0)
    w.reset()
    for i in 60:
        one_second_tier4 += w.tick(1.0 / 60.0, 4)
    assert_gt(one_second_tier4, one_second_tier0,
        "a higher tier must fire more often per second, not just hit harder")

func test_reset_clears_the_accumulator():
    weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.9, 0)
    weapon.reset()
    assert_eq(weapon.tick(Weapon.TIER_FIRE_INTERVAL[0] * 0.5, 0), 0)

func test_projectiles_per_shot_and_spread_scale_with_tier():
    # Not every tier needs spread (a single tight shot is a valid tier), but
    # the top tier must fire more projectiles than the bottom one, or the
    # tier table has no reason to exist.
    assert_gt(Weapon.projectiles_per_shot_at(4), Weapon.projectiles_per_shot_at(0))
