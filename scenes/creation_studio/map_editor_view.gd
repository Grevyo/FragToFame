class_name MapEditorView
extends Node3D
## 3D view of the document being edited. Mirrors MapEditController signals into nodes built by
## MapBuilder (EDITOR mode), draws selection outlines, the navmesh overlay and the measuring
## line, applies editor-only layer visibility and answers picking queries.

const PICK_DISTANCE: float = 2000.0
const SURFACE_PROBE_MARGIN: float = 0.015
const OUTLINE_COLOR: Color = Color(1.0, 0.75, 0.2)
const MEASURE_COLOR: Color = Color(0.4, 0.95, 1.0)

var controller: MapEditController

var _nodes: Dictionary[String, Node3D] = {}
var _outline: MeshInstance3D
var _overlay: MeshInstance3D
var _measure: MeshInstance3D
var _measure_label: Label3D


func _ready() -> void:
	_outline = _line_instance("SelectionOutline", OUTLINE_COLOR)
	_measure = _line_instance("MeasureLine", MEASURE_COLOR)
	_measure_label = Label3D.new()
	_measure_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_measure_label.no_depth_test = true
	_measure_label.modulate = MEASURE_COLOR
	_measure_label.pixel_size = 0.012
	_measure.add_child(_measure_label)
	_overlay = MeshInstance3D.new()
	_overlay.name = "NavmeshOverlay"
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.visible = false
	add_child(_overlay)


func _line_instance(node_name: String, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	instance.material_override = material
	instance.visible = false
	add_child(instance)
	return instance


func bind(edit_controller: MapEditController) -> void:
	controller = edit_controller
	controller.document_replaced.connect(rebuild_all)
	controller.piece_added.connect(_rebuild_piece)
	controller.piece_changed.connect(_rebuild_piece)
	controller.piece_removed.connect(_remove_piece)
	controller.selection_changed.connect(func(_id: String) -> void: _update_outline())
	controller.document_state_changed.connect(func(key: String) -> void:
		if key == "layers":
			_apply_layers())
	rebuild_all()


func node_count() -> int:
	return _nodes.size()


func node_for(piece_id: String) -> Node3D:
	return _nodes.get(piece_id, null)


func rebuild_all() -> void:
	for id: String in _nodes:
		_discard(_nodes[id])
	_nodes.clear()
	for piece: Dictionary in controller.document.pieces:
		_rebuild_piece(str(piece["id"]))
	_update_outline()
	set_overlay(null)
	set_measure(null, null)


## Shows a navmesh overlay mesh (null hides it).
func set_overlay(mesh: Mesh) -> void:
	_overlay.mesh = mesh
	_overlay.visible = mesh != null


func has_overlay() -> bool:
	return _overlay.visible and _overlay.mesh != null


## Draws the measuring line between two points (null hides it).
func set_measure(from: Variant, to: Variant, text: String = "") -> void:
	_measure.visible = from is Vector3 and to is Vector3
	if not _measure.visible:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from as Vector3)
	mesh.surface_add_vertex(to as Vector3)
	mesh.surface_end()
	_measure.mesh = mesh
	_measure_label.text = text
	_measure_label.position = ((from as Vector3) + (to as Vector3)) / 2.0 + Vector3(0, 0.4, 0)


## True when the piece may be picked: its layer is visible and not locked.
func is_pickable(piece: Dictionary) -> bool:
	var layer := str(piece.get("layer", MapDocument.DEFAULT_LAYER))
	return controller.document.is_layer_visible(layer) and not controller.document.is_layer_locked(layer)


## Nearest piece hit by the ray, or {} — returns {"piece_id", "point", "normal"}.
## [param solid_only] ignores markers and zones (used for stacking placement and measuring).
## Hidden layers and excluded pieces are skipped. Locked geometry still provides solid surfaces.
func pick(origin: Vector3, direction: Vector3, solid_only: bool = false, exclude: Array[String] = []) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var end := origin + direction * PICK_DISTANCE
	for piece: Dictionary in controller.document.pieces:
		var type := str(piece["type"])
		if (solid_only and not PieceCatalog.is_solid(type)) or exclude.has(str(piece["id"])):
			continue
		if not (controller.document.is_layer_visible(str(piece["layer"])) if solid_only else is_pickable(piece)):
			continue
		var is_zone := PieceCatalog.kind(type) == "zone"
		var hit := _intersect_piece(piece, origin, end)
		if hit.is_empty():
			continue
		var distance := origin.distance_to(hit["point"])
		# Prefer non-zone pieces when distances tie closely.
		if is_zone:
			distance += 0.25
		if distance < best_distance:
			best_distance = distance
			best = hit
	return best


## Keeps a snapped anchor on the upward face under the cursor. A vertical probe at the new X/Z
## checks nearby support on the same piece, or finds the tread there on a stair run.
func surface_anchor(origin: Vector3, direction: Vector3, grid: float, exclude: Array[String] = []) -> Variant:
	var hit := pick(origin, direction, true, exclude)
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.y <= 0.001:
		return null
	var point: Vector3 = hit["point"]
	var snapped := MapSnapping.snap_position(point, grid)
	if snapped == point:
		return point
	snapped.y -= normal.dot(snapped - point) / normal.y
	var piece := controller.document.get_piece(str(hit["piece_id"]))
	var top := snapped.y
	var bottom := snapped.y
	if PieceCatalog.kind(str(piece["type"])) == "stairs":
		var bounds := MapDocument.piece_aabb(piece)
		top = bounds.end.y
		bottom = bounds.position.y
	var support := _intersect_piece(piece, Vector3(snapped.x, top + SURFACE_PROBE_MARGIN, snapped.z),
		Vector3(snapped.x, bottom - SURFACE_PROBE_MARGIN, snapped.z))
	if support.is_empty() or (support["normal"] as Vector3).y <= 0.001:
		return null
	snapped.y = (support["point"] as Vector3).y
	return snapped


