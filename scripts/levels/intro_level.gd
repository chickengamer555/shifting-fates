class_name IntroLevel
extends LevelController
## The intro: the player arrives in the intro level art (the upper echelon) with no body yet.
##
## The level art is whatever scene the intro instances as [code]Art[/code]; this script only
## needs a [code]SpawnPoint[/code], a [code]Portal[/code], a [code]TitleCross[/code] and the
## [code]UI/DialogueBox[/code]. The skater starts invisible and the [code]intro[/code]
## dialogue plays as a cutscene (skater frozen, HUD hidden). A line's event fires once the
## player has read the line and pressed on (it moves to an empty cue line after it), so God's
## words are always seen before what they set off. The [code]open_player_paint[/code]
## and [code]open_board_paint[/code] events open the [PaintCreator] in place: it paints the
## real skater where it stands, starting from the white mannequin, while its camera glides
## from the skater's view into an orbit around the rig. The dialogue box hides until the
## creator's [signal PaintCreator.finished], then the skater's camera takes the view back.
## The creator frees the mouse while open; the skater takes it back once it may skate.
## Without a paint creator the dialogue simply carries on. The flying cross is
## [code]TitleCross/Cross[/code]: the art's own cross when the art has one (see
## [method find_art_cross]), taken out of the art exactly as the user posed and placed it,
## otherwise the game's own cross, laid flat high ahead of the player with its head towards
## them. Either way it stays hidden until the dialogue ends; then it flies dead level in a
## straight line the way its head points (the user's note on it: "Fly straight ahead over
## above"), held in its pose, over the player and on past them. A rope
## ([code]TitleCross/Tow/Rope[/code]) hangs from the cross's foot with the "Shifting fates"
## billboard ([code]TitleCross/Tow/Banner[/code]) hanging from it, fixed in the world and
## facing the way the cross flies; the tow trails back in the wind and sways a little. A
## glow trails behind ([code]TitleCross/Trail[/code]). It is hidden again once it has flown.
## The player then skates freely (HUD shown) and, when
## [member follow_up_dialogue_id] is set, that dialogue starts once the cross has flown.
## Once the dialogue ends the portal to level 1 opens, as the cross starts to fly: the intro
## needs no score. Coming
## back into the intro from level 1 skips the dialogue, painting and cross: the player is
## simply there, the portal open.

## Where the intro begins. [constant PAINT] (dev hub, previews) skips the lines before the
## player paint.
enum StartStep { INTRO, PAINT }

const EVENT_PLAYER_PAINT := &"open_player_paint"
const EVENT_BOARD_PAINT := &"open_board_paint"
const PAINT_CREATOR_SCENE := preload("res://scenes/paint/paint_creator.tscn")
const PAINT_NODE_NAME := &"PaintCreator"
const CLOSED_PAINT_NODE_NAME := &"PaintCreatorClosing"
## Name of the flying cross under [code]TitleCross[/code] (the game's own or the art's).
const CROSS_NAME := &"Cross"
## A node of the art is a cross when its name holds one of these (any case; the user names
## art objects with their animation notes, e.g. "Fly straight agheat over above") ...
const ART_CROSS_WORDS: Array[String] = ["cross", "fly straight"]
const ART_CROSS_WORD := "cross"
## ... or the art exporter tagged it as [constant ART_CROSS_WORD] in this metadata.
const ART_KIND_META := &"chickbry_kind"
const ART_NODE_NAME := &"Art"

## The body/board painter. Set it to null to skip painting.
@export var paint_creator_scene: PackedScene = PAINT_CREATOR_SCENE
## Where the intro begins (see [enum StartStep]).
@export var start_step: StartStep = StartStep.INTRO
## Dialogue played while skating once the title cross has flown. Empty: none.
@export var follow_up_dialogue_id: StringName = &""
## How far (m) above where it was placed the cross flies (the user: "Make cross higher up").
@export var cross_lift: float = 30.0
## Seconds the title cross takes to fly over.
@export var cross_seconds: float = 12.0
## How far (m) past the player the cross flies before it is gone.
@export var cross_overshoot: float = 250.0
## Length (m) of the rope from the cross's foot to the billboard.
@export var rope_length: float = 10.0
## How far (degrees) the rope and billboard trail back in the wind...
@export var tow_trail_degrees: float = 16.0
## ...and how far (degrees) they swing about that, every [member tow_sway_seconds].
@export var tow_sway_degrees: float = 4.0
@export var tow_sway_seconds: float = 2.6
## Fallback cross only (the art has none): how far ahead of and above the player it starts.
@export var own_cross_ahead: float = 350.0
@export var own_cross_height: float = 45.0

## True while the paint creator is open.
var painting: bool:
	get:
		return _paint != null

var _appearance: Appearance = null
var _paint: PaintCreator = null
var _intro_over: bool = false

@onready var _title_cross: Node3D = $TitleCross
@onready var _own_cross: Node3D = $TitleCross/Cross
@onready var _cross_trail: CPUParticles3D = $TitleCross/Trail
@onready var _tow: Node3D = $TitleCross/Tow
@onready var _rope: MeshInstance3D = $TitleCross/Tow/Rope
@onready var _banner: Node3D = $TitleCross/Tow/Banner

