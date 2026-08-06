extends GutTest

var gates: Gates
var squad: Squad

func before_each():
    gates = Gates.new()
    squad = Squad.new()

func _pair(left_value: float, right_value: float, y: float) -> GatePair:
    var left := Gate.new(Gate.Op.ADD, left_value, -Gate.SIDE_OFFSET)
    var right := Gate.new(Gate.Op.ADD, right_value, Gate.SIDE_OFFSET)
    return GatePair.new(left, right, y)

func test_pairs_move_toward_zero_each_tick():
    var pair := _pair(0.0, 0.0, 10.0)
    gates.pairs.append(pair)
    gates.tick(1.0, 4.0, squad)
    assert_almost_eq(pair.y, 6.0, 0.001)

func test_a_pair_that_crosses_zero_is_removed():
    gates.pairs.append(_pair(0.0, 0.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(gates.pairs.size(), 0)

func test_a_pair_that_has_not_crossed_yet_survives():
    gates.pairs.append(_pair(0.0, 0.0, 10.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(gates.pairs.size(), 1)

func test_crossing_applies_the_right_gate_when_centre_is_on_the_right():
    squad.centre_x = Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(-100.0, 7.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 17,
        "the RIGHT gate's value must apply when the squad's centre is on the right")

func test_crossing_applies_the_left_gate_when_centre_is_on_the_left():
    squad.centre_x = -Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(7.0, -100.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 17,
        "the LEFT gate's value must apply when the squad's centre is on the left")

func test_crossing_in_the_centre_channel_applies_neither_gate():
    squad.centre_x = 0.0
    squad.set_count(10)
    gates.pairs.append(_pair(50.0, 50.0, 1.0))
    gates.tick(1.0, 4.0, squad)
    assert_eq(squad.count(), 10,
        "steering between both gates must apply nothing, even though both would otherwise help")

func test_a_pair_resolves_exactly_once_even_when_a_large_delta_jumps_past_zero():
    squad.centre_x = Gate.SIDE_OFFSET
    squad.set_count(10)
    gates.pairs.append(_pair(0.0, 7.0, 0.5))
    # A single MAX_DELTA-sized (0.1s) frame at a plausible scroll speed easily
    # covers more than 0.5 world units, jumping y from +0.5 to well past 0 in
    # one tick -- must still apply the gate exactly once, not zero or twice.
    gates.tick(0.1, 14.0, squad)
    assert_eq(squad.count(), 17)
    gates.tick(0.1, 14.0, squad)
    assert_eq(squad.count(), 17,
        "a pair already removed must not somehow apply again on a later tick")

func test_reset_clears_all_pairs():
    gates.pairs.append(_pair(0.0, 0.0, 10.0))
    gates.pairs.append(_pair(0.0, 0.0, 20.0))
    gates.reset()
    assert_eq(gates.pairs.size(), 0)
