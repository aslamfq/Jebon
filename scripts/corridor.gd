class_name Corridor extends RefCounted

# The world's dimensions live here and nowhere else. The previous design
# hardcoded its arc angle in three separate units, which is a defect waiting
# to drift the moment one of them changes.

const HALF_WIDTH := 6.0
const SPAWN_DISTANCE := 60.0
const RECYCLE_DISTANCE := -5.0

const BASE_SCROLL_SPEED := 8.0
const MAX_SCROLL_SPEED := 14.0
const SCROLL_RAMP_SECONDS := 120.0

# Approaches MAX_SCROLL_SPEED asymptotically and never reaches it, so the run
# settles into a steady tempo instead of accelerating until failure is certain.
static func scroll_speed_at(elapsed: float) -> float:
	var t: float = 1.0 - exp(-elapsed / SCROLL_RAMP_SECONDS * 3.0)
	return BASE_SCROLL_SPEED + (MAX_SCROLL_SPEED - BASE_SCROLL_SPEED) * t
