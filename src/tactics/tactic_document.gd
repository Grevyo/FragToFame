class_name TacticDocument
extends RefCounted
## Versioned, map-bound route data shared by the editor and preview.
##
## Format history:
##   v1  five slots of start + waypoints, bound to one exact map revision and fingerprint.
##   v2  records the map's content version, and each start/waypoint may reference the callout
##       area it lies in and the tactical anchor it was snapped to (by stable piece ID).
##       v1 files load unchanged with no references and content version 0 ("unknown"), which
##       makes the editor run a compatibility check instead of refusing the tactic.

const FORMAT: String = "f2f.tactic"
const FORMAT_VERSION: int = 2
const SLOT_COUNT: int = 5
const MAX_WAYPOINTS: int = 128
const MAX_NAME_LENGTH: int = 80


class Slot extends RefCounted:
	var has_start: bool = false
	var start: Vector3
	var start_area: String = ""
	var start_anchor: String = ""
	var route: Array[Vector3] = []
	## Parallel to [member route]: callout area ID and tactical anchor ID per waypoint ("" = none).
	var route_areas: Array[String] = []
	var route_anchors: Array[String] = []

	func set_start(point: Vector3, area: String = "", anchor: String = "") -> void:
		start = point
		start_area = area
		start_anchor = anchor
		has_start = true

	func add_waypoint(point: Vector3, area: String = "", anchor: String = "") -> void:
		_pad()
		route.append(point)
		route_areas.append(area)
		route_anchors.append(anchor)

	func set_waypoint(index: int, point: Vector3, area: String = "", anchor: String = "") -> void:
		_pad()
		route[index] = point
		route_areas[index] = area
		route_anchors[index] = anchor

	func remove_waypoint(index: int) -> void:
		_pad()
		route.remove_at(index)
		route_areas.remove_at(index)
		route_anchors.remove_at(index)

	func area_of(index: int) -> String:
		return route_areas[index] if index < route_areas.size() else ""

	func anchor_of(index: int) -> String:
		return route_anchors[index] if index < route_anchors.size() else ""

	## Keeps the reference arrays as long as the route (callers may edit [member route] directly).
	func _pad() -> void:
		route_areas.resize(route.size())
		route_anchors.resize(route.size())


var tactic_id: String = ""
var display_name: String = "Untitled tactic"
var map_id: String = ""
var map_revision: int = 0
## The map content version this tactic was last saved against (0 = unknown, from a v1 file).
var map_content_version: int = 0
var map_fingerprint: String = ""
var slots: Array[Slot] = []


static func create(map: MapDocument) -> TacticDocument:
	var tactic := TacticDocument.new()
	tactic.tactic_id = Ids.generate("tactic")
	tactic.map_id = map.map_id
	tactic.stamp(map)
	for i: int in SLOT_COUNT:
		tactic.slots.append(Slot.new())
	return tactic


## Fingerprint of the map's gameplay content (cosmetic map edits do not change it).
static func fingerprint(map: MapDocument) -> String:
	return map.content_fingerprint()


## Records that this tactic now matches [param map] as it is. Called when the user saves.
func stamp(map: MapDocument) -> void:
	map_revision = map.revision
	map_content_version = map.content_version
	map_fingerprint = fingerprint(map)


## True when the map's gameplay content is exactly what this tactic was saved against.
func is_current(map: MapDocument) -> bool:
	return map != null and map_id == map.map_id and map_fingerprint == fingerprint(map)


## Hard incompatibility only: no map, or a different map. A changed map is not an error — see
## TacticCompatibility for the warnings it produces.
func compatibility_error(map: MapDocument) -> String:
	if map == null:
		return "Open the saved map for this tactic first."
	if map_id != map.map_id:
		return "This tactic belongs to a different map (%s)." % map_id
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
		var refs: Array[Dictionary] = []
		for j: int in slot.route.size():
			waypoints.append(_coordinates(slot.route[j]))
			refs.append({"area": slot.area_of(j), "anchor": slot.anchor_of(j)})
		players.append({"slot": i + 1, "start": _coordinates(slot.start) if slot.has_start else null,
			"start_area": slot.start_area, "start_anchor": slot.start_anchor,
			"waypoints": waypoints, "waypoint_refs": refs})
	return {
		"format": FORMAT, "format_version": FORMAT_VERSION, "id": tactic_id, "name": display_name,
		"map_id": map_id, "map_revision": map_revision, "map_content_version": map_content_version,
		"map_fingerprint": map_fingerprint, "players": players,
	}


static func from_dict(data: Dictionary) -> TacticDocument:
	var version: Variant = data.get("format_version")
	if data.get("format") != FORMAT or not _is_number(version) or version < 1 or version > FORMAT_VERSION \
			or int(version) != version:
		return null
	for field: String in ["id", "name", "map_id", "map_fingerprint"]:
		if not data.get(field) is String:
			return null
	var revision: Variant = data.get("map_revision")
	if not _is_number(revision) or revision < 1 or revision > 2147483647 or int(revision) != revision:
		return null
	var content_version: Variant = data.get("map_content_version", 0)
	if not _is_number(content_version) or content_version < 0:
		return null
	var players: Variant = data.get("players")
	if not players is Array or players.size() != SLOT_COUNT:
		return null
	var tactic := TacticDocument.new()
	tactic.tactic_id = data["id"]
	tactic.display_name = data["name"]
	tactic.map_id = data["map_id"]
	tactic.map_revision = int(revision)
	tactic.map_content_version = int(content_version)
	tactic.map_fingerprint = data["map_fingerprint"]
	for i: int in SLOT_COUNT:
		var entry: Variant = players[i]
		if not entry is Dictionary or entry.get("slot") != i + 1:
			return null
		var start: Variant = _point_from(entry.get("start"))
		var waypoints: Variant = entry.get("waypoints")
		var refs: Variant = entry.get("waypoint_refs", [])
		if start == null or not waypoints is Array or waypoints.size() > MAX_WAYPOINTS or not refs is Array:
			return null
		var slot := Slot.new()
		slot.set_start(start as Vector3, str(entry.get("start_area", "")), str(entry.get("start_anchor", "")))
		for j: int in (waypoints as Array).size():
			var point: Variant = _point_from(waypoints[j])
			if point == null:
				return null
			var ref: Variant = refs[j] if j < (refs as Array).size() else {}
			if not ref is Dictionary:
				return null
			slot.add_waypoint(point as Vector3, str((ref as Dictionary).get("area", "")), str((ref as Dictionary).get("anchor", "")))
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
