# scripts/views/mesh_extract.gd
class_name MeshExtract extends RefCounted

# Imported glTF/FBX models land as a scene (a Node3D tree containing a
# MeshInstance3D), not a bare Mesh resource -- MultiMesh.mesh needs the
# latter. Instantiates the scene once, takes the first mesh found by
# depth-first search, and discards the instance. Called from _ready(),
# never per-frame.
static func from_scene(scene: PackedScene) -> Mesh:
    var instance := scene.instantiate()
    var mesh := _find_mesh(instance)
    instance.free()
    return mesh

static func _find_mesh(node: Node) -> Mesh:
    if node is MeshInstance3D and node.mesh != null:
        return node.mesh
    for child in node.get_children():
        var found := _find_mesh(child)
        if found != null:
            return found
    return null
