# scripts/views/mesh_extract.gd
class_name MeshExtract extends RefCounted

# Imported glTF/FBX models land as a scene (a Node3D tree), not a bare Mesh
# resource -- MultiMesh.mesh needs the latter. Rigged character packs (e.g.
# KayKit) split a single character across several MeshInstance3D siblings
# (arms, legs, body, head, cape, ...) all parented under one Skeleton3D,
# with no single combined mesh anywhere in the tree. Taking only the first
# mesh found therefore renders one detached body part, not the character.
#
# This walks every MeshInstance3D in the tree and copies every surface of
# every one of them into the result ArrayMesh -- one output surface per
# original surface found, each keeping its own material, rather than
# merging everything into a single materialless surface (SurfaceTool.
# append_from() copies geometry only, never a surface's material, so a
# single merged surface would always render flat/untextured regardless of
# how many distinct materials the parts actually used). Each part's local
# transform is composed down from the instantiated root (not a
# first-found node's transform alone) and baked into its vertices so the
# parts land in the same relative positions they were authored in. Called
# from _ready(), never per-frame.
static func from_scene(scene: PackedScene) -> Mesh:
    var instance := scene.instantiate()
    var result := ArrayMesh.new()
    var found := _append_meshes(instance, Transform3D.IDENTITY, result)
    instance.free()
    if not found:
        return null
    return result

# `parent_transform` is the composed transform from the instantiated root
# down to `node`'s parent (not including `node`'s own transform yet).
static func _append_meshes(node: Node, parent_transform: Transform3D, result: ArrayMesh) -> bool:
    var found := false
    var node_transform := parent_transform
    if node is Node3D:
        node_transform = parent_transform * node.transform

    if node is MeshInstance3D and node.mesh != null:
        for i in node.mesh.get_surface_count():
            var st := SurfaceTool.new()
            st.begin(Mesh.PRIMITIVE_TRIANGLES)
            st.append_from(node.mesh, i, node_transform)
            st.set_material(node.mesh.surface_get_material(i))
            st.commit(result)
        found = true

    for child in node.get_children():
        if _append_meshes(child, node_transform, result):
            found = true

    return found
