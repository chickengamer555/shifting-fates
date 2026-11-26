// Chickbry 3D's look for this level, written by Export to Godot: every exported surface
// includes it and shades itself with Chickbry's own light, haze, fog and sky, so the
// level keeps its look whatever sky, ambient light, fog or light colours Godot is
// given. Re-export from Chickbry to change it.

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

// Sky&Fog, as Chickbry's renderer derives it
const int sky_mode = 3;
const vec3 sky_color = vec3(0.407843137, 0.419607843, 1.0);
const vec3 horizon_color = vec3(0.71372549, 0.909803922, 1.0);
const vec3 haze_color = vec3(1.0, 1.0, 1.0);
const vec3 sun_color = vec3(0.97254902, 1.0, 0.992156863);
const vec3 ambient_color = vec3(1.0, 0.992156863, 0.976470588);
const vec3 dome_color = vec3(1.0, 1.0, 1.0);
const vec3 cloud_color = vec3(1.0, 1.0, 1.0);
const bool cumulus_on = true;
const bool stratus_on = false;
const bool sun_visible = true;
const vec3 sun_dir = vec3(0.579227965, 0.573576436, -0.579227965);
const vec3 zenith = vec3(0.208575779, 0.217998616, 0.92);
const vec3 peak = vec3(0.975, 0.995, 1.0);
const vec3 warm = vec3(0.923921569, 0.58, 0.277803922);
const vec3 night_col = vec3(0.13, 0.05, 0.22);
const float haze_w = 0.55;
const float haze_rs = 0.6;
const float hatm = 500.0;
const float d50 = 8800.0;
const float sunset_w = 0.0;
const float night_w = 0.0;
const float el_sun = 35.0;
const float cl_alt = 3000.0;
const float cl_size = 12150.0;
const float cov_raw = 1.3;
const float amp_raw = 0.0;
const uint cl_seed = 790741u;
// clouds, water and cloud planes flow once the game runs; 0 stops them
const float flow_speed = 1.0;
const vec2 wind = vec2(36.0, 15.0);

// the light on surfaces (render.cpp light_at): the sun or moon, ambient, shade
const bool CB_KEY_ON = true;
const vec3 CB_KEY_DIR = vec3(0.579227965, 0.573576436, -0.579227965);
const vec3 CB_KEY_COL = vec3(0.933444769, 0.959792, 0.95226422);
const vec3 CB_AMBIENT = vec3(2.78861545, 2.76674395, 2.72300097);
const float CB_SHADOW_K = 0.9;
const vec3 CB_SHADOW_COL = vec3(1.0, 1.0, 1.0);
// haze (above) and the fog layer
const vec3 CB_HAZE_K = vec3(9.2e-05, 0.000165, 0.00038);
const float CB_FOG_K = 0.0;
const float CB_FOG_HS = 0.5;
const float CB_FOG_BASE = 0.0;
const vec3 CB_FOG_COL = vec3(1.0, 1.0, 1.0);

// the ground plane, as reflections see it
const bool CB_GROUND = true;
const float CB_GROUND_Y = 0.0;
const vec3 CB_GROUND_BASE = vec3(0.807843137, 0.807843137, 0.807843137);
const float CB_GROUND_DIFFUSION = 1.0;
const float CB_GROUND_AMBIENCE = 0.196078435;
const float CB_GROUND_SPECULARITY = 0.0;
const vec3 CB_GROUND_SPEC = vec3(1.0, 1.0, 1.0);
const float CB_GROUND_REFLECTION = 0.0;
const float CB_GROUND_METAL = 0.0;
const bool CB_GROUND_MIRROR = false;
const uint CB_GROUND_LAYER_BIT = 524288u;

// the water plane, as reflections see it
const bool CB_WATER = false;
const float CB_WATER_Y = 0.0;
const vec3 CB_WATER_COLOR = vec3(0.06, 0.24, 0.27);
const float CB_WATER_REFLECT_MIN = 0.25;
const uint CB_WATER_LAYER_BIT = 262144u;

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

