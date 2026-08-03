class_name Projectiles extends RefCounted

const MAX_PROJECTILES := 512

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_PROJECTILES)
    velocities.resize(MAX_PROJECTILES)

func fire(origin: Vector2, direction: Vector2, speed: float) -> bool:
    if count >= MAX_PROJECTILES:
        return false
    positions[count] = origin
    velocities[count] = direction.normalized() * speed
    count += 1
    return true

func tick(delta: float, despawn_radius: float) -> void:
    var radius_sq := despawn_radius * despawn_radius
    var i := 0
    while i < count:
        positions[i] += velocities[i] * delta
        if positions[i].length_squared() > radius_sq:
            _remove_at(i)
            continue
        i += 1

# Naive nested loop by design. Phase 3 replaces the inner scan with a radial
# broadphase behind this same signature, guarded by these tests.
func resolve_hits(units: Units, hit_radius: float, damage: float) -> int:
    var kills := 0
    var radius_sq := hit_radius * hit_radius
    var i := 0
    while i < count:
        var hit_index := -1
        for j in units.count:
            if positions[i].distance_squared_to(units.positions[j]) <= radius_sq:
                hit_index = j
                break
        if hit_index >= 0:
            kills += units.damage_at(units.positions[hit_index], 0.001, damage)
            _remove_at(i)
            continue
        i += 1
    return kills

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    velocities[i] = velocities[last]
    count = last
