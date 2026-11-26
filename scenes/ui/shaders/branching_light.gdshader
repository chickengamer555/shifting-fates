// The main menu's oscillating white light: a glowing filament that sways across the top of
// the screen and keeps sprouting flickering branches that reach down and fade. Additive.
shader_type canvas_item;
render_mode blend_add;

uniform vec4 light_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Height of the main filament, as a fraction of the rect from the top.
uniform float trunk_height : hint_range(0.0, 1.0) = 0.22;
uniform float sway_amount : hint_range(0.0, 0.3) = 0.06;
uniform float sway_speed : hint_range(0.0, 5.0) = 0.9;
// Core thickness of the filaments; smaller is sharper.
uniform float thickness : hint_range(0.0005, 0.02) = 0.0035;
uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;
// Branch lengths grow and shrink at this rate.
uniform float branch_speed : hint_range(0.0, 5.0) = 0.7;
uniform float branch_reach : hint_range(0.0, 1.0) = 0.65;
uniform float flicker : hint_range(0.0, 1.0) = 0.35;

const int BRANCH_COUNT = 9;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i.x + i.y * 57.0);
	float b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0);
	float d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		total += noise(p) * amplitude;
		p *= 2.1;
		amplitude *= 0.5;
	}
	return total;
}

float filament(float distance_to_line) {
	return thickness / (abs(distance_to_line) + thickness);
}

float trunk_y(float x) {
	float sway = sin(x * 5.0 + TIME * sway_speed) * sway_amount;
	return trunk_height + sway + (fbm(vec2(x * 9.0, TIME * 0.6)) - 0.5) * 0.05;
}

void fragment() {
	vec2 uv = UV;
	float light = filament(uv.y - trunk_y(uv.x)) * 1.4;
	for (int i = 0; i < BRANCH_COUNT; i++) {
		float fi = float(i);
		float root_x = (fi + 0.5) / float(BRANCH_COUNT) + (hash(fi * 3.7) - 0.5) * 0.08;
		float root_y = trunk_y(root_x);
		float depth = uv.y - root_y;
		// Each branch pulses in and out at its own phase.
		float reach = branch_reach * (0.5 + 0.5 * sin(TIME * branch_speed + fi * 1.9));
		if (depth <= 0.0 || depth > reach) {
			continue;
		}
		float slant = (hash(fi * 9.1) - 0.5) * 0.9;
		float jitter = (fbm(vec2(depth * 14.0 + fi * 5.0, TIME * 1.3)) - 0.5) * 0.12;
		float branch_x = root_x + depth * slant + jitter * depth * 3.0;
		float fade = 1.0 - depth / reach;
		light += filament((uv.x - branch_x) * 0.6) * fade * fade;
	}
	float shimmer = 1.0 - flicker * fbm(vec2(TIME * 4.0, uv.x * 3.0));
	float vertical_fade = 1.0 - smoothstep(0.55, 1.0, uv.y);
	float intensity = light * glow_strength * shimmer * vertical_fade;
	COLOR = vec4(light_color.rgb * intensity, 1.0);
}
