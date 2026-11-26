// Chickbry 3D sky dome: a port of render.cpp's Tracer::sky (soft gradient,
// sun glow and disc, Cumulus/Stratus layers, horizon haze). Values come from
// the Sky&Fog palette; see the ShaderMaterial in the exported scene.
shader_type sky;

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

// Sky&Fog values as set in Chickbry (colours 0..1 display, amounts as on the dials)
uniform int sky_mode = 3;
uniform vec3 sky_color = vec3(0.22, 0.3, 0.77);
uniform vec3 horizon_color = vec3(0.86, 0.9, 0.96);
uniform vec3 haze_color = vec3(1.0);
uniform vec3 sun_color = vec3(1.0, 0.98, 0.92);
uniform vec3 ambient_color = vec3(0.35, 0.37, 0.43);
uniform vec3 dome_color = vec3(0.0);
uniform vec3 cloud_color = vec3(0.8);
uniform float haze = 10.0;
uniform float cloud_cover = 20.0;
uniform float cloud_height = 20.0;
uniform bool cumulus_on = false;
uniform bool stratus_on = false;
uniform bool sun_visible = true;
uniform vec3 sun_dir = vec3(0.57, 0.57, -0.57);   // toward the sun, Chickbry coordinates
// derived by Chickbry's renderer (render.cpp Tracer::setup)
uniform vec3 zenith = vec3(0.1, 0.2, 0.7);
uniform vec3 peak = vec3(0.975, 0.995, 1.0);
uniform vec3 warm = vec3(0.95, 0.57, 0.26);
uniform vec3 night_col = vec3(0.13, 0.05, 0.22);
uniform float haze_w = 0.55;
uniform float haze_rs = 0.6;
uniform float hatm = 180.0;
uniform float d50 = 8040.0;        // distance of 50% haze; 0 = no haze
uniform float sunset_w = 0.0;
uniform float night_w = 0.0;
uniform float el_sun = 35.0;
uniform float cl_alt = 1000.0;
uniform float cl_size = 3500.0;
uniform float cov_raw = 0.5;
uniform float amp_raw = 1.0;
uniform uint cl_seed = 790741u;
uniform vec3 eye = vec3(-90.34, 29.47, -90.34);   // the exported camera, Chickbry coordinates
// The cloud layers drift with the wind once the game runs (Chickbry shows TIME = 0); 0 stops them.
uniform float flow_speed = 1.0;
uniform vec2 wind = vec2(36.0, 15.0);   // Chickbry units per second at flow_speed 1

vec3 sky_base(vec3 d, float e) {
	if (sky_mode == 0 || sky_mode == 9) return sky_color;
	vec3 sc = vec3(1.0, 1.7, 3.5) * haze_w;
	float ee = max(0.0, e);
	vec3 fch = 0.85 * exp(-ee / (1.5 * sc)) + 0.15 * exp(-ee / (6.0 * sc));
	vec3 c = mix(zenith, peak, fch);
	float g = pow(max(0.0, (1.0 + dot(d, sun_dir)) * 0.5), 5.0);
	c += sun_color * (0.55 * g);
	if (sunset_w > 0.0) c = mix(c, warm + sun_color * (0.35 * g), sunset_w);
	if (night_w > 0.0) c = mix(c, night_col, night_w);
	return c;
}

float haze_frac(float l) {
	if (d50 <= 0.0 || l <= 0.0) return 0.0;
	return 1.0 / (1.0 + pow(d50 / l, 1.5));
}

vec3 hazed(vec3 c, float l) {
	if (d50 <= 0.0 || l <= 0.0) return c;
	vec3 sc = vec3(haze_rs, 1.0, 1.15);
	vec3 o;
	for (int i = 0; i < 3; i++) {
		float f = haze_frac(l * sc[i]);
		float em = f > 0.0 ? pow(f, 1.2 * (1.0 - clamp(haze_color[i], 0.0, 1.0))) : 0.0;
		o[i] = c[i] * (1.0 - f) + haze_color[i] * em * f;
	}
	return o;
}

vec3 cloud_density(float x, float z) {
	float a = 0.0, sh = 0.0, shade = 0.0;
	if (cumulus_on) {
		float n = cb_fbm(vec3(x / cl_size, 0.37, z / cl_size), 6, cl_seed, 0.42);
		float d = cov_raw + 1.6 * amp_raw * (n - 0.5);
		a = 0.9 * cb_sstep(-0.3, 1.0, d);
		float fine = cb_fbm(vec3(x / (cl_size * 0.3), 2.7, z / (cl_size * 0.3)), 4, cl_seed + 31u, 0.5);
		shade = clamp(0.5 * clamp(d - 0.6, 0.0, 1.0) + 1.1 * (fine - 0.5) * min(1.5, 0.5 + abs(amp_raw)) + 0.3, 0.0, 1.0);
	}
	if (stratus_on) {
		float n = cb_fbm(vec3(x / (cl_size * 2.6), 1.9, z / (cl_size * 0.45)), 6, cl_seed + 77u, 0.6);
		float d = cov_raw + 1.6 * amp_raw * (n - 0.5);
		float b = (cumulus_on ? 0.55 : 0.7) * cb_sstep(-0.2, 1.0, d);
		sh = b / max(1e-6, a + b);
		a = a + b * (1.0 - a);
	}
	return vec3(a, sh, shade);
}

void sky() {
	vec3 d = vec3(EYEDIR.x, EYEDIR.y, -EYEDIR.z);
	float e = degrees(asin(clamp(d.y, -1.0, 1.0)));
	vec3 c;
	if (e >= 0.0) {
		c = sky_base(d, e);
		float sine = max(d.y, 1e-6);
		if ((cumulus_on || stratus_on) && d.y > 1e-4) {
			float t = cl_alt / sine;
			vec2 drift = wind * (TIME * flow_speed);
			vec3 den = cloud_density(eye.x + d.x * t + drift.x, eye.z + d.z * t + drift.y);
			float a = den.x * cb_sstep(0.0, 4.0, e);
			if (a > 0.0) {
				float dl = el_sun >= 0.0 ? 0.3 + 0.7 * sin(radians(min(90.0, el_sun + 10.0))) : 0.45;
				vec3 L = sun_color * dl + ambient_color * 0.3 + dome_color * 0.15;
				vec3 cuc = (cloud_color * 0.75 + vec3(0.25)) * L * (1.2 - 0.6 * den.z);
				vec3 stc = (sun_color * (0.8 * dl) + dome_color * 0.4 + cloud_color * 0.1) * (1.0 - 0.6 * night_w);
				stc = mix(stc, horizon_color, 0.85 * exp(-e / 8.0));
				c = mix(c, mix(cuc, stc, den.y), a);
			}
		}
		c = hazed(c, hatm / sine);
	} else {
		c = mix(haze_color, ambient_color * 0.35, cb_sstep(0.0, -25.0, e));
	}
	if (sun_visible && sky_mode != 0) {
		float ang = degrees(acos(clamp(dot(d, sun_dir), -1.0, 1.0)));
		if (ang < 0.9) c += sun_color * (2.0 * cb_sstep(0.9, 0.7, ang));
		c += sun_color * (0.5 * exp(-ang / 1.8));
	}
	COLOR = cb_linear(c);
}
