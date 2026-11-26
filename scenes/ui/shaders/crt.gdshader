// A gentle CRT look over the whole screen: slight barrel curvature with soft dark corners,
// scanlines, a faint RGB aperture mask with a small colour fringe, a soft glow on bright
// areas and a barely visible flicker and grain. Put it on a full-screen ColorRect on the
// topmost CanvasLayer. Every effect scales with intensity (0 = untouched picture).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Master strength, 0 to 1.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// Barrel distortion at the corners (fraction of the screen).
uniform float curvature : hint_range(0.0, 0.2) = 0.035;
// Scanline pairs from top to bottom, and how dark the gaps get.
uniform float scanline_count = 360.0;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.22;
// Strength of the per-pixel red/green/blue mask.
uniform float mask_strength : hint_range(0.0, 1.0) = 0.08;
// Colour fringe offset in screen pixels at the edges.
uniform float fringe_pixels : hint_range(0.0, 4.0) = 1.0;
// Glow added from blurred bright areas.
uniform float glow_amount : hint_range(0.0, 1.0) = 0.2;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.7;
// Darkening towards the corners.
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_amount : hint_range(0.0, 0.1) = 0.012;
uniform float noise_amount : hint_range(0.0, 0.1) = 0.018;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 barrel(vec2 uv, float amount) {
	vec2 centred = uv * 2.0 - 1.0;
	centred *= 1.0 + amount * dot(centred, centred);
	// Shrink back so the edge midpoints stay on screen and only the corners bend away.
	centred /= 1.0 + amount;
	return centred * 0.5 + 0.5;
}

void fragment() {
	float k = clamp(intensity, 0.0, 1.0);
	vec2 uv = barrel(SCREEN_UV, curvature * k);
	// Soft fall-off where the bent picture leaves the tube.
	vec2 inside = smoothstep(vec2(0.0), vec2(0.004), uv) * smoothstep(vec2(0.0), vec2(0.004),
			1.0 - uv);
	float tube = inside.x * inside.y;
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	vec2 from_centre = uv - 0.5;
	vec2 fringe = from_centre * 2.0 * SCREEN_PIXEL_SIZE * fringe_pixels * k;
	vec3 col;
	col.r = textureLod(screen_texture, uv + fringe, 0.0).r;
	col.g = textureLod(screen_texture, uv, 0.0).g;
	col.b = textureLod(screen_texture, uv - fringe, 0.0).b;

	vec3 blurred = textureLod(screen_texture, uv, 3.0).rgb;
	blurred += textureLod(screen_texture, uv, 4.5).rgb;
	blurred *= 0.5;
	float bright = max(max(blurred.r, blurred.g), blurred.b);
	col += blurred * smoothstep(glow_threshold, 1.0, bright) * glow_amount * k;

	float line = 0.5 + 0.5 * cos(uv.y * scanline_count * 2.0 * PI);
	// Bright pixels bloom across the gap, so scanlines fade where the picture is light.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float depth = scanline_depth * k * (1.0 - 0.5 * luma);
	col *= 1.0 - depth * (1.0 - line);

	int column = int(mod(FRAGCOORD.x, 3.0));
	vec3 mask = vec3(column == 0 ? 1.0 : 0.0, column == 1 ? 1.0 : 0.0, column == 2 ? 1.0 : 0.0);
	col *= mix(vec3(1.0), 0.75 + 0.5 * mask, mask_strength * k);

	// Lift back the light the scanlines and mask took away.
	col *= 1.0 + 0.5 * depth + 0.1 * mask_strength * k;

	float vignette = 1.0 - dot(from_centre, from_centre) * 2.0;
	col *= mix(1.0, smoothstep(0.0, 1.0, vignette), vignette_amount * k);

	col *= 1.0 + flicker_amount * k * sin(TIME * 9.0) * sin(TIME * 47.0);
	col += (hash(SCREEN_UV * 731.0 + fract(TIME)) - 0.5) * noise_amount * k;

	COLOR = vec4(col * tube, 1.0);
}
