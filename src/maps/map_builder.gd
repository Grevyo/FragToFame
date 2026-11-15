class_name MapBuilder
extends RefCounted
## Turns MapDocument pieces into scene nodes. The SAME builder is used by the editor and the FPS
## runtime, so what you build is exactly what you play.
##
## Mode EDITOR shows gameplay markers/zones; mode RUNTIME hides markers and shows zones only as a
## faint floor tint (bombsites) or not at all.

enum Mode { EDITOR, RUNTIME }

const STEP_HEIGHT: float = 0.25

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
	var holder: Node3D
	match kind:
		"block":
			holder = _block(size, PieceCatalog.color(type))
		"ramp":
			holder = _ramp(size, PieceCatalog.color(type))
		"stairs":
			holder = _stairs(size, PieceCatalog.color(type))
		"marker":
			if mode == Mode.RUNTIME:
				holder = Node3D.new()  # Invisible point; still positioned so runtime can read it.
			else:
				holder = _marker(size, PieceCatalog.color(type))
		"zone":
			holder = _zone(piece, size, mode)
		_:
			push_warning("MapBuilder: unknown piece type '%s'" % type)
			return null
	holder.name = str(piece["id"])
	holder.set_meta(&"piece_id", piece["id"])
	holder.set_meta(&"piece_type", type)
	holder.position = piece["position"]
	holder.rotation_degrees.y = float(piece["rotation_y"])
	return holder


static func _block(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	BlockBuilder.make_box(root, size, Vector3(0, size.y / 2.0, 0), color, Vector3.ZERO, "Body")
	return root


static func _ramp(size: Vector3, color: Color) -> Node3D:
	var root := StaticBody3D.new()
	var mesh := PrismMesh.new()
	# PrismMesh slopes along X (apex at -X when left_to_right = 0). Build it rotated so the
	# slope runs along local Z with the high side at -Z.
	mesh.size = Vector3(size.z, size.y, size.x)
	mesh.left_to_right = 0.0
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	instance.material_override = BlockBuilder.checker_material(color)
	instance.position.y = size.y / 2.0
	instance.rotation_degrees.y = -90.0
	root.add_child(instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = mesh.create_convex_shape()
	collision.position = instance.position
	collision.rotation_degrees = instance.rotation_degrees
	root.add_child(collision)
	return root


static func _stairs(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var steps := maxi(1, roundi(size.y / STEP_HEIGHT))
	var rise := size.y / float(steps)
	var run := size.z / float(steps)
	for i: int in steps:
		var top := rise * float(i + 1)
		# Step i sits at the low (+Z) end for i = 0 and climbs toward -Z.
		var z := size.z / 2.0 - run * (float(i) + 0.5)
		BlockBuilder.make_box(root, Vector3(size.x, top, run), Vector3(0, top / 2.0, z), color,
			Vector3.ZERO, "Step%d" % i, false)
	# CharacterBody3D does not auto-step, so walking uses a smooth slope from the floor at +Z
	# to the top of the last step at -Z.
	var slope_length := sqrt(size.z * size.z + size.y * size.y)
	var angle := atan2(size.y, size.z)
	var thickness := 0.2
	var slope := BlockBuilder.make_collision_box(root, Vector3(size.x, thickness, slope_length),
		Vector3(0, size.y / 2.0 - thickness / 2.0 / cos(angle), 0), Vector3(rad_to_deg(angle), 0, 0), "Slope")
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
	# Facing arrow along -Z.
	var arrow_mesh := PrismMesh.new()
	arrow_mesh.size = Vector3(0.5, 0.6, 0.05)
	var arrow := MeshInstance3D.new()
	arrow.mesh = arrow_mesh
	arrow.material_override = material
	arrow.position = Vector3(0, 0.05, -0.7)
	arrow.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(arrow)
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
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.01
	label.position.y = size.y + 0.3
	label.no_depth_test = true
	root.add_child(label)
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
