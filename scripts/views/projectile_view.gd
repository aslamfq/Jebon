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

# How close a pool slot's position must be to a removal's PRE-MOVE position
# (Projectiles.removed_previous_positions) to be accepted as that removal's
# instance. Not a tuned tolerance any more: a slot that is idling in the
# live range holds exactly the position the sync loop gave it last frame,
# which is exactly the pre-move position this frame's tick() recorded before
# moving that same projectile, so a real match lands within floating-point
# noise. The old code compared against the POST-move position instead, which
# is off by exactly speed x delta -- 0.583 units/frame at the squad's
# 35.0-unit/s and 60fps -- so its 0.5 threshold silently excluded every
# squad removal ever while admitting the enemy's slower 0.417. The margin
# kept here only absorbs a projectile whose slot was synced at a slightly
# different sub-step, never a whole frame of travel.
const BURST_MATCH_DISTANCE := 0.25

# Any single-frame position change larger than this is treated as a
# teleport rather than travel, and the instance's TrailPrefab gets its
# position history dropped before the move so it cannot draw a streak
# across the gap. Comfortably above one frame of real travel for the
# fastest projectile in the game (the squad's 35.0 units/s = 0.583
# units/frame at 60fps), and far below the corridor-length jumps this
# exists to catch (measured worst case: 63.8 units). A frame that runs at
# Game.MAX_DELTA's 0.1s clamp does move a squad projectile 3.5 units in one
# go and so trips this, dropping that instance's trail for a frame -- an
# acceptable trade on a resume-from-background hitch that is already
# visibly stuttering, and far cheaper than letting a real teleport draw.
# Deliberately
# does not try to work out WHY a jump happened -- pool re-arm, swap-remove
# reassignment and burst expiry all produce one, and distinguishing them
# would need a per-projectile generation/ID scheme this view does not have.
const TRAIL_RESET_DISTANCE := 2.0

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

    # Correlate each removal against the pool by its PRE-move position, not
    # the position it died at: every pool slot's position is still last
    # frame's at this point (the sync loop below has not run yet), and last
    # frame's position for a projectile that ticked this frame is exactly
    # its removed_previous_positions entry. See BURST_MATCH_DISTANCE above
    # for what comparing against the post-move position cost. The burst
    # itself still plays at the actual death location, which is what the
    # player should see -- only the identification uses the older position.
    for i in projectiles.removed_positions.size():
        var burst_at := projectiles.removed_positions[i]
        # The two reports are filled in lockstep by Projectiles, but a
        # caller that only ever populated the old one (or a partially
        # cleared pair) must degrade to the old behaviour rather than
        # index-error out of render() and take the whole frame's drawing
        # with it.
        var match_at := burst_at
        if i < projectiles.removed_previous_positions.size():
            match_at = projectiles.removed_previous_positions[i]
        _trigger_burst_near(match_at, burst_at)

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
            _move_to(instance,
                Vector3(projectiles.positions[i].x, 0.8, projectiles.positions[i].y))
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

    # The original flat-sphere MultiMesh path, kept as the catch-all so
    # every live projectile is always drawn somehow. Two groups need it:
    #
    #  - overflow, i.e. live projectiles past POOL_SIZE, as before; and
    #  - live projectiles whose pool slot is mid-burst. That slot is
    #    deliberately excluded from the position-sync loop above (its
    #    instance has to stay parked at the death location while the impact
    #    plays), but _remove_at's swap-remove means the same index is
    #    usually still carrying a real, live, moving projectile -- which
    #    would otherwise be drawn nowhere at all for the whole
    #    BURST_DURATION_MS. That was invisible while squad bursts never
    #    fired; with them firing it is not a corner case at all. Measured
    #    over a 900-frame run: an average of 15.0 of 32.8 in-flight squad
    #    projectiles (peak 26) sat in a bursting slot on any given frame,
    #    i.e. nearly half the squad's visible fire would blink out for over
    #    a second at a time. A plain sphere for those is a downgrade in
    #    detail; drawing nothing is a bug.
    var drawn := 0
    for i in pooled:
        if _bursting[i]:
            _draw_fallback(drawn, projectiles.positions[i])
            drawn += 1
    for src in range(pooled, projectiles.count):
        _draw_fallback(drawn, projectiles.positions[src])
        drawn += 1
    multimesh.visible_instance_count = drawn

func _draw_fallback(slot: int, pos: Vector2) -> void:
    multimesh.set_instance_transform(slot,
        Transform3D(Basis(), Vector3(pos.x, 0.8, pos.y)))

# Every position assignment to a pooled instance goes through here. A pool
# slot is not bound to one logical projectile: it gets re-armed at a fresh
# muzzle spawn point after sitting invisible wherever it last died, and
# Projectiles._remove_at()'s swap-remove hands it a completely different
# projectile from anywhere in the corridor, with no burst involved and no
# visibility change to notice it by. Either way the instance's position can
# jump arbitrarily far in one frame, and TrailPrefab is a CHILD node whose
# own _process() is still running (only the pooled instance root's
# processing is disabled, in _ready() above) -- so its append_points() sees
# that jump as one huge move and interpolates a solid line of points across
# it, drawing as a full-corridor streak. Measured on the pre-fix build: 487
# such jumps across a 900-frame run, worst case 63.8 world units, matching
# the three full-length streaks in this branch's own task5_shot3 screenshot.
# Dropping the trail's history first turns the streak into a clean restart.
func _move_to(instance: Node3D, pos: Vector3) -> void:
    if instance.position.distance_to(pos) > TRAIL_RESET_DISTANCE:
        instance.get_node("TrailPrefab").reset_at(pos)
    instance.position = pos

# `match_pos` identifies which pooled instance this removal belonged to (a
# pre-move position, matching what the pool still holds this early in
# render()); `burst_pos` is where the burst actually plays, i.e. where the
# projectile really died. Picks the CLOSEST eligible slot rather than the
# first one inside the threshold: squad units fire volleys from nearly
# coincident muzzle points, so several candidates can sit within the match
# distance of each other and "first found" would burst an arbitrary one.
func _trigger_burst_near(match_pos: Vector2, burst_pos: Vector2) -> void:
    var world := Vector3(match_pos.x, 0.8, match_pos.y)
    var best := -1
    var best_distance := BURST_MATCH_DISTANCE
    for i in _pool.size():
        var instance := _pool[i]
        if not instance.visible or _bursting[i]:
            continue
        var distance := instance.position.distance_to(world)
        if distance < best_distance:
            best = i
            best_distance = distance
    if best < 0:
        return
    _bursting[best] = true
    _burst_started_at_ms[best] = Time.get_ticks_msec()
    # Snap onto the real death location before exploding, so the burst plays
    # where the projectile actually died rather than one frame short of it.
    # Through _move_to like every other assignment: this particular move is
    # only one frame of travel, but the instance is about to sit still for
    # BURST_DURATION_MS with its trail frozen, so it must not be the one
    # position change in render() that bypasses the jump check.
    _move_to(_pool[best], Vector3(burst_pos.x, 0.8, burst_pos.y))
    _pool[best].explode()

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
