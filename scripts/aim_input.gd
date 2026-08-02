class_name AimInput extends RefCounted

const SMOOTHING := 14.0
const MAX_ANGLE := PI / 2.0
const PIXELS_PER_RADIAN := 320.0

var aim := Vector2(0, 1)

var _target_angle := 0.0
var _angle := 0.0

func aim_at_screen_delta(delta_pixels: Vector2) -> void:
    _target_angle = clamp(delta_pixels.x / PIXELS_PER_RADIAN, -MAX_ANGLE, MAX_ANGLE)

func tick(delta: float) -> void:
    # Exponential smoothing, frame-rate independent.
    var t: float = 1.0 - exp(-SMOOTHING * delta)
    _angle += (_target_angle - _angle) * t
    aim = Vector2(sin(_angle), cos(_angle))

func reset() -> void:
    _angle = 0.0
    _target_angle = 0.0
    aim = Vector2(0, 1)
