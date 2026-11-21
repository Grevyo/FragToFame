class_name CharacterRig
extends Node3D
## Builds one animated character from a [CharacterAppearance]: the base body's skeleton (and its
## own meshes), every worn item's skinned meshes bound to that skeleton, colours and skin, and
## the shared animation set.
##
## Animations come from one rig (the modular pack's 24 clips, `CharacterCatalog.animation_library`)
## and are copied onto whichever body is shown by [CharacterRetargeter], so every base character
## moves the same way. Items are skinned to their own pack's skeleton, so they only go on bodies
## of that pack (the catalog's `fits`). Presentation only: nothing here affects gameplay.
##
## Faces +Z like the source models; turn the rig by PI to face a Godot body's forward (-Z).

signal rebuilt(notes: PackedStringArray)

const ANIM_IDLE: StringName = &"Idle_Gun"
const ANIM_WALK: StringName = &"Walk"
const ANIM_RUN: StringName = &"Run"
const ANIM_RUN_BACK: StringName = &"Run_Back"
const ANIM_RUN_LEFT: StringName = &"Run_Left"
const ANIM_RUN_RIGHT: StringName = &"Run_Right"
const ANIM_SHOOT: StringName = &"Gun_Shoot"
const ANIM_AIM: StringName = &"Idle_Gun_Pointing"
const ANIM_DEATH: StringName = &"Death"
## Clips that repeat; everything else plays once and holds its last frame.
const LOOPING: Array[StringName] = [&"Idle", &"Idle_Gun", &"Idle_Gun_Pointing", &"Idle_Neutral", &"Idle_Sword",
	&"Run", &"Run_Back", &"Run_Left", &"Run_Right", &"Run_Shoot", &"Walk"]
const META_FACTORY_COLOUR: StringName = &"f2f_factory_colour"
const META_FACTORY_TEXTURE: StringName = &"f2f_factory_texture"
## Per mesh: surface -> the material it had before a hat hid its hair.
const META_HIDDEN_HAIR: StringName = &"f2f_hidden_hair"

static var _invisible: StandardMaterial3D = null

var catalog: CharacterCatalog = CharacterCatalog.shared()
## The appearance on show (sanitised copy), or null before the first [method apply].
var appearance: CharacterAppearance = null
## The body's skeleton; worn item meshes are its children.
var skeleton: Skeleton3D = null
var animation_player: AnimationPlayer = null
var retargeter: CharacterRetargeter = null

var _body_id: String = ""
var _body_root: Node3D = null
var _source: Node3D = null
var _source_skeleton: Skeleton3D = null
var _base_meshes: Array[MeshInstance3D] = []
## item ID -> its MeshInstance3D nodes.
var _item_meshes: Dictionary[String, Array] = {}
## item ID -> the BoneAttachment3D carrying a head-fitted item.
var _item_holders: Dictionary[String, Node3D] = {}
var _animation: StringName = ANIM_IDLE
## Upper-body layer: the clip laid over the upper body ("" = no layer).
var _upper_clip: StringName = &""
## One animation rig per upper-body clip, shared by every character: they all hold the same
## looping pose, and instancing the animation library per character (on every weapon switch,
## death and respawn) froze the game for a moment whenever a round started.
static var _shared_upper: Dictionary[StringName, Node3D] = {}


func _ready() -> void:
	_bind()
	if retargeter != null:
		retargeter.upper_source = _upper_skeleton()


