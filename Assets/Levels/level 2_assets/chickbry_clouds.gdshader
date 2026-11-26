// Chickbry 3D's Cloud Plane (render.cpp cloud_alpha): a translucent fractal layer.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Chickbry's deterministic Perlin noise (render.cpp hash3 / perlin / fbm).
uint cb_hash3(int x, int y, int z, uint seed) {
	uint h = (seed * 0x9E3779B1u) ^ (uint(x) * 0x85EBCA77u) ^ (uint(y) * 0xC2B2AE3Du) ^ (uint(z) * 0x27D4EB2Fu);
	h ^= h >> 15u; h *= 0x2C1B3C6Du; h ^= h >> 12u; h *= 0x297A2D39u; h ^= h >> 15u;
	return h;
}
float cb_grad(uint h, float x, float y, float z) {
	switch (int(h & 15u)) {
		case 0: return x + y; case 1: return -x + y; case 2: return x - y; case 3: return -x - y;
		case 4: return x + z; case 5: return -x + z; case 6: return x - z; case 7: return -x - z;
		case 8: return y + z; case 9: return -y + z; case 10: return y - z; case 11: return -y - z;
		case 12: return x + y; case 13: return -y + z; case 14: return -x + y;
	}
	return -y - z;
}
float cb_fade(float t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }
float cb_perlin(vec3 p, uint seed) {
	vec3 f = floor(p);
	int ix = int(f.x), iy = int(f.y), iz = int(f.z);
	vec3 q = p - f;
	float u = cb_fade(q.x), v = cb_fade(q.y), w = cb_fade(q.z);
	float g000 = cb_grad(cb_hash3(ix, iy, iz, seed), q.x, q.y, q.z);
	float g100 = cb_grad(cb_hash3(ix + 1, iy, iz, seed), q.x - 1.0, q.y, q.z);
	float g010 = cb_grad(cb_hash3(ix, iy + 1, iz, seed), q.x, q.y - 1.0, q.z);
	float g110 = cb_grad(cb_hash3(ix + 1, iy + 1, iz, seed), q.x - 1.0, q.y - 1.0, q.z);
	float g001 = cb_grad(cb_hash3(ix, iy, iz + 1, seed), q.x, q.y, q.z - 1.0);
	float g101 = cb_grad(cb_hash3(ix + 1, iy, iz + 1, seed), q.x - 1.0, q.y, q.z - 1.0);
	float g011 = cb_grad(cb_hash3(ix, iy + 1, iz + 1, seed), q.x, q.y - 1.0, q.z - 1.0);
	float g111 = cb_grad(cb_hash3(ix + 1, iy + 1, iz + 1, seed), q.x - 1.0, q.y - 1.0, q.z - 1.0);
	float x00 = g000 + u * (g100 - g000), x10 = g010 + u * (g110 - g010);
	float x01 = g001 + u * (g101 - g001), x11 = g011 + u * (g111 - g011);
	float y0 = x00 + v * (x10 - x00), y1 = x01 + v * (x11 - x01);
	return y0 + w * (y1 - y0);
}
float cb_fbm(vec3 p, int oct, uint seed, float gain) {
	float s = 0.0, a = 1.0, norm = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * cb_perlin(p, seed + uint(i) * 101u);
		norm += a;
		a *= gain;
		p *= 2.03;
	}
	return 0.5 + 0.5 * s / norm * 1.6;
}
float cb_sstep(float a, float b, float x) {
	float t = clamp((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
// Chickbry computes in display colour; Godot shades in linear light.
vec3 cb_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

uniform uint seed = 0u;
uniform float y_offset = 0.0;      // the renderer's seed * 0.001, kept small for float precision
uniform float cloud_cover = 0.2;   // 0..1
uniform float cloud_freq = 1.0;
uniform float cloud_amp = 1.0;
uniform bool cumulus_on = false;
uniform vec3 cloud_lit = vec3(1.0);  // cloud colour under the sun and ambient
// The layer drifts and changes once the game runs (Chickbry shows TIME = 0); 0 stops it.
uniform float flow_speed = 1.0;
varying vec3 wp;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wp = vec3(w.x, w.y, -w.z);
}

void fragment() {
	float sc = 1.0 / 140.0 * cloud_freq;
	float tt = TIME * flow_speed;   // render.cpp cloud_alpha with an animated material
	float x = wp.x + tt * 12.0, z = wp.z + tt * 5.0;
	float n = cb_fbm(vec3(x * sc, y_offset + tt * 0.05, z * sc), 6, seed, 0.5);
	if (cumulus_on) n = 0.75 * n + 0.25 * cb_fbm(vec3(x * sc * 0.5 + 9.0, 3.3, z * sc * 0.5), 3, seed + 5u, 0.5);
	float th = 0.5 + (0.5 - cloud_cover) * 0.45;
	float soft = 0.12 / cloud_amp;
	ALBEDO = cb_linear(cloud_lit);
	ALPHA = cb_sstep(th - soft * 0.2, th + soft, n);
}
