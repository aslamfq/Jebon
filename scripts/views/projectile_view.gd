class_name ProjectileView extends MultiMeshInstance3D

const POOL_SIZE := 64

@export var model_scene: PackedScene

var _pool: Array[Node3D] = []

func _ready() -> void:
    var mesh := SphereMesh.new()
    mesh.radius = 0.08
    mesh.height = 0.16

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = Projectiles.MAX_PROJECTILES
    multimesh.visible_instance_count = 0

    if model_scene:
        for i in POOL_SIZE:
            var instance: Node3D = model_scene.instantiate()
            add_child(instance)
            # A synchronous set_process(false)/set_physics_process(false)
            # right after add_child() is NOT enough: Godot defers _ready()
            # to the idle-frame queue, and the engine's own NOTIFICATION_READY
            # handling auto-re-enables processing for any script that
            # overrides _process/_physics_process, which runs AFTER our
            # synchronous call and silently wins. Verified empirically
            # (headless SceneTree probe): a disable call placed synchronously
            # after add_child() still leaves is_processing() == true by the
            # next frame, and the prefab's own lifetime timer
            # (queue_free() in _process() after ~5.5s) frees the pooled
            # instance out from under us. Deferring the disable calls so
            # they run after the queued _ready() call fixes it — confirmed
            # is_processing()/is_physics_processing() stay false from frame 1
            # onward with call_deferred.
            instance.call_deferred("set_physics_process", false)
            instance.call_deferred("set_process", false)
            instance.visible = false
            _pool.append(instance)

func render(projectiles: Projectiles) -> void:
    var pooled := mini(projectiles.count, _pool.size())

    for i in pooled:
        var instance := _pool[i]
        instance.visible = true
        instance.position = Vector3(projectiles.positions[i].x, 0.8, projectiles.positions[i].y)
    for i in range(pooled, _pool.size()):
        _pool[i].visible = false

    # Overflow beyond the pool renders through the original flat-sphere
    # MultiMesh path, so every live projectile is always drawn somehow
    # regardless of how many are in flight.
    var overflow := projectiles.count - pooled
    multimesh.visible_instance_count = max(overflow, 0)
    for i in overflow:
        var src := pooled + i
        var pos := projectiles.positions[src]
        multimesh.set_instance_transform(i,
            Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))
