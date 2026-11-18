class_name MapDocument
extends RefCounted
## A map: metadata plus a list of placed pieces. Pure data, serialised as versioned JSON.
##
## A piece is a Dictionary:
##   {"id": "pc_12", "type": "wall", "position": Vector3, "rotation_y": float degrees [0, 360),
##    "size": Vector3, "props": {...type-specific}, "material": palette id or "",
##    "layer": editor layer id, "group": group id or ""}
## Piece IDs are stable within a document and never reused. Callout areas, tactical anchors and
## AI hints are pieces, so their piece ID is the stable ID tactics and AI refer to.
##
## Format history:
##   v1  pieces with 90° rotations.
##   v2  free yaw, per-piece material/layer/group, lighting, editor layers, saved prefabs and a
##       content version. v1 files load with defaults for everything new (see [method from_dict]).

const FORMAT: String = "f2f.map"
const FORMAT_VERSION: int = 2
const ROTATION_STEP: int = 90
const DEFAULT_LAYER: String = "layer_default"
## Props that do not change how a map plays (excluded from the content fingerprint).
const COSMETIC_KINDS: Array[String] = ["light"]

var map_id: String = ""
var name: String = "Untitled map"
var author: String = ""
var description: String = ""
## Save counter of this map, incremented on each save.
var revision: int = 0
## Incremented by MapStorage only when a save changes gameplay content (see
## [method content_fingerprint]). Tactics record the content version they were authored on.
var content_version: int = 0
var content_hash: String = ""
var pieces: Array[Dictionary] = []
## Sun and ambient settings (see MapLighting). Empty = the runtime's default lighting.
var lighting: Dictionary = {}
## Editor-only layers: [{"id", "name", "visible", "locked"}]. The runtime ignores them.
var layers: Array[Dictionary] = [{"id": DEFAULT_LAYER, "name": "Default", "visible": true, "locked": false}]
## Saved prefabs: [{"id": "pf_1", "name", "pieces": [piece dictionaries relative to a pivot]}].
var prefabs: Array[Dictionary] = []
var _next_piece_number: int = 1
var _next_group_number: int = 1
var _next_prefab_number: int = 1
var _next_layer_number: int = 1


static func create(map_name: String = "Untitled map") -> MapDocument:
	var doc := MapDocument.new()
	doc.map_id = Ids.generate("map")
	doc.name = map_name
	return doc


## Builds a well-formed piece dictionary for [param type] (not yet added to the document).
static func make_piece(type: String, position: Vector3, rotation_y: float = 0.0, size: Vector3 = Vector3.ZERO) -> Dictionary:
	return {
		"id": "",
		"type": type,
		"position": position,
		"rotation_y": normalise_rotation(rotation_y),
		"size": size if size != Vector3.ZERO else PieceCatalog.default_size(type),
		"props": default_props(type),
		"material": "",
		"layer": DEFAULT_LAYER,
		"group": "",
	}


static func normalise_rotation(degrees: float) -> float:
	var value := fposmod(degrees, 360.0)
	return 0.0 if is_equal_approx(value, 360.0) else snappedf(value, 0.001)


static func default_props(type: String) -> Dictionary:
	match type:
		"bombsite":
			return {"site": "A"}
		"buy_zone":
			return {"team": "attack"}
		"callout":
			return {"name": "Callout", "role": ""}
		"spawn_attack":
			return {"team": "attack"}
		"spawn_defence":
			return {"team": "defence"}
		"target_dummy":
			return {"motion": "static"}
		"course_checkpoint":
			return {"order": 1}
		"course_finish":
			return {"par": 30.0}
		"tactical_anchor":
			return {"name": "Anchor", "kind": "default"}
		"ai_cover", "ai_hold", "ai_angle":
			return {"site": ""}
		"light_lamp":
			return {"energy": 1.5, "range": 8.0, "color": "ffd9a0"}
		"light_spot":
			return {"energy": 3.0, "range": 10.0, "color": "fff1d6", "angle": 40.0}
		"doorway":
			return {"opening_width": 1.4, "opening_height": 2.2}
		"double_door":
			return {"opening_width": 2.4, "opening_height": 2.4}
		"arch":
			return {"opening_width": 2.4, "opening_height": 2.2}
		"wall_window":
			return {"opening_width": 1.6, "opening_height": 2.2, "sill_height": 1.0}
	return {}


