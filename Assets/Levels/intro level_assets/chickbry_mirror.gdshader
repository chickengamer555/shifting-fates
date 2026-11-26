// Chickbry 3D's reflective Ground Plane (render.cpp trace(): own light, then the
// reflected ray tinted by the metal formula). chickbry_mirror_floor.gd draws the scene seen
// in the floor into `mirror`; this shades it as Chickbry does.
shader_type spatial;
render_mode ambient_light_disabled, fog_disabled, specular_disabled;
#include "chickbry_look.gdshaderinc"

uniform sampler2D mirror : filter_linear, repeat_disable;   // display colours, as drawn
uniform vec3 base_color = vec3(0.9, 0.0, 0.24);   // display 0..1
uniform float reflection = 1.0;   // how much of the colour is the reflected ray
uniform float metal = 0.0;        // a metal keeps its own hue: the surroundings set its brightness
uniform float diffusion = 0.8;
uniform float ambience = 0.2;
uniform float specularity = 0.3;
uniform vec3 spec_color = vec3(1.0);
uniform bool ripples = false;     // an animated material (a pool's water): its normal ripples with time
uniform uint seed = 0u;           // object seed + 41, as the renderer's ripples use

// one ray at a point of the plane: its colour in sun and in shadow (render.cpp trace())
void cb_mirror_ray(vec3 q, vec2 suv, vec3 eye, vec2 drift, mat4 view, mat4 proj, out vec3 lit, out vec3 dark) {
	vec3 dq = normalize(q - eye);
	vec3 up = vec3(0.0, 1.0, 0.0), nn = up;
	if (ripples) {   // render.cpp trace(): flowing ripples on animated materials
		float tt = TIME * flow_speed;
		vec3 c = q * 0.15 + vec3(tt * 0.35, tt * 0.6, tt * 0.2);
		float n0 = cb_fbm(c, 3, seed, 0.5);
		vec3 g = vec3(cb_fbm(c + vec3(0.06, 0.0, 0.0), 3, seed, 0.5) - n0, cb_fbm(c + vec3(0.0, 0.06, 0.0), 3, seed, 0.5) - n0,
				cb_fbm(c + vec3(0.0, 0.0, 0.06), 3, seed, 0.5) - n0) / 0.4;
		nn = normalize(up - (g - up * dot(g, up)) * 1.5);
	}
	// the reflected ray turns by twice the tilt: read the mirror that far over; out of its
	// picture, Chickbry's own sky (and ground) that way
	vec3 tilt = (view * vec4(cb_world(nn - up), 0.0)).xyz;
	vec2 off = tilt.xy * vec2(proj[0][0], proj[1][1]);
	vec2 uv = vec2(1.0 - suv.x - off.x, suv.y + off.y);
	vec3 rc = all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0))) ? texture(mirror, uv).rgb
			: cb_seen(q, reflect(dq, nn), eye, drift);
	vec3 seen = cb_mirror_tint(rc, base_color, metal) * reflection;
	lit = cb_light(base_color, nn, dq, diffusion, ambience, specularity, spec_color, 40.0, false) * (1.0 - reflection) + seen;
	dark = cb_light(base_color, nn, dq, diffusion, ambience, specularity, spec_color, 40.0, true) * (1.0 - reflection) + seen;
}

void fragment() {
	vec3 p = cb_world((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 eye = cb_world(CAMERA_POSITION_WORLD);
	vec3 n = normalize(cb_world((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
	vec3 d = normalize(p - eye);
	float dist = length(p - eye);
	vec2 drift = wind * (TIME * flow_speed);
	// a mirror's camera (it lacks its plane's layer) sees nothing under the plane, as
	// Chickbry's reflected rays can't: no rock's sunken half shows in the water
	if (CB_GROUND_MIRROR && (CAMERA_VISIBLE_LAYERS & CB_GROUND_LAYER_BIT) == 0u && p.y < CB_GROUND_Y) discard;
	if (CB_WATER && (CAMERA_VISIBLE_LAYERS & CB_WATER_LAYER_BIT) == 0u && p.y < CB_WATER_Y) discard;
	// that camera sits under its plane; Chickbry's reflected ray meets haze only from the plane
	// on (the stretch to the eye is the plane's own): start the air where the ray leaves it
	float mirror_y = CB_GROUND_MIRROR && (CAMERA_VISIBLE_LAYERS & CB_GROUND_LAYER_BIT) == 0u ? CB_GROUND_Y
			: CB_WATER && (CAMERA_VISIBLE_LAYERS & CB_WATER_LAYER_BIT) == 0u ? CB_WATER_Y : 1e30;
	if (mirror_y < 1e29 && eye.y < mirror_y && p.y > mirror_y) {
		eye += (p - eye) * ((mirror_y - eye.y) / (p.y - eye.y));
		dist = length(p - eye);
	}

	// rippled: four rays a pixel, as Chickbry antialiases where neighbours differ
	vec3 lit = vec3(0.0), dark = vec3(0.0);
	if (!ripples) cb_mirror_ray(p, SCREEN_UV, eye, drift, VIEW_MATRIX, PROJECTION_MATRIX, lit, dark);
	else {
		vec3 dpx = dFdx(p), dpy = dFdy(p);
		vec2 px = 1.0 / VIEWPORT_SIZE;
		for (int k = 0; k < 4; k++) {
			vec2 o = (vec2(float(k & 1), float(k >> 1)) - 0.5) * 0.5;
			vec3 l, dk;
			cb_mirror_ray(p + dpx * o.x + dpy * o.y, SCREEN_UV + o * px, eye, drift, VIEW_MATRIX, PROJECTION_MATRIX, l, dk);
			lit += l * 0.25;
			dark += dk * 0.25;
		}
	}
	cb_lit = cb_linear(cb_atmosphere(lit, eye, d, dist));
	cb_dark = cb_linear(cb_atmosphere(dark, eye, d, dist));
	cb_lamp = cb_linear(base_color) * (diffusion / 0.8) * (1.0 - reflection);
	ROUGHNESS = 1.0;
	ALBEDO = vec3(1.0);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = cb_lit;
}

void light() {
	DIFFUSE_LIGHT += cb_light_pass(LIGHT_IS_DIRECTIONAL, ATTENUATION, LIGHT_COLOR, dot(NORMAL, LIGHT), cb_lit, cb_dark, cb_lamp);
}
