class_name TacticDocument
extends RefCounted
## Versioned, map-bound route data shared by the editor and preview.

const FORMAT: String = "f2f.tactic"
const FORMAT_VERSION: int = 1
const SLOT_COUNT: int = 5
const MAX_WAYPOINTS: int = 128
const MAX_NAME_LENGTH: int = 80


class Slot extends RefCounted:
	var has_start: bool = false
	var start: Vector3
	var route: Array[Vector3] = []


var tactic_id: String = ""
var display_name: String = "Untitled tactic"
var map_id: String = ""
var map_revision: int = 0
var map_fingerprint: String = ""
var slots: Array[Slot] = []


static func create(map: MapDocument) -> TacticDocument:
	var tactic := TacticDocument.new()
	tactic.tactic_id = Ids.generate("tactic")
	tactic.map_id = map.map_id
	tactic.map_revision = map.revision
	tactic.map_fingerprint = fingerprint(map)
	for i: int in SLOT_COUNT:
		tactic.slots.append(Slot.new())
	return tactic


static func fingerprint(map: MapDocument) -> String:
	return JSON.stringify(map.to_dict(), "", true, true).sha256_text()


func compatibility_error(map: MapDocument) -> String:
	if map == null:
		return "Open the saved map for this tactic first."
	if map_id != map.map_id:
		return "This tactic belongs to a different map (%s)." % map_id
	if map_revision != map.revision or map_fingerprint != fingerprint(map):
		return "Map revision or content differs from this tactic. Open the matching map revision (%d)." % map_revision
	return ""


func validate() -> String:
	if not Ids.is_file_id(tactic_id) or not Ids.is_file_id(map_id):
		return "The tactic or map ID is invalid."
	if map_revision < 1 or map_fingerprint.length() != 64 or not map_fingerprint.is_valid_hex_number():
		return "The tactic must reference a saved map revision and fingerprint."
	if display_name.strip_edges().is_empty() or display_name.length() > MAX_NAME_LENGTH:
		return "Enter a tactic name of 1 to %d characters." % MAX_NAME_LENGTH
	if slots.size() != SLOT_COUNT:
		return "A tactic needs exactly five player slots."
	for i: int in slots.size():
		var slot := slots[i]
		if slot == null or not slot.has_start or not is_valid_point(slot.start):
			return "Set a valid start position for player %d." % (i + 1)
		if slot.route.size() > MAX_WAYPOINTS or not slot.route.all(is_valid_point):
			return "Player %d has an invalid route (limit %d waypoints)." % [i + 1, MAX_WAYPOINTS]
	return ""


func to_dict() -> Dictionary:
	var players: Array[Dictionary] = []
	for i: int in slots.size():
		var slot := slots[i]
		var waypoints: Array[Array] = []
		for point: Vector3 in slot.route:
			waypoints.append(_coordinates(point))
		players.append({"slot": i + 1, "start": _coordinates(slot.start) if slot.has_start else null,
			"waypoints": waypoints})
	return {
		"format": FORMAT, "format_version": FORMAT_VERSION, "id": tactic_id, "name": display_name,
		"map_id": map_id, "map_revision": map_revision, "map_fingerprint": map_fingerprint,
		"players": players,
	}


static func from_dict(data: Dictionary) -> TacticDocument:
	if data.get("format") != FORMAT or data.get("format_version") != FORMAT_VERSION:
		return null
	for field: String in ["id", "name", "map_id", "map_fingerprint"]:
		if not data.get(field) is String:
			return null
	var revision: Variant = data.get("map_revision")
	if not _is_number(revision) or revision < 1 or revision > 2147483647 or int(revision) != revision:
		return null
	var players: Variant = data.get("players")
	if not players is Array or players.size() != SLOT_COUNT:
		return null
	var tactic := TacticDocument.new()
	tactic.tactic_id = data["id"]
	tactic.display_name = data["name"]
	tactic.map_id = data["map_id"]
	tactic.map_revision = int(revision)
	tactic.map_fingerprint = data["map_fingerprint"]
	for i: int in SLOT_COUNT:
		var entry: Variant = players[i]
		if not entry is Dictionary or entry.get("slot") != i + 1:
			return null
		var start: Variant = _point_from(entry.get("start"))
		var waypoints: Variant = entry.get("waypoints")
		if start == null or not waypoints is Array or waypoints.size() > MAX_WAYPOINTS:
			return null
		var slot := Slot.new()
		slot.has_start = true
		slot.start = start
		for value: Variant in waypoints:
			var point: Variant = _point_from(value)
			if point == null:
				return null
			slot.route.append(point as Vector3)
		tactic.slots.append(slot)
	return tactic if tactic.validate().is_empty() else null


static func is_valid_point(point: Vector3) -> bool:
	var limit := MapValidator.MAX_HALF_EXTENT
	return point.is_finite() and absf(point.x) <= limit and absf(point.y) <= limit and absf(point.z) <= limit


static func _point_from(value: Variant) -> Variant:
	if not value is Array or value.size() != 3 or not value.all(_is_number):
		return null
	var point := Vector3(float(value[0]), float(value[1]), float(value[2]))
	return point if is_valid_point(point) else null


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _coordinates(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]
