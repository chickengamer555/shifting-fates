// Rough, gritty skater dialogue box: dark grip-tape body with grain, scratches and torn,
// uneven edges. Draws the whole box, so the player style uses an empty panel underneath.
shader_type canvas_item;

uniform vec4 body_color : source_color = vec4(0.09, 0.09, 0.1, 0.94);
uniform vec4 grain_color : source_color = vec4(0.32, 0.3, 0.28, 1.0);
uniform vec4 edge_color : source_color = vec4(0.85, 0.82, 0.2, 1.0);
// How deep the torn edge bites into the box, in UV units.
uniform float tear_depth : hint_range(0.0, 0.2) = 0.06;
// Number of tear teeth along the long side.
uniform float tear_frequency : hint_range(4.0, 120.0) = 46.0;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.35;
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.25;
uniform float edge_line_width : hint_range(0.0, 0.05) = 0.012;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	return mix(hash(vec2(i, 3.1)), hash(vec2(i + 1.0, 3.1)), smoothstep(0.0, 1.0, fract(x)));
}

void fragment() {
	// Distance inside each edge, minus a jagged tear amount that differs per side.
	float top = UV.y - tear_depth * noise(UV.x * tear_frequency);
	float bottom = (1.0 - UV.y) - tear_depth * noise(UV.x * tear_frequency + 17.0);
	float left = UV.x - tear_depth * 0.25 * noise(UV.y * tear_frequency * 0.3 + 5.0);
	float right = (1.0 - UV.x) - tear_depth * 0.25 * noise(UV.y * tear_frequency * 0.3 + 9.0);
	float inside = min(min(top, bottom), min(left, right));
	float body = step(0.0, inside);
	float grain = hash(floor(UV * vec2(420.0, 90.0))) * grain_amount;
	float scratch = step(0.992, hash(vec2(floor(UV.x * 160.0 + UV.y * 40.0), 1.0)));
	vec3 colour = mix(body_color.rgb, grain_color.rgb, grain + scratch * scratch_amount);
	float rim = body * (1.0 - step(edge_line_width, inside));
	colour = mix(colour, edge_color.rgb, rim);
	COLOR = vec4(colour, body_color.a * body);
}