## Shows [param new_appearance] (sanitised first). Only items that changed are rebuilt; a new
## body rebuilds everything. Returns what sanitising changed.
func apply(new_appearance: CharacterAppearance) -> PackedStringArray:
	var wanted := new_appearance.duplicate_appearance() if new_appearance != null else CharacterAppearance.new()
	var notes := CharacterWardrobe.sanitize(catalog, wanted)
	if wanted.body.is_empty():
		_clear_body()
		appearance = wanted
		rebuilt.emit(notes)
		return notes
	if wanted.body != _body_id or skeleton == null:
		_build_body(wanted.body)
	var worn: Array[String] = []
	worn.assign(wanted.items.values())
	for item_id: String in _item_meshes.keys():
		if not worn.has(item_id):
			for mesh: MeshInstance3D in _item_meshes[item_id]:
				mesh.queue_free()
			_item_meshes.erase(item_id)
			if _item_holders.has(item_id):
				_item_holders[item_id].queue_free()
				_item_holders.erase(item_id)
	for item_id: String in worn:
		if not _item_meshes.has(item_id):
			_attach_item(item_id)
	appearance = wanted
	_show_base_parts()
	_restore_hair()
	_apply_colours()
	_hide_hair()
	rebuilt.emit(notes)
	return notes


## Plays an animation clip (cross-fading over [param blend] seconds). Unknown clips are ignored.
func play(clip: StringName, blend: float = 0.15, speed: float = 1.0) -> void:
	_animation = clip
	if animation_player == null or not animation_player.has_animation(clip):
		return
	animation_player.speed_scale = speed
	if animation_player.current_animation != String(clip) or not animation_player.is_playing():
		animation_player.play(clip, blend)


func current_clip() -> StringName:
	return _animation


## Lays [param clip] (looping) over the spine, head and arms whatever [method play] plays on the
## legs, e.g. the gun-holding clip so a weapon stays raised while running. "" removes the layer.
## The retargeter's upper-body layer (see [CharacterRetargeter]).
func set_upper_clip(clip: StringName) -> void:
	if clip == _upper_clip:
		return
	_upper_clip = clip
	if retargeter != null:
		retargeter.upper_source = _upper_skeleton()


func upper_clip() -> StringName:
	return _upper_clip


## The shared skeleton playing [member _upper_clip] (null for none, or before the rig is in the
## tree). It is created once per clip under the tree's root and lives for the whole game.
func _upper_skeleton() -> Skeleton3D:
	if _upper_clip.is_empty() or not is_inside_tree():
		return null
	var shared: Node3D = _shared_upper.get(_upper_clip, null)
	if shared == null or not is_instance_valid(shared):
		var scene := load(catalog.animation_library) as PackedScene
		if scene == null:
			return null
		shared = scene.instantiate() as Node3D
		shared.name = "SharedUpperPose_%s" % _upper_clip
		shared.visible = false
		get_tree().root.add_child.call_deferred(shared)
		var player := shared.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation(_upper_clip):
			player.get_animation(_upper_clip).loop_mode = Animation.LOOP_LINEAR
			player.autoplay = _upper_clip
		_shared_upper[_upper_clip] = shared
	return _find_skeleton(shared)


func clips() -> PackedStringArray:
	return animation_player.get_animation_list() if animation_player != null else PackedStringArray()


## Meshes shown for a worn item (empty when it is not worn).
func item_meshes(item_id: String) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	meshes.assign(_item_meshes.get(item_id, []))
	return meshes


func base_meshes() -> Array[MeshInstance3D]:
	return _base_meshes.duplicate()


## The colour a worn item's channel shows now (its model's own colour when not overridden).
func channel_colour(item_id: String, channel_id: String) -> Color:
	var material := _channel_material(item_id, channel_id)
	return material.albedo_color if material != null else Color.WHITE


## The colour a worn item's channel shows when the appearance does not set one: the catalog's
## default for the channel, else the model's own colour.
func factory_colour(item_id: String, channel_id: String) -> Color:
	var material := _channel_material(item_id, channel_id)
	var own: Color = material.get_meta(META_FACTORY_COLOUR, Color.WHITE) if material != null else Color.WHITE
	for channel: Dictionary in catalog.colour_channels(item_id):
		if str(channel["id"]) == channel_id:
			return Color.from_string(str(channel.get("default", "")), own)
	return own


## Height of the character's bounding box top above the rig's origin (for framing cameras).
func top_height() -> float:
	var top := 0.0
	for mesh: MeshInstance3D in _all_meshes():
		if mesh.visible and mesh.mesh != null:
			top = maxf(top, mesh.mesh.get_aabb().end.y)
	return top


