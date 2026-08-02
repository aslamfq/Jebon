class_name WaveDirector extends RefCounted

const SECONDS_PER_WAVE := 20.0
const SPAWN_RADIUS := 30.0

const BASE_SPAWN_INTERVAL := 1.2
const MIN_SPAWN_INTERVAL := 0.12
const BASE_HEALTH := 10.0
const HEALTH_PER_WAVE := 3.0
const BASE_SPEED := 1.8
const MAX_SPEED := 6.0
const SPEED_APPROACH := 0.12

var wave := 1

var _rng := RandomNumberGenerator.new()
var _seed: int
var _wave_clock := 0.0
var _spawn_clock := 0.0

func _init(rng_seed: int) -> void:
    _seed = rng_seed
    _rng.seed = rng_seed

func tick(delta: float, live_count: int) -> PackedVector2Array:
    _wave_clock += delta
    while _wave_clock >= SECONDS_PER_WAVE:
        _wave_clock -= SECONDS_PER_WAVE
        wave += 1

    var spawns := PackedVector2Array()
    var headroom := Horde.MAX_ZOMBIES - live_count
    var interval := _spawn_interval()

    _spawn_clock += delta
    while _spawn_clock >= interval:
        _spawn_clock -= interval
        if spawns.size() >= headroom:
            continue
        var angle := _rng.randf_range(-PI / 2.0, PI / 2.0)
        spawns.append(Vector2(sin(angle), cos(angle)) * SPAWN_RADIUS)
    return spawns

func zombie_health() -> float:
    return BASE_HEALTH + HEALTH_PER_WAVE * float(wave - 1)

func zombie_speed() -> float:
    # Approaches MAX_SPEED asymptotically and never exceeds it, so late waves
    # get denser rather than unreadably fast.
    var t := 1.0 - exp(-SPEED_APPROACH * float(wave - 1))
    return BASE_SPEED + (MAX_SPEED - BASE_SPEED) * t

func reset() -> void:
    wave = 1
    _wave_clock = 0.0
    _spawn_clock = 0.0
    _rng.seed = _seed

func _spawn_interval() -> float:
    var scaled := BASE_SPAWN_INTERVAL * pow(0.93, float(wave - 1))
    return max(scaled, MIN_SPAWN_INTERVAL)
