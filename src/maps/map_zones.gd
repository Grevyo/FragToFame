class_name MapZones
extends RefCounted
## Point-in-zone queries over a map document's gameplay volumes (bombsites, buy zones, callouts).
## Pure data: the runtime asks "is this position inside bombsite A / the defence buy zone?".
## Zones may be rotated to any angle; tests use the zone's own oriented box.

## Extra vertical tolerance so a player standing on a zone's floor counts as inside it.
const FLOOR_TOLERANCE: float = 0.3


## World AABB enclosing the zone, including the floor tolerance.
static func zone_aabb(piece: Dictionary) -> AABB:
	var box := MapDocument.piece_aabb(piece)
	box.position.y -= FLOOR_TOLERANCE
	box.size.y += FLOOR_TOLERANCE
	return box


static func contains(piece: Dictionary, point: Vector3) -> bool:
	return MapDocument.piece_contains(piece, point, FLOOR_TOLERANCE)


## First zone of [param type] containing [param point] (optionally only those whose props match
## [param props_filter]), or an empty Dictionary.
static func zone_at(doc: MapDocument, type: String, point: Vector3, props_filter: Dictionary = {}) -> Dictionary:
	for piece: Dictionary in doc.pieces_of_type(type):
		if not _props_match(piece, props_filter):
			continue
		if contains(piece, point):
			return piece
	return {}


static func is_in_buy_zone(doc: MapDocument, side: String, point: Vector3) -> bool:
	return not zone_at(doc, "buy_zone", point, {"team": side}).is_empty()


## Letter of the bombsite containing [param point] ("A", "B", …) or an empty string.
static func bombsite_at(doc: MapDocument, point: Vector3) -> String:
	var site := zone_at(doc, "bombsite", point)
	return str(site.get("props", {}).get("site", "")) if not site.is_empty() else ""


static func _props_match(piece: Dictionary, filter: Dictionary) -> bool:
	var props: Dictionary = piece.get("props", {})
	for key: Variant in filter:
		if props.get(key) != filter[key]:
			return false
	return true
