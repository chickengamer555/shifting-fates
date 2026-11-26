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

void fragment() {
	vec3 p = cb_world((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 eye = cb_world(CAMERA_POSITION_WORLD);
	vec3 n = normalize(cb_world((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
	vec3 d = normalize(p - eye);
	float dist = length(p - eye);
	vec2 drift = wind * (TIME * flow_speed);

	vec3 rc = texture(mirror, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)).rgb;
	vec3 seen = cb_mirror_tint(rc, base_color, metal) * reflection;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 lit = cb_light(base_color, up, d, diffusion, ambience, specularity, spec_color, 40.0, false) * (1.0 - reflection) + seen;
	vec3 dark = cb_light(base_color, up, d, diffusion, ambience, specularity, spec_color, 40.0, true) * (1.0 - reflection) + seen;
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