func allocate_piece_id() -> String:
	var id := "pc_%d" % _next_piece_number
	_next_piece_number += 1
	return id


func allocate_group_id() -> String:
	var id := "grp_%d" % _next_group_number
	_next_group_number += 1
	return id


func allocate_prefab_id() -> String:
	var id := "pf_%d" % _next_prefab_number
	_next_prefab_number += 1
	return id


func allocate_layer_id() -> String:
	var id := "layer_%d" % _next_layer_number
	_next_layer_number += 1
	return id


## Adds a piece (assigning an ID if it has none) at [param index] (-1 = end). Returns its ID.
func add_piece(piece: Dictionary, index: int = -1) -> String:
	var copy := _complete(piece.duplicate(true))
	if str(copy.get("id", "")).is_empty():
		copy["id"] = allocate_piece_id()
	else:
		_reserve_id(str(copy["id"]))
	var group := str(copy["group"])
	if group.begins_with("grp_") and group.substr(4).is_valid_int():
		_next_group_number = maxi(_next_group_number, int(group.substr(4)) + 1)
	if index < 0 or index > pieces.size():
		pieces.append(copy)
	else:
		pieces.insert(index, copy)
	return str(copy["id"])


func remove_piece(piece_id: String) -> Dictionary:
	var index := index_of(piece_id)
	if index < 0:
		return {}
	var removed := pieces[index]
	pieces.remove_at(index)
	return removed


func replace_piece(piece: Dictionary) -> bool:
	var index := index_of(str(piece.get("id", "")))
	if index < 0:
		return false
	pieces[index] = _complete(piece.duplicate(true))
	return true


func index_of(piece_id: String) -> int:
	for i: int in pieces.size():
		if pieces[i]["id"] == piece_id:
			return i
	return -1


func get_piece(piece_id: String) -> Dictionary:
	var index := index_of(piece_id)
	return pieces[index].duplicate(true) if index >= 0 else {}


func pieces_of_type(type: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in pieces:
		if piece["type"] == type:
			list.append(piece)
	return list


func pieces_of_kind(kind: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in pieces:
		if PieceCatalog.kind(str(piece["type"])) == kind:
			list.append(piece)
	return list


func layer(layer_id: String) -> Dictionary:
	for entry: Dictionary in layers:
		if entry["id"] == layer_id:
			return entry
	return {}


func is_layer_visible(layer_id: String) -> bool:
	return bool(layer(layer_id).get("visible", true))


func is_layer_locked(layer_id: String) -> bool:
	return bool(layer(layer_id).get("locked", false))


func prefab(prefab_id: String) -> Dictionary:
	for entry: Dictionary in prefabs:
		if entry["id"] == prefab_id:
			return entry
	return {}


func duplicate_document() -> MapDocument:
	return MapDocument.from_dict(to_dict())


## Local-to-world transform of a piece (origin at its bottom centre).
static func piece_transform(piece: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(piece["rotation_y"]))), piece["position"] as Vector3)


## The piece's box in its own space (bottom-centre origin).
static func local_box(piece: Dictionary) -> AABB:
	var size: Vector3 = piece["size"]
	return AABB(Vector3(-size.x / 2.0, 0.0, -size.z / 2.0), size)


## World-space AABB enclosing a piece (exact for 90° rotations).
static func piece_aabb(piece: Dictionary) -> AABB:
	var size: Vector3 = piece["size"]
	var position: Vector3 = piece["position"]
	var rotation := float(piece["rotation_y"])
	if is_zero_approx(fmod(rotation, 90.0)):
		var footprint := size
		if roundi(rotation) % 180 != 0:
			footprint = Vector3(size.z, size.y, size.x)
		return AABB(position - Vector3(footprint.x / 2.0, 0.0, footprint.z / 2.0), footprint)
	return piece_transform(piece) * local_box(piece)


## True when [param point] lies inside the piece's oriented box, with vertical slack below.
static func piece_contains(piece: Dictionary, point: Vector3, below: float = 0.0) -> bool:
	var local := piece_transform(piece).affine_inverse() * point
	var box := local_box(piece)
	box.position.y -= below
	box.size.y += below
	return box.has_point(local)


