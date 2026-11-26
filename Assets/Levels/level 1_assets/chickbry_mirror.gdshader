// Chickbry 3D's reflective Ground Plane (render.cpp trace(): own light, then the
// reflected ray tinted by the metal formula). chickbry_mirror_floor.gd draws the scene seen
// in the floor into `mirror`; this shades it as Chickbry does.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D mirror : filter_linear, repeat_disable;   // display colours, as drawn
uniform vec3 base_color = vec3(0.9, 0.0, 0.24);   // display 0..1
uniform float reflection = 1.0;   // how much of the colour is the reflected ray
uniform float metal = 0.0;        // a metal keeps its own hue: the surroundings set its brightness
uniform float diffuse_k = 1.0;    // Chickbry's diffusion / 0.8 (Godot's sun is set for 0.8)

vec3 cb_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

void fragment() {
	vec3 rc = texture(mirror, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)).rgb;
	vec3 seen = rc * mix(vec3(1.0), base_color, 0.3 + 0.7 * metal);
	float l = dot(rc, vec3(0.299, 0.587, 0.114));
	seen = mix(seen, base_color * (l * 1.2), 0.6 * metal);
	ALBEDO = cb_linear(base_color) * diffuse_k * (1.0 - reflection);
	EMISSION = cb_linear(seen * reflection);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;   // no Fresnel sheen of Godot's own: the mirror above is the whole reflection
}
