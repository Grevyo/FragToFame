shader_type sky;
// A painted sky panorama (assets/skies) with the sun or moon drawn where the map's lighting puts
// it, so one panorama works with any sun direction. Column 0.5 of the panorama faces north (-Z).

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
// Overall brightness of the painted sky.
uniform float energy = 1.0;
// Brightness of the sun or moon disc itself (independent of the light's strength, so a dim moon
// still reads as a moon).
uniform float disc_energy = 8.0;
// Angular radius of the disc, degrees.
uniform float disc_size = 0.9;
// Soft glow around the disc, scaled by the light's colour and strength.
uniform float glow = 0.6;
// Warm light low on the horizon toward the sun (sunsets, dusk).
uniform float horizon_glow = 0.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec2 uv = vec2(atan(dir.x, -dir.z) / TAU + 0.5, acos(clamp(dir.y, -1.0, 1.0)) / PI);
	// Level 0 always: a mip lookup would draw a seam where the panorama wraps around.
	vec3 colour = textureLod(panorama, uv, 0.0).rgb * energy;
	if (LIGHT0_ENABLED) {
		vec3 to_light = normalize(LIGHT0_DIRECTION);
		float c = dot(dir, to_light);
		float angle = degrees(acos(clamp(c, -1.0, 1.0)));
		float disc = 1.0 - smoothstep(disc_size * 0.85, disc_size, angle);
		// Only above the horizon: the painted land hides a low sun.
		float above = smoothstep(-0.5, 0.5, degrees(asin(clamp(dir.y, -1.0, 1.0))));
		float halo = pow(max(c, 0.0), 900.0) * 1.5 + pow(max(c, 0.0), 60.0) * 0.35 + pow(max(c, 0.0), 6.0) * 0.08;
		colour += LIGHT0_COLOR * disc * disc_energy * above;
		colour += LIGHT0_COLOR * LIGHT0_ENERGY * halo * glow * above;
		vec2 flat_dir = normalize(dir.xz + vec2(1e-5));
		vec2 flat_light = normalize(to_light.xz + vec2(1e-5));
		float toward = pow(max(dot(flat_dir, flat_light), 0.0), 2.0);
		colour += LIGHT0_COLOR * horizon_glow * toward * exp(-abs(dir.y) * 7.0);
	}
	COLOR = colour;
}
