class_name MapEditorView
extends Node3D
## 3D view of the document being edited. Mirrors MapEditController signals into nodes built by
## MapBuilder (EDITOR mode), draws the selection outline and answers picking queries.

const PICK_DISTANCE: float = 2000.0
const OUTLINE_COLOR: Color = Color(1.0, 0.75, 0.2)

var controller: MapEditController

var _nodes: Dictionary[String, Node3D] = {}
var _outline: MeshInstance3D


func _ready() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "SelectionOutline"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = OUTLINE_COLOR
	material.no_depth_test = true
	_outline.material_override = material
	_outline.visible = false
	add_child(_outline)


func bind(edit_controller: MapEditController) -> void:
	controller = edit_controller
	controller.document_replaced.connect(rebuild_all)
	controller.piece_added.connect(_rebuild_piece)
	controller.piece_changed.connect(_rebuild_piece)
	controller.piece_removed.connect(_remove_piece)
	controller.selection_changed.connect(func(_id: String) -> void: _update_outline())
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


## Nearest piece hit by the ray, or {} — returns {"piece_id", "point", "aabb"}.
## [param solid_only] ignores markers and zones (used for stacking placement).
func pick(origin: Vector3, direction: Vector3, solid_only: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var end := origin + direction * PICK_DISTANCE
	for piece: Dictionary in controller.document.pieces:
		var type := str(piece["type"])
		if solid_only and not PieceCatalog.is_solid(type):
			continue
		var aabb := MapDocument.piece_aabb(piece)
		if PieceCatalog.kind(type) == "zone" and not solid_only:
			# Zones are large; only pick them by their floor so pieces inside stay clickable.
			aabb = AABB(aabb.position, Vector3(aabb.size.x, 0.05, aabb.size.z))
		var hit: Variant = aabb.intersects_segment(origin, end)
		if hit == null:
			continue
		var distance := origin.distance_to(hit as Vector3)
		# Prefer non-zone pieces when distances tie closely.
		if PieceCatalog.kind(type) == "zone":
			distance += 0.25
		if distance < best_distance:
			best_distance = distance
			best = {"piece_id": piece["id"], "point": hit, "aabb": MapDocument.piece_aabb(piece)}
	return best


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
	add_child(node)
	_nodes[piece_id] = node
	if piece_id == controller.selected_id:
		_update_outline()


func _remove_piece(piece_id: String) -> void:
	if _nodes.has(piece_id):
		_discard(_nodes[piece_id])
		_nodes.erase(piece_id)
	_update_outline()


func _update_outline() -> void:
	if _outline == null:
		return
	var piece := controller.selected_piece() if controller != null else {}
	if piece.is_empty():
		_outline.visible = false
		return
	_outline.mesh = wire_box(MapDocument.piece_aabb(piece).grow(0.03))
	_outline.visible = true


## Line mesh of an AABB's 12 edges.
static func wire_box(aabb: AABB) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = []
	for i: int in 8:
		corners.append(aabb.get_endpoint(i))
	# AABB endpoint index bits: bit0 = +z, bit1 = +y, bit2 = +x; edges join indices one bit apart.
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
		Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	for edge: Vector2i in edges:
		mesh.surface_add_vertex(corners[edge.x])
		mesh.surface_add_vertex(corners[edge.y])
	mesh.surface_end()
	return mesh


func _discard(node: Node3D) -> void:
	remove_child(node)
	node.queue_free()
