// Invisible barrier hint: ordered-dither dots in the colour of the nearest material that fade
// in as the player gets close. Dots sit on a world-space grid projected onto the face, so they
// stay put on the wall instead of swimming with the camera. Only the side of the wall facing
// the player shows dots: never its top, its ends or its far side, so the box itself is never
// seen, only a wall.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

// Colour of the floor the barrier stands on.
uniform vec4 floor_color : source_color = vec4(1.0);
// World position of the player, fed by invisible_barrier.gd each frame.
uniform vec3 player_position = vec3(0.0, -100000.0, 0.0);
// Fully hidden beyond this distance (m); fully dotted at the wall.
uniform float reveal_distance = 6.0;
// Distance between dot centres on the wall (m).
uniform float dot_spacing = 0.25;
// Dot radius as a fraction of the spacing.
uniform float dot_radius = 0.22;
// Strongest opacity of a dot.
uniform float max_alpha = 0.9;

// 4x4 Bayer matrix: the order in which grid cells light up as the player approaches.
const float BAYER_4X4[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
const float BAYER_CELLS = 16.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Only upright faces turned towards the player.
	vec3 to_player = player_position - world_position;
	if (abs(world_normal.y) > 0.5 || dot(world_normal, to_player) <= 0.0) {
		discard;
	}
	vec3 n = abs(world_normal);
	vec2 plane = world_position.xy;
	if (n.x >= n.y && n.x >= n.z) {
		plane = world_position.zy;
	} else if (n.y >= n.z) {
		plane = world_position.xz;
	}
	vec2 grid = plane / dot_spacing;
	vec2 cell = floor(grid);
	int bayer_x = int(mod(cell.x, 4.0));
	int bayer_y = int(mod(cell.y, 4.0));
	float threshold = (BAYER_4X4[bayer_y * 4 + bayer_x] + 0.5) / BAYER_CELLS;

	float distance_to_player = distance(world_position, player_position);
	float proximity = 1.0 - smoothstep(0.0, reveal_distance, distance_to_player);
	float in_dot = step(length(fract(grid) - 0.5), dot_radius);
	float lit = step(threshold, proximity) * in_dot;
	if (lit < 0.5) {
		discard;
	}
	ALBEDO = floor_color.rgb;
	ALPHA = max_alpha * floor_color.a * proximity;
}
