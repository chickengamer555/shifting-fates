// Chickbry 3D's Cloud Plane (render.cpp cloud_alpha): a translucent fractal layer.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix;
#include "chickbry_look.gdshaderinc"

uniform uint seed = 0u;
uniform float y_offset = 0.0;      // the renderer's seed * 0.001, kept small for float precision
uniform float cloud_cover = 0.2;   // 0..1
uniform float cloud_freq = 1.0;
uniform float cloud_amp = 1.0;
uniform bool cumulus = false;     // the sky's Cumulus switch: puffier
uniform vec3 cloud_lit = vec3(1.0);  // cloud colour under the sun and ambient (display)
varying vec3 wp;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wp = vec3(w.x, w.y, -w.z);
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

	float sc = 1.0 / 140.0 * cloud_freq;
	float tt = TIME * flow_speed;   // render.cpp cloud_alpha with an animated material
	float x = wp.x + tt * 12.0, z = wp.z + tt * 5.0;
	float nz = cb_fbm(vec3(x * sc, y_offset + tt * 0.05, z * sc), 6, seed, 0.5);
	if (cumulus) nz = 0.75 * nz + 0.25 * cb_fbm(vec3(x * sc * 0.5 + 9.0, 3.3, z * sc * 0.5), 3, seed + 5u, 0.5);
	float th = 0.5 + (0.5 - cloud_cover) * 0.45;
	float soft = 0.12 / cloud_amp;
	float a = cb_sstep(th - soft * 0.2, th + soft, nz);
	vec3 c = cloud_lit * (1.0 - 0.25 * (d.y > 0.0 ? 1.0 : 0.0) * cb_sstep(0.4, 1.0, a));
	ALBEDO = cb_linear(cb_atmosphere(c, eye, d, dist));
	ALPHA = a;
}
