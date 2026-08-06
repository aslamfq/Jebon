extends GutTest

var squad: Squad

func before_each():
    squad = Squad.new()

func test_starts_with_the_starting_count():
    assert_eq(squad.count(), Squad.STARTING_COUNT)

func test_starts_wide():
    assert_eq(squad.formation, Formation.Kind.WIDE)

func test_set_count_grows():
    squad.set_count(40)
    assert_eq(squad.count(), 40)

func test_set_count_shrinks():
    squad.set_count(3)
    assert_eq(squad.count(), 3)

func test_set_count_clamps_to_the_cap():
    squad.set_count(10000)
    assert_eq(squad.count(), Units.MAX_UNITS,
        "a multiplier gate must not be able to exceed the cap")

func test_set_count_cannot_go_negative():
    squad.set_count(-5)
    assert_eq(squad.count(), 0)

func test_wiped_only_at_zero():
    squad.set_count(1)
    assert_false(squad.is_wiped())
    squad.set_count(0)
    assert_true(squad.is_wiped())

func test_units_converge_on_their_slots():
    squad.tick(0.0, 0.0)
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    for i in squad.count():
        var target := Formation.slot(i, squad.formation, 0.0)
        assert_almost_eq(squad.units.positions[i].x, target.x, 0.05)
        assert_almost_eq(squad.units.positions[i].y, target.y, 0.05)

func test_the_squad_follows_a_moving_centre():
    # Settle at centre zero, remember where every unit sits, then move the
    # centre and settle again.
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    var before := PackedFloat32Array()
    for i in squad.count():
        before.append(squad.units.positions[i].x)

    for i in 200:
        squad.tick(1.0 / 60.0, 4.0)

    for i in squad.count():
        var target := Formation.slot(i, squad.formation, 4.0)
        assert_almost_eq(squad.units.positions[i].x, target.x, 0.05,
            "every unit must converge on its own slot for the new centre")
        assert_gt(squad.units.positions[i].x, before[i] - 0.001,
            "no unit may drift left when the centre moves right")

func test_convergence_is_gradual_not_instant():
    squad.tick(1.0 / 60.0, 5.0)
    assert_lt(squad.units.positions[0].x, 5.0,
        "one frame must not snap the squad to its new slot")

func test_changing_formation_moves_the_squad():
    squad.set_count(30)
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    var wide_span := _span()
    squad.formation = Formation.Kind.COLUMN
    for i in 200:
        squad.tick(1.0 / 60.0, 0.0)
    assert_lt(_span(), wide_span,
        "a formation gate must visibly reshape the crowd")

func test_growth_places_new_units_inside_the_corridor():
    squad.set_count(Units.MAX_UNITS)
    for i in squad.count():
        assert_between(squad.units.positions[i].x,
            -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001)

func test_reset_restores_the_opening_state():
    squad.set_count(200)
    squad.formation = Formation.Kind.WEDGE
    for i in 60:
        squad.tick(1.0 / 60.0, 5.0)
    squad.reset()
    assert_eq(squad.count(), Squad.STARTING_COUNT)
    assert_eq(squad.formation, Formation.Kind.WIDE)
    assert_almost_eq(squad.centre_x, 0.0, 0.001)

# The brief's test_set_count_shrinks only checks the resulting count, which a
# wrong implementation that drops the FRONT of the array (lowest indices) and
# renumbers survivors down to 0 would also pass. That renumbering matters:
# since Formation.slot is a pure function of index, renumbering would reassign
# every survivor to a different slot and yank the whole crowd across the
# corridor on the next tick, instead of leaving already-settled units alone.
# Converge fully, record the settled positions of the units that must survive
# a shrink, shrink, and assert those exact positions are untouched -- proof
# that removal dropped the END of the array (highest indices) rather than the
# front.
func test_set_count_shrink_keeps_survivors_pinned_to_their_original_slots():
    squad.set_count(20)
    for i in 300:
        squad.tick(1.0 / 60.0, 0.0)
    var before := PackedVector2Array()
    for i in 8:
        before.append(squad.units.positions[i])
    squad.set_count(8)
    assert_eq(squad.count(), 8)
    for i in 8:
        assert_almost_eq(squad.units.positions[i].x, before[i].x, 0.001,
            "shrinking must drop units from the end, not renumber survivors")
        assert_almost_eq(squad.units.positions[i].y, before[i].y, 0.001,
            "shrinking must drop units from the end, not renumber survivors")

func test_starts_at_weapon_tier_zero():
    assert_eq(squad.weapon_tier, 0)

func test_reset_restores_weapon_tier_zero():
    squad.weapon_tier = 3
    squad.reset()
    assert_eq(squad.weapon_tier, 0)

func test_add_count_increases():
    squad.set_count(10)
    squad.add_count(5)
    assert_eq(squad.count(), 15)

func test_add_count_floors_at_one():
    squad.set_count(1)
    squad.add_count(-50)
    assert_eq(squad.count(), 1,
        "a gate must never be able to wipe the squad -- only combat may reach zero")

func test_add_count_still_clamps_to_the_cap():
    squad.set_count(Units.MAX_UNITS - 2)
    squad.add_count(100)
    assert_eq(squad.count(), Units.MAX_UNITS)

func test_mul_count_scales():
    squad.set_count(10)
    squad.mul_count(2.0)
    assert_eq(squad.count(), 20)

func test_mul_count_floors_at_one():
    squad.set_count(1)
    squad.mul_count(0.5)
    assert_eq(squad.count(), 1,
        "a halving gate on a single-unit squad must not be able to reach zero")

func test_step_weapon_tier_increases():
    squad.step_weapon_tier(1)
    assert_eq(squad.weapon_tier, 1)

func test_step_weapon_tier_clamps_at_the_top():
    squad.weapon_tier = Weapon.TIER_COUNT - 1
    squad.step_weapon_tier(1)
    assert_eq(squad.weapon_tier, Weapon.TIER_COUNT - 1,
        "stepping past the top tier must clamp, not overflow silently")

func test_step_weapon_tier_clamps_at_the_bottom():
    squad.step_weapon_tier(-1)
    assert_eq(squad.weapon_tier, 0,
        "stepping below tier 0 must clamp, or a later good gate could silently do nothing while the squad 'climbs back' through negative tiers")

func test_set_formation_changes_formation():
    squad.set_formation(Formation.Kind.WEDGE)
    assert_eq(squad.formation, Formation.Kind.WEDGE)

func _span() -> float:
    var lo := 1000.0
    var hi := -1000.0
    for i in squad.count():
        lo = min(lo, squad.units.positions[i].x)
        hi = max(hi, squad.units.positions[i].x)
    return hi - lo
