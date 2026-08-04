class_name Projectiles extends RefCounted

const MAX_PROJECTILES := 512

var positions := PackedVector2Array()
# Where each projectile was at the START of its most recent tick (or at fire,
# if never ticked). resolve_hits tests the swept segment from here to
# positions[i], not just where the projectile landed -- a bullet fast enough
# to land on the far side of its target in one frame would otherwise tunnel
# through it untouched, since neither its old nor new sample point falls
# within hit_radius even though the path between them does.
var previous_positions := PackedVector2Array()
var velocities := PackedVector2Array()
var removed_positions := PackedVector2Array()
# Index-parallel to removed_positions: where that same removal was at the
# START of the frame it died in (its previous_positions entry), not where it
# ended up. ProjectileView needs this to work out WHICH of its pooled
# instances a given removal belonged to: it correlates by position, and
# every pooled instance's position is one frame stale at the moment of that
# comparison (render() runs its burst-trigger check before its position-sync
# loop), so the only position a pool slot still holds then is the pre-move
# one. Correlating against removed_positions instead is always off by
# exactly speed x delta -- 0.583 units/frame for the squad's 35.0-unit/s
# projectiles at 60fps, which overshot the old 0.5-unit match threshold on
# every single squad removal (measured: 252 squad removals, 0 bursts, in a
# 900-frame instrumented run) while the enemy's slower 25.0-unit/s
# projectiles squeaked under it at 0.417 and appeared to work. Reporting
# both positions makes the match exact at any speed instead of accidentally
# tuned to one. Same append-only, caller-clears semantics as
# removed_positions below.
var removed_previous_positions := PackedVector2Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_PROJECTILES)
    previous_positions.resize(MAX_PROJECTILES)
    velocities.resize(MAX_PROJECTILES)

func fire(origin: Vector2, direction: Vector2, speed: float) -> bool:
    if count >= MAX_PROJECTILES:
        return false
    positions[count] = origin
    previous_positions[count] = origin
    velocities[count] = direction.normalized() * speed
    count += 1
    return true

func tick(delta: float, despawn_radius: float) -> void:
    # Deliberately does NOT clear removed_positions -- see resolve_hits below
    # for why clearing lives with the caller instead of here.
    var radius_sq := despawn_radius * despawn_radius
    var i := 0
    while i < count:
        previous_positions[i] = positions[i]
        positions[i] += velocities[i] * delta
        if positions[i].length_squared() > radius_sq:
            removed_positions.append(positions[i])
            removed_previous_positions.append(previous_positions[i])
            _remove_at(i)
            continue
        i += 1

# Naive nested loop by design. Phase 3 replaces the inner scan with a radial
# broadphase behind this same signature, guarded by these tests.
func resolve_hits(units: Units, hit_radius: float, damage: float) -> int:
    # Deliberately does NOT clear removed_positions. game.gd calls tick()
    # then resolve_hits() on the same Projectiles instance every frame,
    # before a single render() call reads removed_positions -- if either
    # method cleared its own start, whichever ran second would wipe out
    # the first's report and only that method's removals would ever reach
    # render(), silently losing despawns (tick()'s only source) every
    # frame. Both methods only ever append; the caller (game.gd) clears
    # removed_positions itself, once per frame per pool, before its
    # tick()/resolve_hits() pair, so a frame's removals from both calls
    # accumulate into one combined report.
    var kills := 0
    var radius_sq := hit_radius * hit_radius
    var i := 0
    while i < count:
        var hit_index := -1
        for j in units.count:
            var closest := Geometry2D.get_closest_point_to_segment(
                units.positions[j], previous_positions[i], positions[i])
            if closest.distance_squared_to(units.positions[j]) <= radius_sq:
                hit_index = j
                break
        if hit_index >= 0:
            kills += units.damage_at(units.positions[hit_index], 0.001, damage)
            removed_positions.append(positions[i])
            removed_previous_positions.append(previous_positions[i])
            _remove_at(i)
            continue
        i += 1
    return kills

func clear() -> void:
    count = 0
    # Wiping the live count without wiping the removal reports leaves this
    # frame's pre-restart removals visible to the render() call that follows
    # Game._restart() in the same frame, replaying a wiped run's impact
    # bursts against stale data. It also let any caller that relies on
    # clear() alone rather than on game.gd's own per-frame clears (the
    # _simulate() mirror in test/test_game_integration.gd was doing exactly
    # that) grow both arrays without bound across a long run. A full reset
    # means all of this object's state, not just `count`.
    removed_positions.clear()
    removed_previous_positions.clear()

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    previous_positions[i] = previous_positions[last]
    velocities[i] = velocities[last]
    count = last
