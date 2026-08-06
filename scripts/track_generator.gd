class_name TrackGenerator extends RefCounted

const GROUP_INTERVAL_BASE := 2.5
const GROUP_INTERVAL_MIN := 0.6
const GROUP_INTERVAL_DECAY := 0.02

const GROUP_SIZE_BASE := 1
const GROUP_SIZE_MAX := 5
const GROUP_SIZE_RAMP_SECONDS := 90.0

const ENEMY_BASE_HEALTH := 8.0
const ENEMY_MAX_HEALTH := 24.0
const ENEMY_HEALTH_RAMP_SECONDS := 120.0

const ENEMY_BASE_SPEED := 2.5
const ENEMY_MAX_SPEED := 5.0
const ENEMY_SPEED_RAMP_SECONDS := 120.0

const GROUP_SPREAD := 2.0

# Gate cadence is fixed, not decaying like GROUP_INTERVAL -- the spec escalates
# gate SEVERITY with distance, not how often gates appear.
const GATE_SPAWN_INTERVAL := 6.0

# XORed into the constructor seed so the gate RNG stream is fully independent of
# _rng (enemy spawning). Any fixed nonzero constant works; this one just needs to
# never collide with a real seed in practice.
const GATE_RNG_SEED_XOR := 0x5bd1e995

const COUNT_DELTA_BASE_MIN := 3.0
const COUNT_DELTA_BASE_MAX := 6.0
const COUNT_DELTA_MAX_MIN := 8.0
const COUNT_DELTA_MAX_MAX := 20.0
const COUNT_DELTA_RAMP_SECONDS := 120.0

enum _Family { COUNT, WEAPON, FORMATION }

var _rng := RandomNumberGenerator.new()
var _seed: int
var _elapsed := 0.0
var _spawn_clock := 0.0
var _gate_rng := RandomNumberGenerator.new()
var _gate_spawn_clock := 0.0

func _init(rng_seed: int) -> void:
    _seed = rng_seed
    _rng.seed = rng_seed
    _gate_rng.seed = rng_seed ^ GATE_RNG_SEED_XOR

func tick(delta: float, live_count: int) -> PackedVector2Array:
    _elapsed += delta
    var spawns := PackedVector2Array()
    var interval := _group_interval()
    var headroom := Units.MAX_UNITS - live_count

    _spawn_clock += delta
    while _spawn_clock >= interval:
        _spawn_clock -= interval
        var size := _group_size()
        var margin: float = min(GROUP_SPREAD, Corridor.HALF_WIDTH)
        var centre_x := _rng.randf_range(-Corridor.HALF_WIDTH + margin, Corridor.HALF_WIDTH - margin)
        for i in size:
            if spawns.size() >= headroom:
                continue
            var x: float = clamp(centre_x + _rng.randf_range(-GROUP_SPREAD, GROUP_SPREAD),
                -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)
            spawns.append(Vector2(x, Corridor.SPAWN_DISTANCE))
    return spawns

func enemy_health() -> float:
    var t := 1.0 - exp(-_elapsed / ENEMY_HEALTH_RAMP_SECONDS)
    return ENEMY_BASE_HEALTH + (ENEMY_MAX_HEALTH - ENEMY_BASE_HEALTH) * t

func enemy_speed() -> float:
    var t := 1.0 - exp(-_elapsed / ENEMY_SPEED_RAMP_SECONDS)
    return ENEMY_BASE_SPEED + (ENEMY_MAX_SPEED - ENEMY_BASE_SPEED) * t

func count_delta_range() -> Vector2:
    var t := 1.0 - exp(-_elapsed / COUNT_DELTA_RAMP_SECONDS)
    var lo := COUNT_DELTA_BASE_MIN + (COUNT_DELTA_MAX_MIN - COUNT_DELTA_BASE_MIN) * t
    var hi := COUNT_DELTA_BASE_MAX + (COUNT_DELTA_MAX_MAX - COUNT_DELTA_BASE_MAX) * t
    return Vector2(lo, hi)

func tick_gates(delta: float, current_formation: int) -> Array[GatePair]:
    _gate_spawn_clock += delta
    if _gate_spawn_clock < GATE_SPAWN_INTERVAL:
        return []
    # Reset rather than subtract-and-carry: caps this at exactly one pair per
    # call even if delta covered several intervals (see the "never more than
    # one pair" test). A frame that large is already an edge case Game.MAX_DELTA
    # exists to prevent; losing the small remainder here is not worth the
    # complexity of a carry-and-loop.
    _gate_spawn_clock = 0.0
    return [_spawn_gate_pair(current_formation)]

func reset() -> void:
    _elapsed = 0.0
    _spawn_clock = 0.0
    _rng.seed = _seed
    _gate_spawn_clock = 0.0
    _gate_rng.seed = _seed ^ GATE_RNG_SEED_XOR

func _group_interval() -> float:
    var scaled := GROUP_INTERVAL_BASE * exp(-GROUP_INTERVAL_DECAY * _elapsed)
    return max(scaled, GROUP_INTERVAL_MIN)

func _group_size() -> int:
    var t := 1.0 - exp(-_elapsed / GROUP_SIZE_RAMP_SECONDS)
    return int(round(float(GROUP_SIZE_BASE) + float(GROUP_SIZE_MAX - GROUP_SIZE_BASE) * t))

func _spawn_gate_pair(current_formation: int) -> GatePair:
    var first: int = _gate_rng.randi_range(0, 2)
    var second: int = _gate_rng.randi_range(0, 2)
    while second == first:
        second = _gate_rng.randi_range(0, 2)
    var left_family: int
    var right_family: int
    if _gate_rng.randf() < 0.5:
        left_family = first
        right_family = second
    else:
        left_family = second
        right_family = first

    var left_good := _gate_rng.randf() < 0.5
    var left := _gate_for_family(left_family, left_good, -Gate.SIDE_OFFSET, current_formation)
    var right := _gate_for_family(right_family, not left_good, Gate.SIDE_OFFSET, current_formation)
    return GatePair.new(left, right, Corridor.SPAWN_DISTANCE)

func _gate_for_family(family: int, is_good: bool, x_centre: float, current_formation: int) -> Gate:
    match family:
        _Family.COUNT:
            return _count_gate(is_good, x_centre)
        _Family.WEAPON:
            return Gate.new(Gate.Op.TIER_STEP, 1.0 if is_good else -1.0, x_centre)
        _:
            return Gate.new(Gate.Op.SET_FORMATION,
                float(_random_formation_excluding(current_formation)), x_centre)

func _count_gate(is_good: bool, x_centre: float) -> Gate:
    var range := count_delta_range()
    var n := _gate_rng.randf_range(range.x, range.y)
    if _gate_rng.randf() < 0.5:
        return Gate.new(Gate.Op.MUL, 2.0 if is_good else 0.5, x_centre)
    return Gate.new(Gate.Op.ADD, n if is_good else -n, x_centre)

func _random_formation_excluding(current: int) -> int:
    var options: Array[int] = []
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        if kind != current:
            options.append(kind)
    return options[_gate_rng.randi_range(0, options.size() - 1)]
