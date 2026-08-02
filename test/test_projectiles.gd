extends GutTest

var projectiles: Projectiles
var horde: Horde

func before_each():
    projectiles = Projectiles.new()
    horde = Horde.new()

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
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    var kills := projectiles.resolve_hits(horde, 0.5, 4.0)
    assert_eq(kills, 0)
    assert_eq(projectiles.count, 0, "the bullet is spent")
    assert_almost_eq(horde.healths[0], 6.0, 0.001)

func test_a_lethal_hit_is_reported_as_a_kill():
    horde.spawn(Vector2(0, 10), 4.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 0.5, 4.0), 1)
    assert_eq(horde.count, 0)

func test_a_miss_leaves_both_sides_alone():
    horde.spawn(Vector2(0, 10), 10.0, 2.0)
    projectiles.fire(Vector2(20, 0), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 0.5, 4.0), 0)
    assert_eq(projectiles.count, 1)
    assert_eq(horde.count, 1)

func test_one_bullet_hits_only_one_zombie():
    horde.spawn(Vector2(0, 10), 4.0, 2.0)
    horde.spawn(Vector2(0.1, 10), 4.0, 2.0)
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)
    assert_eq(projectiles.resolve_hits(horde, 1.0, 4.0), 1,
        "no accidental piercing — that is an upgrade, not a default")
    assert_eq(horde.count, 1)

func test_resolve_hits_reprocesses_the_projectile_swapped_into_a_removed_slot():
    # Two bullets, each a dead-on hit against its own (widely separated)
    # zombie. Bullet 0 scores and is swap-removed with the tail (bullet 1),
    # which lands in slot 0 and must still be tested against its own target
    # in this same resolve_hits call — not skipped by an i += 1 that treats
    # slot 0 as already handled.
    horde.spawn(Vector2(0, 10), 4.0, 2.0)     # zombie A
    horde.spawn(Vector2(50, 10), 4.0, 2.0)    # zombie B, far from A
    projectiles.fire(Vector2(0, 10), Vector2(0, 1), 45.0)   # index 0: hits A
    projectiles.fire(Vector2(50, 10), Vector2(0, 1), 45.0)  # index 1: hits B
    var kills := projectiles.resolve_hits(horde, 0.5, 4.0)
    assert_eq(kills, 2, "both bullets must register their own kill despite the reindex")
    assert_eq(projectiles.count, 0, "the swapped-in bullet must still be resolved, not skipped")
    assert_eq(horde.count, 0)

func test_clear_empties_the_pool():
    projectiles.fire(Vector2.ZERO, Vector2(0, 1), 45.0)
    projectiles.clear()
    assert_eq(projectiles.count, 0)
