extends GutTest

var weapon: Weapon

func before_each():
    weapon = Weapon.new()

func test_no_shots_before_the_interval_elapses():
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 0)

func test_one_shot_per_interval():
    assert_eq(weapon.tick(weapon.fire_interval), 1)

func test_a_long_frame_fires_the_whole_backlog():
    assert_eq(weapon.tick(weapon.fire_interval * 3.0), 3,
        "a stutter must not silently swallow shots")

func test_remainder_carries_into_the_next_frame():
    weapon.tick(weapon.fire_interval * 0.75)
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 1,
        "0.75 + 0.5 = 1.25 intervals, so exactly one shot")

func test_rate_is_frame_independent():
    var coarse := Weapon.new()
    var fine := Weapon.new()
    var coarse_shots := 0
    var fine_shots := 0
    for i in 60:
        coarse_shots += coarse.tick(1.0 / 60.0)
    for i in 240:
        fine_shots += fine.tick(1.0 / 240.0)
    assert_eq(coarse_shots, fine_shots,
        "one second of fire must be the same at any frame rate")

func test_reset_clears_the_accumulator():
    weapon.tick(weapon.fire_interval * 0.9)
    weapon.reset()
    assert_eq(weapon.tick(weapon.fire_interval * 0.5), 0)
