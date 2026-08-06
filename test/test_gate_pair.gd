extends GutTest

var pair: GatePair

func before_each():
    var left := Gate.new(Gate.Op.ADD, -5.0, -Gate.SIDE_OFFSET)
    var right := Gate.new(Gate.Op.ADD, 5.0, Gate.SIDE_OFFSET)
    pair = GatePair.new(left, right, 10.0)

func test_resolve_picks_left_when_centre_is_inside_the_left_gate():
    assert_eq(pair.resolve(-Gate.SIDE_OFFSET), pair.left)

func test_resolve_picks_right_when_centre_is_inside_the_right_gate():
    assert_eq(pair.resolve(Gate.SIDE_OFFSET), pair.right)

func test_resolve_returns_null_in_the_centre_channel():
    # Midway between the two gates -- inside neither's HALF_WIDTH.
    assert_null(pair.resolve(0.0),
        "the corridor's centre channel must let the squad skip both gates")

func test_resolve_returns_null_beyond_the_outer_edge():
    # Just past the right gate's outer edge but still within SteerInput.MAX_CENTRE (3.75).
    assert_null(pair.resolve(Gate.SIDE_OFFSET + Gate.HALF_WIDTH + 0.3),
        "steering past a gate's outer edge must also skip it -- the whole point of the corridor being wider than the gate pair")

func test_resolve_boundary_is_inclusive():
    # Exactly on the gate's inner/outer edge must still count as inside it --
    # matches Gate.contains's own <= semantics, tested separately in test_gate.gd.
    assert_eq(pair.resolve(Gate.SIDE_OFFSET - Gate.HALF_WIDTH), pair.right)
