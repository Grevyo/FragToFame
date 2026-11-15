class_name MapLighting
extends RefCounted
## A map's sun and ambient light settings. Stored in the map document; an empty dictionary means
## "leave the scene's default lighting alone", so maps made before lighting existed look the same.

const DEFAULTS: Dictionary = {
	"sun_yaw": 30.0, "sun_pitch": 45.0, "sun_energy": 1.0, "sun_color": "ffffff",
	"ambient_color": "8c99ad", "ambient_energy": 0.6,
}
const LIMITS: Dictionary[String, Vector2] = {
	"sun_yaw": Vector2(0, 360), "sun_pitch": Vector2(5, 90), "sun_energy": Vector2(0, 4),
	"ambient_energy": Vector2(0, 2),
}


## A complete, clamped settings dictionary from possibly partial or unsafe input.
static func normalised(lighting: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key: String in DEFAULTS:
		if not lighting.has(key):
			continue
		if LIMITS.has(key):
			var value: Variant = lighting[key]
			if value is int or value is float:
				result[key] = clampf(float(value), LIMITS[key].x, LIMITS[key].y)
		else:
			var fallback := Color.from_string(str(DEFAULTS[key]), Color.WHITE)
			result[key] = Color.from_string(str(lighting[key]), fallback).to_html(false)
	return result


## Direction the sunlight travels for the given yaw (compass) and pitch (elevation) in degrees.
static func sun_direction(lighting: Dictionary) -> Vector3:
	var settings := normalised(lighting)
	var euler := Vector3(deg_to_rad(-float(settings["sun_pitch"])), deg_to_rad(float(settings["sun_yaw"])), 0)
	return Basis.from_euler(euler) * Vector3.FORWARD


## Applies the settings to a scene's sun and environment. Does nothing for empty settings.
static func apply(lighting: Dictionary, sun: DirectionalLight3D, environment: Environment) -> void:
	if lighting.is_empty():
		return
	var settings := normalised(lighting)
	if sun != null:
		sun.rotation_degrees = Vector3(-float(settings["sun_pitch"]), float(settings["sun_yaw"]), 0)
		sun.light_energy = float(settings["sun_energy"])
		sun.light_color = Color.from_string(str(settings["sun_color"]), Color.WHITE)
	if environment != null:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.from_string(str(settings["ambient_color"]), Color.WHITE)
		environment.ambient_light_energy = float(settings["ambient_energy"])
