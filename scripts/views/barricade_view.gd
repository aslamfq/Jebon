class_name BarricadeView extends Node3D

const SECTION_ANGLES := [-PI / 3.0, 0.0, PI / 3.0]

var _sections: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(3.4, 1.0, 0.4)

    for i in 3:
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(0.6, 0.6, 0.6)

        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = material

        var angle: float = SECTION_ANGLES[i]
        var pos := Vector2(sin(angle), cos(angle)) * BarricadeSet.RADIUS
        instance.transform = Transform3D(
            Basis().rotated(Vector3.UP, angle),
            Vector3(pos.x, 0.5, pos.y))

        add_child(instance)
        _sections.append(instance)
        _materials.append(material)

func render(barricades: BarricadeSet) -> void:
    for i in 3:
        var ratio: float = barricades.healths[i] / BarricadeSet.SECTION_MAX_HEALTH
        # Grey-box damage readout: sinks into the ground as it is chewed away.
        var instance := _sections[i]
        var pos := instance.position
        pos.y = 0.5 - (1.0 - ratio) * 0.5
        instance.position = pos
        _materials[i].albedo_color = Color(0.6, 0.6, 0.6).lerp(
            Color(0.25, 0.25, 0.25), 1.0 - ratio)
