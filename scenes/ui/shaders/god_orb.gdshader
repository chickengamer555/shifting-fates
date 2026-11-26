shader_type canvas_item;
// A god as a ball of light: a hot core, a soft halo, faint slowly turning rays and a flicker.
// Drawn over the whole rect of a GodOrb; the orb sits at the rect's centre. The script feeds
// intensity (how bright, already including the breathing pulse) and speak (0 calm, 1 talking).

uniform vec4 tint : source_color = vec4(1.0, 0.98, 0.92, 1.0);
// Overall brightness, roughly 0..1.5. Zero draws nothing.
uniform float intensity = 0.6;
// 0 = calm, 1 = speaking: faster, stronger rays and flicker.
uniform float speak = 0.0;
// Per-orb offset so neighbouring orbs never flicker in step.
uniform float seed = 0.0;
// Core radius as a fraction of the half-size of the rect.
uniform float core_radius = 0.085;
// Inner glow hugging the core (exponential) and the wide, faint haze around it (gaussian, so it
// is gone well before the edge of the rect). Falloff: higher = tighter.
uniform float glow_falloff = 6.0;
uniform float glow_strength = 1.0;
uniform float haze_falloff = 5.0;
uniform float haze_strength = 0.5;
uniform float ray_count = 6.0;
uniform float ray_strength = 0.14;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float t = TIME + seed * 17.0;
	float flicker = 1.0 + (noise(t * mix(2.5, 8.0, speak)) - 0.5) * mix(0.06, 0.14, speak);
	float energy = max(intensity, 0.0) * flicker;
	float core_r = core_radius * (0.8 + 0.35 * energy);
	float core = 1.0 - smoothstep(core_r * 0.45, core_r * 1.3, d);
	float glow = exp(-d * glow_falloff / (0.6 + 0.4 * energy)) * glow_strength;
	float haze = exp(-d * d * haze_falloff) * haze_strength;
	float angle = atan(p.y, p.x);
	float rays_a = pow(abs(sin(angle * ray_count * 0.5 + t * 0.12)), 6.0);
	float rays_b = pow(abs(sin(angle * (ray_count + 3.0) * 0.5 - t * 0.09 + seed)), 10.0);
	float ray_fall = exp(-d * 4.0) * smoothstep(core_r, core_r * 2.5, d);
	float rays = (rays_a + rays_b * 0.5) * ray_fall * ray_strength * (0.4 + speak);
	float edge = 1.0 - smoothstep(0.4, 1.0, d);
	float light = (glow + haze + rays) * energy * edge;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core * 0.8 + glow * 0.2, 0.0, 1.0));
	float alpha = clamp(core * min(energy * 1.8, 1.0) + light, 0.0, 1.0);
	COLOR = vec4(col, alpha * tint.a);
}
