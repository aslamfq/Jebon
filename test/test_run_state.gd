extends GutTest

var run_state: RunState

func before_all():
    # Defensive: a crashed prior run could leave a stale save file behind.
    # Starting from a known-clean slate keeps this script order- and
    # state-independent whether it runs alone or inside the full suite.
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func before_each():
    run_state = RunState.new()

func after_all():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))

func test_starts_empty_and_live():
    assert_eq(run_state.kills, 0)
    assert_eq(run_state.wave, 1)
    assert_almost_eq(run_state.elapsed, 0.0, 0.001)
    assert_eq(run_state.best_wave, 0)
    assert_false(run_state.is_over)

func test_tick_accumulates_elapsed_time():
    run_state.tick(0.5, 1)
    run_state.tick(0.25, 1)
    assert_almost_eq(run_state.elapsed, 0.75, 0.001)

func test_tick_mirrors_the_directors_wave():
    run_state.tick(0.1, 7)
    assert_eq(run_state.wave, 7)

func test_kills_accumulate():
    run_state.record_kills(3)
    run_state.record_kills(2)
    assert_eq(run_state.kills, 5)

func test_end_run_marks_it_over():
    run_state.end_run()
    assert_true(run_state.is_over)

func test_end_run_promotes_a_new_best():
    run_state.tick(0.1, 9)
    run_state.end_run()
    assert_eq(run_state.best_wave, 9)

func test_end_run_does_not_demote_an_existing_best():
    run_state.best_wave = 20
    run_state.tick(0.1, 3)
    run_state.end_run()
    assert_eq(run_state.best_wave, 20, "a bad run must never erase a good one")

func test_reset_clears_the_run_but_keeps_the_best():
    run_state.tick(0.1, 9)
    run_state.record_kills(5)
    run_state.end_run()
    run_state.reset()
    assert_eq(run_state.kills, 0)
    assert_eq(run_state.wave, 1)
    assert_almost_eq(run_state.elapsed, 0.0, 0.001)
    assert_false(run_state.is_over)
    assert_eq(run_state.best_wave, 9)

func test_best_wave_survives_a_save_and_load():
    run_state.tick(0.1, 12)
    run_state.end_run()
    run_state.save_best()

    var reloaded := RunState.new()
    reloaded.load_best()
    assert_eq(reloaded.best_wave, 12)
    # load_best() must persist best_wave only -- it must not reach into or
    # otherwise fabricate the rest of a fresh run's state.
    assert_eq(reloaded.wave, 1, "load_best must not touch the run's other fields")

func test_load_without_a_save_file_is_harmless():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(RunState.SAVE_PATH))
    var fresh := RunState.new()
    # Seed a nonzero sentinel first: best_wave already defaults to 0, so
    # calling load_best() and merely leaving it untouched would falsely
    # pass a plain "== 0" check. Forcing it away from 0 first proves
    # load_best() actively resets it rather than being a no-op.
    fresh.best_wave = 99
    fresh.load_best()
    assert_eq(fresh.best_wave, 0, "a first launch must not crash or corrupt")