# --- building ------------------------------------------------------------------------------------

func _clear_body() -> void:
	if _body_root != null:
		remove_child(_body_root)
		_body_root.queue_free()
	_body_root = null
	skeleton = null
	retargeter = null
	_base_meshes.clear()
	_item_meshes.clear()
	_item_holders.clear()
	_body_id = ""


func _build_body(body_id: String) -> void:
	_clear_body()
	_ensure_source()
	var model := catalog.skeleton_model(body_id)
	var scene := load(model) as PackedScene if not model.is_empty() else null
	if scene == null:
		push_warning("CharacterRig: no model for %s" % body_id)
		return
	var instance := scene.instantiate() as Node3D
	var found := _find_skeleton(instance)
	if found == null:
		instance.free()
		return
	var relative := _relative_transform(found, instance)
	found.get_parent().remove_child(found)
	instance.free()
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)
	skeleton = found
	skeleton.owner = null
	skeleton.transform = relative
	_body_root.add_child(skeleton)
	var own_model := not str(catalog.body(body_id).get("model", "")).is_empty()
	for child: Node in skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		if own_model:
			mesh.owner = null
			_prepare_materials(mesh)
			_base_meshes.append(mesh)
		else:
			# The modular body borrows a part's skeleton; the part itself is worn as an item.
			mesh.free()
	retargeter = CharacterRetargeter.new()
	retargeter.name = "Retargeter"
	skeleton.add_child(retargeter)
	_body_id = body_id
	_bind()


func _ensure_source() -> void:
	if _source != null:
		return
	var scene := load(catalog.animation_library) as PackedScene
	if scene == null:
		push_warning("CharacterRig: animation library missing: %s" % catalog.animation_library)
		return
	_source = scene.instantiate() as Node3D
	_source.name = "AnimationSource"
	add_child(_source)
	_source_skeleton = _find_skeleton(_source)
	animation_player = _source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player != null:
		for clip: StringName in LOOPING:
			if animation_player.has_animation(clip):
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		play(_animation, 0.0)


func _bind() -> void:
	if retargeter != null and _source_skeleton != null and is_inside_tree():
		retargeter.bind(_source_skeleton)
		retargeter.upper_source = _upper_skeleton()


func _attach_item(item_id: String) -> void:
	var scene := load(str(catalog.item(item_id)["model"])) as PackedScene
	if scene == null or skeleton == null:
		return
	var instance := scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	var holder: Node3D = null
	if catalog.fit_mode(item_id, _body_id) == CharacterCatalog.FIT_HEAD:
		holder = _head_holder(item_id)
	for mesh: MeshInstance3D in meshes:
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		if holder != null:
			# Carried rigidly by the head: drawn unskinned, in its bind pose.
			mesh.skin = null
			mesh.skeleton = NodePath()
			mesh.transform = Transform3D.IDENTITY
			holder.add_child(mesh)
		else:
			skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
		_prepare_materials(mesh)
	instance.free()
	var stored: Array = []
	stored.assign(meshes)
	_item_meshes[item_id] = stored


## A node that follows this body's Head bone and maps the item's own body's head box (its
## model space at rest) onto this body's, axis by axis. The item's meshes go under it; the
## attachment is freed when the item comes off.
func _head_holder(item_id: String) -> Node3D:
	var head := skeleton.find_bone(&"Head")
	if head < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "Head_%s" % item_id
	attachment.bone_name = &"Head"
	skeleton.add_child(attachment)
	var from := catalog.head_box(catalog.native_body(item_id))
	var to := catalog.head_box(_body_id)
	var tweak: Dictionary = (catalog.item(item_id).get("adapt", {}) as Dictionary).get(_body_id, {})
	var scale := Vector3(to["size"] / from["size"]) * CharacterCatalog._vector(tweak.get("scale", [1.0, 1.0, 1.0]))
	var offset := CharacterCatalog._vector(tweak.get("offset", [0.0, 0.0, 0.0]))
	var place := Transform3D(Basis.from_scale(scale), Vector3(to["center"]) + offset) * Transform3D(Basis.IDENTITY, -Vector3(from["center"]))
	var holder := Node3D.new()
	holder.name = "Fit"
	holder.transform = _head_bind() * place
	attachment.add_child(holder)
	_item_holders[item_id] = attachment
	return holder


