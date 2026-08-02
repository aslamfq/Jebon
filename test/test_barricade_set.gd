extends GutTest

var barricades: BarricadeSet

func before_each():
    barricades = BarricadeSet.new()

func test_starts_at_full_health():
    for i in 3:
        assert_almost_eq(barricades.healths[i], BarricadeSet.SECTION_MAX_HEALTH, 0.001)

func test_straight_ahead_is_centre():
    assert_eq(BarricadeSet.section_for_angle(0.0), BarricadeSet.Section.CENTRE)

func test_hard_left_is_left():
    assert_eq(BarricadeSet.section_for_angle(-PI / 2.0), BarricadeSet.Section.LEFT)

func test_hard_right_is_right():
    assert_eq(BarricadeSet.section_for_angle(PI / 2.0), BarricadeSet.Section.RIGHT)

func test_boundaries_land_predictably():
    assert_eq(BarricadeSet.section_for_angle(-PI / 5.0), BarricadeSet.Section.LEFT)
    assert_eq(BarricadeSet.section_for_angle(-PI / 7.0), BarricadeSet.Section.CENTRE)
    assert_eq(BarricadeSet.section_for_angle(PI / 7.0), BarricadeSet.Section.CENTRE)
    assert_eq(BarricadeSet.section_for_angle(PI / 5.0), BarricadeSet.Section.RIGHT)

# Strengthens the boundary coverage above: the brief's boundary test only checks angles
# strictly inside/outside the CENTRE_HALF_WIDTH cutoff (PI/5 and PI/7 bracket PI/6 loosely).
# Nothing in the brief pins down what happens at the cutoff itself, so an implementation
# using <=/>= instead of </> at the boundary would pass every test above while disagreeing
# on which section owns the exact edge. This test locks that down: the edge belongs to CENTRE.
func test_boundary_angle_is_centre_inclusive():
    assert_eq(BarricadeSet.section_for_angle(BarricadeSet.CENTRE_HALF_WIDTH),
        BarricadeSet.Section.CENTRE, "the exact +half-width edge must land in CENTRE, not RIGHT")
    assert_eq(BarricadeSet.section_for_angle(-BarricadeSet.CENTRE_HALF_WIDTH),
        BarricadeSet.Section.CENTRE, "the exact -half-width edge must land in CENTRE, not LEFT")

func test_damage_affects_only_its_own_section():
    barricades.damage(BarricadeSet.Section.LEFT, 30.0)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.LEFT], 70.0, 0.001)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.CENTRE],
        BarricadeSet.SECTION_MAX_HEALTH, 0.001)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.RIGHT],
        BarricadeSet.SECTION_MAX_HEALTH, 0.001)

func test_health_floors_at_zero():
    barricades.damage(BarricadeSet.Section.CENTRE, 500.0)
    assert_almost_eq(barricades.healths[BarricadeSet.Section.CENTRE], 0.0, 0.001)

func test_intact_set_is_not_broken():
    barricades.damage(BarricadeSet.Section.LEFT, 99.0)
    assert_false(barricades.is_broken())

func test_any_single_section_falling_ends_the_run():
    barricades.damage(BarricadeSet.Section.RIGHT, BarricadeSet.SECTION_MAX_HEALTH)
    assert_true(barricades.is_broken(),
        "one section is enough — the run ends on the first breach")

# Strengthens the single-section test above with the complementary case: two sections down
# to nearly nothing (but not zero) must NOT trip is_broken(). Without this, an implementation
# that (wrongly) trips on "total health below some threshold" rather than "any section at
# zero" could still pass test_any_single_section_falling_ends_the_run by coincidence.
func test_two_sections_badly_damaged_but_not_broken_is_not_broken():
    barricades.damage(BarricadeSet.Section.LEFT, 99.0)
    barricades.damage(BarricadeSet.Section.RIGHT, 99.0)
    assert_false(barricades.is_broken(),
        "no section has hit zero yet — the run must not end on aggregate damage")

func test_reset_restores_every_section():
    barricades.damage(BarricadeSet.Section.LEFT, 500.0)
    barricades.reset()
    assert_false(barricades.is_broken())
    for i in 3:
        assert_almost_eq(barricades.healths[i], BarricadeSet.SECTION_MAX_HEALTH, 0.001)
