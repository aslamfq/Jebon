extends Node3D

const HIT_RADIUS := 0.45
const ZOMBIE_DPS := 6.0
const DESPAWN_MARGIN := 5.0

@onready var horde_view: HordeView = $HordeView
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var barricade_view: BarricadeView = $BarricadeView
@onready var hud: Label = $HUD/WaveLabel

var horde: Horde
var director: WaveDirector
var barricades: BarricadeSet
var weapon: Weapon
var projectiles: Projectiles
var aim: AimInput
var run: RunState

var _dragging := false
var _drag_origin := Vector2.ZERO
var _time := 0.0

func _ready() -> void:
    horde = Horde.new()
    director = WaveDirector.new(randi())
    barricades = BarricadeSet.new()
    weapon = Weapon.new()
    projectiles = Projectiles.new()
    aim = AimInput.new()
    run = RunState.new()
    run.load_best()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        aim.aim_at_screen_delta(event.position - _drag_origin)

func _process(delta: float) -> void:
    _time += delta

    for pos in director.tick(delta, horde.count):
        horde.spawn(pos, director.zombie_health(), director.zombie_speed())

    aim.tick(delta)
    horde.tick(delta, BarricadeSet.RADIUS)

    for _shot in weapon.tick(delta):
        projectiles.fire(Vector2.ZERO, aim.aim, weapon.projectile_speed)

    projectiles.tick(delta, WaveDirector.SPAWN_RADIUS + DESPAWN_MARGIN)
    run.record_kills(projectiles.resolve_hits(horde, HIT_RADIUS, weapon.damage))

    for i in horde.attackers(BarricadeSet.RADIUS):
        barricades.damage(BarricadeSet.section_for_angle(horde.angle_of(i)), ZOMBIE_DPS * delta)

    run.tick(delta, director.wave)

    if barricades.is_broken():
        _restart()

    horde_view.render(horde, _time)
    projectile_view.render(projectiles)
    barricade_view.render(barricades)
    hud.text = "WAVE %d    KILLS %d    BEST %d" % [run.wave, run.kills, run.best_wave]

func _restart() -> void:
    run.end_run()
    run.save_best()
    run.reset()
    horde.clear()
    projectiles.clear()
    barricades.reset()
    director.reset()
    weapon.reset()
    aim.reset()
