@tool
extends MeshInstance3D

var points: Array[Vector3]  = []
var uvs: Array[float]  = []
var widths: Array[float]  = []
var age: Array[float] = []

@export var enabled: bool = true
@export var speed_scale := 1.0

@export var width: float = 1.0
@export var width_over_lifetime: Curve
@export var motion_threshold: float = 0.1
@export var lifetime: float = 1.0
@export var texture_length: float = 1.0

var previous_position: Vector3
var texture_offset: float = 1.0

func _ready() -> void:
	previous_position = get_global_transform().origin
	scale = get_parent().get_global_transform().basis.get_scale()
	mesh = ImmediateMesh.new()
	texture_offset = randf_range(0.0, 2.0)

func _process(delta: float) -> void:
	append_points()
	for i in points.size():
		age[i] += delta * speed_scale
	clear_points()
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam := get_viewport().get_camera_3d()
	var cam_pos := Vector3()
	if Engine.is_editor_hint():
		cam = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if cam:
		cam_pos = cam.global_position
	var alive_count := 0
	var first_alive := -1
	for i in points.size():
		if age[i] < lifetime:
			alive_count += 1
			if first_alive == -1:
				first_alive = i
	var dir := Vector3()
	for i in points.size():
		if i + 1 < points.size():
			dir = (points[i + 1] - points[i]).normalized()
		var normalized_age := clampf((age[i] / lifetime), 0, 1)
		var normalized_alive := 1.0
		if alive_count > 0:
			normalized_alive = 1.0 -  clampf(float(i - first_alive) / float(alive_count), 0, 1)
		var w := 1.0
		if width_over_lifetime:
			w = width_over_lifetime.sample(normalized_alive)
		var tangent := dir.cross((cam_pos - points[i]).normalized()).normalized() * get_global_scale() * width * w
		var uv_normalized := float(i) / (points.size() - 1)
		var t0 := uvs[i]
		mesh.surface_set_uv(Vector2(0, t0))
		mesh.surface_set_color(Color(normalized_age, uv_normalized, normalized_alive, 1))
		mesh.surface_add_vertex(to_local(points[i] + tangent))
		mesh.surface_set_uv(Vector2(1, t0))
		mesh.surface_set_color(Color(normalized_age, uv_normalized, normalized_alive, 1))
		mesh.surface_add_vertex(to_local(points[i] - tangent))
	mesh.surface_end()

func append_points() -> void:
	if !enabled:
		return
	var pos := global_position
	var amount := int((previous_position - pos).length() / maxf(0.01, motion_threshold))
	if !amount:
		return
	var dir := (pos - previous_position).normalized()
	var age_delta := 0.0
	if !age.is_empty():
		age_delta = age.back() / float(amount)
	for i in amount:
		var next := previous_position + dir * motion_threshold
		points.append(next)
		uvs.append(texture_offset)
		widths.append(get_global_scale())
		age.append(i * age_delta)
		texture_offset -= motion_threshold / max(texture_length * get_global_scale(), 0.001);
		previous_position = next

func remove_point(i: int) -> void:
	points.remove_at(i)
	uvs.remove_at(i)
	widths.remove_at(i)
	age.remove_at(i)

func clear_points() -> void:
	if age.is_empty():
		return
	var oldest_index := -1
	for i in age.size():
		if age[i] < lifetime:
			oldest_index = i
			break
	if oldest_index == -1:
		remove_point(0)
	elif oldest_index > 1:
		points = points.slice(oldest_index - 1, points.size())
		uvs = uvs.slice(oldest_index - 1, uvs.size())
		widths = widths.slice(oldest_index - 1, widths.size())
		age = age.slice(oldest_index - 1, age.size())

func get_global_scale() -> float:
	var t := global_transform
	return maxf(t.basis.y.length(), 0.001)