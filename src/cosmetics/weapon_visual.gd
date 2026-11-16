class_name WeaponVisual
extends Node3D
## A weapon model as the game shows it: turned and scaled into weapon space (see WeaponModels),
## wearing its factory finish or a Coat, with up to five Magnets. Used by the first-person
## viewmodel, weapon inspection and the Armoury preview. Presentation only.
##
## A Coat replaces the albedo texture of the model's painted materials; the factory materials
## are kept and restored when the Coat is removed. Magnets are Decal nodes projected onto the
## mesh at the weapon's slots, so they sit on top of any Coat and are never baked into one.

## Render layer shared by weapon meshes and Magnet decals, so Magnets never project onto the
## world behind the weapon.
const WEAPON_LAYER: int = 1 << 9
const MAGNET_DEPTH: float = 0.03

var weapon_id: StringName = &""
## Size of the weapon in weapon space (metres), available after [method setup].
var size: Vector3 = Vector3.ZERO
var coat_id: String = ""
## Magnet ID per slot ("" = empty), always five entries.
var magnets: Array[String] = ["", "", "", "", ""]

var _weapon_root: Node3D
var _model: Node3D
var _factory: Array[Array] = []  # [mesh instance, surface index, factory material]
var _decals: Array[Decal] = []
var _markers: Node3D

## weapon_id -> [pivot basis, pivot position, size]; working these out once keeps weapon
## switches cheap.
static var _fit_cache: Dictionary[StringName, Array] = {}
static var _orm: Texture2D = null


## Builds the model for [param id]. Returns false when the weapon has no model.
func setup(id: StringName) -> bool:
	# Decals share a render layer with every weapon mesh. Detach the outgoing model and its
	# decals together before the replacement enters that layer.
	if _weapon_root != null:
		remove_child(_weapon_root)
		_weapon_root.queue_free()
	_weapon_root = null
	_model = null
	_markers = null
	_factory.clear()
	_decals.clear()
	magnets.fill("")
	coat_id = ""
	size = Vector3.ZERO
	weapon_id = id

	var scene := load(WeaponModels.model_path(id)) as PackedScene if WeaponModels.has_model(id) else null
	if scene == null:
		return false
	_weapon_root = Node3D.new()
	_weapon_root.name = "Weapon"
	add_child(_weapon_root)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	_weapon_root.add_child(pivot)
	_model = scene.instantiate() as Node3D
	pivot.add_child(_model)
	_remove_extras(_model)
	var info := WeaponModels.info(id)
	_arrange_parts(info)
	if not _fit_cache.has(id):
		var euler: Vector3 = info["rotation"]
		var turn := Basis.from_euler(Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z)))
		pivot.basis = turn
		var bounds := merged_bounds(_model, self)
		var scale_factor := float(info["length"]) / maxf(bounds.size.z, 0.0001)
		_fit_cache[id] = [turn.scaled(Vector3.ONE * scale_factor), -bounds.get_center() * scale_factor, bounds.size * scale_factor]
	pivot.basis = _fit_cache[id][0]
	pivot.position = _fit_cache[id][1]
	size = _fit_cache[id][2]
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		instance.layers = 1 | WEAPON_LAYER
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if material is BaseMaterial3D:
				var factory := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				# Decals only draw on opaque surfaces; blended factory materials become cut-outs.
				if factory.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
					factory.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					factory.alpha_scissor_threshold = 0.5
				instance.set_surface_override_material(surface, factory)
				_factory.append([instance, surface, factory])
	_build_decals()
	return true


## True when the model has at least one painted (textured) material a Coat can replace.
func accepts_coats() -> bool:
	return not paint_surfaces().is_empty()


## The factory albedo texture of the painted surfaces (the weapon's stock finish), or null.
func factory_texture() -> Texture2D:
	var surfaces := paint_surfaces()
	return (surfaces[0][2] as BaseMaterial3D).albedo_texture if not surfaces.is_empty() else null


## Surfaces whose factory material has an albedo texture: [[mesh instance, surface, material]].
func paint_surfaces() -> Array[Array]:
	return _factory.filter(func(entry: Array) -> bool: return (entry[2] as BaseMaterial3D).albedo_texture != null)


