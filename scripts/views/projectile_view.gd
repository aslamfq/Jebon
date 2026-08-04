class_name ProjectileView extends MultiMeshInstance3D

const POOL_SIZE := 64

@export var model_scene: PackedScene

var _pool: Array[Node3D] = []
# Parallel to _pool: true while pool slot i's burst is playing. Tracked here
# rather than read from the vendored prefab's own `collided` property --
# that property is only ever set true (in the prefab's own explode()) and
# never reset anywhere in the prefab's script, and Task 5 additionally
# disables set_process()/set_physics_process() on every pooled instance
# (via call_deferred, to stop the prefab's own lifetime queue_free() timer),
# which means the prefab's _process() never runs on a pooled instance at
# all -- not for the trail fade, and not for any reset of `collided` either.
# Relying on instance.get("collided") would leave a pooled instance
# permanently unable to burst again after its first hit, and permanently
# un-hideable by the overflow-cleanup loop below once it drifts past the
# pool's live range: a frozen, stuck-visible ghost burst. This project's own
# view code owns burst-state instead, as a single source of truth, reset in
# the same re-arm block that already resets the emitter scale/visibility.
var _bursting: Array[bool] = []
# Parallel to _pool: engine ms timestamp (Time.get_ticks_msec()) when slot
# i's burst was triggered. Needed because nothing else ever flips
# `_bursting[i]` back to false: reading the loop below literally, an
# instance that is mid-burst is deliberately excluded both from the
# "hide it" cleanup pass (so the burst isn't cut off mid-play) and, as a
# consequence, from the "re-arm on becoming visible again" block (which
# only runs once an instance has *gone* invisible first) -- a closed loop
# with no exit, so every instance that ever bursts would stay stuck
# `visible = true` forever, either as a frozen ghost once it drifts past
# the pool's live range, or silently repositioned onto whatever live
# projectile next lands on its pool index while still showing its old
# burst. A fixed duration is the timeout that breaks the loop:
# BURST_DURATION_MS below clears `_bursting[i]` once enough real time has
# passed for the burst to have visibly finished, giving the existing
# cleanup/re-arm logic an actual path back to idle. (`Time` rather than a
# per-frame delta so this doesn't require changing render()'s signature or
# game.gd's call sites.)
var _burst_started_at_ms: Array[int] = []

# Comfortably longer than the longest-lived child GPUParticles3D under the
# prefab's Impact node. Read directly from projectiles/projectile_1.tscn:
# Impact/Glow and Impact/Sparks both set lifetime = 0.6, but Impact/Bits
# has NO lifetime line at all, so it uses GPUParticles3D's own default of
# 1.0s -- and its process shader (m4_randomize_lifetime) further scales
# that down by up to 80% per-particle (lifetime *= 1.0 - rand() * 0.8), so
# individual Bits particles range roughly 0.2s-1.0s, topping out at the
# full 1.0s default. 0.6s (Glow/Sparks) is not the longest-lived child;
# Bits is, at up to 1.0s. Bits also has local_coords = true, so an
# unhandled position snap at burst expiry would drag its still-animating
# particles along with it too, not just the trail -- so the margin here
# matters for more than just the trail fix below.
const BURST_DURATION_MS := 1100

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
            _bursting.append(false)
            _burst_started_at_ms.append(0)

