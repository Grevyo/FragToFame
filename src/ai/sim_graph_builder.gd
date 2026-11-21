class_name SimGraphBuilder
extends RefCounted
## Bakes a map's simulation graph: the pure data the career match engine plays rounds on
## ([SimMap] reads it). Built from the same navmesh bots use (via [MapAnalysis]), so every map
## made in the editor can be baked the same way.
##
## Nodes are the map's places: each bombsite ("site_A", "site_B"), each callout area and each
## team's spawn. Two nodes are neighbours when the shortest walk between them passes from one
## straight into the other (stretches of floor outside every zone are crossed, not counted).
## Every pair of nodes also gets its shortest walking distance in metres.
##
## Output (JSON-ready):
##   {"format": "f2f.sim_map", "format_version": 1, "map_id", "map_name", "content_hash",
##    "nodes": [{"id", "kind": "spawn"|"site"|"area", "name", "role", "site", "side",
##               "centre": [x, y, z], "floor": m²}],
##    "edges": [[a, b, metres]], "distances": {a: {b: metres}},
##    "routes": {spawn or site id: {id: [places walked through, in order]}}}

const FORMAT: String = "f2f.sim_map"
const FORMAT_VERSION: int = 1
## Path points are checked this often (metres) when finding which zones a walk passes through.
const SAMPLE_STEP: float = 0.75
## Places count as neighbours when at most this much unnamed floor (metres) lies between them.
const GAP_LIMIT: float = 6.0


## Builds the graph for [param doc] (the map is built under [param host] while baking).
## Returns {} when the map has no navmesh.
static func build(doc: MapDocument, host: Node) -> Dictionary:
	var analysis := MapAnalysis.analyse(doc, host)
	if analysis.polygon_count() == 0:
		return {}
	var nodes := _nodes(doc, analysis)
	var ids: Array[String] = []
	for node: Dictionary in nodes:
		ids.append(str(node["id"]))
	var distances: Dictionary = {}
	var routes: Dictionary = {}
	var edges: Dictionary[String, float] = {}
	for i: int in nodes.size():
		var row: Dictionary = {}
		distances[ids[i]] = row
		for j: int in nodes.size():
			if i == j:
				row[ids[j]] = 0.0
				continue
			var path := _path(analysis, nodes[i]["point"] as Vector3, nodes[j]["point"] as Vector3)
			if path.is_empty():
				row[ids[j]] = -1.0
				continue
			row[ids[j]] = snappedf(_length(path), 0.1)
			var walked := _add_edges(doc, path, ids[i], ids[j], nodes, edges)
			if nodes[i]["kind"] != "area":
				if not routes.has(ids[i]):
					routes[ids[i]] = {}
				routes[ids[i]][ids[j]] = walked
	var edge_list: Array = []
	for key: String in _direct_edges(edges, ids):
		var pair := key.split("|")
		# An edge's length is the walk between the two places' measuring points.
		var metres := float((distances[pair[0]] as Dictionary)[pair[1]])
		if metres >= 0.0:
			edge_list.append([pair[0], pair[1], metres])
	var out_nodes: Array = []
	for node: Dictionary in nodes:
		var clean := node.duplicate()
		var point: Vector3 = clean["point"]
		clean.erase("point")
		clean["centre"] = [snappedf(point.x, 0.01), snappedf(point.y, 0.01), snappedf(point.z, 0.01)]
		out_nodes.append(clean)
	return {"format": FORMAT, "format_version": FORMAT_VERSION, "map_id": doc.map_id, "map_name": doc.name,
		"content_hash": doc.content_hash, "nodes": out_nodes, "edges": edge_list, "distances": distances,
		"routes": routes}


## Spawns, sites and callout areas, each with a point on the navmesh to measure from.
static func _nodes(doc: MapDocument, analysis: MapAnalysis) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for side: String in ["attack", "defence"]:
		var points := MapBuilder.spawn_points(doc, side)
		if points.is_empty():
			continue
		var centre := Vector3.ZERO
		for spawn: Array in points:
			centre += spawn[0] as Vector3
		centre /= points.size()
		var on_mesh: Variant = analysis.nav_point(centre, 4.0)
		nodes.append({"id": "spawn_" + side, "kind": "spawn", "name": "%s spawn" % side.capitalize(), "role": "",
			"site": "", "side": side, "point": on_mesh if on_mesh != null else centre, "floor": 0.0})
	for piece: Dictionary in doc.pieces_of_type("bombsite"):
		var letter := str(piece.get("props", {}).get("site", ""))
		var point: Variant = _zone_point(piece, analysis)
		if letter.is_empty() or point == null:
			continue
		nodes.append({"id": "site_" + letter, "kind": "site", "name": "Site " + letter, "role": "", "site": letter,
			"side": "", "point": point, "floor": _floor(piece)})
	for piece: Dictionary in MapTactical.areas(doc):
		var point: Variant = _zone_point(piece, analysis)
		if point == null:
			continue
		var props: Dictionary = piece.get("props", {})
		nodes.append({"id": str(piece["id"]), "kind": "area", "name": str(props.get("name", piece["id"])),
			"role": str(props.get("role", "")), "site": MapZones.bombsite_at(doc, point as Vector3), "side": "",
			"point": point, "floor": _floor(piece)})
	return nodes


