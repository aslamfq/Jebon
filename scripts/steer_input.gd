class_name SteerInput extends RefCounted

const SMOOTHING := 14.0
const PIXELS_PER_UNIT := 90.0

var centre_x := 0.0

var _target_x := 0.0

func steer_to_screen_delta(delta_pixels: Vector2) -> void:
    _target_x = clamp(delta_pixels.x / PIXELS_PER_UNIT,
        -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)

func tick(delta: float) -> void:
    # Exponential smoothing. A raw lerp(a, b, k*delta) changes feel with frame
    # rate and can overshoot on a long frame; steering feel is the one thing
    # this whole phase exists to evaluate, so it must not vary by machine.
    var t: float = 1.0 - exp(-SMOOTHING * delta)
    centre_x += (_target_x - centre_x) * t

func reset() -> void:
    centre_x = 0.0
    _target_x = 0.0
