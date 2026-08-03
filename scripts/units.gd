class_name Units extends RefCounted

const MAX_UNITS := 256

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var healths := PackedFloat32Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_UNITS)
    velocities.resize(MAX_UNITS)
    healths.resize(MAX_UNITS)

func spawn(pos: Vector2, velocity: Vector2, health: float) -> bool:
    if count >= MAX_UNITS:
        return false
    positions[count] = pos
    velocities[count] = velocity
    healths[count] = health
    count += 1
    return true

func tick(delta: float) -> void:
    for i in count:
        positions[i] += velocities[i] * delta

func set_position(i: int, pos: Vector2) -> void:
    positions[i] = pos

func damage_at(point: Vector2, radius: float, amount: float) -> int:
    var kills := 0
    var radius_sq := radius * radius
    var i := 0
    while i < count:
        if positions[i].distance_squared_to(point) <= radius_sq:
            healths[i] -= amount
            if healths[i] <= 0.0:
                _remove_at(i)
                kills += 1
                continue   # slot i now holds a different unit; re-test it
        i += 1
    return kills

func remove_beyond(min_y: float) -> int:
    var removed := 0
    var i := 0
    while i < count:
        if positions[i].y < min_y:
            _remove_at(i)
            removed += 1
            continue
        i += 1
    return removed

func remove_last(n: int) -> void:
    count = max(count - n, 0)

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    velocities[i] = velocities[last]
    healths[i] = healths[last]
    count = last
