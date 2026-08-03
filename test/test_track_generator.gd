extends GutTest

func test_health_and_speed_start_at_their_base_values():
    var g := TrackGenerator.new(42)
    var early_health := g.enemy_health()
    var early_speed := g.enemy_speed()
    for i in 10:
        g.tick(1.0 / 60.0, 0)
    assert_almost_eq(g.enemy_health(), early_health, 0.5)
    assert_almost_eq(g.enemy_speed(), early_speed, 0.5)

func test_health_and_speed_escalate_and_plateau():
    var g := TrackGenerator.new(42)
    var early_health := g.enemy_health()
    var early_speed := g.enemy_speed()
    for i in 36000:  # 600s at 1/60
        g.tick(1.0 / 60.0, 0)
    assert_gt(g.enemy_health(), early_health)
    assert_gt(g.enemy_speed(), early_speed)
    var plateaued_health := g.enemy_health()
    var plateaued_speed := g.enemy_speed()
    for i in 6000:  # another 100s
        g.tick(1.0 / 60.0, 0)
    assert_almost_eq(g.enemy_health(), plateaued_health, 0.5,
        "difficulty must plateau, or an endless game becomes a countdown")
    assert_almost_eq(g.enemy_speed(), plateaued_speed, 0.5)

func test_spawns_land_at_the_spawn_distance():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(10.0, 0)
    assert_gt(spawns.size(), 0, "ten seconds must produce at least one spawn")
    for p in spawns:
        assert_almost_eq(p.y, Corridor.SPAWN_DISTANCE, 0.001)

func test_spawns_stay_inside_the_corridor():
    var g := TrackGenerator.new(42)
    for i in 600:
        var spawns := g.tick(1.0, 0)
        for p in spawns:
            assert_between(p.x, -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001)

func test_group_size_escalates_so_later_spawns_have_more_enemies_per_group():
    # A group is however many spawns land at the same tick call. Measures
    # the largest single-tick burst in a short window near the start (well
    # inside GROUP_SIZE_RAMP_SECONDS=90, so size must still be small)
    # against a window well past it (near GROUP_SIZE_MAX). Two windows of
    # the SAME long duration back-to-back would both already sit at the
    # plateau and make this assertion trivially true regardless of whether
    # escalation happens at all -- the windows must straddle the ramp, not
    # just be "early" and "late" in name.
    var g := TrackGenerator.new(42)
    var early_max := 0
    for i in 10:
        early_max = max(early_max, g.tick(1.0, 0).size())
    for i in 300:
        g.tick(1.0, 0)
    var late_max := 0
    for i in 10:
        late_max = max(late_max, g.tick(1.0, 0).size())
    assert_gt(late_max, early_max,
        "group size must genuinely grow, not start at its plateau value")

func test_is_deterministic_for_a_given_seed():
    var a := TrackGenerator.new(7)
    var b := TrackGenerator.new(7)
    for i in 200:
        assert_eq(a.tick(1.0, 0), b.tick(1.0, 0),
            "same seed must produce an identical run")

func test_different_seeds_diverge():
    var a := TrackGenerator.new(1)
    var b := TrackGenerator.new(2)
    var same := true
    for i in 200:
        if a.tick(1.0, 0) != b.tick(1.0, 0):
            same = false
    assert_false(same, "different seeds must produce different runs")

func test_respects_the_concurrency_cap():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(60.0, Units.MAX_UNITS)
    assert_eq(spawns.size(), 0, "must not spawn past the cap")

func test_spawns_only_up_to_remaining_headroom():
    var g := TrackGenerator.new(42)
    var spawns := g.tick(60.0, Units.MAX_UNITS - 3)
    assert_eq(spawns.size(), 3,
        "must fill the available headroom exactly, not merely stay under it")

func test_reset_replays_the_same_spawn_sequence():
    var g := TrackGenerator.new(42)
    var first := []
    for i in 50:
        first.append(g.tick(1.0, 0))
    g.reset()
    var second := []
    for i in 50:
        second.append(g.tick(1.0, 0))
    for i in 50:
        assert_eq(first[i], second[i])

func test_reset_restores_base_difficulty():
    var g := TrackGenerator.new(42)
    for i in 36000:
        g.tick(1.0 / 60.0, 0)
    var escalated_health := g.enemy_health()
    g.reset()
    assert_lt(g.enemy_health(), escalated_health)