## SHA-256 over everything that changes how the map plays: solid geometry and gameplay pieces.
## Names, layers, materials, lights, groups and prefabs are left out, so cosmetic edits never
## invalidate tactics.
func content_fingerprint() -> String:
	var rows: Array[String] = []
	for piece: Dictionary in pieces:
		if PieceCatalog.kind(str(piece["type"])) in COSMETIC_KINDS:
			continue
		var p: Vector3 = piece["position"]
		var s: Vector3 = piece["size"]
		rows.append(JSON.stringify([piece["id"], piece["type"], snappedf(p.x, 0.001), snappedf(p.y, 0.001),
			snappedf(p.z, 0.001), piece["rotation_y"], snappedf(s.x, 0.001), snappedf(s.y, 0.001),
			snappedf(s.z, 0.001), piece.get("props", {})], "", true))
	rows.sort()
	return "\n".join(rows).sha256_text()


# --- serialisation ------------------------------------------------------------------------------

static func piece_to_raw(piece: Dictionary) -> Dictionary:
	var p: Vector3 = piece["position"]
	var s: Vector3 = piece["size"]
	return {
		"id": piece["id"],
		"type": piece["type"],
		"position": [p.x, p.y, p.z],
		"rotation_y": piece["rotation_y"],
		"size": [s.x, s.y, s.z],
		"props": piece.get("props", {}),
		"material": piece.get("material", ""),
		"layer": piece.get("layer", DEFAULT_LAYER),
		"group": piece.get("group", ""),
	}


func to_dict() -> Dictionary:
	var list: Array = []
	for piece: Dictionary in pieces:
		list.append(piece_to_raw(piece))
	var prefab_list: Array = []
	for entry: Dictionary in prefabs:
		var raw_pieces: Array = []
		for piece: Dictionary in entry["pieces"] as Array:
			raw_pieces.append(piece_to_raw(piece))
		prefab_list.append({"id": entry["id"], "name": entry["name"], "pieces": raw_pieces})
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"map_id": map_id,
		"name": name,
		"author": author,
		"description": description,
		"revision": revision,
		"content_version": content_version,
		"content_hash": content_hash,
		"next_piece_number": _next_piece_number,
		"next_group_number": _next_group_number,
		"next_prefab_number": _next_prefab_number,
		"next_layer_number": _next_layer_number,
		"lighting": lighting.duplicate(true),
		"layers": layers.duplicate(true),
		"prefabs": prefab_list,
		"pieces": list,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Parses a document. Returns null if the format/version is unknown or the data is malformed.
## Version 1 documents are migrated in memory: pieces get the default layer, no material and no
## group; lighting, prefabs and the content version start empty.
static func from_dict(data: Dictionary) -> MapDocument:
	if data.get("format", "") != FORMAT:
		return null
	var version := int(data.get("format_version", 0))
	if version < 1 or version > FORMAT_VERSION:
		return null
	var doc := MapDocument.new()
	doc.map_id = str(data.get("map_id", ""))
	if not Ids.is_file_id(doc.map_id):
		return null
	doc.name = str(data.get("name", "Untitled map"))
	doc.author = str(data.get("author", ""))
	doc.description = str(data.get("description", ""))
	doc.revision = int(data.get("revision", 0))
	doc.content_version = int(data.get("content_version", 0))
	doc.content_hash = str(data.get("content_hash", ""))
	doc._next_piece_number = maxi(1, int(data.get("next_piece_number", 1)))
	doc._next_group_number = maxi(1, int(data.get("next_group_number", 1)))
	doc._next_prefab_number = maxi(1, int(data.get("next_prefab_number", 1)))
	doc._next_layer_number = maxi(1, int(data.get("next_layer_number", 1)))
	var raw_lighting: Variant = data.get("lighting", {})
	doc.lighting = (raw_lighting as Dictionary).duplicate(true) if raw_lighting is Dictionary else {}
	if not _read_layers(doc, data.get("layers", null)) or not _read_prefabs(doc, data.get("prefabs", [])):
		return null
	var raw_pieces: Variant = data.get("pieces", [])
	if not raw_pieces is Array:
		return null
	var seen: Dictionary[String, bool] = {}
	for raw: Variant in raw_pieces as Array:
		if not raw is Dictionary:
			return null
		var piece := piece_from_raw(raw as Dictionary)
		if piece.is_empty() or str(piece["id"]).is_empty():
			return null
		var id := str(piece["id"])
		if seen.has(id):
			return null
		seen[id] = true
		if doc.layer(str(piece["layer"])).is_empty():
			piece["layer"] = DEFAULT_LAYER
		doc.add_piece(piece)
	return doc


