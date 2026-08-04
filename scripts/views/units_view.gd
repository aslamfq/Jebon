class_name UnitsView extends MultiMeshInstance3D

const BOB_HEIGHT := 0.12
const BOB_SPEED := 9.0

# Unset by default so any other instance of this script (there are none
# today besides Squad's own UnitsView and Game's EnemyView, both of which
# now set this in game.tscn) still gets a working placeholder.
@export var model_scene: PackedScene

func _ready() -> void:
    var mesh: Mesh = MeshExtract.from_scene(model_scene) if model_scene else null
    if mesh == null:
        var capsule := CapsuleMesh.new()
        capsule.radius = 0.25
        capsule.height = 1.4
        mesh = capsule

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Units.MAX_UNITS
    multimesh.visible_instance_count = 0

func render(units: Units, time: float) -> void:
    multimesh.visible_instance_count = units.count
    for i in units.count:
        var pos := units.positions[i]
        # Phase offset per index so the crowd does not bob in lockstep.
        var bob: float = sin(time * BOB_SPEED + float(i) * 0.7) * BOB_HEIGHT
        var basis := Basis().rotated(Vector3.UP, atan2(pos.x, pos.y))
        multimesh.set_instance_transform(i,
            Transform3D(basis, Vector3(pos.x, 0.7 + bob, pos.y)))
