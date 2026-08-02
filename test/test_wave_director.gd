extends GutTest

func test_starts_at_wave_one():
    var d := WaveDirector.new(42)
    assert_eq(d.wave, 1)

func test_wave_advances_on_the_timer():
    var d := WaveDirector.new(42)
    d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_eq(d.wave, 2)

func test_spawns_land_on_the_spawn_radius():
    var d := WaveDirector.new(42)
    var spawns := d.tick(5.0, 0)
    assert_gt(spawns.size(), 0, "five seconds must produce at least one spawn")
    for p in spawns:
        assert_almost_eq(p.length(), WaveDirector.SPAWN_RADIUS, 0.001)

func test_spawns_stay_inside_the_frontal_arc():
    var d := WaveDirector.new(42)
    var spawns := d.tick(30.0, 0)
    for p in spawns:
        var angle := atan2(p.x, p.y)
        assert_between(angle, -PI / 2.0, PI / 2.0,
            "nothing may spawn behind the player")

func test_is_deterministic_for_a_given_seed():
    var a := WaveDirector.new(7)
    var b := WaveDirector.new(7)
    for i in 20:
        assert_eq(a.tick(1.0, 0), b.tick(1.0, 0),
            "same seed must produce an identical run")

func test_different_seeds_diverge():
    var a := WaveDirector.new(1)
    var b := WaveDirector.new(2)
    var same := true
    for i in 20:
        if a.tick(1.0, 0) != b.tick(1.0, 0):
            same = false
    assert_false(same, "different seeds must produce different runs")

func test_respects_the_concurrency_cap():
    var d := WaveDirector.new(42)
    var spawns := d.tick(60.0, Horde.MAX_ZOMBIES)
    assert_eq(spawns.size(), 0, "must not spawn past the cap")

func test_spawns_only_up_to_remaining_headroom():
    var d := WaveDirector.new(42)
    var spawns := d.tick(60.0, Horde.MAX_ZOMBIES - 3)
    assert_lte(spawns.size(), 3)

func test_difficulty_escalates():
    var d := WaveDirector.new(42)
    var early_health := d.zombie_health()
    var early_speed := d.zombie_speed()
    for i in 10:
        d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_gt(d.zombie_health(), early_health, "later waves must be tougher")
    assert_gt(d.zombie_speed(), early_speed, "later waves must be faster")

func test_speed_plateaus_so_it_stays_playable():
    var d := WaveDirector.new(42)
    for i in 500:
        d.tick(WaveDirector.SECONDS_PER_WAVE + 0.1, 0)
    assert_lte(d.zombie_speed(), 8.0,
        "speed must converge, or late waves become unreadable")

func test_reset_returns_to_wave_one():
    var d := WaveDirector.new(42)
    d.tick(100.0, 0)
    d.reset()
    assert_eq(d.wave, 1)
