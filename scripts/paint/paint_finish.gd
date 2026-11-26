class_name PaintFinish
extends RefCounted
## The material finishes a painted part can wear (matte, gloss, chrome, glow, ...).
##
## A finish only sets how the surface takes light: roughness, metal, clear coat and glow. The
## painted colours stay as they are. [constant ORIGINAL] keeps the look the part was made
## with. [method apply] sets a finish on a paint material and remembers it in the material's
## metadata ([method of]), so a later paint layer on the same surface carries it on.

const ORIGINAL := &"original"
const MATTE := &"matte"
const SATIN := &"satin"
const GLOSS := &"gloss"
const METAL := &"metal"
const CHROME := &"chrome"
const GLOW := &"glow"
## Every finish in the order the paint screen offers them.
const ORDER: Array[StringName] = [ORIGINAL, MATTE, SATIN, GLOSS, METAL, CHROME, GLOW]
const NAMES: Dictionary[StringName, String] = {
	ORIGINAL: "Original",
	MATTE: "Matte",
	SATIN: "Satin",
	GLOSS: "Gloss",
	METAL: "Metal",
	CHROME: "Chrome",
	GLOW: "Glow",
}
## roughness, metallic, specular, clear coat (0 = off), glow energy (0 = off), rim light
## (0 = off).
## [br]Metal and Chrome stay below full metal and catch a rim of light: a fully metal surface
## shows only what it reflects, and the levels have no sky to reflect, so paint on it would
## turn black. Glow is gentle and dims the lit colour ([constant GLOW_ALBEDO]) so the glowing
## paint keeps its colour and the part keeps its shading.
const VALUES: Dictionary[StringName, Array] = {
	MATTE: [1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	SATIN: [0.45, 0.0, 0.5, 0.0, 0.0, 0.1],
	GLOSS: [0.12, 0.0, 0.8, 1.0, 0.0, 0.0],
	METAL: [0.3, 0.6, 0.7, 0.0, 0.0, 0.25],
	CHROME: [0.06, 0.75, 1.0, 1.0, 0.0, 0.6],
	GLOW: [0.6, 0.0, 0.4, 0.0, 0.55, 0.0],
}
## Lit colour of a glowing finish (the glow adds the rest).
const GLOW_ALBEDO := Color(0.6, 0.6, 0.6)
## How much a finish's rim light takes the surface's colour.
const RIM_TINT := 0.6
## Finish button swatches: clear border round the ball (room for Glow's halo) and the light
## direction they are shaded with.
const SWATCH_PAD := 3
const SWATCH_LIGHT := Vector3(-0.45, 0.6, 0.66)
## Metadata key on a paint material: its finish id.
const META_FINISH := &"paint_finish"


## True when [param finish] is a finish this game knows.
static func is_known(finish: StringName) -> bool:
	return NAMES.has(finish)


## The display name of [param finish].
static func display_name(finish: StringName) -> String:
	return NAMES.get(finish, String(finish))


## The finish [param material] wears ([constant ORIGINAL] when it was never given one).
static func of(material: Material) -> StringName:
	if material == null:
		return ORIGINAL
	return StringName(material.get_meta(META_FINISH, ORIGINAL))


## Gives [param material] the finish [param finish]. [param source] is the material the
## part was made with: [constant ORIGINAL] copies its light settings back.
static func apply(material: BaseMaterial3D, finish: StringName, source: Material) -> void:
	if not is_known(finish):
		finish = ORIGINAL
	material.set_meta(META_FINISH, finish)
	if finish == ORIGINAL:
		var original := source as BaseMaterial3D
		if original == null:
			original = StandardMaterial3D.new()
		material.roughness = original.roughness
		material.metallic = original.metallic
		material.metallic_specular = original.metallic_specular
		material.clearcoat_enabled = original.clearcoat_enabled
		material.clearcoat = original.clearcoat
		material.clearcoat_roughness = original.clearcoat_roughness
		material.emission_enabled = original.emission_enabled
		material.emission = original.emission
		material.emission_energy_multiplier = original.emission_energy_multiplier
		material.emission_texture = original.emission_texture
		material.emission_operator = original.emission_operator
		material.rim_enabled = original.rim_enabled
		material.rim = original.rim
		material.rim_tint = original.rim_tint
		material.albedo_color = Color.WHITE
		return
	var values: Array = VALUES[finish]
	material.roughness = values[0]
	material.metallic = values[1]
	material.metallic_specular = values[2]
	material.clearcoat_enabled = float(values[3]) > 0.0
	material.clearcoat = values[3]
	material.clearcoat_roughness = 0.1
	var glow := float(values[4])
	material.emission_enabled = glow > 0.0
	material.albedo_color = GLOW_ALBEDO if glow > 0.0 else Color.WHITE
	if glow > 0.0:
		material.emission = Color.WHITE
		material.emission_energy_multiplier = glow
		# Multiply: the glow is the painted colour (add would put white on top of it).
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_texture = material.albedo_texture
	else:
		material.emission_texture = null
	var rim := float(values[5])
	material.rim_enabled = rim > 0.0
	material.rim = rim
	material.rim_tint = RIM_TINT


## Keeps a glowing material's glow showing [param texture] (call when its albedo changes).
static func follow_texture(material: BaseMaterial3D, texture: Texture2D) -> void:
	if of(material) == GLOW:
		material.emission_texture = texture


## A small ball in [param color] wearing [param finish], [param diameter] pixels across with
## a clear border of [constant SWATCH_PAD] (for the finish buttons). Shaded by hand, so it
## needs no 3D view.
static func swatch(finish: StringName, color: Color, diameter: int) -> Image:
	var side := diameter + SWATCH_PAD * 2
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var radius := diameter * 0.5
	var centre := Vector2(side, side) * 0.5
	var halo := radius + SWATCH_PAD
	for y in range(side):
		for x in range(side):
			var offset := (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / radius
			var distance := offset.length()
			if distance >= 1.0:
				if finish == GLOW and distance * radius < halo:
					var fade := 1.0 - (distance * radius - radius) / SWATCH_PAD
					image.set_pixel(x, y, Color(color, 0.45 * fade * fade))
				continue
			var normal := Vector3(offset.x, -offset.y, sqrt(1.0 - distance * distance))
			var shaded := _swatch_shade(finish, color, normal)
			shaded.a = clampf((1.0 - distance) * radius + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, shaded)
	return image


## The colour of a point of the swatch ball with surface [param normal] (view along -z).
static func _swatch_shade(finish: StringName, color: Color, normal: Vector3) -> Color:
	var diffuse := maxf(normal.dot(SWATCH_LIGHT), 0.0)
	var half_way := (SWATCH_LIGHT + Vector3.BACK).normalized()
	var facing := maxf(normal.dot(half_way), 0.0)
	var lit := color * (0.3 + 0.7 * diffuse)
	match finish:
		SATIN:
			return _plus(lit, 0.3 * pow(facing, 10.0))
		GLOSS:
			return _plus(lit, pow(facing, 90.0) + 0.12 * pow(1.0 - normal.z, 3.0))
		METAL:
			var sheen := 0.35 + 0.65 * clampf(0.5 + normal.y * 0.6, 0.0, 1.0)
			return _plus(color * sheen * (0.5 + 0.5 * diffuse), 0.6 * pow(facing, 24.0))
		CHROME:
			# A sharp horizon: bright sky above, a dark band, then lighter ground.
			var sky := 0.95 if normal.y > 0.05 else (0.12 if normal.y > -0.35 else 0.45)
			var mirror := color.lerp(Color.WHITE, 0.25) * sky
			return _plus(mirror, pow(facing, 160.0))
		GLOW:
			return color.lerp(Color.WHITE, 0.25 * normal.z)
		MATTE:
			return color * (0.25 + 0.6 * diffuse)
	return _plus(lit, 0.12 * pow(facing, 16.0))


static func _plus(base: Color, light: float) -> Color:
	return Color(minf(base.r + light, 1.0), minf(base.g + light, 1.0), minf(base.b + light, 1.0))
