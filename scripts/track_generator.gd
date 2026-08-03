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

var _rng := RandomNumberGenerator.new()
var _seed: int
var _elapsed := 0.0
var _spawn_clock := 0.0

func _init(rng_seed: int) -> void:
    _seed = rng_seed
    _rng.seed = rng_seed

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

func reset() -> void:
    _elapsed = 0.0
    _spawn_clock = 0.0
    _rng.seed = _seed

func _group_interval() -> float:
    var scaled := GROUP_INTERVAL_BASE * exp(-GROUP_INTERVAL_DECAY * _elapsed)
    return max(scaled, GROUP_INTERVAL_MIN)

func _group_size() -> int:
    var t := 1.0 - exp(-_elapsed / GROUP_SIZE_RAMP_SECONDS)
    return int(round(float(GROUP_SIZE_BASE) + float(GROUP_SIZE_MAX - GROUP_SIZE_BASE) * t))
