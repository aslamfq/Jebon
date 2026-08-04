class_name CorridorView extends Node3D

const WALL_HEIGHT := 1.2
const STRIPE_DEPTH := 0.6
const SCENERY_STRIDE := 3
const SCENERY_MARGIN := 1.0

# Unset by default, matching UnitsView.model_scene: either export left
# empty must degrade to a placeholder rather than error out of render().
@export var wall_prop: PackedScene
@export var fence_prop: PackedScene

var _stripes: Array[MeshInstance3D] = []
var _walls: Array[MeshInstance3D] = []
var _fences: Array[MeshInstance3D] = []

# Extracted once each, in _ready, and then shared by every instance that
# needs them. MeshExtract.from_scene() instantiates the source scene, walks
# it, and rebuilds every surface through SurfaceTool -- far too much work to
# repeat per prop instance, which is what _spawn_prop used to do: with
# SCENERY_STRIDE 3 and the ~12 markers a run typically holds, that was 4
# wall instances plus 4 fence instances each re-running the whole extraction
# and each keeping its own private ArrayMesh copy of geometry identical to
# its siblings'. Mesh is a Resource; MeshInstance3D.mesh is meant to be
# shared, so two unique meshes now back all eight instances (and any grown
# later) instead of eight duplicates.
var _wall_mesh: Mesh
var _fence_mesh: Mesh

func _ready() -> void:
    _wall_mesh = _prop_mesh(wall_prop)
    _fence_mesh = _prop_mesh(fence_prop)
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
    _render_scenery(runner)

func _render_scenery(runner: TrackRunner) -> void:
    var n := runner.markers.size() / SCENERY_STRIDE
    _ensure_scenery(n)
    for i in n:
        var z := runner.markers[i * SCENERY_STRIDE]
        var left := _walls[i].position
        left.z = z
        _walls[i].position = left
        var right := _fences[i].position
        right.z = z
        _fences[i].position = right

func _ensure_scenery(n: int) -> void:
    while _walls.size() < n:
        _walls.append(_spawn_prop(_wall_mesh, -(Corridor.HALF_WIDTH + SCENERY_MARGIN)))
        _fences.append(_spawn_prop(_fence_mesh, Corridor.HALF_WIDTH + SCENERY_MARGIN))

# Same guard style as UnitsView._ready(): an unset export (or a source scene
# with no MeshInstance3D in it, which MeshExtract reports as null too) falls
# back to a plain box instead of assigning null and erroring inside the
# render path.
func _prop_mesh(scene: PackedScene) -> Mesh:
    var mesh: Mesh = MeshExtract.from_scene(scene) if scene else null
    if mesh == null:
        var box := BoxMesh.new()
        box.size = Vector3(0.5, WALL_HEIGHT, 0.5)
        mesh = box
    return mesh

func _spawn_prop(mesh: Mesh, x: float) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = Vector3(x, 0, 0)
    add_child(instance)
    return instance

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
