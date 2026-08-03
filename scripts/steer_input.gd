class_name SteerInput extends RefCounted

const SMOOTHING := 14.0

# How many screen pixels of drag correspond to one world unit of steering.
# Aslam found the previous value (90) too insensitive after MAX_CENTRE grew
# from 1.5 to 3.75 (WIDE_COLUMNS 11 -> 6): the range widened but this ratio
# didn't follow, so covering the same fraction of the corridor started
# needing 2.5x the finger travel. Lowered so a full-range swipe stays a
# comfortable thumb's-width (3.75 * 70 = 262.5px) rather than nearly a
# third of the 1080px viewport.
const PIXELS_PER_UNIT := 70.0

# The corridor's own half-width is not the right bound for centre_x: Formation
# slots sit up to WIDE_HALF_SPAN either side of centre_x, and WIDE is the
# widest formation. Clamping centre_x to the bare corridor edge let the WIDE
# formation's outer columns get clamped by Formation.slot's own safety net
# instead -- which collapses several distinct starting units onto the same
# x at full deflection (they all clamp to the same wall value). Reserving
# WIDE_HALF_SPAN here means centre_x itself stays far enough from the wall
# that ordinary play never reaches that clamp; Formation.slot's clamp remains
# only as a last-resort safety net.
const MAX_CENTRE := Corridor.HALF_WIDTH - Formation.WIDE_HALF_SPAN

var centre_x := 0.0

var _target_x := 0.0

func steer_to_screen_delta(delta_pixels: Vector2) -> void:
    _target_x = clamp(delta_pixels.x / PIXELS_PER_UNIT,
        -MAX_CENTRE, MAX_CENTRE)

func tick(delta: float) -> void:
    # Exponential smoothing. A raw lerp(a, b, k*delta) changes feel with frame
    # rate and can overshoot on a long frame; steering feel is the one thing
    # this whole phase exists to evaluate, so it must not vary by machine.
    var t: float = 1.0 - exp(-SMOOTHING * delta)
    centre_x += (_target_x - centre_x) * t

func reset() -> void:
    centre_x = 0.0
    _target_x = 0.0