## Flight: start and end of the TitleCross origin (global) and the travel direction.
var _cross_from: Vector3 = Vector3.ZERO
var _cross_to: Vector3 = Vector3.ZERO
var _cross_travel: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_title_cross.visible = false
	_adopt_art_cross()
	super._ready()
	_plan_cross_flight()
	# The dialogue may already have opened the painter (and shown the mannequin) on ready.
	if not painting and not _intro_over:
		skater.visible = false


func _begin_dialogue() -> void:
	skater.visible = false
	var sequence := find_dialogue(dialogue_id)
	if sequence != null:
		sequence = _events_after_lines(sequence)
		if start_step == StartStep.PAINT:
			sequence = _from_event(sequence, EVENT_PLAYER_PAINT)
	play_dialogue(sequence, true)


func _handle_dialogue_event(event: StringName) -> void:
	var opened := false
	match event:
		EVENT_PLAYER_PAINT:
			skater.visible = true
			opened = _open_paint(PaintCreator.Mode.PLAYER)
		EVENT_BOARD_PAINT:
			opened = _open_paint(PaintCreator.Mode.BOARD)
	if not opened:
		# Nothing to wait for: move past the empty cue line once it is done.
		dialogue_box.advance.call_deferred()


func _handle_dialogue_finished() -> void:
	if _intro_over:
		return
	_intro_over = true
	skater.visible = true
	# No score needed in the intro: the way to level 1 opens as the cross starts to fly.
	open_portal()
	_fly_title_cross()


## No Repaint while the intro's own paint screen is open.
func can_repaint() -> bool:
	return not painting and super.can_repaint()


## Opens the paint creator on the skater in [param mode]. Returns false when none is available.
func _open_paint(mode: PaintCreator.Mode) -> bool:
	if paint_creator_scene == null:
		return false
	_paint = paint_creator_scene.instantiate() as PaintCreator
	if _paint == null:
		push_warning("IntroLevel: paint creator scene is not a PaintCreator")
		return false
	_paint.name = PAINT_NODE_NAME
	_paint.mode = mode
	_paint.save_path = game_state.appearance_path
	_paint.target_rig = skater.rig
	_paint.glide_from = skater.camera
	if _appearance != null:
		_paint.appearance = _appearance
	_paint.finished.connect(_on_paint_creator_finished)
	add_child(_paint)
	dialogue_box.visible = false
	if hud != null:
		hud.visible = false
	return true


func _close_paint() -> void:
	# Free the name now so the next pass can take it in the same frame.
	_paint.name = CLOSED_PAINT_NODE_NAME
	_paint.visible = false
	_paint.queue_free()
	_paint = null
	skater.camera.make_current()
	skater.refresh_mouse()
	dialogue_box.visible = true
	# The cue line that opened the painter is still on; the next line follows.
	dialogue_box.advance()


## The level art's cross: the first node under [code]Art[/code] whose name holds "cross" or
## "fly straight" (any case) or that the art exporter tagged as a cross. Null when the art has none.
func find_art_cross() -> Node3D:
	var art := get_node_or_null(NodePath(ART_NODE_NAME))
	if art == null:
		return null
	for node: Node in art.find_children("*", "Node3D", true, false):
		if _is_cross(node):
			return node as Node3D
	return null


static func _is_cross(node: Node) -> bool:
	var lower_name := String(node.name).to_lower()
	for word: String in ART_CROSS_WORDS:
		if lower_name.contains(word):
			return true
	return String(node.get_meta(ART_KIND_META, "")).to_lower() == ART_CROSS_WORD


## Moves the art's cross into [code]TitleCross[/code] in place of the game's own cross, keeping
## exactly the pose and place the user gave it (no collision), so it only shows while it
## flies. Keeps the game's own cross when the art has none; an art cross with no mesh to show
## is only taken out of the art.
func _adopt_art_cross() -> void:
	var art_cross := find_art_cross()
	if art_cross == null:
		return
	var posed := art_cross.global_transform
	art_cross.get_parent().remove_child(art_cross)
	if _mesh_bounds(art_cross).size.y <= 0.0:
		art_cross.queue_free()
		return
	for body: Node in [art_cross] + art_cross.find_children("*", "CollisionObject3D", true, false):
		var solid := body as CollisionObject3D
		if solid != null:
			solid.collision_layer = 0
			solid.collision_mask = 0
	_title_cross.remove_child(_own_cross)
	_own_cross.queue_free()
	art_cross.name = CROSS_NAME
	_title_cross.add_child(art_cross)
	_title_cross.global_transform = Transform3D(Basis.IDENTITY, posed.origin)
	art_cross.global_transform = posed
	_own_cross = art_cross
	_own_cross.set_meta(&"from_art", true)


