class_name ProjectileView extends MultiMeshInstance3D

func _ready() -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 0.08
    mesh.height = 0.16

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Projectiles.MAX_PROJECTILES
    multimesh.visible_instance_count = 0

func render(projectiles: Projectiles) -> void:
    multimesh.visible_instance_count = projectiles.count
    for i in projectiles.count:
        var pos := projectiles.positions[i]
        multimesh.set_instance_transform(i,
            Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))
