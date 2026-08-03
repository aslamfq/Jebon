class_name Formation extends RefCounted

enum Kind { WIDE = 0, COLUMN = 1, WEDGE = 2 }

const SPACING := 0.9
const WIDE_COLUMNS := 6
const COLUMN_COLUMNS := 3

# Half the width WIDE's outermost column sits from centre_x. WIDE is the
# widest formation, so this is the margin SteerInput must reserve at the
# corridor edge: if centre_x itself never gets closer to the wall than this,
# no WIDE slot ever needs the clamp below during ordinary play.
const WIDE_HALF_SPAN := (WIDE_COLUMNS - 1) / 2.0 * SPACING

# Slot position is a function of index alone, so an existing unit never moves
# when the squad grows. Ranks extend backwards (negative y) from the centre.
static func slot(index: int, kind: int, centre_x: float) -> Vector2:
	var offset := Vector2.ZERO
	match kind:
		Kind.WEDGE:
			offset = _wedge_offset(index)
		Kind.COLUMN:
			offset = _grid_offset(index, COLUMN_COLUMNS)
		_:
			offset = _grid_offset(index, WIDE_COLUMNS)
	var x: float = clamp(centre_x + offset.x, -Corridor.HALF_WIDTH, Corridor.HALF_WIDTH)
	return Vector2(x, offset.y)

# Fills each row from its centre outward rather than raster left-to-right,
# so the first unit in any row lands at the centre instead of the row's left
# edge -- important for a growing squad, since it means a half-full row
# still looks centred rather than jammed against one side.
static func _grid_offset(index: int, columns: int) -> Vector2:
	var row := index / columns
	var col := index % columns
	var x := _centered_offset(col, columns) * SPACING
	return Vector2(x, -float(row) * SPACING)

# Maps a raster column (0..columns-1) to its signed offset in units of
# SPACING from the row's centre, in centre-outward fill order.
#
# Originally this only handled an odd `columns`, where an integer centre
# column exists (offset 0) to start from: 0, +1, -1, +2, -2, ... An even
# `columns` has no integer centre -- the two most-central columns sit at
# +0.5 and -0.5 either side of it -- and was never actually exercised until
# WIDE_COLUMNS became 6, so the gap went unnoticed. Generalised here to
# cover both parities, which also closes a previously-deferred concern
# (formation.gd used to assume odd counts silently).
#
# Either way the FULLY FILLED row ends up symmetric and evenly spaced --
# {-2,-1,0,1,2} for 5 columns, {-2.5,-1.5,-0.5,0.5,1.5,2.5} for 6 -- only the
# fill ORDER differs between parities.
static func _centered_offset(col: int, columns: int) -> float:
	if columns % 2 == 1:
		if col == 0:
			return 0.0
		var magnitude := (col + 1) / 2
		return float(magnitude if col % 2 == 1 else -magnitude)
	else:
		var pair := col / 2
		var half := 0.5 + float(pair)
		return half if col % 2 == 0 else -half

# Row r holds r+1 units, so the crowd forms a triangle with its point forward.
static func _wedge_offset(index: int) -> Vector2:
	var row := 0
	var consumed := 0
	while consumed + row + 1 <= index:
		consumed += row + 1
		row += 1
	var col := index - consumed
	var x := (float(col) - float(row) * 0.5) * SPACING
	return Vector2(x, -float(row) * SPACING)
