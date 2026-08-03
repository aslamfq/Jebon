class_name Weapon extends RefCounted

const TIER_COUNT := 5

# Placeholder first-pass numbers. Expect to retune these after playing, the
# same way SteerInput.SMOOTHING and PIXELS_PER_UNIT were tuned post-playtest
# in phase 1 -- these are the values that make the wiring provably correct,
# not a claim about final balance.
static var TIER_FIRE_INTERVAL := PackedFloat32Array([0.5, 0.42, 0.35, 0.3, 0.25])
static var TIER_DAMAGE := PackedFloat32Array([4.0, 5.0, 6.0, 7.0, 9.0])
static var TIER_PROJECTILES_PER_SHOT := PackedInt32Array([1, 1, 2, 3, 4])
static var TIER_SPREAD_DEGREES := PackedFloat32Array([0.0, 0.0, 8.0, 14.0, 20.0])

var projectile_speed := 35.0

var _accumulator := 0.0

static func damage_at(tier: int) -> float:
    return Weapon.TIER_DAMAGE[tier]

static func projectiles_per_shot_at(tier: int) -> int:
    return Weapon.TIER_PROJECTILES_PER_SHOT[tier]

static func spread_degrees_at(tier: int) -> float:
    return Weapon.TIER_SPREAD_DEGREES[tier]

func tick(delta: float, tier: int) -> int:
    _accumulator += delta
    var interval := TIER_FIRE_INTERVAL[tier]
    var shots := int(_accumulator / interval)
    _accumulator -= float(shots) * interval
    return shots

func reset() -> void:
    _accumulator = 0.0
