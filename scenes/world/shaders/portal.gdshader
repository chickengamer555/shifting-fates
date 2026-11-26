shader_type spatial;
// Ethereal portal surface ("Veil"). A quad facing +Z; its middle shows the other world (the
// preview viewport, sampled in screen space so it reads as a window, not a picture). Its edge
// is a soft rim of light, pushed around by slow noise, that frays outward into drifting mist
// and sparks. The rim takes `rim_color`: the portal sets it to the other world's main colour.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// Never drawn over a rider riding through (marked 7 by portal_rider_mask.gdshader).
stencil_mode read, compare_not_equal, 7;

uniform sampler2D preview : source_color, filter_linear, repeat_disable;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
// Half the quad's side, in metres; positions below are in metres from the centre.
uniform float half_size = 2.5;
uniform float radius = 1.4;
// 0 closed (only a speck of light) to 1 fully open.
uniform float openness : hint_range(0.0, 1.0) = 1.0;
uniform float glow_energy = 1.6;
// 1 when the viewer is right at the opening, in line with it: the view through shows pure,
// with no rim, mist, sparks or ripple over it (set by portal.gd).
uniform float clarity : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

// Tiny drifting sparks: returns brightness at p for a field of motes rising at `speed`.
float motes(vec2 p, float t, float density, float speed) {
	vec2 q = p * density + vec2(0.0, -t * speed);
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash(cell);
	vec2 offset = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(f - offset * 0.6);
	float twinkle = 0.5 + 0.5 * sin(t * 3.0 + h * TAU);
	return step(0.72, h) * smoothstep(0.09, 0.0, d) * twinkle;
}

vec3 sample_preview(vec2 uv) {
	return texture(preview, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}

// The far world seen through the opening, shaded darker and tinted towards the rim so the
// opening reads as a passage with depth and the light around it stands out.
vec3 deepen(vec3 view, float edge, vec3 tint) {
	float depth = smoothstep(-0.02, -0.85, edge);
	return view * mix(tint * 0.3, vec3(1.0), depth);
}

void fragment() {
	float t = TIME;
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	p.y = -p.y;
	float r = length(p);
	float a = atan(p.y, p.x);
	float open_r = radius * openness;

	// The rim is pushed around by slow noise and dissolves outward into mist.
	float wobble = (fbm(vec2(a * 2.0, t * 0.35)) - 0.5) * 0.35;
	float edge = r - (open_r + wobble * openness);
	float inside = smoothstep(0.12, -0.18, edge);
	float mist = fbm(p * 1.6 + vec2(0.0, -t * 0.4)) * smoothstep(1.1, 0.0, edge);
	float rim = exp(-abs(edge) * 9.0);
	// The rim's hot core runs towards white; the mist keeps the colour.
	vec3 light = mix(rim_color, mix(rim_color, vec3(1.0), 0.55), rim);
	float haze = 1.0 - clarity;
	vec3 view = sample_preview(SCREEN_UV + p * 0.004 * sin(t + r * 4.0) * haze);
	view = mix(view, deepen(view, edge, rim_color), haze);
	vec3 col = mix(light * glow_energy * (rim + mist * 0.8), view, inside);
	col += mix(rim_color, vec3(1.0), 0.6) * motes(p, t, 3.0, 0.35)
		* smoothstep(1.4, 0.0, edge) * 2.0 * haze;
	float alpha = max(inside, clamp(rim * 1.2 + mist * mist * 1.4, 0.0, 1.0)
		* smoothstep(1.4, 0.2, edge) * haze);

	// While opening, only a bright point is visible at the centre.
	float speck = exp(-r * 18.0) * (1.0 - openness) * step(0.001, openness);
	// Fade out well before the quad's own border so no straight edge ever shows.
	float border = smoothstep(half_size, half_size * 0.72, max(abs(p.x), abs(p.y)));
	ALBEDO = col + vec3(1.0, 0.95, 0.85) * speck * 4.0;
	ALPHA = clamp(alpha + speck, 0.0, 1.0) * border;
}
