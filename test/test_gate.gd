extends GutTest

var squad: Squad

func before_each():
    squad = Squad.new()

func test_add_applies_to_squad_count():
    squad.set_count(10)
    var gate := Gate.new(Gate.Op.ADD, 5.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.count(), 15)

func test_mul_applies_to_squad_count():
    squad.set_count(10)
    var gate := Gate.new(Gate.Op.MUL, 2.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.count(), 20)

func test_tier_step_applies_to_weapon_tier():
    var gate := Gate.new(Gate.Op.TIER_STEP, 1.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.weapon_tier, 1)

func test_tier_step_negative_clamps_at_zero():
    var gate := Gate.new(Gate.Op.TIER_STEP, -1.0, 0.0)
    gate.apply(squad)
    assert_eq(squad.weapon_tier, 0,
        "Gate must go through Squad's clamped setter, not write weapon_tier directly")

func test_set_formation_applies_to_squad_formation():
    var gate := Gate.new(Gate.Op.SET_FORMATION, float(Formation.Kind.COLUMN), 0.0)
    gate.apply(squad)
    assert_eq(squad.formation, Formation.Kind.COLUMN)

func test_contains_true_inside_half_width():
    var gate := Gate.new(Gate.Op.ADD, 0.0, 2.4)
    assert_true(gate.contains(2.4))
    assert_true(gate.contains(1.4))
    assert_true(gate.contains(3.4))

func test_contains_false_outside_half_width():
    var gate := Gate.new(Gate.Op.ADD, 0.0, 2.4)
    assert_false(gate.contains(1.39))
    assert_false(gate.contains(3.41))

func test_contains_false_on_the_opposite_side():
    var gate := Gate.new(Gate.Op.ADD, 0.0, -2.4)
    assert_false(gate.contains(2.4),
        "a gate centred on the left must not claim a point on the right")

func test_is_good_for_add_positive():
    assert_true(Gate.new(Gate.Op.ADD, 5.0, 0.0).is_good())

func test_is_good_for_add_negative():
    assert_false(Gate.new(Gate.Op.ADD, -5.0, 0.0).is_good())

func test_is_good_for_mul_above_one():
    assert_true(Gate.new(Gate.Op.MUL, 2.0, 0.0).is_good())

func test_is_good_for_mul_below_one():
    assert_false(Gate.new(Gate.Op.MUL, 0.5, 0.0).is_good())

func test_is_good_for_tier_step_positive():
    assert_true(Gate.new(Gate.Op.TIER_STEP, 1.0, 0.0).is_good())

func test_is_good_for_tier_step_negative():
    assert_false(Gate.new(Gate.Op.TIER_STEP, -1.0, 0.0).is_good())

# SET_FORMATION is intentionally not covered here: is_good() only documents a
# contract for non-SET_FORMATION gates (see the doc comment on Gate.is_good()).
# GateView's own SET_FORMATION-is-neutral check happens before it would ever
# consult is_good() for a Formation gate, so there is no meaningful "correct"
# is_good() answer to pin for that op.
