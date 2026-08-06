class_name Game extends Node3D

const CONTACT_DEPTH := 0.0
const HIT_RADIUS := 0.5
const ENEMY_WEAPON_TIER := 0
const ENEMY_PROJECTILE_SPEED := 25.0

# First-pass value, same spirit as SteerInput.SMOOTHING/PIXELS_PER_UNIT --
# expect to retune after more device play, not a claim of final balance.
# Caps how much game time a single _process() call can advance. Without
# this, backgrounding the app (Android suspends rendering but Godot's own
# clock keeps running) delivers one enormous delta on the resume frame,
# and every per-delta system here (TrackGenerator's spawn catch-up loop,
# Units.tick's movement, Projectiles.resolve_hits's O(units x projectiles)
# loop) scales directly with it -- one frame then tries to simulate the
# entire missed duration at once. Found on a real device: minimize, then
# reopen, produced a severe stutter followed by an erratic FPS reading.
const MAX_DELTA := 0.1

@onready var units_view: UnitsView = $UnitsView
@onready var enemy_view: UnitsView = $EnemyView
@onready var corridor_view: CorridorView = $CorridorView
@onready var squad_projectile_view: ProjectileView = $SquadProjectileView
@onready var enemy_projectile_view: ProjectileView = $EnemyProjectileView
@onready var gate_view: GateView = $GateView
@onready var hud: Label = $HUD/DistanceLabel

var squad: Squad
var steer: SteerInput
var runner: TrackRunner
var generator: TrackGenerator
var enemies: Units
var squad_weapon: Weapon
var enemy_weapon: Weapon
var squad_projectiles: Projectiles
var enemy_projectiles: Projectiles
var run: RunState
var gates: Gates

var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_base := 0.0
var _time := 0.0

func _ready() -> void:
    # Pins the render rate to a fixed target instead of letting the engine
    # follow whatever refresh rate the display negotiates. project.godot has
    # never set this (Godot's own default is uncapped/display-follows), which
    # is fine on a fixed-refresh monitor but not on a phone with an
    # adaptive/variable refresh panel: those renegotiate their rate on every
    # resume from the background, which is what produced the oscillating FPS
    # readout (120, then 20-30, then 100+ across successive minimize/reopen
    # cycles) Aslam saw on a real device. Distinct from MAX_DELTA above,
    # which caps simulated game time per frame, not the actual render rate.
    Engine.max_fps = 60
    squad = Squad.new()
    steer = SteerInput.new()
    runner = TrackRunner.new()
    generator = TrackGenerator.new(randi())
    enemies = Units.new()
    squad_weapon = Weapon.new()
    enemy_weapon = Weapon.new()
    squad_projectiles = Projectiles.new()
    enemy_projectiles = Projectiles.new()
    run = RunState.new()
    run.load_best()
    gates = Gates.new()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
            _drag_base = steer.centre_x
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        var moved: float = _screen_delta_to_steer_delta(event.position.x - _drag_origin.x)
        steer.steer_to_screen_delta(
            Vector2(moved + _drag_base * SteerInput.PIXELS_PER_UNIT, 0))

# The Camera3D in game.tscn is yawed 180 degrees (rotation_degrees.y = 180)
# so it can look down +Z instead of Godot's default -Z -- this game's
# "forward" is +Z (see Corridor/Formation). That yaw flips the camera's
# local right vector relative to world +X: screen-right corresponds to
# world -X, not world +X. Feeding a raw screen-space drag straight into a
# world-space steer target therefore moves the squad opposite the finger.
# Found via actual phone play; no automated check catches this, because it
# depends on the camera's orientation, which SteerInput deliberately knows
# nothing about. See test_screen_delta_to_steer_delta_inverts_because_camera_is_yawed_180.
static func _screen_delta_to_steer_delta(screen_delta_x: float) -> float:
    return -screen_delta_x

func _process(delta: float) -> void:
    delta = min(delta, MAX_DELTA)
    _time += delta

    for pos in generator.tick(delta, enemies.count):
        enemies.spawn(pos, Vector2(0, -generator.enemy_speed()), generator.enemy_health())

    runner.tick(delta)
    steer.tick(delta)
    squad.tick(delta, steer.centre_x)
    for pair in generator.tick_gates(delta, squad.formation):
        gates.pairs.append(pair)
    gates.tick(delta, Corridor.scroll_speed_at(runner.elapsed), squad)
    enemies.tick(delta, Vector2(0, -Corridor.scroll_speed_at(runner.elapsed)))

    var squad_shots := squad_weapon.tick(delta, squad.weapon_tier)
    Volley.fire(squad.units, squad_projectiles, squad_shots,
        Weapon.projectiles_per_shot_at(squad.weapon_tier),
        Weapon.spread_degrees_at(squad.weapon_tier),
        Vector2(0, 1), squad_weapon.projectile_speed)

    var enemy_shots := enemy_weapon.tick(delta, ENEMY_WEAPON_TIER)
    Volley.fire(enemies, enemy_projectiles, enemy_shots,
        Weapon.projectiles_per_shot_at(ENEMY_WEAPON_TIER),
        Weapon.spread_degrees_at(ENEMY_WEAPON_TIER),
        Vector2(0, -1), ENEMY_PROJECTILE_SPEED)

    # Projectiles.tick()/resolve_hits() only ever append to
    # removed_positions now (see scripts/projectiles.gd) -- clearing is the
    # caller's job, once per frame per pool, so a single frame's despawns
    # (from tick()) and hits (from resolve_hits()) both survive to reach
    # the render() calls below instead of the second call's clear wiping
    # out the first's report.
    squad_projectiles.removed_positions.clear()
    squad_projectiles.removed_previous_positions.clear()
    squad_projectiles.tick(delta, Corridor.SPAWN_DISTANCE + 5.0)

    enemy_projectiles.removed_positions.clear()
    enemy_projectiles.removed_previous_positions.clear()
    enemy_projectiles.tick(delta, Corridor.SPAWN_DISTANCE + 5.0)

    run.record_kills(squad_projectiles.resolve_hits(enemies, HIT_RADIUS,
        Weapon.damage_at(squad.weapon_tier)))
    enemy_projectiles.resolve_hits(squad.units, HIT_RADIUS,
        Weapon.damage_at(ENEMY_WEAPON_TIER))

    var contacts := enemies.remove_beyond(CONTACT_DEPTH)
    squad.set_count(max(squad.count() - contacts, 0))

    run.tick(delta, runner.distance)
    if squad.is_wiped():
        _restart()

    units_view.render(squad.units, _time)
    enemy_view.render(enemies, _time)
    corridor_view.render(runner)
    gate_view.render(gates)
    squad_projectile_view.render(squad_projectiles)
    enemy_projectile_view.render(enemy_projectiles)
    hud.text = "%d m    %d kills    %d fps" % [int(runner.distance), run.kills, Engine.get_frames_per_second()]

func _restart() -> void:
    run.end_run()
    run.save_best()
    run.reset()
    squad.reset()
    steer.reset()
    runner.reset()
    generator.reset()
    gates.reset()
    enemies.clear()
    squad_weapon.reset()
    enemy_weapon.reset()
    squad_projectiles.clear()
    enemy_projectiles.clear()