## Puts a Coat texture on every painted surface, or restores the factory finish (null).
func apply_coat(texture: Texture2D, id: String = "") -> void:
	coat_id = id if texture != null else ""
	for entry: Array in _factory:
		var instance := entry[0] as MeshInstance3D
		var factory := entry[2] as BaseMaterial3D
		if texture == null or factory.albedo_texture == null:
			instance.set_surface_override_material(int(entry[1]), factory)
			continue
		var painted := factory.duplicate() as BaseMaterial3D
		painted.albedo_texture = texture
		instance.set_surface_override_material(int(entry[1]), painted)


## Applies a Magnet to a slot (0–4), or clears the slot with "". Returns false for a bad slot
## or an unknown Magnet.
func set_magnet(slot: int, magnet_id: String) -> bool:
	if slot < 0 or slot >= WeaponModels.SLOT_COUNT or slot >= _decals.size():
		return false
	var texture: Texture2D = null
	if not magnet_id.is_empty():
		texture = MagnetCatalog.texture(magnet_id)
		if texture == null:
			return false
	magnets[slot] = magnet_id
	_decals[slot].texture_albedo = texture
	_decals[slot].visible = texture != null
	return true


## Applies a whole customisation: {"coat": id, "magnets": [five ids]} (see WeaponCosmetics).
func apply_loadout(loadout: Dictionary) -> void:
	var coat := str(loadout.get("coat", ""))
	apply_coat(CoatLibrary.texture(weapon_id, coat), coat)
	var list: Array = loadout.get("magnets", [])
	for slot: int in WeaponModels.SLOT_COUNT:
		set_magnet(slot, str(list[slot]) if slot < list.size() else "")


func decal(slot: int) -> Decal:
	return _decals[slot] if slot >= 0 and slot < _decals.size() else null


## Shows a small marker on every Magnet slot (Armoury slot picking and developer checks).
func show_slot_markers(on: bool, highlighted: int = -1) -> void:
	if _markers != null:
		_weapon_root.remove_child(_markers)
		_markers.queue_free()
		_markers = null
	if not on or _weapon_root == null:
		return
	_markers = Node3D.new()
	_weapon_root.add_child(_markers)
	var slots := WeaponModels.slots(weapon_id)
	for i: int in slots.size():
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.42, 0.16) if i == highlighted else Color(0.2, 0.85, 1.0)
		material.no_depth_test = true
		var mesh := TorusMesh.new()
		mesh.inner_radius = float(slots[i]["size"]) * 0.5
		mesh.outer_radius = float(slots[i]["size"]) * 0.58
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.material_override = material
		ring.transform = _slot_transform(slots[i])
		_markers.add_child(ring)