## Works out the flight: straight and level along the cross's head (its local up, flattened),
## from where it was placed to [member cross_overshoot] m past the player. Hangs the tow
## from the cross's foot.
func _plan_cross_flight() -> void:
	var spawn := skater.global_position if skater != null else global_position
	if not _own_cross.has_meta(&"from_art"):
		var ahead := -skater.heading if skater != null else Vector3.BACK
		ahead.y = 0.0
		ahead = ahead.normalized() if not ahead.is_zero_approx() else Vector3.BACK
		# Laid flat, head towards the player: local up along ahead, face to the sky.
		var flat := Basis(ahead.cross(Vector3.UP).normalized(), ahead, Vector3.UP)
		flat = Basis(flat.x, flat.y, flat.x.cross(flat.y))
		_title_cross.global_transform = Transform3D(Basis.IDENTITY,
			spawn - ahead * own_cross_ahead + Vector3.UP * own_cross_height)
		_own_cross.global_basis = flat.scaled_local(_own_cross.transform.basis.get_scale())
		_own_cross.position = Vector3.ZERO
	var head := _own_cross.global_basis.y
	head.y = 0.0
	_cross_travel = head.normalized() if not head.is_zero_approx() else Vector3.BACK
	_title_cross.global_position += Vector3.UP * cross_lift
	_cross_from = _title_cross.global_position
	var box := _mesh_bounds(_own_cross)
	var middle := _own_cross.global_transform * box.get_center()
	var to_player := maxf((spawn - middle).dot(_cross_travel), 0.0)
	_cross_to = _cross_from + _cross_travel * (to_player + cross_overshoot)
	# The tow hangs from the cross's foot, the billboard facing the way it flies.
	var foot_local := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_tow.position = _own_cross.transform * foot_local
	_tow.basis = Basis.looking_at(-_cross_travel, Vector3.UP)
	var rope_mesh := (_rope.mesh as CylinderMesh).duplicate() as CylinderMesh
	rope_mesh.height = rope_length
	_rope.mesh = rope_mesh
	_rope.position = Vector3.DOWN * rope_length * 0.5
	_banner.position = Vector3.DOWN * rope_length
	_place_title_cross(0.0)


## The bounds of every mesh under [param root], in [param root]'s own space.
static func _mesh_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	# Not only owned nodes: a node taken out of its scene has lost its owner.
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box := _relative_transform(mesh_node, root) * mesh_node.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## The transform of [param node] relative to its ancestor [param root].
static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform


func _fly_title_cross() -> void:
	_place_title_cross(0.0)
	_title_cross.visible = true
	_cross_trail.emitting = true
	var tween := create_tween()
	tween.tween_method(_place_title_cross, 0.0, 1.0, maxf(cross_seconds, 0.01))
	tween.tween_callback(_land_title_cross)
	tween.finished.connect(_on_title_cross_flown)


## Puts the title cross [param progress] (0..1) of the way along its straight, level flight,
## at a steady speed, the tow trailing and swaying.
func _place_title_cross(progress: float) -> void:
	_title_cross.global_position = _cross_from.lerp(_cross_to, progress)
	var seconds := progress * cross_seconds
	var sway := sin(seconds * TAU / maxf(tow_sway_seconds, 0.01))
	var trail := deg_to_rad(tow_trail_degrees + tow_sway_degrees * 0.5 * sway)
	var side := deg_to_rad(tow_sway_degrees) * sin(seconds * TAU / maxf(tow_sway_seconds * 1.7, 0.01))
	var hang := Basis.looking_at(-_cross_travel, Vector3.UP)
	_tow.basis = hang * Basis(Vector3.RIGHT, trail) * Basis(Vector3.FORWARD, side)


func _land_title_cross() -> void:
	_cross_trail.emitting = false
	_title_cross.visible = false


## A copy of [param sequence] where every line with an event is followed by an empty cue line
## carrying that event instead, so it fires only once the line has been read.
static func _events_after_lines(sequence: DialogueSequence) -> DialogueSequence:
	var spaced := DialogueSequence.new()
	spaced.id = sequence.id
	var lines: Array[DialogueLine] = []
	for line: DialogueLine in sequence.lines:
		if line.event == &"" or line.text.is_empty():
			lines.append(line)
			continue
		var read := line.duplicate() as DialogueLine
		read.event = &""
		lines.append(read)
		var cue := DialogueLine.new()
		cue.event = line.event
		lines.append(cue)
	spaced.lines = lines
	return spaced


## A copy of [param sequence] that starts at the first line carrying [param event].
static func _from_event(sequence: DialogueSequence, event: StringName) -> DialogueSequence:
	var trimmed := DialogueSequence.new()
	trimmed.id = sequence.id
	trimmed.lines = sequence.lines
	for index: int in sequence.lines.size():
		if sequence.lines[index].event == event:
			trimmed.lines = sequence.lines.slice(index)
			break
	return trimmed


func _on_paint_creator_finished(appearance: Appearance) -> void:
	_appearance = appearance
	skater.visible = true
	_close_paint()


func _handle_returned() -> void:
	_intro_over = true
	skater.visible = true
	open_portal(true)


func _on_title_cross_flown() -> void:
	if follow_up_dialogue_id != &"":
		play_dialogue(find_dialogue(follow_up_dialogue_id), false)
