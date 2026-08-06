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

enum _Family { COUNT, WEAPON, FORMATION }

func _family_of(gate: Gate) -> int:
    match gate.op:
        Gate.Op.ADD, Gate.Op.MUL:
            return _Family.COUNT
        Gate.Op.TIER_STEP:
            return _Family.WEAPON
        _:
            return _Family.FORMATION

func test_tick_gates_produces_nothing_before_the_interval_elapses():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(0.5, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 0)

func test_tick_gates_spawns_a_pair_at_the_spawn_distance_once_the_interval_elapses():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 1)
    assert_almost_eq(spawns[0].y, Corridor.SPAWN_DISTANCE, 0.001)

func test_tick_gates_never_returns_more_than_one_pair_per_call():
    var g := TrackGenerator.new(42)
    # Five intervals' worth of delta in a single call -- a real backgrounded-app
    # catch-up frame could plausibly do this before Game.MAX_DELTA clamps it.
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL * 5.0, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 1,
        "at most one pair per call, or two pairs could land at the identical y and make trigger resolution ambiguous")

func test_a_spawned_pair_has_gates_on_opposite_sides():
    var g := TrackGenerator.new(42)
    var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
    var pair: GatePair = spawns[0]
    assert_almost_eq(pair.left.x_centre, -Gate.SIDE_OFFSET, 0.001)
    assert_almost_eq(pair.right.x_centre, Gate.SIDE_OFFSET, 0.001)

func test_pairs_are_cross_family_never_the_same_family_on_both_sides():
    var g := TrackGenerator.new(42)
    for i in 40:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        assert_ne(_family_of(pair.left), _family_of(pair.right),
            "a pair must always offer two different families, never the same family on both sides")

func test_formation_gate_never_offers_the_squads_current_formation():
    var g := TrackGenerator.new(42)
    var found_formation_gate := false
    for i in 200:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        for gate in [pair.left, pair.right]:
            if gate.op == Gate.Op.SET_FORMATION:
                found_formation_gate = true
                assert_ne(int(gate.value), Formation.Kind.WIDE,
                    "a Formation gate must never offer the formation the squad is already in")
    assert_true(found_formation_gate,
        "test setup problem: 200 pairs produced no Formation gate at all to check")

func test_non_formation_pairs_are_one_good_one_bad():
    # When neither side is Formation, Count/Weapon must split good/bad -- never
    # both positive or both negative, per the design's cross-family tension rule.
    var g := TrackGenerator.new(42)
    var checked := 0
    for i in 60:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        if pair.left.op == Gate.Op.SET_FORMATION or pair.right.op == Gate.Op.SET_FORMATION:
            continue
        checked += 1
        assert_ne(pair.left.is_good(), pair.right.is_good(),
            "exactly one side of a non-Formation pair must be good and the other bad")
    assert_gt(checked, 0, "test setup problem: no non-Formation pair appeared to check")

func test_formation_side_of_a_pair_is_never_treated_as_the_deliberately_bad_side():
    # Design intent: Formation is neutral, never the coin-flipped "bad" side of
    # a pair (see Gate.is_good()'s doc comment -- callers must not read it for
    # SET_FORMATION gates). Pin this at the generator level: across many pairs,
    # a Formation gate's is_good coin-flip parameter must vary (it's still
    # randomly assigned true/false by _spawn_gate_pair), but the OTHER side of
    # the pair must never itself be forced bad merely because Formation was
    # picked -- i.e. when one side is Formation, the non-Formation side's
    # good/bad must still vary across runs rather than being pinned to "bad".
    var g := TrackGenerator.new(42)
    var non_formation_good_seen := false
    var non_formation_bad_seen := false
    for i in 200:
        var spawns := g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL, Formation.Kind.WIDE)
        if spawns.size() == 0:
            continue
        var pair: GatePair = spawns[0]
        var formation_side: Gate = null
        var other_side: Gate = null
        if pair.left.op == Gate.Op.SET_FORMATION:
            formation_side = pair.left
            other_side = pair.right
        elif pair.right.op == Gate.Op.SET_FORMATION:
            formation_side = pair.right
            other_side = pair.left
        if formation_side == null:
            continue
        assert_eq(formation_side.op, Gate.Op.SET_FORMATION)
        if other_side.is_good():
            non_formation_good_seen = true
        else:
            non_formation_bad_seen = true
    assert_true(non_formation_good_seen and non_formation_bad_seen,
        "the non-Formation side of a Formation pair must still vary good/bad across runs, not be pinned bad because Formation was 'the other side'")

func test_count_delta_range_widens_with_elapsed_time():
    var g := TrackGenerator.new(42)
    var early := g.count_delta_range()
    for i in 36000:  # 600s at 1/60, well past every ramp constant in this file
        g.tick(1.0 / 60.0, 0)
        g.tick_gates(1.0 / 60.0, Formation.Kind.WIDE)
    var late := g.count_delta_range()
    assert_gt(late.y, early.y,
        "the maximum Count delta must grow with distance, or later gates never feel more severe")

func test_gate_spawning_does_not_perturb_the_enemy_spawn_sequence():
    # Gate values must be drawn from a separate RNG stream. If they shared
    # _rng with enemy spawning, interleaving tick_gates() calls would change
    # the enemy spawn sequence for a fixed seed -- silently breaking every
    # existing determinism test above the moment gates were added.
    var without_gates := TrackGenerator.new(7)
    var with_gates := TrackGenerator.new(7)
    for i in 100:
        var a := without_gates.tick(1.0, 0)
        with_gates.tick_gates(1.0, Formation.Kind.WIDE)
        var b := with_gates.tick(1.0, 0)
        assert_eq(a, b, "enemy spawns must be identical whether or not tick_gates was ever called")

func test_reset_replays_the_same_gate_sequence():
    var g := TrackGenerator.new(42)
    var first: Array[bool] = []
    for i in 50:
        first.append(g.tick_gates(1.0, Formation.Kind.WIDE).size() > 0)
    g.reset()
    var second: Array[bool] = []
    for i in 50:
        second.append(g.tick_gates(1.0, Formation.Kind.WIDE).size() > 0)
    assert_eq(first, second)

func test_reset_zeroes_the_gate_spawn_clock():
    var g := TrackGenerator.new(42)
    g.tick_gates(TrackGenerator.GATE_SPAWN_INTERVAL - 0.1, Formation.Kind.WIDE)
    g.reset()
    var spawns := g.tick_gates(0.5, Formation.Kind.WIDE)
    assert_eq(spawns.size(), 0,
        "reset must zero the gate clock -- otherwise a run that reset just before a spawn would spawn immediately on the new run's very first tick")
