extends Node
## Dev tool: turns the third-party skater models into native Godot resources.
##
## Run it with the harness:
## [code]./shoot.sh res://scenes/dev/skater_model_baker.tscn <dir> 2[/code].
## It reads the source GLBs at runtime with [GLTFDocument] (so no editor import is needed),
## then:
## [br]- splits the Quaternius mannequin into paintable parts by dominant bone (Head, Torso,
##   ArmL, ArmR, LegL, LegR), keeping the skin weights;
## [br]- splits the Kenney skateboard into Deck, TruckFront/Back and four wheels;
## [br]- gives every part a fresh non-overlapping UV0 (xatlas, via
##   [method ArrayMesh.lightmap_unwrap]): the source UVs point at palette swatches, which
##   can't be painted on;
## [br]- saves the skeleton as a scene, the skin, every part mesh and the chosen animation
##   clips into [constant OUT_DIR].
## The game only loads the baked files.

const UAL_SOURCE := "res://third_party/models/quaternius_ual/source/UAL1_Standard.glb"
const BOARD_SOURCE := "res://third_party/models/kenney_mini_skate/source/skateboard.glb"
const OUT_DIR := "res://third_party/models/baked/"
## Unwrap resolution: world units per lightmap texel.
const TEXEL_SIZE := 0.004
## Animation clips kept from the library.
const CLIPS: Array[String] = ["Idle_Loop", "Jump_Loop", "Hit_Chest"]
## Body part per bone name; any bone not listed belongs to the Torso.
const HEAD_BONES: Array[String] = ["neck_01", "Head"]
const LEG_BONES: Array[String] = ["thigh", "calf", "foot", "ball"]
const ARM_BONES: Array[String] = [
	"upperarm", "lowerarm", "hand", "index", "middle", "pinky", "ring", "thumb",
]
## Positions closer than this are one vertex when finding the board's pieces.
const WELD := 0.0001


## Vertices and triangles collected for one part.
class PartData:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	## Source vertex index -> index in this part, for the surface being read.
	var map := {}
	var bones_per_vertex := 4
	var surface := -1

	## Adds source vertex [param src] once; returns true when it was new.
	func add_vertex(src: int, pos: Vector3, normal: Vector3) -> bool:
		var fresh := not map.has(src)
		if fresh:
			map[src] = verts.size()
			verts.append(pos)
			normals.append(normal)
		indices.append(int(map[src]))
		return fresh


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_bake_mannequin()
	_bake_board()
	print("BAKE DONE")
	get_tree().quit()


func _bake_mannequin() -> void:
	var scene := _load_gltf(UAL_SOURCE)
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skin := source.skin
	var bind_part: PackedStringArray = []
	for bind in skin.get_bind_count():
		var bone_name := skin.get_bind_name(bind)
		if bone_name.is_empty():
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
		bind_part.append(_part_for_bone(bone_name))
	var parts := {}
	for surface in source.mesh.get_surface_count():
		_split_skinned(source.mesh.surface_get_arrays(surface), surface, bind_part, parts)
	for part: String in parts:
		var mesh := _unwrapped(parts[part] as PartData, true)
		_save(mesh, "mannequin_%s.res" % part.to_snake_case())
	_save(skin, "mannequin_skin.res")
	_save_skeleton(skeleton)
	_save_clips(scene)
	scene.free()


func _bake_board() -> void:
	var scene := _load_gltf(BOARD_SOURCE)
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays := source.mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var groups := _components(verts, indices)
	for root: int in groups:
		var tris := PackedInt32Array(groups[root] as Array)
		var bounds := AABB(verts[indices[tris[0]]], Vector3.ZERO)
		for t in tris:
			for k in 3:
				bounds = bounds.expand(verts[indices[t + k]])
		var part := _board_part(bounds)
		var data := PartData.new()
		for t in tris:
			for k in 3:
				var src := indices[t + k]
				data.add_vertex(src, verts[src], normals[src])
		var mesh := _unwrapped(data, false)
		_save(mesh, "board_%s.res" % part.to_snake_case())
	scene.free()


func _load_gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "could not read %s" % path)
	return doc.generate_scene(state)


static func _part_for_bone(bone_name: String) -> String:
	if bone_name in HEAD_BONES:
		return "Head"
	var side := "L" if bone_name.ends_with("_l") else "R"
	var stem := bone_name.get_slice("_", 0)
	if stem in LEG_BONES:
		return "Leg" + side
	if stem in ARM_BONES:
		return "Arm" + side
	return "Torso"


