# scripts/views/mesh_extract.gd
class_name MeshExtract extends RefCounted

# Imported glTF/FBX models land as a scene (a Node3D tree), not a bare Mesh
# resource -- MultiMesh.mesh needs the latter. Rigged character packs (e.g.
# KayKit) split a single character across several MeshInstance3D siblings
# (arms, legs, body, head, cape, ...) all parented under one Skeleton3D,
# with no single combined mesh anywhere in the tree. Taking only the first
# mesh found therefore renders one detached body part, not the character.
# Instead, this walks every MeshInstance3D in the tree and merges every
# surface of every one of them into a single ArrayMesh via SurfaceTool,
# baking each part's local transform (composed down from the instantiated
# root, not a first-found node's transform alone) into its vertices so the
# parts land in the same relative positions they were authored in. Called
# from _ready(), never per-frame.
static func from_scene(scene: PackedScene) -> Mesh:
    var instance := scene.instantiate()
    var surface_tool := SurfaceTool.new()
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var found := _append_meshes(instance, Transform3D.IDENTITY, surface_tool)
    instance.free()
    if not found:
        return null
    return surface_tool.commit()

# `parent_transform` is the composed transform from the instantiated root
# down to `node`'s parent (not including `node`'s own transform yet).
static func _append_meshes(node: Node, parent_transform: Transform3D, st: SurfaceTool) -> bool:
    var found := false
    var node_transform := parent_transform
    if node is Node3D:
        node_transform = parent_transform * node.transform

    if node is MeshInstance3D and node.mesh != null:
        for i in node.mesh.get_surface_count():
            st.append_from(node.mesh, i, node_transform)
        found = true

    for child in node.get_children():
        if _append_meshes(child, node_transform, st):
            found = true

    return found