## From this body's model space (where its meshes were modelled and its head box measured) into
## the Head bone's space: the inverse bind matrix the body's own skin uses for Head. A rig's bone
## rest can differ from the pose its meshes were bound in (the modular rig's does), so the rest
## pose alone would leave head items floating and tilted.
func _head_bind() -> Transform3D:
	for mesh: MeshInstance3D in _base_meshes + _skinned_item_meshes():
		var skin := mesh.skin
		if skin == null:
			continue
		for bind: int in skin.get_bind_count():
			if skin.get_bind_name(bind) == &"Head":
				return skin.get_bind_pose(bind)
	return skeleton.get_bone_global_rest(skeleton.find_bone(&"Head")).affine_inverse()


func _skinned_item_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for item_id: String in _item_meshes:
		if not _item_holders.has(item_id):
			for mesh: MeshInstance3D in _item_meshes[item_id]:
				meshes.append(mesh)
	return meshes


## Gives each surface its own copy of its material (imported meshes share theirs) and remembers
## the model's own colour and texture.
func _prepare_materials(mesh: MeshInstance3D) -> void:
	for surface: int in mesh.mesh.get_surface_count():
		var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
		if original == null:
			continue
		var copy := original.duplicate() as BaseMaterial3D
		copy.set_meta(META_FACTORY_COLOUR, original.albedo_color)
		copy.set_meta(META_FACTORY_TEXTURE, original.albedo_texture)
		mesh.set_surface_override_material(surface, copy)


## Whether a worn item hides the hair (a hat modelled for a bald head, a hood).
func hair_hidden() -> bool:
	for item_id: String in appearance.items.values():
		if bool(catalog.item(item_id).get("hides_hair", false)):
			return true
	return false


## Hides the hair while a worn item asks for it: the item in the hair slot, and surfaces drawn
## with the body's hair materials (the modular heads have their hair modelled in).
func _hide_hair() -> void:
	var hide := hair_hidden()
	var hair_item := appearance.item_in("hair")
	if not hair_item.is_empty():
		for mesh: MeshInstance3D in item_meshes(hair_item):
			mesh.visible = not hide
	if not hide:
		return
	var hair_materials: Array = catalog.body(_body_id).get("hair_materials", [])
	if hair_materials.is_empty():
		return
	if _invisible == null:
		_invisible = StandardMaterial3D.new()
		_invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_invisible.albedo_color = Color(0, 0, 0, 0)
		_invisible.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh: MeshInstance3D in _all_meshes():
		var saved: Dictionary = mesh.get_meta(META_HIDDEN_HAIR, {})
		for surface: int in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface)
			if material != null and material != _invisible and hair_materials.has(material.resource_name):
				saved[surface] = material
				mesh.set_surface_override_material(surface, _invisible)
		if not saved.is_empty():
			mesh.set_meta(META_HIDDEN_HAIR, saved)


## Puts back hair surfaces hidden by [method _hide_hair].
func _restore_hair() -> void:
	for mesh: MeshInstance3D in _all_meshes():
		if not mesh.has_meta(META_HIDDEN_HAIR):
			continue
		var saved: Dictionary = mesh.get_meta(META_HIDDEN_HAIR)
		for surface: Variant in saved:
			mesh.set_surface_override_material(int(surface), saved[surface] as Material)
		mesh.remove_meta(META_HIDDEN_HAIR)


func _show_base_parts() -> void:
	var parts: Dictionary = catalog.body(_body_id).get("base_parts", {})
	for mesh: MeshInstance3D in _base_meshes:
		var hidden := false
		for slot_id: Variant in parts:
			if str(parts[slot_id]) == String(mesh.name) and appearance.items.has(str(slot_id)):
				hidden = true
		mesh.visible = not hidden


# --- colours --------------------------------------------------------------------------------------

