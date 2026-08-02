class_name BarricadeSet extends RefCounted

enum Section { LEFT = 0, CENTRE = 1, RIGHT = 2 }

const SECTION_MAX_HEALTH := 100.0
const RADIUS := 4.0
const CENTRE_HALF_WIDTH := PI / 6.0   # three equal 60-degree sections across 180

var healths := PackedFloat32Array()

func _init() -> void:
    healths.resize(3)
    reset()

static func section_for_angle(angle: float) -> int:
    if angle < -CENTRE_HALF_WIDTH:
        return Section.LEFT
    if angle > CENTRE_HALF_WIDTH:
        return Section.RIGHT
    return Section.CENTRE

func damage(section: int, amount: float) -> void:
    healths[section] = max(healths[section] - amount, 0.0)

func is_broken() -> bool:
    for i in 3:
        if healths[i] <= 0.0:
            return true
    return false

func reset() -> void:
    for i in 3:
        healths[i] = SECTION_MAX_HEALTH
