class_name CorridorView extends Node3D

const WALL_HEIGHT := 1.2
const STRIPE_DEPTH := 0.6

var _stripes: Array[MeshInstance3D] = []

func _ready() -> void:
    _add_ground()
    _add_wall(-Corridor.HALF_WIDTH)
    _add_wall(Corridor.HALF_WIDTH)

func render(runner: TrackRunner) -> void:
    _ensure_stripes(runner.markers.size())
    for i in runner.markers.size():
        var stripe := _stripes[i]
        var pos := stripe.position
        pos.z = runner.markers[i]
        stripe.position = pos

func _ensure_stripes(n: int) -> void:
    while _stripes.size() < n:
        var mesh := BoxMesh.new()
        mesh.size = Vector3(Corridor.HALF_WIDTH * 2.0, 0.02, STRIPE_DEPTH)
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.45, 0.45, 0.5)
        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = material
        instance.position = Vector3(0, 0.01, 0)
        add_child(instance)
        _stripes.append(instance)

func _add_ground() -> void:
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(Corridor.HALF_WIDTH * 2.0,
        Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.62, 0.6, 0.58)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = Vector3(0, 0,
        (Corridor.SPAWN_DISTANCE + Corridor.RECYCLE_DISTANCE) * 0.5)
    add_child(instance)

func _add_wall(x: float) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.2, WALL_HEIGHT,
        Corridor.SPAWN_DISTANCE - Corridor.RECYCLE_DISTANCE)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.5, 0.52, 0.58)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = Vector3(x, WALL_HEIGHT * 0.5,
        (Corridor.SPAWN_DISTANCE + Corridor.RECYCLE_DISTANCE) * 0.5)
    add_child(instance)

func _stripe_count() -> int:
    return _stripes.size()
