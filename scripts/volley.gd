class_name Volley extends RefCounted

# Fires `shots` trigger pulses from every live unit in `units`, each pulse
# fanning `projectiles_per_shot` projectiles evenly across `spread_degrees`
# around `forward`, into `projectiles`. Pure spawn geometry -- knows nothing
# about weapon tiers; the caller resolves those into plain numbers first.
# Used for both the squad (forward toward the enemies) and enemy crowds
# (forward toward the squad); the only difference between the two calls is
# which Units/Projectiles pair and which direction is passed in.
static func fire(units: Units, projectiles: Projectiles, shots: int,
        projectiles_per_shot: int, spread_degrees: float, forward: Vector2, speed: float) -> void:
    if shots <= 0 or projectiles_per_shot <= 0:
        return
    var spread := deg_to_rad(spread_degrees)
    for _shot in shots:
        for i in units.count:
            var origin := units.positions[i]
            if projectiles_per_shot == 1:
                projectiles.fire(origin, forward, speed)
            else:
                for p in projectiles_per_shot:
                    var t: float = float(p) / float(projectiles_per_shot - 1) - 0.5
                    projectiles.fire(origin, forward.rotated(t * spread), speed)