## Sorts every triangle of one surface into its part by the dominant bone of its vertices.
func _split_skinned(arrays: Array, surface: int, bind_part: PackedStringArray,
		parts: Dictionary) -> void:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var per := bones.size() / verts.size()
	var vertex_part: PackedStringArray = []
	for v in verts.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		vertex_part.append(bind_part[bones[v * per + best]])
	for t in range(0, indices.size(), 3):
		var a := vertex_part[indices[t]]
		var b := vertex_part[indices[t + 1]]
		var c := vertex_part[indices[t + 2]]
		var part := b if b == c else a
		if not parts.has(part):
			parts[part] = PartData.new()
		var data := parts[part] as PartData
		data.bones_per_vertex = per
		if data.surface != surface:
			data.map = {}
			data.surface = surface
		for k in 3:
			var src := indices[t + k]
			if data.add_vertex(src, verts[src], normals[src]):
				data.bones.append_array(bones.slice(src * per, src * per + per))
				data.weights.append_array(weights.slice(src * per, src * per + per))



## A one-surface mesh of [param data] whose UV0 is a fresh xatlas unwrap.
func _unwrapped(data: PartData, skinned: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.verts
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var flags := 0
	if skinned:
		arrays[Mesh.ARRAY_BONES] = data.bones
		arrays[Mesh.ARRAY_WEIGHTS] = data.weights
		if data.bones_per_vertex == 8:
			flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var err := mesh.lightmap_unwrap(Transform3D.IDENTITY, TEXEL_SIZE)
	assert(err == OK, "unwrap failed")
	var out := mesh.surface_get_arrays(0)
	out[Mesh.ARRAY_TEX_UV] = out[Mesh.ARRAY_TEX_UV2]
	if skinned and out[Mesh.ARRAY_BONES] == null:
		push_error("unwrap dropped the skin weights")
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 0.85
	baked.surface_set_material(0, material)
	return baked


## Triangles grouped by connected piece (welded by position): root -> Array of triangle starts.
static func _components(verts: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var key_of := {}
	var parent: PackedInt32Array = []
	var id_of: PackedInt32Array = []
	for v in verts.size():
		var key := Vector3i((verts[v] / WELD).round())
		if not key_of.has(key):
			key_of[key] = parent.size()
			parent.append(parent.size())
		id_of.append(int(key_of[key]))
	for t in range(0, indices.size(), 3):
		var a := _find(parent, id_of[indices[t]])
		for k in [1, 2]:
			var b := _find(parent, id_of[indices[t + k]])
			parent[b] = a
	var groups := {}
	for t in range(0, indices.size(), 3):
		var root := _find(parent, id_of[indices[t]])
		if not groups.has(root):
			groups[root] = []
		(groups[root] as Array).append(t)
	return groups


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		x = parent[x]
	return x


## Names a board piece by where it sits: the top slab is the deck, the narrow pieces
## between the wheels are trucks. Front is -Z (the board's nose in the rig).
static func _board_part(bounds: AABB) -> String:
	var center := bounds.get_center()
	var front := center.z < 0.0
	if bounds.size.z > 0.4:
		return "Deck"
	if absf(center.x) < 0.05:
		return "TruckFront" if front else "TruckBack"
	return "Wheel%s%s" % ["F" if front else "B", "L" if center.x < 0.0 else "R"]


func _save_skeleton(source: Skeleton3D) -> void:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for bone in source.get_bone_count():
		skeleton.add_bone(source.get_bone_name(bone))
	for bone in source.get_bone_count():
		skeleton.set_bone_parent(bone, source.get_bone_parent(bone))
		skeleton.set_bone_rest(bone, source.get_bone_rest(bone))
		skeleton.reset_bone_pose(bone)
	var packed := PackedScene.new()
	packed.pack(skeleton)
	_save(packed, "mannequin_skeleton.scn")
	skeleton.free()


## Keeps [constant CLIPS], re-rooted so tracks read [code]Skeleton3D:<bone>[/code].
func _save_clips(scene: Node) -> void:
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var library := AnimationLibrary.new()
	for clip in CLIPS:
		if not player.has_animation(clip):
			push_error("missing clip %s" % clip)
			continue
		var anim := player.get_animation(clip).duplicate(true) as Animation
		for track in anim.get_track_count():
			var path := String(anim.track_get_path(track))
			anim.track_set_path(track, NodePath("Skeleton3D:" + path.get_slice(":", 1)))
		anim.loop_mode = Animation.LOOP_LINEAR if clip.ends_with("_Loop") \
				else Animation.LOOP_NONE
		library.add_animation(StringName(clip), anim)
	_save(library, "mannequin_clips.res")


func _save(resource: Resource, file: String) -> void:
	var err := ResourceSaver.save(resource, OUT_DIR + file, ResourceSaver.FLAG_COMPRESS)
	print("saved ", file, " err ", err)