// the sky toward d (Chickbry coordinates) in display colour; clouds seen from `from`, `drift`
// Chickbry units moved by the wind
vec3 cb_sky(vec3 d, vec3 from, vec2 drift) {
	float e = degrees(asin(clamp(d.y, -1.0, 1.0)));
	vec3 c;
	if (e >= 0.0) {
		c = sky_base(d, e);
		float sine = max(d.y, 1e-6);
		if ((cumulus_on || stratus_on) && d.y > 1e-4) {
			float t = cl_alt / sine;
			vec3 den = cloud_density(from.x + d.x * t + drift.x, from.z + d.z * t + drift.y);
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
	return c;
}

// fragment() fills these; light() reads them
varying vec3 cb_lit;       // the finished colour, sunlit (linear)
varying vec3 cb_dark;      // the same in the sun's full shadow (linear)
varying vec3 cb_lamp;      // what a lamp placed in Godot lights (linear albedo)

vec3 cb_world(vec3 v) { return vec3(v.x, v.y, -v.z); }

// The sky Godot really draws (chickbry_sky_capture.gd renders it into six faces, in the game
// and the editor): what reflections see, so they show the user's own sky if they swap it.
// Until the first capture, Chickbry's sky.
uniform bool cb_sky_live = false;
uniform sampler2D cb_sky_f0 : filter_linear, repeat_disable;   // +X, -X, +Y, -Y, +Z, -Z (Godot axes)
uniform sampler2D cb_sky_f1 : filter_linear, repeat_disable;
uniform sampler2D cb_sky_f2 : filter_linear, repeat_disable;
uniform sampler2D cb_sky_f3 : filter_linear, repeat_disable;
uniform sampler2D cb_sky_f4 : filter_linear, repeat_disable;
uniform sampler2D cb_sky_f5 : filter_linear, repeat_disable;
vec3 cb_sky_seen(vec3 r, vec3 eye, vec2 drift) {   // r in Chickbry coordinates
	if (!cb_sky_live) return cb_sky(r, eye, drift);
	vec3 g = normalize(cb_world(r)), a = abs(g);
	int f = a.x >= a.y && a.x >= a.z ? (g.x > 0.0 ? 0 : 1) : a.y >= a.z ? (g.y > 0.0 ? 2 : 3) : (g.z > 0.0 ? 4 : 5);
	vec3 fwd = f == 0 ? vec3(1.0, 0.0, 0.0) : f == 1 ? vec3(-1.0, 0.0, 0.0) : f == 2 ? vec3(0.0, 1.0, 0.0)
			: f == 3 ? vec3(0.0, -1.0, 0.0) : f == 4 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 0.0, -1.0);
	vec3 up = f == 2 ? vec3(0.0, 0.0, -1.0) : f == 3 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 z = -fwd, x = normalize(cross(up, z)), y = cross(z, x);   // Basis.looking_at(fwd, up)
	float k = dot(g, fwd);
	vec2 uv = clamp(vec2(0.5 + 0.5 * dot(g, x) / k, 0.5 - 0.5 * dot(g, y) / k), vec2(0.0), vec2(1.0));
	if (f == 0) return texture(cb_sky_f0, uv).rgb;
	if (f == 1) return texture(cb_sky_f1, uv).rgb;
	if (f == 2) return texture(cb_sky_f2, uv).rgb;
	if (f == 3) return texture(cb_sky_f3, uv).rgb;
	if (f == 4) return texture(cb_sky_f4, uv).rgb;
	return texture(cb_sky_f5, uv).rgb;
}

// Chickbry's own light on a surface: the sun (or moon) and the ambient; in_shadow is the
// sun's full shadow (Sky&Fog's shadow amount, the ambient tinted by the shadow colour)
vec3 cb_light(vec3 base, vec3 n, vec3 d, float diffusion, float ambience, float specularity, vec3 spec_col, float shininess, bool in_shadow) {
	float ndl = dot(n, CB_KEY_DIR);
	vec3 diff = vec3(0.0), spec = vec3(0.0);
	float sh = 0.0;
	if (CB_KEY_ON && ndl > 0.0) {
		sh = in_shadow ? CB_SHADOW_K : 0.0;
		diff = CB_KEY_COL * (ndl * (1.0 - sh));
		vec3 h = normalize(CB_KEY_DIR - d);
		spec = CB_KEY_COL * (pow(max(0.0, dot(n, h)), shininess) * (1.0 - sh));
	} else if (ndl <= 0.0) {
		sh = CB_SHADOW_K * 0.5;
	}
	vec3 amb = CB_AMBIENT * mix(vec3(1.0), CB_SHADOW_COL, sh);
	return base * (diff * diffusion + amb * ambience) + spec_col * spec * specularity;
}

// haze and fog over the path from o along d (unit) for t
vec3 cb_atmosphere(vec3 c, vec3 o, vec3 d, float t) {
	if (sky_mode == 3 || sky_mode == 5) {
		vec3 f = vec3(1.0) - exp(-CB_HAZE_K * t);
		c = mix(c, mix(peak, night_col, night_w), f);
	}
	c = hazed(c, t);
	if (CB_FOG_K <= 0.0) return c;
	float dy = d.y, I = 0.0;
	if (CB_FOG_BASE != 0.0) {   // a layer from the base altitude up, clear below it
		float s0 = 0.0, s1 = t;
		if (abs(dy) < 1e-6) {
			if (o.y >= CB_FOG_BASE) I = exp(-(o.y - CB_FOG_BASE) / CB_FOG_HS) * min(t, 1e7);
		} else {
			float sb = (CB_FOG_BASE - o.y) / dy;
			if (dy > 0.0) s0 = max(0.0, sb);
			else s1 = o.y >= CB_FOG_BASE ? min(t, sb) : -1.0;
			if (s1 > s0) {
				float ya = o.y + dy * s0 - CB_FOG_BASE, yb = o.y + dy * s1 - CB_FOG_BASE;
				I = max(0.0, CB_FOG_HS / dy * (exp(-ya / CB_FOG_HS) - exp(-yb / CB_FOG_HS)));
			}
		}
	} else {
		float y0 = max(0.0, o.y);
		if (abs(dy) < 1e-6) I = exp(-y0 / CB_FOG_HS) * min(t, 1e7);
		else {
			float y1 = max(0.0, o.y + dy * t);
			I = CB_FOG_HS / dy * (exp(-y0 / CB_FOG_HS) - exp(-y1 / CB_FOG_HS));
			if (I < 0.0) I = exp(-y0 / CB_FOG_HS) * t;
		}
	}
	return mix(c, CB_FOG_COL, 1.0 - exp(-CB_FOG_K * I));
}

// what a mirror tints its reflection to (render.cpp trace()): a metal keeps its own hue
vec3 cb_mirror_tint(vec3 rc, vec3 base, float metal) {
	vec3 seen = rc * mix(vec3(1.0), base, 0.3 + 0.7 * metal);
	if (metal > 0.0) seen = mix(seen, base * (dot(rc, vec3(0.299, 0.587, 0.114)) * 1.2), 0.6 * metal);
	return seen;
}

// what a reflected ray from p along r sees: the ground (lit, reflecting the sky) or the sky
vec3 cb_seen(vec3 p, vec3 r, vec3 eye, vec2 drift) {
	// water above the ground is met first (render.cpp water(), its ripples left out)
	if (CB_WATER && r.y < -1e-4 && p.y > CB_WATER_Y && (!CB_GROUND || CB_WATER_Y >= CB_GROUND_Y)) {
		float t = (p.y - CB_WATER_Y) / -r.y;
		vec3 up = vec3(0.0, 1.0, 0.0);
		float F = max(0.12 + 0.88 * pow(1.0 + r.y, 5.0), CB_WATER_REFLECT_MIN);
		vec3 body = cb_light(CB_WATER_COLOR, up, r, 0.6, 0.35, 0.9, vec3(1.0), 200.0, false);
		return cb_atmosphere(mix(body, cb_sky_seen(reflect(r, up), eye, drift), F), p, r, t);
	}
	if (CB_GROUND && r.y < -1e-4 && p.y > CB_GROUND_Y) {
		float t = (p.y - CB_GROUND_Y) / -r.y;
		vec3 g = cb_light(CB_GROUND_BASE, vec3(0.0, 1.0, 0.0), r, CB_GROUND_DIFFUSION, CB_GROUND_AMBIENCE,
				CB_GROUND_SPECULARITY, CB_GROUND_SPEC, 40.0, false);
		if (CB_GROUND_REFLECTION > 0.0)
			g = mix(g, cb_mirror_tint(cb_sky_seen(reflect(r, vec3(0.0, 1.0, 0.0)), eye, drift), CB_GROUND_BASE, CB_GROUND_METAL), CB_GROUND_REFLECTION);
		return cb_atmosphere(g, p, r, t);
	}
	return cb_sky_seen(r, eye, drift);
}

// light(): Godot's directional light only casts the sun's shadow (Chickbry's own sun is in
// cb_lit); lamps placed in the game light the surface as Godot's Lambert would
vec3 cb_light_pass(bool directional, float att, vec3 light_col, float nl, vec3 lit, vec3 dark, vec3 lamp) {
	if (directional) return CB_SHADOW_K > 0.0 ? (dark - lit) * clamp((1.0 - att) / CB_SHADOW_K, 0.0, 1.0) : vec3(0.0);
	return lamp * light_col * (max(nl, 0.0) * att / PI);
}
