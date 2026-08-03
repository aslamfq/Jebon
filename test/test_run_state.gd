extends GutTest

var run_state: RunState

func before_all():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func before_each():
	run_state = RunState.new()

func after_all():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func test_starts_empty_and_live():
	assert_eq(run_state.kills, 0)
	assert_almost_eq(run_state.distance, 0.0, 0.001)
	assert_almost_eq(run_state.elapsed, 0.0, 0.001)
	assert_almost_eq(run_state.best_distance, 0.0, 0.001)
	assert_false(run_state.is_over)

func test_tick_accumulates_elapsed_time():
	run_state.tick(0.5, 1.0)
	run_state.tick(0.25, 1.0)
	assert_almost_eq(run_state.elapsed, 0.75, 0.001)

func test_tick_mirrors_the_runners_distance():
	run_state.tick(0.1, 42.5)
	assert_almost_eq(run_state.distance, 42.5, 0.001)

func test_kills_accumulate():
	run_state.record_kills(3)
	run_state.record_kills(2)
	assert_eq(run_state.kills, 5)

func test_end_run_marks_it_over():
	run_state.end_run()
	assert_true(run_state.is_over)

func test_end_run_promotes_a_new_best():
	run_state.tick(0.1, 90.0)
	run_state.end_run()
	assert_almost_eq(run_state.best_distance, 90.0, 0.001)

func test_end_run_does_not_demote_an_existing_best():
	run_state.best_distance = 200.0
	run_state.tick(0.1, 30.0)
	run_state.end_run()
	assert_almost_eq(run_state.best_distance, 200.0, 0.001,
		"a bad run must never erase a good one")

func test_reset_clears_the_run_but_keeps_the_best():
	run_state.tick(0.1, 90.0)
	run_state.record_kills(5)
	run_state.end_run()
	run_state.reset()
	assert_eq(run_state.kills, 0)
	assert_almost_eq(run_state.distance, 0.0, 0.001)
	assert_almost_eq(run_state.elapsed, 0.0, 0.001)
	assert_false(run_state.is_over)
	assert_almost_eq(run_state.best_distance, 90.0, 0.001)

func test_best_distance_survives_a_save_and_load():
	run_state.tick(0.1, 120.0)
	run_state.end_run()
	run_state.save_best()

	var reloaded := RunState.new()
	reloaded.load_best()
	assert_almost_eq(reloaded.best_distance, 120.0, 0.001)
	assert_almost_eq(reloaded.distance, 0.0, 0.001,
		"load_best must not touch the run's other fields")

func test_load_without_a_save_file_is_harmless():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
	var fresh := RunState.new()
	fresh.best_distance = 99.0
	fresh.load_best()
	assert_almost_eq(fresh.best_distance, 0.0, 0.001,
		"a first launch must not crash or corrupt")
