class_name Horde extends RefCounted

const MAX_ZOMBIES := 256

var positions := PackedVector2Array()
var healths := PackedFloat32Array()
var speeds := PackedFloat32Array()
var count := 0

func _init() -> void:
    positions.resize(MAX_ZOMBIES)
    healths.resize(MAX_ZOMBIES)
    speeds.resize(MAX_ZOMBIES)

func spawn(pos: Vector2, health: float, speed: float) -> bool:
    if count >= MAX_ZOMBIES:
        return false
    positions[count] = pos
    healths[count] = health
    speeds[count] = speed
    count += 1
    return true

func tick(delta: float, stop_radius: float) -> void:
    for i in count:
        var pos := positions[i]
        var dist := pos.length()
        if dist <= stop_radius:
            continue
        var step: float = min(speeds[i] * delta, dist - stop_radius)
        positions[i] = pos - pos.normalized() * step

func attackers(stop_radius: float) -> PackedInt32Array:
    var result := PackedInt32Array()
    for i in count:
        if positions[i].length() <= stop_radius + 0.001:
            result.append(i)
    return result

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
                continue   # index i now holds a different zombie; re-check it
        i += 1
    return kills

func angle_of(i: int) -> float:
    return atan2(positions[i].x, positions[i].y)

func clear() -> void:
    count = 0

func _remove_at(i: int) -> void:
    var last := count - 1
    positions[i] = positions[last]
    healths[i] = healths[last]
    speeds[i] = speeds[last]
    count = last
