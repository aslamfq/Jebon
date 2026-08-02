class_name RunState extends RefCounted

const SAVE_PATH := "user://holdout.cfg"

var wave := 1
var kills := 0
var elapsed := 0.0
var best_wave := 0
var is_over := false

func tick(delta: float, current_wave: int) -> void:
    elapsed += delta
    wave = current_wave

func record_kills(n: int) -> void:
    kills += n

func end_run() -> void:
    is_over = true
    if wave > best_wave:
        best_wave = wave

func reset() -> void:
    wave = 1
    kills = 0
    elapsed = 0.0
    is_over = false

func save_best() -> void:
    var config := ConfigFile.new()
    config.set_value("progress", "best_wave", best_wave)
    config.save(SAVE_PATH)

func load_best() -> void:
    var config := ConfigFile.new()
    if config.load(SAVE_PATH) != OK:
        best_wave = 0
        return
    best_wave = config.get_value("progress", "best_wave", 0)
