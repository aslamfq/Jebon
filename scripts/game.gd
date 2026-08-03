extends Node3D

@onready var units_view: UnitsView = $UnitsView
@onready var corridor_view: CorridorView = $CorridorView
@onready var hud: Label = $HUD/DistanceLabel

var squad: Squad
var steer: SteerInput
var runner: TrackRunner

var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_base := 0.0
var _time := 0.0

func _ready() -> void:
    squad = Squad.new()
    steer = SteerInput.new()
    runner = TrackRunner.new()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _dragging = event.pressed
        if event.pressed:
            _drag_origin = event.position
            _drag_base = steer.centre_x
    elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        var moved: float = event.position.x - _drag_origin.x
        steer.steer_to_screen_delta(
            Vector2(moved + _drag_base * SteerInput.PIXELS_PER_UNIT, 0))

func _process(delta: float) -> void:
    _time += delta
    runner.tick(delta)
    steer.tick(delta)
    squad.tick(delta, steer.centre_x)

    units_view.render(squad.units, _time)
    corridor_view.render(runner)
    hud.text = "%d m" % int(runner.distance)

func _restart() -> void:
    squad.reset()
    steer.reset()
    runner.reset()
