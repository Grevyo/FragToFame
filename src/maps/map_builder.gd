class_name MapBuilder
extends RefCounted
## Turns MapDocument pieces into scene nodes. The SAME builder is used by the editor and the FPS
## runtime, so what you build is exactly what you play.
##
## Mode EDITOR shows gameplay markers, zones, anchors, hints and light gizmos; mode RUNTIME hides
## them (bombsites keep a faint floor tint). Lights emit in both modes.

enum Mode { EDITOR, RUNTIME }

const STEP_HEIGHT: float = 0.25
const ANCHOR_SHAPES: Dictionary[String, String] = {"plant": "PLANT", "default": "POS", "utility": "UTIL"}
const HINT_LABELS: Dictionary[String, String] = {"ai_cover": "COVER", "ai_hold": "HOLD", "ai_angle": "ANGLE"}

static var _zone_materials: Dictionary[Color, StandardMaterial3D] = {}


## Builds every piece of [param doc] under a new Node3D. Each piece node is named by its ID
## and carries meta "piece_id".
static func build(doc: MapDocument, mode: Mode) -> Node3D:
	var root := Node3D.new()
	root.name = "Map"
	for piece: Dictionary in doc.pieces:
		var node := build_piece(piece, mode)
		if node != null:
			root.add_child(node)
	return root


## Builds one piece. Returns null when the piece has no representation in [param mode].
static func build_piece(piece: Dictionary, mode: Mode) -> Node3D:
	var type := str(piece["type"])
	var kind := PieceCatalog.kind(type)
	var size: Vector3 = piece["size"]
	var props: Dictionary = piece.get("props", {})
	var surface := MapMaterials.for_piece(type, str(piece.get("material", "")))
	var holder: Node3D
	match kind:
		"block":
			holder = Node3D.new()
			_add_part(holder, {"shape": "box", "size": size, "pos": Vector3(0, size.y / 2.0, 0), "rot": Vector3.ZERO, "mat": ""}, surface, "Body")
		"compound":
			holder = Node3D.new()
			var parts := PieceShapes.parts(type, size, props)
			for i: int in parts.size():
				_add_part(holder, parts[i], surface, "Part%d" % i)
		"ramp":
			holder = _ramp(size, surface)
		"stairs":
			holder = _stairs(size, surface)
		"marker":
			if mode == Mode.RUNTIME:
				holder = Node3D.new()  # Invisible point; still positioned so runtime can read it.
			else:
				holder = _marker(size, PieceCatalog.color(type))
		"zone":
			holder = _zone(piece, size, mode)
		"light":
			holder = _light(type, props, mode)
		"anchor":
			holder = _point_marker(PieceCatalog.color(type), "%s · %s" % [
				ANCHOR_SHAPES.get(str(props.get("kind", "default")), "POS"), str(props.get("name", ""))], false, mode)
		"hint":
			holder = _point_marker(PieceCatalog.color(type), "%s%s" % [HINT_LABELS.get(type, "HINT"),
				(" " + str(props.get("site", ""))) if not str(props.get("site", "")).is_empty() else ""], true, mode)
		_:
			push_warning("MapBuilder: unknown piece type '%s'" % type)
			return null
	if not str(piece["id"]).is_empty():  # Previews of unplaced pieces have no ID yet.
		holder.name = str(piece["id"])
	holder.set_meta(&"piece_id", piece["id"])
	holder.set_meta(&"piece_type", type)
	holder.position = piece["position"]
	holder.rotation_degrees.y = float(piece["rotation_y"])
	return holder


