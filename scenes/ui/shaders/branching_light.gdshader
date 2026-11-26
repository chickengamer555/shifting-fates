// The main menu's oscillating white light: filaments of light radiate out of the god orb at
// [origin] and branch across the top of the screen, mostly sideways, short ones reaching
// down. Each filament meanders slowly, forks into thinner branches, breathes in length and
// carries soft pulses travelling outward. Additive; drawn over a rect across the top.
// The menu script feeds rect_size, origin (px, in the rect) and breath (-1..1, the orb's).
shader_type canvas_item;
render_mode blend_add;

uniform vec4 light_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec2 rect_size = vec2(1152.0, 360.0);
// Where the light comes from, in px inside the rect (the orb's centre).
uniform vec2 origin = vec2(576.0, 72.0);
// The orb's breathing, -1..1: the rays swell and fade with it.
uniform float breath = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
// Length (px) of the rays that run sideways and of those that point straight down.
uniform float side_reach = 980.0;
uniform float down_reach = 46.0;
// No ray reaches further than this (px) below the orb, so the light stays above the title.
uniform float max_drop = 92.0;
// Core width of a filament (px) at the orb and how much it widens per px outward.
uniform float core_width = 0.8;
uniform float spread = 0.0035;
// How far (fraction of distance) a filament meanders off its straight line.
uniform float meander = 0.035;
// Speed of the light pulses running outward along the filaments.
uniform float pulse_speed = 1.6;

const int RAY_COUNT = 14;
const int FORKS = 2;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// Sideways offset (px) of a filament at distance [along] from its root.
float wobble(float along, float seed) {
	float slow = sin(along * 0.011 + seed * 3.1 + TIME * 0.35) * 0.6;
	float fast = sin(along * 0.029 - TIME * 0.6 + seed * 7.3) * 0.4;
	return (slow + fast) * along * meander;
}

// Light of one filament from [root] along [angle], [reach] px long.
float filament(vec2 p, vec2 root, float angle, float reach, float seed, float strength) {
	vec2 dir = vec2(cos(angle), sin(angle));
	vec2 rel = p - root;
	float along = dot(rel, dir);
	if (along <= 0.0 || along >= reach) {
		return 0.0;
	}
	float across = abs(dot(rel, vec2(-dir.y, dir.x)) - wobble(along, seed));
	float width = core_width + along * spread;
	float core = width / (across + width);
	core *= core;
	float halo = exp(-across / (7.0 + along * 0.035)) * 0.3;
	float fade = pow(1.0 - along / reach, 1.4);
	float pulse = 0.72 + 0.28 * sin(along * 0.025 - TIME * pulse_speed + seed * 5.0);
	return (core + halo) * fade * pulse * strength;
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 rel = p - origin;
	float swell = 0.88 + 0.12 * breath;
	float light = 0.0;
	for (int i = 0; i < RAY_COUNT; i++) {
		float fi = float(i);
		float f = (fi + 0.5) / float(RAY_COUNT);
		// A fan from just above the right horizon, down, to just above the left one.
		float angle = mix(-0.14, PI + 0.14, f) + (hash(fi) - 0.5) * 0.12
			+ sin(TIME * 0.17 + fi * 1.3) * 0.025;
		float sideways = pow(abs(cos(angle)), 1.6);
		float reach = mix(down_reach, side_reach, sideways) * swell
			* (0.85 + 0.15 * sin(TIME * 0.45 + fi * 1.7)) * (0.8 + 0.3 * hash(fi + 4.0));
		reach = min(reach, max_drop / max(sin(angle), 0.01));
		float strength = mix(0.2, 1.0, sideways);
		light += filament(p, origin, angle, reach, fi, strength);
		for (int b = 0; b < FORKS; b++) {
			float fb = float(b);
			float at = reach * (0.28 + 0.24 * fb + 0.06 * hash(fi * 3.0 + fb));
			vec2 dir = vec2(cos(angle), sin(angle));
			vec2 fork = origin + dir * at + vec2(-dir.y, dir.x) * wobble(at, fi);
			float side = mod(fi + fb, 2.0) < 1.0 ? 1.0 : -1.0;
			float turn = side * (0.18 + 0.2 * hash(fi * 7.0 + fb))
				+ sin(TIME * 0.3 + fi + fb) * 0.04;
			float fork_reach = (reach - at) * (0.42 - 0.08 * fb) * swell;
			light += filament(p, fork, angle + turn, fork_reach, fi * 5.0 + fb + 1.0,
				strength * 0.4);
		}
	}
	// A soft canopy of light hugging the top, densest at the orb.
	float canopy = exp(-abs(rel.y + 10.0) / 42.0) * exp(-abs(rel.x) / 420.0) * 0.22;
	float bloom = exp(-length(rel) / 95.0) * 0.35;
	light += (canopy + bloom) * swell;
	float bottom_fade = 1.0 - smoothstep(0.6, 1.0, UV.y);
	vec3 col = light_color.rgb * light * intensity * bottom_fade;
	// Soft shoulder, so overlapping filaments glow instead of clipping to a flat white.
	col = vec3(1.0) - exp(-col * 1.3);
	COLOR = vec4(col, 1.0);
}
