class_name TrackRunner extends RefCounted

const MARKER_SPACING := 6.0

var distance := 0.0
var elapsed := 0.0
var markers := PackedFloat32Array()

func _init() -> void:
    var span := Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE
    markers.resize(int(ceil(span / MARKER_SPACING)) + 1)
    reset()

func tick(delta: float) -> void:
    elapsed += delta
    var speed := Corridor.scroll_speed_at(elapsed)
    var step := speed * delta
    distance += step
    var span := float(markers.size()) * MARKER_SPACING
    for i in markers.size():
        var y := markers[i] - step
        # Wrap rather than reallocate, so a long run allocates nothing.
        while y < Corridor.RECYCLE_DISTANCE:
            y += span
        markers[i] = y

func reset() -> void:
    distance = 0.0
    elapsed = 0.0
    for i in markers.size():
        markers[i] = Corridor.RECYCLE_DISTANCE + float(i) * MARKER_SPACING
