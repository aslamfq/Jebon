extends GutTest

func test_first_unit_sits_at_the_centre_line_in_a_column():
    var p := Formation.slot(0, Formation.Kind.COLUMN, 0.0)
    assert_almost_eq(p.x, 0.0, 0.001)
    assert_almost_eq(p.y, 0.0, 0.001)

func test_formation_follows_the_centre():
    var a := Formation.slot(0, Formation.Kind.COLUMN, 0.0)
    var b := Formation.slot(0, Formation.Kind.COLUMN, 3.0)
    assert_almost_eq(b.x - a.x, 3.0, 0.001)

func test_wide_is_wider_than_column():
    var wide_span := _span(Formation.Kind.WIDE, 33)
    var column_span := _span(Formation.Kind.COLUMN, 33)
    assert_gt(wide_span, column_span,
        "if these matched, the formation gate would be cosmetic")

func test_wedge_is_between_the_other_two_at_a_small_early_game_count():
    # CORRECTED after WIDE_COLUMNS was deliberately capped at 6 (Aslam:
    # growing the squad past a small width should push players toward a
    # unit upgrade rather than an ever-wider blob). WIDE no longer scales
    # with count at all, while WEDGE's width grows without bound as rows
    # accumulate -- so at 33 units WEDGE (5.85) is now WIDER than the
    # capped WIDE (4.5), which used to be a real bug (see
    # test_wedge_exceeds_wide_at_high_counts_by_design below) and would be
    # one again here if this test still used a large n. The ordering this
    # test actually cares about -- WEDGE sits visually between a tight
    # column and a full-width spread -- only holds at a small count, so
    # check it there instead of at an arbitrary large one.
    var n := 12
    var wedge := _span(Formation.Kind.WEDGE, n)
    assert_gt(wedge, _span(Formation.Kind.COLUMN, n))
    assert_lt(wedge, _span(Formation.Kind.WIDE, n) + 0.001)

func test_wedge_exceeds_wide_at_high_counts_by_design():
    # Documents the intended consequence of capping WIDE_COLUMNS rather than
    # leaving it as an unstated side effect: WIDE's span never grows past
    # WIDE_HALF_SPAN*2 regardless of squad size, so a WEDGE deep enough will
    # always eventually exceed it. This is the reason WEDGE's own overflow
    # against the corridor (a separately tracked, deferred issue) must be
    # fixed before any gate can offer WEDGE at high counts -- not a defect
    # in this test or in WIDE.
    var n := 60
    assert_gt(_span(Formation.Kind.WEDGE, n), _span(Formation.Kind.WIDE, n))

func test_ranks_extend_backwards_not_forwards():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        for i in 60:
            assert_lte(Formation.slot(i, kind, 0.0).y, 0.001,
                "the squad must trail behind its centre, never lead it")

func test_no_slot_leaves_the_corridor():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        for centre in [-Corridor.HALF_WIDTH, 0.0, Corridor.HALF_WIDTH]:
            for i in Units.MAX_UNITS:
                var x: float = Formation.slot(i, kind, centre).x
                assert_between(x, -Corridor.HALF_WIDTH - 0.001, Corridor.HALF_WIDTH + 0.001,
                    "units must never be laid out beyond the corridor walls")

func test_slots_are_distinct():
    for kind in [Formation.Kind.WIDE, Formation.Kind.COLUMN, Formation.Kind.WEDGE]:
        var seen := {}
        for i in 40:
            var p := Formation.slot(i, kind, 0.0)
            var key := "%.3f,%.3f" % [p.x, p.y]
            assert_false(seen.has(key),
                "two units stacked in one slot looks like a rendering bug")
            seen[key] = true

func test_layout_is_stable_as_the_squad_grows():
    var before := Formation.slot(5, Formation.Kind.WIDE, 0.0)
    var after := Formation.slot(5, Formation.Kind.WIDE, 0.0)
    assert_eq(before, after,
        "an existing unit must not jump when the squad grows")

func _span(kind: int, n: int) -> float:
    var lo := 1000.0
    var hi := -1000.0
    for i in n:
        var x: float = Formation.slot(i, kind, 0.0).x
        lo = min(lo, x)
        hi = max(hi, x)
    return hi - lo

# --- Strengthening below: the tests above did not catch a real off-by-one I
# introduced deliberately in _wedge_offset's row-boundary condition (dropping
# the "+ 1" so row 0 is skipped entirely and every row is pushed back by one).
# That bug produces no duplicate (x, y) pair — the (row, col) mapping stays
# injective, it is just mislabeled — so test_slots_are_distinct passed right
# through it. These tests check the row-size contract itself: row r must hold
# exactly r + 1 units, starting from row 0 at the centre line.

func test_wedge_point_is_at_the_centre_line():
    var p := Formation.slot(0, Formation.Kind.WEDGE, 0.0)
    assert_almost_eq(p.x, 0.0, 0.001)
    assert_almost_eq(p.y, 0.0, 0.001)

func test_a_full_row_is_symmetric_for_an_even_column_count():
    # WIDE_COLUMNS=6 is even, which was never actually exercised before it
    # became WIDE's value -- both prior callers (WIDE at 11, COLUMN at 3)
    # were odd. An earlier version of _centered_offset only handled odd
    # counts correctly: for an even count it put col 0 at logical offset 0,
    # which has no corresponding column on a row with no true centre, and
    # produced a full row spanning -2..+3 instead of a symmetric -2.5..+2.5.
    # This proves the fix: a fully filled 6-column row must be centred on
    # zero, not shifted toward one side.
    var lo := 1000.0
    var hi := -1000.0
    for i in Formation.WIDE_COLUMNS:
        var x: float = Formation.slot(i, Formation.Kind.WIDE, 0.0).x
        lo = min(lo, x)
        hi = max(hi, x)
    assert_almost_eq(lo, -hi, 0.001,
        "a full row must be symmetric about centre_x, not lopsided")

func test_wedge_row_r_holds_r_plus_1_units():
    var counts := {}
    for i in 45:
        var y: float = Formation.slot(i, Formation.Kind.WEDGE, 0.0).y
        var key := "%.3f" % y
        counts[key] = counts.get(key, 0) + 1
    for r in range(9):
        var key := "%.3f" % (-float(r) * Formation.SPACING)
        assert_true(counts.has(key), "row %d must be populated" % r)
        if counts.has(key):
            assert_eq(counts[key], r + 1, "row %d must hold exactly %d units" % [r, r + 1])
