extends GutTest

var projectiles: Projectiles
var units: Units

func before_each():
    projectiles = Projectiles.new()
    units = Units.new()

func test_fire_increases_count():
    assert_true(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0))
    assert_eq(projectiles.count, 1)

func test_fire_fails_when_pool_is_full():
    for i in Projectiles.MAX_PROJECTILES:
        assert_true(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0))
    assert_false(projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0), "cap must be enforced")
    assert_eq(projectiles.count, Projectiles.MAX_PROJECTILES)

func test_direction_is_normalised_before_use():
    projectiles.fire(Vector2.ZERO, Vector2(0, 5), 10.0)
    projectiles.tick(1.0, 100.0)
    assert_almost_eq(projectiles.positions[0].y, 10.0, 0.001,
        "an unnormalised direction must not multiply the speed")

func test_tick_moves_along_the_velocity():
    projectiles.fire(Vector2.ZERO, Vector2(1, 0), 10.0)
    projectiles.tick(0.5, 100.0)
    assert_almost_eq(projectiles.positions[0].x, 5.0, 0.001)

func test_projectiles_despawn_past_the_radius():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0, "bullets must not accumulate off-screen forever")

func test_tick_reprocesses_the_projectile_swapped_into_a_removed_slot():
    # index 0 despawns this tick and is swap-removed with the tail (index 1).
    # The tail must then be re-tested at its NEW slot 0 in the same tick call
    # — moved exactly once and despawn-checked — not skipped by an i += 1
    # that assumes slot 0 was already handled.
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 1000.0)   # index 0: despawns this tick
    projectiles.fire(Vector2.ZERO, Vector2(1, 0), 10.0)     # index 1: must survive and still move
    projectiles.tick(1.0, 50.0)
    assert_eq(projectiles.count, 1, "the despawning projectile must be removed")
    assert_almost_eq(projectiles.positions[0].x, 10.0, 0.001,
        "the swapped-in survivor must still be advanced by this tick, exactly once")

func test_hit_damages_the_zombie_and_consumes_the_bullet():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    var kills := projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(kills, 0)
    assert_eq(projectiles.count, 0, "the bullet is spent")
    assert_almost_eq(units.healths[0], 6.0, 0.001)

func test_a_lethal_hit_is_reported_as_a_kill():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(units, 0.5, 4.0), 1)
    assert_eq(units.count, 0)

func test_a_miss_leaves_both_sides_alone():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(20, 0), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(units, 0.5, 4.0), 0)
    assert_eq(projectiles.count, 1)
    assert_eq(units.count, 1)

func test_one_bullet_hits_only_one_zombie():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    units.spawn(Vector2(0.1, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(units, 1.0, 4.0), 1,
        "no accidental piercing — that is an upgrade, not a default")
    assert_eq(units.count, 1)

func test_resolve_hits_reprocesses_the_projectile_swapped_into_a_removed_slot():
    # Two bullets, each a dead-on hit against its own (widely separated)
    # zombie. Bullet 0 scores and is swap-removed with the tail (bullet 1),
    # which lands in slot 0 and must still be tested against its own target
    # in this same resolve_hits call — not skipped by an i += 1 that treats
    # slot 0 as already handled.
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)     # zombie A
    units.spawn(Vector2(50, 10), Vector2.ZERO, 4.0)    # zombie B, far from A
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)   # index 0: hits A
    projectiles.fire(Vector2(50, 10), Vector2(0, 1), 45.0)  # index 1: hits B
    var kills := projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(kills, 2, "both bullets must register their own kill despite the reindex")
    assert_eq(projectiles.count, 0, "the swapped-in bullet must still be resolved, not skipped")
    assert_eq(units.count, 0)

func test_a_fast_bullet_does_not_tunnel_through_a_target():
    # resolve_hits used to sample only the position AFTER tick() moved it --
    # a bullet fast enough to land on the far side of its target in a single
    # frame would never have a sample point within hit_radius of it, even
    # though the swept path passed straight through. Fires from just behind
    # a stationary target, at a speed/step that jumps clean past it.
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 9), Vector2(0, 1), 20.0)
    projectiles.tick(0.1, 100.0)
    assert_almost_eq(projectiles.positions[0].y, 11.0, 0.001,
        "sanity check: the bullet must have actually jumped past the target this tick")
    assert_eq(projectiles.resolve_hits(units, 0.5, 4.0), 0)
    assert_eq(projectiles.count, 0, "the bullet is spent")
    assert_almost_eq(units.healths[0], 6.0, 0.001,
        "the swept path passed directly through the target -- a point-only check at the final position alone would miss this entirely")

func test_clear_empties_the_pool():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0)
    projectiles.clear()
    assert_eq(projectiles.count, 0)

func test_clear_also_empties_the_removal_reports():
    # Game._restart() calls clear() mid-frame and then renders. Leaving the
    # removal reports populated lets that frame's render() replay a wiped
    # run's impact bursts against stale data, and lets any caller that
    # relies on clear() alone (test_game_integration's _simulate mirror
    # among them) grow both arrays without bound across a long run.
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 1, "sanity check: a removal was reported")
    projectiles.clear()
    assert_eq(projectiles.count, 0)
    assert_eq(projectiles.removed_positions.size(), 0,
        "clear() must wipe the removal report, not just the live count")
    assert_eq(projectiles.removed_previous_positions.size(), 0,
        "clear() must wipe the parallel pre-move report too")

func test_removed_positions_is_empty_when_nothing_is_removed():
    units.spawn(Vector2(0, 100), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 0), Vector2(0, 1), 1.0)
    projectiles.tick(0.1, 1000.0)
    assert_eq(projectiles.removed_positions.size(), 0)

