class_name RunState extends RefCounted

const SAVE_PATH := "user://holdout.cfg"

var distance := 0.0
var kills := 0
var elapsed := 0.0
var best_distance := 0.0
var is_over := false

func tick(delta: float, current_distance: float) -> void:
	elapsed += delta
	distance = current_distance

func record_kills(n: int) -> void:
	kills += n

func end_run() -> void:
	is_over = true
	if distance > best_distance:
		best_distance = distance

func reset() -> void:
	distance = 0.0
	kills = 0
	elapsed = 0.0
	is_over = false

func save_best() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "best_distance", best_distance)
	config.save(SAVE_PATH)

func load_best() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		best_distance = 0.0
		return
	best_distance = config.get_value("progress", "best_distance", 0.0)
