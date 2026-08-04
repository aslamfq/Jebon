@tool
extends Node3D

const PROJECTILE_1 := preload("res://projectiles/projectile_1.tscn")
const PROJECTILE_2 := preload("res://projectiles/projectile_2.tscn")
const PROJECTILE_3 := preload("res://projectiles/projectile_3.tscn")
const PROJECTILE_4 := preload("res://projectiles/projectile_4.tscn")

var prefab
var ray

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event.keycode == KEY_F:
		prepare(PROJECTILE_1)
	elif event.is_pressed() and event.keycode == KEY_1:
		prepare(PROJECTILE_1)
	elif event.is_pressed() and event.keycode == KEY_2:
		prepare(PROJECTILE_2)
	elif event.is_pressed() and event.keycode == KEY_3:
		prepare(PROJECTILE_3)
	if event.is_pressed() and event.keycode == KEY_4:
		prepare(PROJECTILE_4)

func _physics_process(_delta: float) -> void:
	if !ray:
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 1000.0)
	var result = space_state.intersect_ray(query)
	if result:
		var target: Vector3 = result.position
		var projectile: Node = prefab.instantiate()
		projectile.position = Vector3(0, 1, 0)
		add_child(projectile)
		projectile.launch((target - Vector3(0, 1, 0)).normalized())
	ray = null

func prepare(scene: PackedScene) -> void:
	var point = get_viewport().get_mouse_position()
	var camera := get_viewport().get_camera_3d()
	if camera:
		prefab = scene
		ray = [
			camera.project_ray_origin(point),
			camera.project_ray_normal(point)
		]