func render(projectiles: Projectiles) -> void:
    var pooled := mini(projectiles.count, _pool.size())

    # Expire bursts whose timeout has elapsed *before* touching position or
    # visibility this frame, and re-arm trail emitters right here rather
    # than only in the `if not instance.visible:` block below -- a pool
    # slot that stays continuously within the live [0, pooled) range across
    # a burst (the common case with small in-flight counts, since the
    # index that just finished bursting is usually still needed by the
    # projectile swapped into it) never goes invisible at all, so that
    # block alone would leave its trail emitters disabled forever even
    # after the burst is long over.
    var now := Time.get_ticks_msec()
    for i in _pool.size():
        if _bursting[i] and now - _burst_started_at_ms[i] >= BURST_DURATION_MS:
            _bursting[i] = false
            _rearm(_pool[i])
            # A slot that's still within this frame's live pool range gets
            # its position snapped to whatever projectile now occupies it,
            # in the sync loop right below -- read TrailPrefab's own
            # append_points() (projectiles/scripts/trail3d.gd) to see why
            # that snap alone used to draw a kink: it compares
            # global_position against its own remembered previous_position
            # every _process() and interpolates points across the gap, and
            # while bursting that previous_position sits frozen at the
            # death location (position sync was skipped, so nothing moved
            # it), so the very next sample after the snap reads as one huge
            # single-frame move and gets drawn as a straight connecting
            # segment across the screen. Resetting the trail's own history
            # to the new position *before* that sync loop runs removes the
            # jump at its source instead of just not rendering it -- the
            # frame where the snap happens is also the frame Impact/Bits
            # (local_coords = true, still animating for up to 1.0s per
            # BURST_DURATION_MS above) would otherwise drag along with the
            # same snap, so this has to happen before position sync either
            # way, not just for the trail.
            if i < pooled:
                var new_pos := Vector3(
                    projectiles.positions[i].x, 0.8, projectiles.positions[i].y)
                _pool[i].get_node("TrailPrefab").reset_at(new_pos)

    for pos in projectiles.removed_positions:
        _trigger_burst_near(pos)

    for i in pooled:
        var instance := _pool[i]
        if not instance.visible:
            instance.visible = true
            _rearm(instance)
        # Skip the position sync while bursting: a pool index below
        # `pooled` isn't reserved for one logical projectile across
        # frames (_remove_at's swap-remove can reassign it to a different
        # still-live projectile the very same frame a burst triggers on
        # it), and forcing a mid-burst instance's position to jump to
        # wherever that reassigned projectile now is would corrupt
        # TrailPrefab's own position-history trail (a child node, and so
        # unaffected by set_process(false) above, which only touches the
        # instance root) into a visible diagonal kink connecting the two
        # points -- confirmed on screen during Step 3's visual check.
        # Leaving the burst's position untouched keeps it fixed at the
        # actual death location, matching what the design doc claims.
        if not _bursting[i]:
            instance.position = Vector3(projectiles.positions[i].x, 0.8, projectiles.positions[i].y)
            # The prefab's own launch() (never called here -- see the
            # call_deferred comment in _ready() for why) is what normally
            # orients it to face its travel direction; skipping launch()
            # to avoid its physics side effects also skipped this, so
            # every pooled instance kept whatever orientation it imported
            # with regardless of which way it was actually moving. Fine by
            # coincidence for the squad's own forward-firing bolts, visibly
            # backwards for the enemy's, which travel the opposite way --
            # reported from a real device. Same basis construction as the
            # prefab's launch(), replicated here instead of calling it.
            var vel := projectiles.velocities[i]
            if vel.length_squared() > 0.0001:
                var dir3 := Vector3(vel.x, 0.0, vel.y).normalized()
                var right := Vector3(0, 1, 0).cross(dir3).normalized()
                var up := dir3.cross(right).normalized()
                instance.basis = Basis(right, up, dir3)
    for i in range(pooled, _pool.size()):
        if _pool[i].visible and not _bursting[i]:
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

func _trigger_burst_near(pos: Vector2) -> void:
    var world := Vector3(pos.x, 0.8, pos.y)
    for i in _pool.size():
        var instance := _pool[i]
        if instance.visible and not _bursting[i] \
                and instance.position.distance_to(world) < 0.5:
            _bursting[i] = true
            _burst_started_at_ms[i] = Time.get_ticks_msec()
            instance.explode()
            return

# Restores a pool instance's flight-trail emitters to their idle,
# ready-to-render state -- undoes explode()'s "stop the trail, play the
# impact" effect. Called both from the normal re-arm-on-visible path and
# from the burst-timeout expiry above, since a slot that stays continuously
# within the live pool range across a burst never toggles `visible` at all.
func _rearm(instance: Node3D) -> void:
    instance.get_node("Emitters").scale = Vector3.ONE
    for e in instance.get_node("Emitters").get_children():
        e.emitting = true
        e.visible = true
