class_name Weapon extends RefCounted

var fire_interval := 0.12
var damage := 5.0
var projectile_speed := 45.0

var _accumulator := 0.0

func tick(delta: float) -> int:
    _accumulator += delta
    var shots := int(_accumulator / fire_interval)
    _accumulator -= float(shots) * fire_interval
    return shots

func reset() -> void:
    _accumulator = 0.0