## A point in the zone on floor bots can walk to from a spawn (centre first, then a 5 x 5 grid
## across the zone); null when the zone has no reachable floor (such zones are left out).
static func _zone_point(piece: Dictionary, analysis: MapAnalysis) -> Variant:
	var size: Vector3 = piece["size"]
	var transform := MapDocument.piece_transform(piece)
	var samples: Array[Vector3] = [transform * Vector3(0, 0.1, 0)]
	for fx: float in [-0.4, -0.2, 0.0, 0.2, 0.4]:
		for fz: float in [-0.4, -0.2, 0.0, 0.2, 0.4]:
			samples.append(transform * Vector3(size.x * fx, 0.1, size.z * fz))
	for point: Vector3 in samples:
		var found: Variant = analysis.nav_point(point)
		if found != null and analysis.is_reachable(found as Vector3):
			return found
	return null


static func _floor(piece: Dictionary) -> float:
	var size: Vector3 = piece["size"]
	return snappedf(size.x * size.z, 0.1)


static func _path(analysis: MapAnalysis, from: Vector3, to: Vector3) -> PackedVector3Array:
	return analysis.path(from, to)


static func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## The node a point belongs to: a bombsite first, then the smallest callout area ("" outside all).
static func _node_at(doc: MapDocument, point: Vector3, nodes: Array[Dictionary]) -> String:
	var letter := MapZones.bombsite_at(doc, point)
	if not letter.is_empty():
		return "site_" + letter
	var area := MapTactical.area_id_at(doc, point)
	if not area.is_empty():
		return area
	for node: Dictionary in nodes:
		if node["kind"] == "spawn" and (node["point"] as Vector3).distance_to(point) < 4.0:
			return str(node["id"])
	return ""


## Walks the path and records each step from one place into the next as a candidate edge, with
## the metres of unnamed floor crossed between them (the smallest seen over all walks). Returns
## the places walked through, in order.
static func _add_edges(doc: MapDocument, path: PackedVector3Array, from_id: String, to_id: String, nodes: Array[Dictionary],
		edges: Dictionary[String, float]) -> Array[String]:
	var known: Dictionary[String, bool] = {}
	for node: Dictionary in nodes:
		known[str(node["id"])] = true
	var current := from_id
	var walked: Array[String] = [from_id]
	var gap := 0.0
	for i: int in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var steps := maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP))
		var step_length := a.distance_to(b) / steps
		for s: int in steps:
			var here := _node_at(doc, a.lerp(b, float(s + 1) / steps), nodes)
			if not known.has(here):
				gap += step_length
				continue
			if here != current:
				_note_edge(edges, current, here, gap)
				current = here
				walked.append(here)
			gap = 0.0
	if current != to_id:
		_note_edge(edges, current, to_id, gap)
		walked.append(to_id)
	return walked


static func _note_edge(edges: Dictionary[String, float], a: String, b: String, gap: float) -> void:
	var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
	edges[key] = minf(float(edges.get(key, INF)), gap)


## Neighbours are places stepped between directly (at most [constant GAP_LIMIT] of unnamed floor
## between them). Longer crossings are added back, shortest first, only where they are needed to
## keep every place reachable.
static func _direct_edges(edges: Dictionary[String, float], ids: Array[String]) -> Array[String]:
	var parent: Dictionary[String, String] = {}
	for id: String in ids:
		parent[id] = id
	var find := func(start: String) -> String:
		var here := start
		while parent[here] != here:
			here = parent[here]
		return here
	var ordered: Array = edges.keys()
	ordered.sort_custom(func(x: String, y: String) -> bool: return edges[x] < edges[y] or (edges[x] == edges[y] and x < y))
	var kept: Array[String] = []
	for key: String in ordered:
		var pair := key.split("|")
		var a: String = find.call(pair[0])
		var b: String = find.call(pair[1])
		if edges[key] <= GAP_LIMIT or a != b:
			kept.append(key)
			parent[a] = b
	kept.sort()
	return kept
