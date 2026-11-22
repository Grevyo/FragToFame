class_name MapLighting
extends RefCounted
## A map's sun and ambient light settings. Stored in the map document; an empty dictionary means
## "leave the scene's default lighting alone", so maps made before lighting existed look the same.

const DEFAULTS: Dictionary = {
	"sun_yaw": 30.0, "sun_pitch": 45.0, "sun_energy": 1.0, "sun_color": "ffffff",
	"ambient_color": "8c99ad", "ambient_energy": 0.6, "haze": 0.35, "sky": "",
}
const LIMITS: Dictionary[String, Vector2] = {
	"sun_yaw": Vector2(0, 360), "sun_pitch": Vector2(5, 90), "sun_energy": Vector2(0, 4),
	"ambient_energy": Vector2(0, 2), "haze": Vector2(0, 1),
}
## Furthest distance (m) the sun's shadows are drawn; covers a whole competitive map.
const SHADOW_DISTANCE: float = 140.0


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
		elif key == "sky":
			# A panorama from MapSkies; anything unknown falls back to the plain sky.
			var sky_id := str(lighting[key])
			result[key] = sky_id if MapSkies.has(sky_id) else ""
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
		# With a sky, the ambient colour is blended with light from the sky so shaded faces still
		# pick up its tint; without one, the colour alone lights them.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if environment.sky != null else Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.45
		environment.ambient_light_color = Color.from_string(str(settings["ambient_color"]), Color.WHITE)
		environment.ambient_light_energy = float(settings["ambient_energy"])


## The shared outdoor look, applied in the editor and the game alike so what you build is what you
## play: a sky tinted by the sun, soft four-split sun shadows, ambient occlusion and global
## illumination (bounce light, shaded interiors), haze that fades distant geometry toward the horizon, gentle bloom and filmic
## tonemapping. Empty [param lighting] uses the defaults (only the sky and haze depend on it).
static func apply_atmosphere(lighting: Dictionary, sun: DirectionalLight3D, environment: Environment) -> void:
	var settings := normalised(lighting)
	var sun_color := Color.from_string(str(settings["sun_color"]), Color.WHITE)
	var ambient := Color.from_string(str(settings["ambient_color"]), Color.WHITE)
	var elevation := clampf(float(settings["sun_pitch"]) / 90.0, 0.0, 1.0)
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = SHADOW_DISTANCE
		sun.directional_shadow_split_1 = 0.06
		sun.directional_shadow_split_2 = 0.16
		sun.directional_shadow_split_3 = 0.42
		sun.directional_shadow_blend_splits = true
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.4
		sun.shadow_blur = 1.6
		sun.light_angular_distance = 0.6
	if environment == null:
		return
	var horizon := ambient.lerp(sun_color, 0.35).lightened(0.18)
	var sky := Sky.new()
	sky.sky_material = _sky_material(str(settings["sky"]), ambient, horizon)
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 2.2
	environment.ssao_power = 1.6
	environment.ssao_detail = 0.6
	environment.ssao_light_affect = 0.15
	# Real-time global illumination: sky light is blocked by walls and roofs, so rooms, covered
	# passages and narrow alleys fall into shade, and sunlit ground bounces warm light back up.
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = true
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	environment.sdfgi_bounce_feedback = 0.6
	environment.sdfgi_energy = 1.0
	environment.ssil_enabled = false
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.2
	var haze := float(settings["haze"])
	environment.fog_enabled = haze > 0.0
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = horizon
	environment.fog_sun_scatter = 0.25
	environment.fog_density = 1.0
	environment.fog_depth_begin = lerpf(160.0, 24.0, haze)
	environment.fog_depth_end = lerpf(420.0, 170.0, haze)
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.5 * haze
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.0 + 0.08 * elevation


## The map's painted panorama (MapSkies) or, without one, a plain sky tinted by the light colours.
static func _sky_material(sky_id: String, ambient: Color, horizon: Color) -> Material:
	var painted := MapSkies.material(sky_id)
	if painted != null:
		return painted
	var plain := ProceduralSkyMaterial.new()
	plain.sky_top_color = ambient.darkened(0.35).lerp(Color("3d6aa8"), 0.55)
	plain.sky_horizon_color = horizon
	plain.sky_curve = 0.12
	plain.ground_horizon_color = horizon
	plain.ground_bottom_color = ambient.darkened(0.7)
	plain.sun_angle_max = 24.0
	plain.sun_curve = 0.12
	return plain