func test_removed_positions_reports_a_despawn():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0, "sanity check: the despawn actually happened")
    assert_eq(projectiles.removed_positions.size(), 1)
    assert_almost_eq(projectiles.removed_positions[0].y, 100.0, 0.001,
        "must report where the projectile actually was when it despawned, not the origin")

func test_removed_positions_reports_a_hit():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 1)
    assert_almost_eq(projectiles.removed_positions[0].x, 0.0, 0.001)
    assert_almost_eq(projectiles.removed_positions[0].y, 10.0, 0.001)

func test_removed_positions_accumulates_across_calls_with_no_clear_between():
    # game.gd calls tick() then resolve_hits() on the same Projectiles
    # instance every frame, with no clear in between, before a single
    # render() call reads removed_positions -- so a real frame's report
    # must combine both calls' removals, not just reflect whichever ran
    # last. Neither method clears at its own start any more; that's the
    # caller's job, once per frame (see game.gd).
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.removed_positions.size(), 1, "sanity check: first call reported one")
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 1.0)
    projectiles.tick(0.01, 1000.0)
    assert_eq(projectiles.removed_positions.size(), 1,
        "a second call that removes nothing must leave the first call's report intact")

func test_removed_positions_reports_every_removal_in_one_call():
    # Two bullets that both despawn in the same tick() call.
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.fire(Vector2(5, 0), Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.count, 0)
    assert_eq(projectiles.removed_positions.size(), 2,
        "both removals in this call must be reported, not just the last one")

func test_removed_positions_accumulates_across_tick_then_resolve_hits():
    # The exact sequence game.gd runs every frame for one pool: tick()
    # (despawns) immediately followed by resolve_hits() (hits), with no
    # clear between them. Both calls' removals must land in one combined
    # report for render() to see -- this is the property that was broken
    # when each method cleared removed_positions at its own start:
    # resolve_hits()'s clear silently wiped out tick()'s despawn every
    # frame.
    units.spawn(Vector2(0, 100), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 0), Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.removed_positions.size(), 1, "sanity check: first call reported one")
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 2,
        "resolve_hits() must add to tick()'s report, not replace it")

# ---- removed_previous_positions: the pre-move half of the removal report ----
#
# ProjectileView correlates a removal against its pooled instances by
# position, but every pooled instance's position is one frame stale at the
# point of that comparison (the position-sync loop runs after the
# burst-trigger check in render()). Comparing against removed_positions --
# the position AFTER that frame's tick() -- is therefore always off by
# exactly speed x delta, which for the squad's 35.0-unit/s projectiles is
# 0.583 units per 60fps frame: far enough that no pooled instance ever
# matched and squad-side impact bursts never played at all (measured: 252
# squad removals, 0 bursts, over a 900-frame instrumented run). The
# pre-move position is what a pool slot actually still holds at comparison
# time, so reporting it alongside makes the correlation exact instead of
# speed-dependent.

func test_removed_previous_positions_reports_the_pre_move_position_of_a_despawn():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)
    projectiles.tick(1.0, 30.0)
    assert_eq(projectiles.removed_previous_positions.size(), 1)
    assert_almost_eq(projectiles.removed_positions[0].y, 100.0, 0.001,
        "sanity check: the removal itself is still reported at the post-move position")
    assert_almost_eq(projectiles.removed_previous_positions[0].y, 0.0, 0.001,
        "the parallel report must be where the projectile was BEFORE this tick moved it")

func test_removed_previous_positions_reports_the_pre_move_position_of_a_hit():
    units.spawn(Vector2(0, 10), Vector2.ZERO, 10.0)
    projectiles.fire(Vector2(0, 9), Vector2(0, 1), 20.0)
    projectiles.tick(0.1, 100.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 1, "sanity check: the hit was reported")
    assert_almost_eq(projectiles.removed_positions[0].y, 11.0, 0.001)
    assert_almost_eq(projectiles.removed_previous_positions[0].y, 9.0, 0.001,
        "a hit's pre-move position is where the swept segment started, not where it ended")

func test_removed_previous_positions_stays_parallel_across_tick_then_resolve_hits():
    # The exact per-frame sequence game.gd runs. Every entry in one report
    # must have a same-index counterpart in the other, or ProjectileView's
    # correlation reads a mismatched pair.
    units.spawn(Vector2(0, 10), Vector2.ZERO, 4.0)
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 100.0)    # despawns in tick()
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)   # hits in resolve_hits()
    projectiles.tick(0.31, 30.0)
    projectiles.resolve_hits(units, 0.5, 4.0)
    assert_eq(projectiles.removed_positions.size(), 2, "sanity check: both removals happened")
    assert_eq(projectiles.removed_previous_positions.size(),
        projectiles.removed_positions.size(),
        "both methods must append to both reports, keeping them index-parallel")

func test_removed_previous_positions_is_one_frame_of_travel_behind_the_removal():
    # The property that makes the correlation work at any projectile speed:
    # the gap between the two reports is exactly one frame of travel, which
    # is precisely the offset that defeated the old post-move comparison.
    var speed := 35.0
    var step := 1.0 / 60.0
    projectiles.fire(Vector2(0, 29.9), Vector2(0, 1), speed)
    projectiles.tick(step, 30.0)
    assert_eq(projectiles.count, 0, "sanity check: the despawn actually happened")
    var gap: float = projectiles.removed_positions[0].distance_to(
        projectiles.removed_previous_positions[0])
    assert_almost_eq(gap, speed * step, 0.0001)
