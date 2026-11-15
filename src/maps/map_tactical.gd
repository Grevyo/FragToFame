class_name MapTactical
extends RefCounted
## Queries over a map's tactical pieces: named callout areas, tactical anchors and AI hints.
## Their piece ID is the stable ID that tactics and team AI refer to (never raw coordinates).
##
## Readers today: the editor and Tactical Play Creator (areas, anchors as snap targets), the FPS
## HUD (current area name), TacticCompatibility (missing areas/anchors), MapAnalysis (timing
## targets from area roles) and BotSquad (defenders hold "ai_hold" points and face along them).
## "ai_cover" and "ai_angle" points are stored and queryable for the M7 team AI.

const AREA_ROLES: Array[String] = ["", "mid", "entrance_a", "entrance_b"]
const ANCHOR_KINDS: Array[String] = ["plant", "default", "utility"]
const HINT_TYPES: Array[String] = ["ai_cover", "ai_hold", "ai_angle"]
const ANCHOR_SNAP_RADIUS: float = 1.0


static func areas(doc: MapDocument) -> Array[Dictionary]:
	return doc.pieces_of_type("callout")


## The smallest callout area containing [param point] ({} when outside every area).
static func area_at(doc: MapDocument, point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_size := INF
	for piece: Dictionary in areas(doc):
		var size: Vector3 = piece["size"]
		if size.x * size.z < best_size and MapDocument.piece_contains(piece, point, MapZones.FLOOR_TOLERANCE):
			best = piece
			best_size = size.x * size.z
	return best


static func area_id_at(doc: MapDocument, point: Vector3) -> String:
	return str(area_at(doc, point).get("id", ""))


## Display name of the area containing [param point] ("" when outside every area).
static func area_name_at(doc: MapDocument, point: Vector3) -> String:
	return str(area_at(doc, point).get("props", {}).get("name", ""))


static func area_name(doc: MapDocument, area_id: String) -> String:
	var piece := doc.get_piece(area_id)
	return str(piece.get("props", {}).get("name", "")) if piece.get("type", "") == "callout" else ""


static func areas_with_role(doc: MapDocument, role: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in areas(doc):
		if str(piece.get("props", {}).get("role", "")) == role:
			list.append(piece)
	return list


static func anchors(doc: MapDocument, kind: String = "") -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in doc.pieces_of_type("tactical_anchor"):
		if kind.is_empty() or str(piece.get("props", {}).get("kind", "")) == kind:
			list.append(piece)
	return list


## Nearest anchor within [param radius] (horizontal) of [param point], or {}.
static func anchor_near(doc: MapDocument, point: Vector3, radius: float = ANCHOR_SNAP_RADIUS) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	for piece: Dictionary in doc.pieces_of_type("tactical_anchor"):
		var position: Vector3 = piece["position"]
		var distance := Vector2(position.x - point.x, position.z - point.z).length()
		if distance <= best_distance and absf(position.y - point.y) < 1.5:
			best = piece
			best_distance = distance
	return best


static func anchor_label(piece: Dictionary) -> String:
	var props: Dictionary = piece.get("props", {})
	return "%s (%s)" % [str(props.get("name", "Anchor")), str(props.get("kind", "default"))]


## AI hint pieces of [param type], optionally only those assigned to bombsite [param site].
static func hints(doc: MapDocument, type: String, site: String = "") -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in doc.pieces_of_type(type):
		if site.is_empty() or str(piece.get("props", {}).get("site", "")) == site:
			list.append(piece)
	return list


## Point a hint looks at: [param distance] metres along its facing (-Z), at eye height.
static func hint_watch_point(piece: Dictionary, distance: float = 14.0) -> Vector3:
	var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(float(piece["rotation_y"])))
	return (piece["position"] as Vector3) + forward * distance + Vector3(0, 1.5, 0)
