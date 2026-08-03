class_name Formation extends RefCounted

enum Kind { WIDE = 0, COLUMN = 1, WEDGE = 2 }

const SPACING := 0.9
const WIDE_COLUMNS := 11
const COLUMN_COLUMNS := 3

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

# Fills each row from its centre outward (0, +1, -1, +2, -2, ...) rather than
# raster left-to-right, so the first unit in any row lands on x=0 instead of
# the row's left edge. columns is assumed odd (both callers pass 3 and 11),
# which is what makes a true centre column exist to start from.
static func _grid_offset(index: int, columns: int) -> Vector2:
	var row := index / columns
	var col := index % columns
	var x := float(_centered_column(col)) * SPACING
	return Vector2(x, -float(row) * SPACING)

static func _centered_column(col: int) -> int:
	if col == 0:
		return 0
	var magnitude := (col + 1) / 2
	return magnitude if col % 2 == 1 else -magnitude

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
