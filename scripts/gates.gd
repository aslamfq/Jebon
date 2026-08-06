class_name Gates extends RefCounted

var pairs: Array[GatePair] = []

func tick(delta: float, scroll_speed: float, squad: Squad) -> void:
    var step := scroll_speed * delta
    var remaining: Array[GatePair] = []
    for pair in pairs:
        pair.y -= step
        if pair.y <= 0.0:
            var gate := pair.resolve(squad.centre_x)
            if gate != null:
                gate.apply(squad)
            continue
        remaining.append(pair)
    pairs = remaining

func reset() -> void:
    pairs.clear()