func _apply_colours() -> void:
	var skin: Dictionary = catalog.body(_body_id).get("skin", {})
	var skin_materials: Array = skin.get("materials", [])
	var tone := Color.from_string(appearance.skin_tone, Color.WHITE) if not appearance.skin_tone.is_empty() else Color(0, 0, 0, 0)
	var reference := _factory_skin_reference(skin_materials)
	var texture_path := CharacterWardrobe.skin_texture_path(catalog, _body_id, appearance.skin_texture)
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	var base_tints: Dictionary = catalog.body(_body_id).get("base_tints", {})
	for mesh: MeshInstance3D in _base_meshes:
		for surface: int in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if skin_materials.has(material.resource_name):
				_apply_skin(material, skin, tone, reference, texture)
			elif base_tints.has(material.resource_name):
				material.albedo_color = Color.from_string(str(base_tints[material.resource_name]), Color.WHITE)
	for item_id: String in _item_meshes:
		var channels: Dictionary[String, Dictionary] = {}
		for channel: Dictionary in catalog.colour_channels(item_id):
			channels[str(channel["material"])] = channel
		for mesh: MeshInstance3D in _item_meshes[item_id]:
			for surface: int in mesh.get_surface_override_material_count():
				var material := mesh.get_surface_override_material(surface) as BaseMaterial3D
				if material == null:
					continue
				var factory: Color = material.get_meta(META_FACTORY_COLOUR, Color.WHITE)
				if channels.has(material.resource_name):
					var channel := channels[material.resource_name]
					var fallback := Color.from_string(str(channel.get("default", "")), factory)
					material.albedo_color = appearance.colour(item_id, str(channel["id"]), fallback)
				elif skin_materials.has(material.resource_name):
					_apply_skin(material, skin, tone, reference, null)
				else:
					material.albedo_color = factory


## Skin: "replace" sets the first skin material to the tone and keeps the others' shade relative
## to it (e.g. a darker skin shadow); "multiply" tints the textured skin.
func _apply_skin(material: BaseMaterial3D, skin: Dictionary, tone: Color, reference: Color, texture: Texture2D) -> void:
	var factory: Color = material.get_meta(META_FACTORY_COLOUR, Color.WHITE)
	if texture != null:
		material.albedo_texture = texture
	else:
		material.albedo_texture = material.get_meta(META_FACTORY_TEXTURE, null)
	if tone.a == 0.0:
		material.albedo_color = factory
	elif str(skin.get("mode", "multiply")) == "replace":
		var ratio := Color(factory.r / maxf(reference.r, 0.001), factory.g / maxf(reference.g, 0.001), factory.b / maxf(reference.b, 0.001))
		material.albedo_color = Color(tone.r * ratio.r, tone.g * ratio.g, tone.b * ratio.b)
	else:
		material.albedo_color = Color(factory.r * tone.r, factory.g * tone.g, factory.b * tone.b, factory.a)


## The model's own colour of the first skin material, from any shown mesh (white if none).
func _factory_skin_reference(skin_materials: Array) -> Color:
	if skin_materials.is_empty():
		return Color.WHITE
	for mesh: MeshInstance3D in _all_meshes():
		for surface: int in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == str(skin_materials[0]):
				return material.get_meta(META_FACTORY_COLOUR, Color.WHITE)
	return Color.WHITE


func _channel_material(item_id: String, channel_id: String) -> BaseMaterial3D:
	var material_name := ""
	for channel: Dictionary in catalog.colour_channels(item_id):
		if str(channel["id"]) == channel_id:
			material_name = str(channel["material"])
	for mesh: MeshInstance3D in item_meshes(item_id):
		for surface: int in mesh.get_surface_override_material_count():
			var material := mesh.get_surface_override_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == material_name:
				return material
	return null


func _all_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = _base_meshes.duplicate()
	for item_id: String in _item_meshes:
		meshes.append_array(item_meshes(item_id))
	return meshes


# --- helpers ----------------------------------------------------------------------------------------

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


## [param node]'s transform relative to [param ancestor] (both outside the tree).
static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
