// Elegant gold shimmer for god dialogue boxes: a soft warm glow plus a diagonal band of white
// light that sweeps across, with a faint sparkle. Drawn additively over the gold panel.
shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Seconds for the band to cross the box once.
uniform float sweep_seconds : hint_range(0.5, 10.0) = 2.6;
// Band width in UV units.
uniform float band_width : hint_range(0.01, 0.5) = 0.12;
uniform float band_slant : hint_range(-2.0, 2.0) = 0.35;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.12;
uniform float flash_strength : hint_range(0.0, 2.0) = 0.65;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.25;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// The band travels past both edges so it fully leaves before restarting.
	float head = fract(TIME / sweep_seconds) * (1.0 + 4.0 * band_width) - 2.0 * band_width;
	float along = UV.x + (UV.y - 0.5) * band_slant;
	float band = smoothstep(band_width, 0.0, abs(along - head));
	float edge_glow = (1.0 - UV.y) * glow_strength;
	vec2 cell = floor(UV * vec2(90.0, 18.0));
	float twinkle = step(0.985, hash(cell)) * (0.5 + 0.5 * sin(TIME * 6.0 + hash(cell) * 40.0));
	vec3 light = glow_color.rgb * edge_glow + flash_color.rgb * band * flash_strength;
	light += flash_color.rgb * twinkle * sparkle_strength * band;
	COLOR = vec4(light, 1.0);
}
