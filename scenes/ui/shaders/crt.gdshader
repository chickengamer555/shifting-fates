// An arcade-monitor CRT look over the whole screen. Put it on a full-screen ColorRect on the
// topmost CanvasLayer. In order of how much they show:
// - scanlines: a beam profile repeated every few output pixels (a whole number, so no moire);
//   dark pixels draw a thin beam with wide dark gaps, bright pixels a fat beam that fills them;
// - an aperture-grille mask of red, green and blue stripes fixed to the glass;
// - bloom and halation: bright areas glow over the gaps and into their neighbours;
// - beam softness (a small horizontal blur) and convergence error (red and blue drift apart
//   towards the edges);
// - vignette, flicker, grain, a slow rolling hum bar and a slight curvature.
// Every effect scales with intensity (0 = untouched picture). Scanline and mask darkening are
// capped so text stays readable at full intensity.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Master strength, 0 to 1.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// Barrel distortion at the corners (fraction of the screen). Kept small on purpose.
uniform float curvature : hint_range(0.0, 0.1) = 0.012;
// Roughly how many scanlines from top to bottom; rounded so each is a whole number of pixels.
uniform float scanline_target : hint_range(120.0, 540.0) = 240.0;
// How dark the gap between scanlines gets on a dark pixel (bright pixels fill it in).
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.85;
// Beam width (fraction of a scanline) on black and on white pixels.
uniform float beam_width_dark : hint_range(0.05, 1.0) = 0.2;
uniform float beam_width_bright : hint_range(0.05, 1.0) = 0.6;
// How much the off-colour stripes of the aperture grille are darkened.
uniform float mask_strength : hint_range(0.0, 1.0) = 0.45;
// Width in screen pixels of one red, green and blue stripe triad.
uniform float mask_triad_pixels : hint_range(2.0, 6.0) = 3.0;
// Horizontal beam softness in screen pixels.
uniform float beam_blur_pixels : hint_range(0.0, 3.0) = 0.5;
// Red/blue convergence error in screen pixels at the left and right edges.
uniform float convergence_pixels : hint_range(0.0, 6.0) = 1.2;
// Glow from bright areas over their neighbours, and the wide faint halo around them.
uniform float bloom_amount : hint_range(0.0, 2.0) = 0.4;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float halation_amount : hint_range(0.0, 1.0) = 0.05;
// Darkening towards the corners.
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.45;
uniform float flicker_amount : hint_range(0.0, 0.1) = 0.02;
uniform float noise_amount : hint_range(0.0, 0.2) = 0.035;
// Brightness of the slow band rolling down the screen (0 hides it).
uniform float hum_amount : hint_range(0.0, 0.2) = 0.04;
uniform float hum_speed = 0.12;

// The scanline gap never darkens a pixel by more than this, so text keeps its shape.
const float MAX_SCAN_DARKEN = 0.78;
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

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

// One colour channel with beam softness: three taps along the line.
float soft_channel(vec2 uv, float dx, int channel) {
	vec3 a = textureLod(screen_texture, uv - vec2(dx, 0.0), 0.0).rgb;
	vec3 b = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 c = textureLod(screen_texture, uv + vec2(dx, 0.0), 0.0).rgb;
	vec3 s = 0.25 * a + 0.5 * b + 0.25 * c;
	return channel == 0 ? s.r : (channel == 1 ? s.g : s.b);
}

