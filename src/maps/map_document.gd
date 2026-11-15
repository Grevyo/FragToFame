class_name MapDocument
extends RefCounted
## A map: metadata plus a list of placed pieces. Pure data, serialised as versioned JSON.
##
## A piece is a Dictionary:
##   {"id": "pc_12", "type": "wall", "position": Vector3, "rotation_y": 0..270 (step 90),
##    "size": Vector3, "props": {...type-specific, e.g. "site": "A", "team": "attack", "name": "Long"}}
## Piece IDs are stable within a document and never reused.

const FORMAT: String = "f2f.map"
const FORMAT_VERSION: int = 1
const ROTATION_STEP: int = 90

var map_id: String = ""
var name: String = "Untitled map"
var author: String = ""
var description: String = ""
## Content revision of this map, incremented on each save.
var revision: int = 0
var pieces: Array[Dictionary] = []
var _next_piece_number: int = 1


static func create(map_name: String = "Untitled map") -> MapDocument:
	var doc := MapDocument.new()
	doc.map_id = Ids.generate("map")
	doc.name = map_name
	return doc


## Builds a well-formed piece dictionary for [param type] (not yet added to the document).
static func make_piece(type: String, position: Vector3, rotation_y: int = 0, size: Vector3 = Vector3.ZERO) -> Dictionary:
	return {
		"id": "",
		"type": type,
		"position": position,
		"rotation_y": posmod(rotation_y, 360),
		"size": size if size != Vector3.ZERO else PieceCatalog.default_size(type),
		"props": default_props(type),
	}


static func default_props(type: String) -> Dictionary:
	match type:
		"bombsite":
			return {"site": "A"}
		"buy_zone":
			return {"team": "attack"}
		"callout":
			return {"name": "Callout"}
		"spawn_attack":
			return {"team": "attack"}
		"spawn_defence":
			return {"team": "defence"}
		"target_dummy":
			return {"motion": "static"}
	return {}


func allocate_piece_id() -> String:
	var id := "pc_%d" % _next_piece_number
	_next_piece_number += 1
	return id


## Adds a piece (assigning an ID if it has none) at [param index] (-1 = end). Returns its ID.
func add_piece(piece: Dictionary, index: int = -1) -> String:
	var copy := piece.duplicate(true)
	if str(copy.get("id", "")).is_empty():
		copy["id"] = allocate_piece_id()
	else:
		_reserve_id(str(copy["id"]))
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
	pieces[index] = piece.duplicate(true)
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


func duplicate_document() -> MapDocument:
	return MapDocument.from_dict(to_dict())


## World-space AABB of a piece (exact for 90° rotations).
static func piece_aabb(piece: Dictionary) -> AABB:
	var size: Vector3 = piece["size"]
	var footprint := size
	if int(piece["rotation_y"]) % 180 != 0:
		footprint = Vector3(size.z, size.y, size.x)
	var position: Vector3 = piece["position"]
	return AABB(position - Vector3(footprint.x / 2.0, 0.0, footprint.z / 2.0), footprint)


# --- serialisation ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for piece: Dictionary in pieces:
		var p: Vector3 = piece["position"]
		var s: Vector3 = piece["size"]
		list.append({
			"id": piece["id"],
			"type": piece["type"],
			"position": [p.x, p.y, p.z],
			"rotation_y": piece["rotation_y"],
			"size": [s.x, s.y, s.z],
			"props": piece.get("props", {}),
		})
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"map_id": map_id,
		"name": name,
		"author": author,
		"description": description,
		"revision": revision,
		"next_piece_number": _next_piece_number,
		"pieces": list,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Parses a document. Returns null if the format/version is unknown or the data is malformed.
static func from_dict(data: Dictionary) -> MapDocument:
	if data.get("format", "") != FORMAT:
		return null
	var version := int(data.get("format_version", 0))
	if version < 1 or version > FORMAT_VERSION:
		return null
	var doc := MapDocument.new()
	doc.map_id = str(data.get("map_id", ""))
	if doc.map_id.is_empty():
		return null
	doc.name = str(data.get("name", "Untitled map"))
	doc.author = str(data.get("author", ""))
	doc.description = str(data.get("description", ""))
	doc.revision = int(data.get("revision", 0))
	doc._next_piece_number = maxi(1, int(data.get("next_piece_number", 1)))
	var raw_pieces: Variant = data.get("pieces", [])
	if not raw_pieces is Array:
		return null
	for raw: Variant in raw_pieces as Array:
		if not raw is Dictionary:
			return null
		var piece := _piece_from_raw(raw as Dictionary)
		if piece.is_empty():
			return null
		doc.add_piece(piece)
	return doc


static func from_json(text: String) -> MapDocument:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data as Dictionary)


static func _piece_from_raw(raw: Dictionary) -> Dictionary:
	var type := str(raw.get("type", ""))
	var id := str(raw.get("id", ""))
	if id.is_empty() or not PieceCatalog.has_type(type):
		return {}
	var position: Variant = _vec3(raw.get("position", null))
	var size: Variant = _vec3(raw.get("size", null))
	if position == null or size == null:
		return {}
	var props: Variant = raw.get("props", {})
	return {
		"id": id,
		"type": type,
		"position": position,
		"rotation_y": posmod(int(raw.get("rotation_y", 0)), 360),
		"size": size,
		"props": (props as Dictionary).duplicate(true) if props is Dictionary else {},
	}


static func _vec3(value: Variant) -> Variant:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() == 3:
		var a := value as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return null


func _reserve_id(id: String) -> void:
	if id.begins_with("pc_") and id.substr(3).is_valid_int():
		_next_piece_number = maxi(_next_piece_number, int(id.substr(3)) + 1)
