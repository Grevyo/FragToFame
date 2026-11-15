class_name ShooterMotion
extends RefCounted
## Movement state of whoever holds a weapon, as far as accuracy cares. Filled by the player
## controller today and by bots later, so weapon logic never reads a specific body type.

## Horizontal speed at which [member WeaponDefinition.run_spread] applies in full (m/s).
const REFERENCE_SPEED: float = 5.6

var speed: float = 0.0
var airborne: bool = false
var crouched: bool = false


## 0 when standing still, 1 at full running speed; squared so walking is much more accurate.
func movement_factor() -> float:
	var ratio := clampf(speed / REFERENCE_SPEED, 0.0, 1.0)
	return ratio * ratio