static func from_json(text: String) -> MapDocument:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data as Dictionary)


static func _read_layers(doc: MapDocument, raw: Variant) -> bool:
	if raw == null:
		return true
	if not raw is Array:
		return false
	var list: Array[Dictionary] = []
	for entry: Variant in raw as Array:
		if not entry is Dictionary or not Ids.is_file_id(str((entry as Dictionary).get("id", ""))):
			return false
		var layer_entry := entry as Dictionary
		list.append({"id": str(layer_entry["id"]), "name": str(layer_entry.get("name", "Layer")),
			"visible": bool(layer_entry.get("visible", true)), "locked": bool(layer_entry.get("locked", false))})
	doc.layers = list
	if doc.layer(DEFAULT_LAYER).is_empty():
		doc.layers.insert(0, {"id": DEFAULT_LAYER, "name": "Default", "visible": true, "locked": false})
	return true


static func _read_prefabs(doc: MapDocument, raw: Variant) -> bool:
	if not raw is Array:
		return false
	for entry: Variant in raw as Array:
		if not entry is Dictionary:
			return false
		var prefab_entry := entry as Dictionary
		var id := str(prefab_entry.get("id", ""))
		var raw_pieces: Variant = prefab_entry.get("pieces", null)
		if not Ids.is_file_id(id) or not raw_pieces is Array or not doc.prefab(id).is_empty():
			return false
		var prefab_pieces: Array[Dictionary] = []
		for raw_piece: Variant in raw_pieces as Array:
			var piece := piece_from_raw(raw_piece as Dictionary) if raw_piece is Dictionary else {}
			if piece.is_empty():
				return false
			prefab_pieces.append(piece)
		doc.prefabs.append({"id": id, "name": str(prefab_entry.get("name", "Prefab")), "pieces": prefab_pieces})
		if id.begins_with("pf_") and id.substr(3).is_valid_int():
			doc._next_prefab_number = maxi(doc._next_prefab_number, int(id.substr(3)) + 1)
	return true


## Parses one stored piece ({} when malformed). Prefab and clipboard pieces may have an empty id.
static func piece_from_raw(raw: Dictionary) -> Dictionary:
	var type := str(raw.get("type", ""))
	if not PieceCatalog.has_type(type):
		return {}
	var position: Variant = _vec3(raw.get("position", null))
	var size: Variant = _vec3(raw.get("size", null))
	var rotation: Variant = raw.get("rotation_y", 0)
	if position == null or size == null or not (rotation is int or rotation is float) or not is_finite(float(rotation)):
		return {}
	var props: Variant = raw.get("props", {})
	return {
		"id": str(raw.get("id", "")),
		"type": type,
		"position": position,
		"rotation_y": normalise_rotation(float(rotation)),
		"size": size,
		"props": (props as Dictionary).duplicate(true) if props is Dictionary else {},
		"material": str(raw.get("material", "")),
		"layer": str(raw.get("layer", DEFAULT_LAYER)),
		"group": str(raw.get("group", "")),
	}


static func _complete(piece: Dictionary) -> Dictionary:
	piece["rotation_y"] = normalise_rotation(float(piece.get("rotation_y", 0.0)))
	if not piece.has("props"):
		piece["props"] = {}
	if not piece.has("material"):
		piece["material"] = ""
	if not piece.has("layer"):
		piece["layer"] = DEFAULT_LAYER
	if not piece.has("group"):
		piece["group"] = ""
	return piece


static func _vec3(value: Variant) -> Variant:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() == 3:
		var a := value as Array
		for component: Variant in a:
			if not (component is int or component is float):
				return null
		var vector := Vector3(float(a[0]), float(a[1]), float(a[2]))
		return vector if vector.is_finite() else null
	return null


func _reserve_id(id: String) -> void:
	if id.begins_with("pc_") and id.substr(3).is_valid_int():
		_next_piece_number = maxi(_next_piece_number, int(id.substr(3)) + 1)
