class_name Squad extends RefCounted

const SLOT_LERP := 12.0
const STARTING_COUNT := 12
const UNIT_HEALTH := 1.0

var units: Units
var formation: int = Formation.Kind.WIDE
var weapon_tier := 0
var centre_x := 0.0

func _init() -> void:
    units = Units.new()
    reset()

func count() -> int:
    return units.count

func set_count(n: int) -> void:
    var target: int = clamp(n, 0, Units.MAX_UNITS)
    if target < units.count:
        units.remove_last(units.count - target)
        return
    while units.count < target:
        # New units appear at their own slot rather than at the centre, so a
        # growth gate reads as the crowd widening instead of erupting from a point.
        var slot := Formation.slot(units.count, formation, centre_x)
        units.spawn(slot, Vector2.ZERO, UNIT_HEALTH)

func add_count(delta: int) -> void:
    set_count(max(count() + delta, 1))

func mul_count(factor: float) -> void:
    set_count(max(int(round(count() * factor)), 1))

func step_weapon_tier(delta: int) -> void:
    weapon_tier = clampi(weapon_tier + delta, 0, Weapon.TIER_COUNT - 1)

func set_formation(kind: int) -> void:
    formation = kind

func tick(delta: float, new_centre_x: float) -> void:
    centre_x = new_centre_x
    var t: float = 1.0 - exp(-SLOT_LERP * delta)
    for i in units.count:
        var target := Formation.slot(i, formation, centre_x)
        units.set_position(i, units.positions[i] + (target - units.positions[i]) * t)

func is_wiped() -> bool:
    return units.count <= 0

func reset() -> void:
    formation = Formation.Kind.WIDE
    weapon_tier = 0
    centre_x = 0.0
    units.clear()
    set_count(STARTING_COUNT)