func _intersect_piece(piece: Dictionary, origin: Vector3, end: Vector3) -> Dictionary:
	var kind := PieceCatalog.kind(str(piece["type"]))
	var box := MapDocument.local_box(piece)
	if kind == "zone":
		# Zones are large; only pick their floor so pieces inside stay clickable.
		box.size.y = 0.05
	var xform := MapDocument.piece_transform(piece)
	var inverse := xform.affine_inverse()
	var start := inverse * origin
	var finish := inverse * end
	var intersection: Variant = box.intersects_segment(start, finish)
	if intersection == null:
		return {}
	var point := intersection as Vector3
	var normal := Vector3.UP if start.y > finish.y and is_equal_approx(point.y, box.end.y) else Vector3.ZERO
	if kind in ["surface", "compound", "ramp", "stairs"]:
		var geometry := _pick_mesh(str(piece["id"]), start, finish)
		if geometry.is_empty():
			return {}
		point = geometry["point"]
		normal = geometry["normal"]
	return {"piece_id": piece["id"], "point": xform * point, "normal": xform.basis * normal}


func _pick_mesh(id: String, start: Vector3, end: Vector3) -> Dictionary:
	var node := node_for(id)
	if node == null:
		return {}
	if not node.has_meta(&"pick_faces"):
		# Cache the real geometry behind the broad-phase box. Openings in compound pieces
		# should let a ray through, just like notches in a drawn surface.
		var compound_faces := PackedVector3Array()
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			var visual := child as MeshInstance3D
			var to_piece := node.global_transform.affine_inverse() * visual.global_transform
			for vertex: Vector3 in visual.mesh.get_faces():
				compound_faces.append(to_piece * vertex)
		node.set_meta(&"pick_faces", compound_faces)
	var faces: PackedVector3Array = node.get_meta(&"pick_faces")
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for i: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(start, end, faces[i], faces[i + 1], faces[i + 2])
		if hit == null:
			continue
		var distance := start.distance_squared_to(hit)
		if distance < nearest_distance:
			nearest_distance = distance
			var normal := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).normalized()
			if normal.dot(end - start) > 0.0:
				normal = -normal
			nearest = {"point": hit, "normal": normal}
	return nearest


## IDs of pickable pieces whose centre projects inside the screen rectangle (box select).
func pieces_in_rect(camera: Camera3D, rect: Rect2) -> Array[String]:
	var found: Array[String] = []
	var area := rect.abs()
	for piece: Dictionary in controller.document.pieces:
		if not is_pickable(piece):
			continue
		var centre := MapDocument.piece_transform(piece) * Vector3(0, (piece["size"] as Vector3).y / 2.0, 0)
		if not camera.is_position_behind(centre) and area.has_point(camera.unproject_position(centre)):
			found.append(str(piece["id"]))
	return found


func _rebuild_piece(piece_id: String) -> void:
	if _nodes.has(piece_id):
		_discard(_nodes[piece_id])
		_nodes.erase(piece_id)
	var piece := controller.document.get_piece(piece_id)
	if piece.is_empty():
		return
	var node := MapBuilder.build_piece(piece, MapBuilder.Mode.EDITOR)
	if node == null:
		return
	node.visible = controller.document.is_layer_visible(str(piece["layer"]))
	add_child(node)
	_nodes[piece_id] = node
	if controller.is_selected(piece_id):
		_update_outline()


func _remove_piece(piece_id: String) -> void:
	if _nodes.has(piece_id):
		_discard(_nodes[piece_id])
		_nodes.erase(piece_id)
	_update_outline()


func _apply_layers() -> void:
	for piece: Dictionary in controller.document.pieces:
		var node := node_for(str(piece["id"]))
		if node != null:
			node.visible = controller.document.is_layer_visible(str(piece["layer"]))


func _update_outline() -> void:
	if _outline == null:
		return
	var pieces := controller.selected_pieces() if controller != null else []
	_outline.visible = not pieces.is_empty()
	if pieces.is_empty():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for piece: Dictionary in pieces:
		_add_box_lines(mesh, MapDocument.local_box(piece).grow(0.03), MapDocument.piece_transform(piece))
	mesh.surface_end()
	_outline.mesh = mesh


## Line mesh of an AABB's 12 edges.
static func wire_box(aabb: AABB) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_box_lines(mesh, aabb, Transform3D.IDENTITY)
	mesh.surface_end()
	return mesh


static func _add_box_lines(mesh: ImmediateMesh, aabb: AABB, xform: Transform3D) -> void:
	var corners: Array[Vector3] = []
	for i: int in 8:
		corners.append(xform * aabb.get_endpoint(i))
	# AABB endpoint index bits: bit0 = +z, bit1 = +y, bit2 = +x; edges join indices one bit apart.
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
		Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	for edge: Vector2i in edges:
		mesh.surface_add_vertex(corners[edge.x])
		mesh.surface_add_vertex(corners[edge.y])


func _discard(node: Node3D) -> void:
	remove_child(node)
	node.queue_free()
