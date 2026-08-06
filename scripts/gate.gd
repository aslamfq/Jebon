class_name Gate extends RefCounted

# Corrected from the original design doc's x=+/-3, half-width 1.2: that footprint
# (spanning [1.8, 4.2]) sits partly outside SteerInput.MAX_CENTRE (3.75), which would
# make the "skip both gates" lane unreachable. This footprint ([1.4, 3.4]) fits inside
# it. See docs/specs/2026-08-06-onrush-gates-design.md.
const SIDE_OFFSET := 2.4
const HALF_WIDTH := 1.0

enum Op { ADD, MUL, TIER_STEP, SET_FORMATION }

var op: Op
var value: float
var x_centre: float

func _init(p_op: Op, p_value: float, p_x_centre: float) -> void:
    op = p_op
    value = p_value
    x_centre = p_x_centre

func contains(x: float) -> bool:
    return abs(x - x_centre) <= HALF_WIDTH

func apply(squad: Squad) -> void:
    match op:
        Op.ADD:
            squad.add_count(int(value))
        Op.MUL:
            squad.mul_count(value)
        Op.TIER_STEP:
            squad.step_weapon_tier(int(value))
        Op.SET_FORMATION:
            squad.set_formation(int(value))
