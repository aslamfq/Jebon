# Camera derivation (Task 8)

Derives the corridor camera's position, rotation, `fov` and `keep_aspect` for the game's
1080×1920 portrait viewport, and proves — by computation against Godot's own projection
matrix, not by hand-rolled trig assumed to match the engine — that it satisfies the framing
requirement below. Task 9 places these exact values in the scene.

This exists as its own task because the predecessor design's camera was signed off as
"verified" when only its facing direction had been checked, never its field of view. It could
not see roughly two-thirds of its own play area. Facing is not framing.

## Source values (read from the repo at derivation time)

| Value | Source | Value read |
|---|---|---|
| `viewport_width` | `project.godot`, `[display]` | `1080` |
| `viewport_height` | `project.godot`, `[display]` | `1920` |
| aspect (w/h) | derived | `0.5625` |
| `Corridor.HALF_WIDTH` | [scripts/corridor.gd:7](file:///C:/Users/aslam/Documents/Repo/Projects/Holdout/scripts/corridor.gd) | `6.0` |
| `Corridor.SPAWN_DISTANCE` | [scripts/corridor.gd:8](file:///C:/Users/aslam/Documents/Repo/Projects/Holdout/scripts/corridor.gd) | `60.0` |
| `Formation.SPACING` | [scripts/formation.gd:5](file:///C:/Users/aslam/Documents/Repo/Projects/Holdout/scripts/formation.gd) | `0.9` (not directly used below, recorded for context) |
| `Formation.WIDE_COLUMNS` | [scripts/formation.gd:6](file:///C:/Users/aslam/Documents/Repo/Projects/Holdout/scripts/formation.gd) | `11` (not directly used below, recorded for context) |

These matched the transcription in the task brief exactly; nothing had drifted.

## The requirement

The camera must show, with at least **15% angular margin**:

- both corridor walls at `x = ±Corridor.HALF_WIDTH`, at the squad's depth `y = 0`
- the corridor floor from `y = 0` out to at least `y = 30`
- a unit capsule (0.5 units wide) at no less than **10 screen pixels** at `y = 30`

Note on coordinates: the codebase's 2D convention (`Vector2(x, y)` → `Vector3(x, 0, y)`, per
[CLAUDE.md](file:///C:/Users/aslam/Documents/Repo/Projects/Holdout/CLAUDE.md)) means every
world point checked below is `Vector3(x, 0, z)` with world `z` standing in for the brief's `y`
(forward depth) and world `y` fixed at `0` (ground level).

## keep_aspect

`Camera3D.fov` is **vertical** by default (`keep_aspect = KEEP_HEIGHT = 1`). On a portrait
screen that starves the horizontal field — exactly how the previous camera failed to see its
own corridor walls.

**Chosen: `keep_aspect = KEEP_WIDTH` (`0`)**, so `fov` specifies the **horizontal** half-angle
directly, and the (larger) vertical field is derived from the portrait aspect ratio. Verified
directly against the engine: with `keep_aspect = KEEP_WIDTH` and `fov = 56`, reading
`Camera3D.get_camera_projection()`'s own matrix gives `h_half_fov = 28.000°` (exactly `fov/2`,
confirming `fov` is horizontal) and `v_half_fov = 43.388°` (larger, confirming the "generous
forward visibility for free" the brief describes).

## Chosen camera

| Property | Value |
|---|---|
| `position` | `(0, 9, -12)` |
| `rotation_degrees` | `(-22.25, 180, 0)` |
| `fov` | `56.0` |
| `keep_aspect` | `KEEP_WIDTH` (`0`) |

- **`h_half_fov` = 28.000°** (horizontal half-FOV, directly `fov / 2`)
- **`v_half_fov` = 43.388°** (vertical half-FOV, derived from `h_half_fov` and the 0.5625
  aspect ratio via the engine's own projection matrix)

### Per-point verification

Angles are measured off the forward axis, decomposed independently into the camera's
horizontal and vertical planes (`h_angle = atan2(local.x, -local.z)`,
`v_angle = atan2(local.y, -local.z)` in camera-local space — the standard rectilinear
perspective decomposition). Margin = `(half_fov − |angle|) / half_fov`.

| Point | h_angle | h_margin | v_angle | v_margin |
|---|---|---|---|---|
| `(-6, 0, 0)` | 22.459° | **+19.8%** | -14.620° | +66.3% |
| `(+6, 0, 0)` | -22.459° | **+19.8%** | -14.620° | +66.3% |
| `(-6, 0, 30)` | 8.077° | +71.2% | 10.155° | +76.6% |
| `(+6, 0, 30)` | -8.077° | +71.2% | 10.155° | +76.6% |
| `(0, 0, 30)` | 0.000° | +100.0% | 10.155° | +76.6% |
| `(0, 0, 60)` (`SPAWN_DISTANCE`, informational — not required by the brief) | 0.000° | +100.0% | 15.125° | +65.1% |

**Worst required margin: 19.8%**, at both wall points `(±6, 0, 0)` — comfortably clear of the
15% floor. Every other checked point has margin ≥ 65%.

### Capsule pixel width

Measured by unprojecting the two edges of a 0.5-unit-wide capsule (`x = ∓0.25`) through the
camera's actual projection, via `Camera3D.unproject_position()`:

| Depth | Pixel width |
|---|---|
| `y = 0` | 34.99 px |
| `y = 30` | **12.01 px** (required: ≥ 10 px) |

## Why this camera, not the brief's starting point

The brief's suggested starting point — `position (0, 6, -9)`, `rotation (-22, 180, 0)`,
`fov ≈ 62` — was tested first (see the script's "stage 1" output below). It **failed**: the
near wall points `(±6, 0, 0)` only cleared **4.7%** margin (and 6.2% with a steeper -30° pitch
at the same position), well short of the required 15%. The corridor is narrow (12 units wide)
relative to how close the squad's own depth (`y = 0`) sits to the camera, so the nearest wall
points are the tightest constraint on horizontal FOV — exactly the "widest lateral point at
closest depth" case the brief's point selection was designed to catch.

Moving the camera straight in (`(0, 6, -6)`) to compensate made it worse (-16.8% margin): at
closer range the near walls get *more* angularly wide, not less.

The fix is the opposite of "zoom in": retreat the camera (larger `|z|`) and raise it, which
shrinks the near-wall angular size faster than a fixed `fov` budget shrinks, and narrow `fov`
slightly since a large `fov` was never the actual bottleneck once distance is fixed. A grid
search (script "stage 2" below) swept `camZ ∈ [-9, -14]`, `camH ∈ [5, 9]`, `fov ∈ [56, 70]`
(pitch computed by aiming at a variable look-at depth), deliberately bounded to a conventional
third-person `fov` range rather than letting an unconstrained search chase the margin to
infinity — margin increases monotonically as the camera retreats and narrows `fov` toward an
orthographic top-down view, which is a degenerate telephoto camera, not a good crowd-runner
camera. Within that bounded, reasonable envelope, `(0, 9, -12)`, pitch -22.25°, `fov = 56` gave
the best worst-case margin (19.8%) while keeping both the capsule pixel width and the pitch
magnitude close to the brief's own suggestion.

### Rejected candidates

| Position | Rotation | `fov` | Worst margin | Verdict |
|---|---|---|---|---|
| `(0, 6, -9)` | `(-22, 180, 0)` | 62 | +4.7% | Rejected — brief's literal starting point; fails 15% floor |
| `(0, 6, -9)` | `(-30, 180, 0)` | 62 | +6.2% | Rejected — steeper pitch alone isn't enough |
| `(0, 6, -6)` | `(-30, 180, 0)` | 62 | -16.8% | Rejected — moving closer makes the near-wall angle worse |
| `(0, 8, -14)` | `(-18.43, 180, 0)` | 52 | +20.1% | Passes, but `fov = 52` and `camZ = -14` drift further from the brief's envelope than needed |
| `(0, 12, -22)` | `(-20.56, 180, 0)` | 40 | +32.0% | Passes with a huge margin, but is the degenerate unbounded-search result: telephoto, near-orthographic, not a reasonable crowd-runner camera |
| **`(0, 9, -12)`** | **`(-22.25, 180, 0)`** | **56** | **+19.8%** | **Chosen** — clears the floor with real headroom, stays within a conventional third-person `fov`, and its pitch magnitude (22.25°) matches the brief's own suggestion almost exactly |

## Re-running this derivation

If `Corridor.HALF_WIDTH` (or any other source value above) changes, re-run the script below
from the project root — it reads `Corridor` and `project.godot` directly, so it cannot drift
from source the way a transcribed constant can:

```
C:\Users\aslam\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64.exe --headless -s res://camera_derive.gd
```

(save the script below as `camera_derive.gd` at the project root first — it was deleted after
this derivation, per the throwaway-script convention).

### Script source

```gdscript
extends SceneTree

# Throwaway camera derivation script for Task 8. Run from res:// so
# Corridor's constants are read from source, not retyped. Deleted before
# commit; its full source is pasted into docs/camera-derivation.md for
# reproducibility.

const HALF_WIDTH := Corridor.HALF_WIDTH
const SPAWN_DISTANCE := Corridor.SPAWN_DISTANCE
const MARGIN_REQUIRED := 0.15
const MIN_CAPSULE_PX := 10.0
const CAPSULE_WIDTH := 0.5

func _init() -> void:
	_run()

func _run() -> void:
	var vw := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var vh := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	print("viewport: %dx%d  aspect(w/h)=%.6f" % [vw, vh, vw / vh])
	print("Corridor.HALF_WIDTH=%s  Corridor.SPAWN_DISTANCE=%s" % [HALF_WIDTH, SPAWN_DISTANCE])
	print("")

	var cam := Camera3D.new()
	root.add_child(cam)
	root.size = Vector2i(int(vw), int(vh))
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.05
	cam.far = 200.0
	cam.current = true
	cam.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	await process_frame  # camera must be inside the tree once before get_camera_projection() works

	print("---- stage 1: hand-picked starting points (from the brief, and first adjustments) ----")
	var stage1 := [
		{"pos": Vector3(0, 6, -9), "rot": Vector3(-22, 180, 0), "fov": 62.0},
		{"pos": Vector3(0, 6, -9), "rot": Vector3(-30, 180, 0), "fov": 62.0},
		{"pos": Vector3(0, 6, -6), "rot": Vector3(-30, 180, 0), "fov": 62.0},
	]
	for c in stage1:
		_evaluate(cam, c.pos, c.rot, c.fov, true)

	print("")
	print("---- stage 2: grid search, pitch aimed at a look-at depth, sweeping camZ/camH/fov/aim ----")
	# NOTE: margin grows monotonically as the camera retreats and narrows its
	# fov (approaching an orthographic top-down view), so an unconstrained
	# search converges on a degenerate telephoto camera. That is not what a
	# crowd-runner wants visually. This pass deliberately bounds fov to a
	# conventional third-person range and keeps the camera within a modest
	# distance of the brief's suggested starting point, then finds the best
	# margin achievable inside that design envelope.
	var passing: Array = []
	for camZ in [-9.0, -10.0, -11.0, -12.0, -13.0, -14.0]:
		for camH in [5.0, 6.0, 7.0, 8.0, 9.0]:
			for aimZ in [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0]:
				var pitch_deg := rad_to_deg(atan2(camH, aimZ - camZ))
				for fov in [56.0, 58.0, 60.0, 62.0, 64.0, 66.0, 68.0, 70.0]:
					var pos := Vector3(0, camH, camZ)
					var rot := Vector3(-pitch_deg, 180, 0)
					var result := _evaluate(cam, pos, rot, fov, false)
					if result.all_pass:
						# capsule_margin: how far px30 clears the 10px floor,
						# expressed the same way as the angular margins so it
						# can be compared on equal footing.
						result["capsule_margin"] = (result.px30 - MIN_CAPSULE_PX) / MIN_CAPSULE_PX
						result["overall_worst"] = min(result.worst_margin, result.capsule_margin)
						passing.append(result)

	print("  %d passing candidates found out of the grid" % passing.size())
	passing.sort_custom(func(a, b): return a.overall_worst > b.overall_worst)

	print("")
	print("---- top 10 by overall worst margin (angular margins and capsule margin compared equally) ----")
	for i in range(min(10, passing.size())):
		var r = passing[i]
		print("  #%d pos=%s rot=%s fov=%.1f  worst_angular=%.1f%%  capsule_margin=%.1f%% (px30=%.2f)  overall=%.1f%%" % [
			i + 1, r.pos, r.rot, r.fov, r.worst_margin * 100.0, r.capsule_margin * 100.0, r.px30, r.overall_worst * 100.0])

	if passing.size() > 0:
		print("")
		print("---- chosen candidate (best overall-worst margin within the bounded search) ----")
		var best = passing[0]
		_evaluate(cam, best.pos, best.rot, best.fov, true)
	else:
		print("  NO PASSING CANDIDATE FOUND IN GRID")

	print("")
	print("---- FINAL: chosen values, rounded for the scene, re-verified ----")
	_evaluate(cam, Vector3(0, 9, -12), Vector3(-22.25, 180, 0), 56.0, true)

	quit()

func _evaluate(cam: Camera3D, pos: Vector3, rot_deg: Vector3, fov: float, verbose: bool) -> Dictionary:
	if verbose:
		print("==================================================================")
		print("candidate: pos=%s  rot_deg=%s  fov=%.3f  keep_aspect=KEEP_WIDTH" % [pos, rot_deg, fov])

	var rot_rad := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	var basis := Basis.from_euler(rot_rad)
	var xform := Transform3D(basis, pos)
	var inv := xform.affine_inverse()

	cam.fov = fov
	cam.global_transform = xform
	var proj := cam.get_camera_projection()
	var h_half_fov: float = atan(1.0 / proj.x.x)
	var v_half_fov: float = atan(1.0 / proj.y.y)
	if verbose:
		print("  h_half_fov=%.3f deg   v_half_fov=%.3f deg  (read from cam.get_camera_projection())" % [
			rad_to_deg(h_half_fov), rad_to_deg(v_half_fov)])

	var points := [
		["(-HALF_WIDTH, 0, 0)", Vector3(-HALF_WIDTH, 0, 0)],
		["(+HALF_WIDTH, 0, 0)", Vector3(HALF_WIDTH, 0, 0)],
		["(-HALF_WIDTH, 0, 30)", Vector3(-HALF_WIDTH, 0, 30)],
		["(+HALF_WIDTH, 0, 30)", Vector3(HALF_WIDTH, 0, 30)],
		["(0, 0, 30)", Vector3(0, 0, 30)],
		["(0, 0, SPAWN_DISTANCE)", Vector3(0, 0, SPAWN_DISTANCE)],
	]

	var worst_margin := INF
	var worst_label := ""
	var any_required_fail := false

	for entry in points:
		var label: String = entry[0]
		var world: Vector3 = entry[1]
		var local: Vector3 = inv * world
		var h_angle: float = atan2(local.x, -local.z)
		var v_angle: float = atan2(local.y, -local.z)
		var h_margin: float = (h_half_fov - abs(h_angle)) / h_half_fov
		var v_margin: float = (v_half_fov - abs(v_angle)) / v_half_fov
		var required: bool = label != "(0, 0, SPAWN_DISTANCE)"
		if verbose:
			print("  %-24s h_angle=%7.3f deg (margin %+7.1f%%)  v_angle=%7.3f deg (margin %+7.1f%%)%s" % [
				label, rad_to_deg(h_angle), h_margin * 100.0, rad_to_deg(v_angle), v_margin * 100.0,
				("" if required else "  [informational]")])
		if required:
			var point_worst: float = min(h_margin, v_margin)
			if point_worst < worst_margin:
				worst_margin = point_worst
				worst_label = label
			if h_margin < MARGIN_REQUIRED or v_margin < MARGIN_REQUIRED:
				any_required_fail = true

	var px0 := _capsule_pixels(cam, 0.0)
	var px30 := _capsule_pixels(cam, 30.0)
	var capsule_ok := px30 >= MIN_CAPSULE_PX
	if verbose:
		print("  capsule width px @ z=0:  %.2f px" % px0)
		print("  capsule width px @ z=30: %.2f px" % px30)
		print("  worst required margin: %.1f%% at %s (need >= 15%%)   capsule@30 ok: %s   ALL PASS: %s" % [
			worst_margin * 100.0, worst_label, capsule_ok, (not any_required_fail) and capsule_ok])

	return {
		"pos": pos, "rot": rot_deg, "fov": fov,
		"h_half_fov": h_half_fov, "v_half_fov": v_half_fov,
		"worst_margin": worst_margin, "worst_label": worst_label,
		"px0": px0, "px30": px30,
		"all_pass": (not any_required_fail) and capsule_ok,
	}

func _capsule_pixels(cam: Camera3D, z: float) -> float:
	var p_left := cam.unproject_position(Vector3(-CAPSULE_WIDTH / 2.0, 0, z))
	var p_right := cam.unproject_position(Vector3(CAPSULE_WIDTH / 2.0, 0, z))
	return abs(p_right.x - p_left.x)
```

### Full script output

```
viewport: 1080x1920  aspect(w/h)=0.562500
Corridor.HALF_WIDTH=6.0  Corridor.SPAWN_DISTANCE=60.0

---- stage 1: hand-picked starting points (from the brief, and first adjustments) ----
==================================================================
candidate: pos=(0.0, 6.0, -9.0)  rot_deg=(-22.0, 180.0, 0.0)  fov=62.000  keep_aspect=KEEP_WIDTH
  h_half_fov=31.000 deg   v_half_fov=46.889 deg  (read from cam.get_camera_projection())
  (-HALF_WIDTH, 0, 0)      h_angle= 29.529 deg (margin    +4.7%)  v_angle=-11.690 deg (margin   +75.1%)
  (+HALF_WIDTH, 0, 0)      h_angle=-29.529 deg (margin    +4.7%)  v_angle=-11.690 deg (margin   +75.1%)
  (-HALF_WIDTH, 0, 30)     h_angle=  8.879 deg (margin   +71.4%)  v_angle= 13.254 deg (margin   +71.7%)
  (+HALF_WIDTH, 0, 30)     h_angle= -8.879 deg (margin   +71.4%)  v_angle= 13.254 deg (margin   +71.7%)
  (0, 0, 30)               h_angle=  0.000 deg (margin  +100.0%)  v_angle= 13.254 deg (margin   +71.7%)
  (0, 0, SPAWN_DISTANCE)   h_angle=  0.000 deg (margin  +100.0%)  v_angle= 17.030 deg (margin   +63.7%)  [informational]
  capsule width px @ z=0:  42.42 px
  capsule width px @ z=30: 11.70 px
  worst required margin: 4.7% at (-HALF_WIDTH, 0, 0) (need >= 15%)   capsule@30 ok: true   ALL PASS: false
==================================================================
candidate: pos=(0.0, 6.0, -9.0)  rot_deg=(-30.0, 180.0, 0.0)  fov=62.000  keep_aspect=KEEP_WIDTH
  h_half_fov=31.000 deg   v_half_fov=46.889 deg  (read from cam.get_camera_projection())
  (-HALF_WIDTH, 0, 0)      h_angle= 29.068 deg (margin    +6.2%)  v_angle= -3.690 deg (margin   +92.1%)
  (+HALF_WIDTH, 0, 0)      h_angle=-29.068 deg (margin    +6.2%)  v_angle= -3.690 deg (margin   +92.1%)
  (-HALF_WIDTH, 0, 30)     h_angle=  9.266 deg (margin   +70.1%)  v_angle= 21.254 deg (margin   +54.7%)
  (+HALF_WIDTH, 0, 30)     h_angle= -9.266 deg (margin   +70.1%)  v_angle= 21.254 deg (margin   +54.7%)
  (0, 0, 30)               h_angle=  0.000 deg (margin  +100.0%)  v_angle= 21.254 deg (margin   +54.7%)
  (0, 0, SPAWN_DISTANCE)   h_angle=  0.000 deg (margin  +100.0%)  v_angle= 25.030 deg (margin   +46.6%)  [informational]
  capsule width px @ z=0:  41.63 px
  capsule width px @ z=30: 12.22 px
  worst required margin: 6.2% at (-HALF_WIDTH, 0, 0) (need >= 15%)   capsule@30 ok: true   ALL PASS: false
==================================================================
candidate: pos=(0.0, 6.0, -6.0)  rot_deg=(-30.0, 180.0, 0.0)  fov=62.000  keep_aspect=KEEP_WIDTH
  h_half_fov=31.000 deg   v_half_fov=46.889 deg  (read from cam.get_camera_projection())
  (-HALF_WIDTH, 0, 0)      h_angle= 36.206 deg (margin   -16.8%)  v_angle=-15.000 deg (margin   +68.0%)
  (+HALF_WIDTH, 0, 0)      h_angle=-36.206 deg (margin   -16.8%)  v_angle=-15.000 deg (margin   +68.0%)
  (-HALF_WIDTH, 0, 30)     h_angle=  9.957 deg (margin   +67.9%)  v_angle= 20.538 deg (margin   +56.2%)
  (+HALF_WIDTH, 0, 30)     h_angle= -9.957 deg (margin   +67.9%)  v_angle= 20.538 deg (margin   +56.2%)
  (0, 0, 30)               h_angle=  0.000 deg (margin  +100.0%)  v_angle= 20.538 deg (margin   +56.2%)
  (0, 0, SPAWN_DISTANCE)   h_angle=  0.000 deg (margin  +100.0%)  v_angle= 24.806 deg (margin   +47.1%)  [informational]
  capsule width px @ z=0:  54.83 px
  capsule width px @ z=30: 13.15 px
  worst required margin: -16.8% at (-HALF_WIDTH, 0, 0) (need >= 15%)   capsule@30 ok: true   ALL PASS: false

---- stage 2: grid search, pitch aimed at a look-at depth, sweeping camZ/camH/fov/aim ----
  591 passing candidates found out of the grid

---- top 10 by overall worst margin (angular margins and capsule margin compared equally) ----
  #1 pos=(0.0, 9.0, -12.0) rot=(-22.24902, 180.0, 0.0) fov=56.0  worst_angular=19.8%  capsule_margin=20.1% (px30=12.01)  overall=19.8%
  #2 pos=(0.0, 9.0, -12.0) rot=(-20.55605, 180.0, 0.0) fov=56.0  worst_angular=19.2%  capsule_margin=19.5% (px30=11.95)  overall=19.2%
  #3 pos=(0.0, 9.0, -12.0) rot=(-19.09349, 180.0, 0.0) fov=56.0  worst_angular=18.6%  capsule_margin=19.1% (px30=11.91)  overall=18.6%
  #4 pos=(0.0, 9.0, -11.0) rot=(-23.19859, 180.0, 0.0) fov=58.0  worst_angular=18.2%  capsule_margin=18.1% (px30=11.81)  overall=18.1%
  #5 pos=(0.0, 9.0, -12.0) rot=(-17.81889, 180.0, 0.0) fov=56.0  worst_angular=18.1%  capsule_margin=18.8% (px30=11.88)  overall=18.1%
  #6 pos=(0.0, 6.0, -13.0) rot=(-14.62087, 180.0, 0.0) fov=56.0  worst_angular=17.6%  capsule_margin=17.8% (px30=11.78)  overall=17.6%
  #7 pos=(0.0, 7.0, -13.0) rot=(-16.92751, 180.0, 0.0) fov=56.0  worst_angular=19.6%  capsule_margin=17.6% (px30=11.76)  overall=17.6%
  #8 pos=(0.0, 9.0, -12.0) rot=(-16.69924, 180.0, 0.0) fov=56.0  worst_angular=17.6%  capsule_margin=18.6% (px30=11.86)  overall=17.6%
  #9 pos=(0.0, 9.0, -11.0) rot=(-21.37062, 180.0, 0.0) fov=58.0  worst_angular=17.5%  capsule_margin=17.5% (px30=11.75)  overall=17.5%
  #10 pos=(0.0, 8.0, -13.0) rot=(-19.17901, 180.0, 0.0) fov=56.0  worst_angular=21.7%  capsule_margin=17.4% (px30=11.74)  overall=17.4%

---- chosen candidate (best overall-worst margin within the bounded search) ----
==================================================================
candidate: pos=(0.0, 9.0, -12.0)  rot_deg=(-22.24902, 180.0, 0.0)  fov=56.000  keep_aspect=KEEP_WIDTH
  h_half_fov=28.000 deg   v_half_fov=43.388 deg  (read from cam.get_camera_projection())
  (-HALF_WIDTH, 0, 0)      h_angle= 22.460 deg (margin   +19.8%)  v_angle=-14.621 deg (margin   +66.3%)
  (+HALF_WIDTH, 0, 0)      h_angle=-22.460 deg (margin   +19.8%)  v_angle=-14.621 deg (margin   +66.3%)
  (-HALF_WIDTH, 0, 30)     h_angle=  8.077 deg (margin   +71.2%)  v_angle= 10.154 deg (margin   +76.6%)
  (+HALF_WIDTH, 0, 30)     h_angle= -8.077 deg (margin   +71.2%)  v_angle= 10.154 deg (margin   +76.6%)
  (0, 0, 30)               h_angle=  0.000 deg (margin  +100.0%)  v_angle= 10.154 deg (margin   +76.6%)
  (0, 0, SPAWN_DISTANCE)   h_angle=  0.000 deg (margin  +100.0%)  v_angle= 15.124 deg (margin   +65.1%)  [informational]
  capsule width px @ z=0:  34.99 px
  capsule width px @ z=30: 12.01 px
  worst required margin: 19.8% at (-HALF_WIDTH, 0, 0) (need >= 15%)   capsule@30 ok: true   ALL PASS: true

---- FINAL: chosen values, rounded for the scene, re-verified ----
==================================================================
candidate: pos=(0.0, 9.0, -12.0)  rot_deg=(-22.25, 180.0, 0.0)  fov=56.000  keep_aspect=KEEP_WIDTH
  h_half_fov=28.000 deg   v_half_fov=43.388 deg  (read from cam.get_camera_projection())
  (-HALF_WIDTH, 0, 0)      h_angle= 22.459 deg (margin   +19.8%)  v_angle=-14.620 deg (margin   +66.3%)
  (+HALF_WIDTH, 0, 0)      h_angle=-22.459 deg (margin   +19.8%)  v_angle=-14.620 deg (margin   +66.3%)
  (-HALF_WIDTH, 0, 30)     h_angle=  8.077 deg (margin   +71.2%)  v_angle= 10.155 deg (margin   +76.6%)
  (+HALF_WIDTH, 0, 30)     h_angle= -8.077 deg (margin   +71.2%)  v_angle= 10.155 deg (margin   +76.6%)
  (0, 0, 30)               h_angle=  0.000 deg (margin  +100.0%)  v_angle= 10.155 deg (margin   +76.6%)
  (0, 0, SPAWN_DISTANCE)   h_angle=  0.000 deg (margin  +100.0%)  v_angle= 15.125 deg (margin   +65.1%)  [informational]
  capsule width px @ z=0:  34.99 px
  capsule width px @ z=30: 12.01 px
  worst required margin: 19.8% at (-HALF_WIDTH, 0, 0) (need >= 15%)   capsule@30 ok: true   ALL PASS: true
```
