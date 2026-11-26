// Faint edge drawn behind a grapple line (a next pass): the back faces pushed out along the
// normals by a fixed number of screen pixels, so a black line still reads on a dark sky.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 edge_color : source_color = vec4(0.7, 0.72, 0.78, 0.5);
uniform float edge_pixels = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float world_per_pixel = 2.0 * clip.w / (VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]);
	VERTEX += NORMAL * edge_pixels * world_per_pixel;
}

void fragment() {
	ALBEDO = edge_color.rgb;
	ALPHA = edge_color.a;
}
