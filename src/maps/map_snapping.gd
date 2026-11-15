class_name MapSnapping
extends RefCounted
## Pure geometry helpers for the editor: grid and angle snapping, snap-to-surface, snap-to-edge,
## group transforms and measuring. No nodes, so every editing rule is testable headlessly.

const EDGE_THRESHOLD: float = 0.35
## Measured run speeds used by the measuring tool and the route timing readout.
const RUN_SPEED: float = 6.35
const RIFLE_MOBILITY: float = 0.86


static func snap_position(position: Vector3, grid: float) -> Vector3:
	return Vector3(snappedf(position.x, grid), position.y, snappedf(position.z, grid)) if grid > 0.0 else position


static func snap_angle(degrees: float, step: float) -> float:
	return MapDocument.normalise_rotation(snappedf(degrees, step) if step > 0.0 else degrees)


## World box around [param pieces] (zero-size AABB at the origin when empty).
static func bounds(pieces: Array[Dictionary]) -> AABB:
	var box := AABB()
	var first := true
	for piece: Dictionary in pieces:
		var piece_box := MapDocument.piece_aabb(piece)
		box = piece_box if first else box.merge(piece_box)
		first = false
	return box


## Bottom centre of the pieces' bounds, on a 0.25 m grid so pasted groups stay grid-aligned.
static func pivot(pieces: Array[Dictionary]) -> Vector3:
	var box := bounds(pieces)
	var centre := box.get_center()
	return Vector3(snappedf(centre.x, 0.25), box.position.y, snappedf(centre.z, 0.25))


static func moved(pieces: Array[Dictionary], offset: Vector3) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in pieces:
		var copy := piece.duplicate(true)
		copy["position"] = (copy["position"] as Vector3) + offset
		list.append(copy)
	return list


## Rotates pieces as a rigid group around a vertical axis through [param centre].
static func rotated(pieces: Array[Dictionary], centre: Vector3, degrees: float) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for piece: Dictionary in pieces:
		var copy := piece.duplicate(true)
		var offset := (copy["position"] as Vector3) - centre
		var turned := offset.rotated(Vector3.UP, deg_to_rad(degrees))
		copy["position"] = centre + Vector3(snappedf(turned.x, 0.001), offset.y, snappedf(turned.z, 0.001))
		copy["rotation_y"] = MapDocument.normalise_rotation(float(copy["rotation_y"]) + degrees)
		list.append(copy)
	return list


## Copies of [param pieces] positioned relative to [param origin], without IDs (clipboard/prefab form).
static func relative_to(pieces: Array[Dictionary], origin: Vector3) -> Array[Dictionary]:
	var list := moved(pieces, -origin)
	for piece: Dictionary in list:
		piece["id"] = ""
	return list


## Top of the highest solid piece under (x, z) that is not in [param exclude]; [param fallback]
## when nothing is there. Ramps and stairs report their full height.
static func surface_height(doc: MapDocument, x: float, z: float, exclude: Array[String], fallback: float) -> float:
	var best := -INF
	for piece: Dictionary in doc.pieces:
		if exclude.has(str(piece["id"])) or not PieceCatalog.is_solid(str(piece["type"])):
			continue
		var top := (piece["position"] as Vector3).y + (piece["size"] as Vector3).y
		if top > best and MapDocument.piece_contains(piece, Vector3(x, top - 0.01, z)):
			best = top
	return best if best > -INF else fallback


## Offset that brings a face of [param box] flush with the nearest parallel face of another solid
## piece within [param threshold] (X and Z independently). Zero when nothing is close.
static func edge_offset(doc: MapDocument, box: AABB, exclude: Array[String], threshold: float = EDGE_THRESHOLD) -> Vector3:
	var offset := Vector3.ZERO
	var best_x := threshold
	var best_z := threshold
	for piece: Dictionary in doc.pieces:
		if exclude.has(str(piece["id"])) or not PieceCatalog.is_solid(str(piece["type"])):
			continue
		var other := MapDocument.piece_aabb(piece)
		if other.position.y > box.end.y + 0.01 or other.end.y < box.position.y - 0.01:
			continue
		if box.position.z < other.end.z + threshold and box.end.z > other.position.z - threshold:
			for mine: float in [box.position.x, box.end.x]:
				for theirs: float in [other.position.x, other.end.x]:
					if absf(theirs - mine) < best_x:
						best_x = absf(theirs - mine)
						offset.x = theirs - mine
		if box.position.x < other.end.x + threshold and box.end.x > other.position.x - threshold:
			for mine: float in [box.position.z, box.end.z]:
				for theirs: float in [other.position.z, other.end.z]:
					if absf(theirs - mine) < best_z:
						best_z = absf(theirs - mine)
						offset.z = theirs - mine
	return offset


## Distance readout between two points: straight line, horizontal run, height change and the
## time to run the horizontal distance with a pistol/SMG and with the rifle.
static func measure(from: Vector3, to: Vector3) -> Dictionary:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return {
		"distance": from.distance_to(to),
		"horizontal": flat,
		"height": to.y - from.y,
		"seconds": flat / RUN_SPEED,
		"seconds_rifle": flat / (RUN_SPEED * RIFLE_MOBILITY),
	}


static func measure_text(result: Dictionary) -> String:
	return "%.2f m  ·  flat %.2f m  ·  height %+.2f m  ·  %.1f s run (%.1f s rifle)" % [
		float(result["distance"]), float(result["horizontal"]), float(result["height"]),
		float(result["seconds"]), float(result["seconds_rifle"])]
