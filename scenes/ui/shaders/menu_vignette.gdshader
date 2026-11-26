// Darkens the menu's live background where text and light sit, so they read over bright
// skies: a soft vignette at the edges, a band across the top (under the god's light) and a
// pool in the bottom-left corner (under the wishes). Alpha blended over the background.
shader_type canvas_item;

uniform vec4 shade_color : source_color = vec4(0.01, 0.012, 0.03, 1.0);
// Darkening everywhere, at the edges, across the top and under the wishes (0..1 each).
uniform float base_amount : hint_range(0.0, 1.0) = 0.26;
uniform float edge_amount : hint_range(0.0, 1.0) = 0.5;
uniform float top_amount : hint_range(0.0, 1.0) = 0.6;
uniform float corner_amount : hint_range(0.0, 1.0) = 0.45;
// Width / height of the screen, so the vignette stays round on any aspect.
uniform float aspect = 1.7778;

void fragment() {
	vec2 centred = (UV - 0.5) * vec2(aspect, 1.0);
	float edge = smoothstep(0.45, 1.05, length(centred));
	float top = 1.0 - smoothstep(0.0, 0.5, UV.y);
	vec2 corner = (UV - vec2(0.0, 1.0)) * vec2(aspect, 1.0);
	float pool = 1.0 - smoothstep(0.1, 0.85, length(corner * vec2(0.85, 1.25)));
	float shade = base_amount + edge * edge_amount + top * top_amount + pool * corner_amount;
	COLOR = vec4(shade_color.rgb, clamp(shade, 0.0, 0.92));
}