## One solid part: a StaticBody3D holding a mesh and a collider of exactly the same shape.
static func _add_part(parent: Node3D, part: Dictionary, surface: Material, part_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = part_name
	body.position = part["pos"]
	body.rotation_degrees = part["rot"]
	var size: Vector3 = part["size"]
	var mesh: PrimitiveMesh
	var shape: Shape3D
	if part["shape"] == "cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size.x / 2.0
		cylinder.bottom_radius = size.x / 2.0
		cylinder.height = size.y
		cylinder.radial_segments = 16
		cylinder.rings = 1
		mesh = cylinder
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = size.x / 2.0
		cylinder_shape.height = size.y
		shape = cylinder_shape
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh = box
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape = box_shape
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	var fixed := MapMaterials.material(str(part.get("mat", "")))
	instance.material_override = fixed if fixed != null else surface
	body.add_child(instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


## A wedge rising toward local -Z: mesh and (optionally) a convex collider of the same shape.
static func _wedge(parent: Node3D, size: Vector3, surface: Material, visible: bool, body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	var mesh := PrismMesh.new()
	# PrismMesh slopes along X (apex at -X when left_to_right = 0). Build it rotated so the
	# slope runs along local Z with the high side at -Z.
	mesh.size = Vector3(size.z, size.y, size.x)
	mesh.left_to_right = 0.0
	if visible:
		var instance := MeshInstance3D.new()
		instance.name = "Mesh"
		instance.mesh = mesh
		instance.material_override = surface
		instance.position.y = size.y / 2.0
		instance.rotation_degrees.y = -90.0
		body.add_child(instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = mesh.create_convex_shape()
	collision.position.y = size.y / 2.0
	collision.rotation_degrees.y = -90.0
	body.add_child(collision)
	parent.add_child(body)
	return body


static func _ramp(size: Vector3, surface: Material) -> Node3D:
	var root := Node3D.new()
	_wedge(root, size, surface, true, "Body")
	return root


static func _stairs(size: Vector3, surface: Material) -> Node3D:
	var root := Node3D.new()
	var steps := maxi(1, roundi(size.y / STEP_HEIGHT))
	var rise := size.y / float(steps)
	var run := size.z / float(steps)
	for i: int in steps:
		var top := rise * float(i + 1)
		# Step i sits at the low (+Z) end for i = 0 and climbs toward -Z.
		var z := size.z / 2.0 - run * (float(i) + 0.5)
		var box := BoxMesh.new()
		box.size = Vector3(size.x, top, run)
		var step := MeshInstance3D.new()
		step.name = "Step%d" % i
		step.mesh = box
		step.material_override = surface
		step.position = Vector3(0, top / 2.0, z)
		root.add_child(step)
	# CharacterBody3D does not auto-step, so walking uses a solid wedge whose top runs from the
	# floor at +Z to the top of the last step at -Z. Solid (not a thin sheet) so nothing can
	# walk or shoot through the space under the steps.
	var slope := _wedge(root, size, surface, false, "Slope")
	slope.set_meta(&"is_walk_slope", true)
	return root


static func _marker(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = size.x / 2.0
	body_mesh.height = size.y
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = material
	body.position.y = size.y / 2.0
	root.add_child(body)
	root.add_child(_arrow(material))
	return root


## Facing arrow along -Z.
static func _arrow(material: Material) -> MeshInstance3D:
	var arrow_mesh := PrismMesh.new()
	arrow_mesh.size = Vector3(0.5, 0.6, 0.05)
	var arrow := MeshInstance3D.new()
	arrow.mesh = arrow_mesh
	arrow.material_override = material
	arrow.position = Vector3(0, 0.05, -0.7)
	arrow.rotation_degrees = Vector3(-90, 0, 0)
	return arrow


## Editor-only diamond with a caption (anchors and AI hints). Invisible point at runtime.
static func _point_marker(color: Color, caption: String, with_arrow: bool, mode: Mode) -> Node3D:
	var root := Node3D.new()
	if mode == Mode.RUNTIME:
		return root
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 4
	mesh.rings = 2
	var gem := MeshInstance3D.new()
	gem.mesh = mesh
	gem.material_override = material
	gem.position.y = 0.3
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gem)
	if with_arrow:
		root.add_child(_arrow(material))
	root.add_child(_caption(caption, 0.75, 36, color))
	return root


static func _caption(text: String, height: float, font_size: int, color: Color = Color.WHITE) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.pixel_size = 0.01
	label.modulate = color
	label.position.y = height
	label.no_depth_test = true
	return label


static func _light(type: String, props: Dictionary, mode: Mode) -> Node3D:
	var root := Node3D.new()
	var color := Color.from_string(str(props.get("color", "ffffff")), Color.WHITE)
	var light: Light3D
	if type == "light_spot":
		var spot := SpotLight3D.new()
		spot.spot_range = clampf(float(props.get("range", 10.0)), 1.0, 60.0)
		spot.spot_angle = clampf(float(props.get("angle", 40.0)), 5.0, 85.0)
		spot.rotation_degrees.x = -90.0
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = clampf(float(props.get("range", 8.0)), 1.0, 60.0)
		light = omni
	light.name = "Light"
	light.light_color = color
	light.light_energy = clampf(float(props.get("energy", 1.5)), 0.0, 16.0)
	root.add_child(light)
	if mode == Mode.EDITOR:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mesh := SphereMesh.new()
		mesh.radius = 0.15
		mesh.height = 0.3
		var bulb := MeshInstance3D.new()
		bulb.mesh = mesh
		bulb.material_override = material
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bulb)
	return root


static func _zone(piece: Dictionary, size: Vector3, mode: Mode) -> Node3D:
	var root := Node3D.new()
	var type := str(piece["type"])
	var props: Dictionary = piece.get("props", {})
	if mode == Mode.RUNTIME:
		if type == "bombsite":
			# Faint painted floor so players can see the site boundary.
			var paint := MeshInstance3D.new()
			var paint_mesh := BoxMesh.new()
			paint_mesh.size = Vector3(size.x, 0.02, size.z)
			paint.mesh = paint_mesh
			paint.material_override = _zone_material(Color(0.95, 0.3, 0.3, 0.18))
			paint.position.y = 0.011
			root.add_child(paint)
		return root
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _zone_material(PieceCatalog.color(type))
	box.position.y = size.y / 2.0
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(box)
	var text := ""
	match type:
		"bombsite":
			text = "SITE %s" % props.get("site", "?")
		"buy_zone":
			text = "BUY (%s)" % props.get("team", "?")
		"callout":
			text = str(props.get("name", "Callout"))
	root.add_child(_caption(text, size.y + 0.3, 64))
	return root


static func _zone_material(color: Color) -> StandardMaterial3D:
	if _zone_materials.has(color):
		return _zone_materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	_zone_materials[color] = material
	return material


## Spawn points of a team ("attack" / "defence") as [position, yaw_radians] pairs.
static func spawn_points(doc: MapDocument, team: String) -> Array[Array]:
	var list: Array[Array] = []
	for piece: Dictionary in doc.pieces:
		if PieceCatalog.kind(str(piece["type"])) == "marker" and piece.get("props", {}).get("team", "") == team:
			list.append([piece["position"], deg_to_rad(float(piece["rotation_y"]))])
	return list