## Bounds of every visible mesh under [param node], in the space of [param relative_to]
## (an ancestor of the meshes). Skinned meshes are measured as the skeleton poses them.
static func merged_bounds(node: Node3D, relative_to: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if not _shown(instance, relative_to):
			continue
		var box: AABB
		if instance.skin != null:
			var points := mesh_points(instance, relative_to)
			if points.is_empty():
				continue
			box = AABB(points[0], Vector3.ZERO)
			for point: Vector3 in points:
				box = box.expand(point)
		else:
			box = _local_transform(instance, relative_to) * instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Every triangle of the visible model in this visual's space (three vertices per triangle).
func triangles() -> PackedVector3Array:
	return geometry()[0]


## The visible model's triangles and their texture coordinates, in this visual's space:
## [points, uvs], three entries per triangle (uvs are zero for surfaces without UVs).
func geometry() -> Array:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		if _shown(child as MeshInstance3D, self):
			var part := mesh_geometry(child as MeshInstance3D, self)
			points.append_array(part[0] as PackedVector3Array)
			uvs.append_array(part[1] as PackedVector2Array)
	return [points, uvs]


## Triangle vertices of one mesh in the space of [param relative_to], as it is drawn.
static func mesh_points(instance: MeshInstance3D, relative_to: Node3D) -> PackedVector3Array:
	return mesh_geometry(instance, relative_to)[0]


## [points, uvs] of one mesh in the space of [param relative_to], as it is drawn: rigid meshes
## by their node transform, skinned meshes by their skeleton's pose.
static func mesh_geometry(instance: MeshInstance3D, relative_to: Node3D) -> Array:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
	var skinned := instance.skin != null and skeleton != null
	var binds: Array[Transform3D] = []
	if skinned:
		for i: int in instance.skin.get_bind_count():
			var bone := instance.skin.get_bind_bone(i)
			if bone < 0:
				bone = skeleton.find_bone(instance.skin.get_bind_name(i))
			binds.append((skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY) * instance.skin.get_bind_pose(i))
	var to_space := _local_transform(skeleton if skinned else instance, relative_to)
	for surface: int in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var posed := PackedVector3Array()
		posed.resize(vertices.size())
		if skinned and arrays[Mesh.ARRAY_BONES] != null:
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per_vertex := int(float(bones.size()) / maxi(1, vertices.size()))
			for v: int in vertices.size():
				var point := Vector3.ZERO
				var total := 0.0
				for k: int in per_vertex:
					var weight := weights[v * per_vertex + k]
					if weight > 0.0:
						point += (binds[bones[v * per_vertex + k]] * vertices[v]) * weight
						total += weight
				posed[v] = to_space * (point / total if total > 0.0 else vertices[v])
		else:
			for v: int in vertices.size():
				posed[v] = to_space * vertices[v]
		var surface_uvs := PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			surface_uvs = arrays[Mesh.ARRAY_TEX_UV]
		var order := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			order = arrays[Mesh.ARRAY_INDEX]
		if order.is_empty():
			order = PackedInt32Array(range(vertices.size()))
		for index: int in order:
			points.append(posed[index])
			uvs.append(surface_uvs[index] if index < surface_uvs.size() else Vector2.ZERO)
	return [points, uvs]


## False when the node or anything between it and [param ancestor] is hidden (works outside the
## scene tree, unlike is_visible_in_tree).
static func _shown(node: Node3D, ancestor: Node3D) -> bool:
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D and not (current as Node3D).visible:
			return false
		current = current.get_parent()
	return true


static func _local_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Models exported from scene files can carry lamps and cameras; the game supplies its own.
static func _remove_extras(model: Node3D) -> void:
	for type: String in ["Light3D", "Camera3D", "AnimationPlayer"]:
		for node: Node in model.find_children("*", type, true, false):
			node.get_parent().remove_child(node)
			node.queue_free()


## Some source files lay accessories out beside the weapon. "hide" removes loose parts from
## view; "align" moves a part sideways onto the axis of another (a suppressor onto its barrel).
func _arrange_parts(info: Dictionary) -> void:
	for part_name: String in info.get("hide", []):
		var part := _model.find_child(part_name, true, false) as Node3D
		if part != null:
			part.visible = false
	var align: Dictionary = info.get("align", {})
	for part_name: String in align:
		var part := _model.find_child(part_name, true, false) as Node3D
		var target := _model.find_child(str(align[part_name]), true, false) as Node3D
		if part == null or target == null:
			continue
		var offset := merged_bounds(target, _model).get_center() - merged_bounds(part, _model).get_center()
		offset.z = 0.0
		part.position += (part.get_parent() as Node3D).transform.basis.inverse() * offset if part.get_parent() != _model else offset


func _build_decals() -> void:
	var slots := WeaponModels.slots(weapon_id)
	for i: int in slots.size():
		var item := Decal.new()
		item.name = "MagnetSlot%d" % (i + 1)
		var edge := float(slots[i]["size"])
		item.size = Vector3(edge, MAGNET_DEPTH, edge)
		item.transform = _slot_transform(slots[i])
		item.cull_mask = WEAPON_LAYER
		item.texture_orm = _magnet_surface()
		item.upper_fade = 0.0
		item.lower_fade = 0.0
		item.visible = false
		_weapon_root.add_child(item)
		_decals.append(item)


## Magnets are printed vinyl: matt and non-metallic whatever they are stuck to. Without this a
## Magnet on bare metal would take the metal's shine and all but vanish.
static func _magnet_surface() -> Texture2D:
	if _orm == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 0.75, 0.0, 1.0))  # occlusion, roughness, metallic
		_orm = ImageTexture.create_from_image(image)
	return _orm


## Decal frame for a slot: projects along the inward normal with the picture upright (+Y up).
static func _slot_transform(slot: Dictionary) -> Transform3D:
	var normal: Vector3 = (slot["normal"] as Vector3).normalized()
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := -(up - normal * up.dot(normal)).normalized()
	var x := normal.cross(z).normalized()
	return Transform3D(Basis(x, normal, z), slot["position"] as Vector3)
