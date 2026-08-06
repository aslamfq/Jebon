class_name GatePair extends RefCounted

var left: Gate
var right: Gate
var y: float

func _init(p_left: Gate, p_right: Gate, p_y: float) -> void:
    left = p_left
    right = p_right
    y = p_y

func resolve(squad_centre_x: float) -> Gate:
    if left.contains(squad_centre_x):
        return left
    if right.contains(squad_centre_x):
        return right
    return null