void fragment() {
	float k = clamp(intensity, 0.0, 1.0);
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = barrel(SCREEN_UV, curvature * k);
	// Soft fall-off where the bent picture leaves the tube.
	vec2 inside = smoothstep(vec2(0.0), vec2(0.003), uv) * smoothstep(vec2(0.0), vec2(0.003),
			1.0 - uv);
	float tube = mix(1.0, inside.x * inside.y, step(0.0001, curvature * k));
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 from_centre = uv - 0.5;

	// Beam softness and convergence error: red and blue land beside green near the edges.
	float dx = beam_blur_pixels * k * SCREEN_PIXEL_SIZE.x;
	float shift = convergence_pixels * k * SCREEN_PIXEL_SIZE.x
			* (2.0 * from_centre.x) * abs(2.0 * from_centre.x);
	vec3 col;
	col.r = soft_channel(uv + vec2(shift, 0.0), dx, 0);
	col.g = soft_channel(uv, dx, 1);
	col.b = soft_channel(uv - vec2(shift, 0.0), dx, 2);
	vec3 source = col;

	// Scanlines: a whole number of pixels per line, beam wider on bright pixels.
	float period = max(2.0, floor(screen_size.y / scanline_target + 0.5));
	float pos = uv.y * screen_size.y / period;
	float d = fract(pos) - 0.5;
	vec3 width = mix(vec3(beam_width_dark), vec3(beam_width_bright), sqrt(clamp(col, 0.0, 1.0)));
	vec3 beam = exp(-0.5 * (d * d) / (width * width * 0.25));
	vec3 scan_dark = min(vec3(scanline_depth * k), vec3(MAX_SCAN_DARKEN));
	vec3 scanned = col * mix(vec3(1.0), beam, scan_dark);

	// Aperture grille: each pixel column belongs to one red, green or blue stripe.
	float stripe = floor(mod(FRAGCOORD.x, mask_triad_pixels) * 3.0 / mask_triad_pixels);
	vec3 mask = vec3(stripe == 0.0 ? 1.0 : 0.0, stripe == 1.0 ? 1.0 : 0.0,
			stripe == 2.0 ? 1.0 : 0.0);
	float mask_k = mask_strength * k;
	scanned *= mask + (1.0 - mask) * (1.0 - mask_k);

	// Give back the average light the gaps and the mask took, as a real tube is driven harder.
	float scan_loss = 0.5 * min(scanline_depth * k, MAX_SCAN_DARKEN);
	float mask_loss = mask_k * 2.0 / 3.0;
	// Only most of it: full compensation would wash out light backgrounds.
	scanned *= 1.0 / max((1.0 - 0.6 * scan_loss) * (1.0 - 0.6 * mask_loss), 0.3);

	// Bloom and halation from blurred copies of the picture (the screen texture's mipmaps).
	vec3 near_glow = textureLod(screen_texture, uv, 2.0).rgb * 0.5
			+ textureLod(screen_texture, uv, 3.0).rgb * 0.5;
	vec3 wide_glow = textureLod(screen_texture, uv, 4.5).rgb * 0.5
			+ textureLod(screen_texture, uv, 6.0).rgb * 0.5;
	vec3 glow = near_glow * 0.6 + wide_glow * 0.4;
	float glow_luma = dot(glow, LUMA);
	vec3 bloom = glow * smoothstep(bloom_threshold, 1.0, glow_luma);
	col = scanned + (bloom * bloom_amount + wide_glow * halation_amount) * k;

	// Vignette.
	vec2 v = from_centre * 2.0;
	float vignette = clamp(1.0 - 0.5 * dot(v * v, v * v) - 0.15 * dot(v, v), 0.0, 1.0);
	col *= mix(1.0, vignette, vignette_amount * k);

	// Flicker, rolling hum bar and grain.
	col *= 1.0 + flicker_amount * k * (sin(TIME * 60.0) * 0.5 + sin(TIME * 7.3) * 0.5);
	float hum_pos = fract(SCREEN_UV.y - TIME * hum_speed);
	col *= 1.0 + hum_amount * k * smoothstep(0.0, 0.08, hum_pos) * smoothstep(0.2, 0.08, hum_pos);
	col += (hash(FRAGCOORD.xy + fract(TIME * 7.13) * 97.0) - 0.5) * noise_amount * k;

	col = mix(source, col, step(0.0001, k));
	COLOR = vec4(col * tube, 1.0);
}
