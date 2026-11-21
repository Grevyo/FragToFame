class_name MapAnalysis
extends RefCounted
## Navigation analysis of a map document: bakes the same navmesh bots use (NavigationBuilder)
## and answers what the structural MapValidator cannot — reachability, unreachable islands,
## routes people can take but bots cannot, and route timings.
##
## Usage: [code]var analysis := MapAnalysis.analyse(doc, any_node_in_the_tree)[/code]. The map is
## built under the host only for the duration of the call. The analysis owns a private
## navigation map (never the scene's), freed with the object.
##
## Findings are dictionaries {"code", "text", "position"}; all are warnings. Codes:
##   "no_navmesh"            nothing walkable was baked
##   "spawn_off_navmesh"     a spawn is not on walkable ground
##   "unreachable_objective" a team's spawn cannot reach a bombsite or its buy zone
##   "island"                playable floor with no route from any spawn
##   "bot_unpathable"        playable floor people reach by jumping or crouching, but bots cannot

const POINT_TOLERANCE: float = 1.0
## Smaller pockets (between props, behind pillars) are ignored.
const MIN_ISLAND_AREA: float = 1.5
## The "human" agent used to find jump/crouch-only routes: crouched height, and a climb just
## under it (a standing jump clears 1.39 m; Recast needs climb below the agent height).
const HUMAN_HEIGHT: float = CombatantMovementBody.CROUCH_HEIGHT
const HUMAN_CLIMB: float = 1.1
const OVERLAY_REACHABLE: Color = Color(0.2, 0.85, 0.45, 0.35)
const OVERLAY_ISLAND: Color = Color(0.95, 0.3, 0.25, 0.5)

var document: MapDocument
var navmesh: NavigationMesh
var issues: Array[Dictionary] = []
## Route timings: {"label", "group", "length_min", "length_max", "seconds", "seconds_rifle"}
## (lengths in metres over the shortest path; -1 when there is no route).
var timings: Array[Dictionary] = []
var _site_setup_lines: Array[String] = []
var bake_msec: int = 0

var _map: RID
var _region: RID
var _human_map: RID
var _human_region: RID
var _vertices: PackedVector3Array
var _polygons: Array[PackedInt32Array] = []
var _component: PackedInt32Array
var _component_area: PackedFloat32Array
var _reachable: Dictionary[int, bool] = {}


static func analyse(doc: MapDocument, host: Node) -> MapAnalysis:
	var analysis := MapAnalysis.new()
	analysis._run(doc, host)
	return analysis


## Structural validation plus navigation findings and route timings:
## {"errors", "warnings", "timings", "timing_text", "analysis"}. Navigation is skipped (analysis
## null) when the structure already has errors.
static func full_validation(doc: MapDocument, host: Node) -> Dictionary:
	var report := MapValidator.validate(doc)
	var errors: Array[String] = report["errors"]
	var warnings: Array[String] = report["warnings"]
	var analysis: MapAnalysis = null
	if errors.is_empty() and host != null and host.is_inside_tree():
		analysis = analyse(doc, host)
		for issue: Dictionary in analysis.issues:
			warnings.append(str(issue["text"]))
	return {
		"errors": errors, "warnings": warnings,
		"timings": analysis.timings if analysis != null else [],
		"timing_text": analysis.timing_text() if analysis != null else "",
		"analysis": analysis,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid: RID in [_region, _human_region, _map, _human_map]:
			if rid.is_valid():
				NavigationServer3D.free_rid(rid)


func has_issue(code: String) -> bool:
	return issues.any(func(issue: Dictionary) -> bool: return issue["code"] == code)


func issues_with(code: String) -> Array[Dictionary]:
	return issues.filter(func(issue: Dictionary) -> bool: return issue["code"] == code)


func polygon_count() -> int:
	return _polygons.size()


## Closest point on the bot navmesh, or null when [param point] is further than [param tolerance].
func nav_point(point: Vector3, tolerance: float = POINT_TOLERANCE) -> Variant:
	if _polygons.is_empty():
		return null
	var closest := NavigationServer3D.map_get_closest_point(_map, point)
	return closest if closest.distance_to(point) <= tolerance else null


## True when bots can stand at [param point] and walk there from a spawn.
func is_reachable(point: Vector3, tolerance: float = POINT_TOLERANCE) -> bool:
	return _reachable.has(_component_at(point, tolerance))


## Shortest bot path between two points in metres, or -1 when there is none.
func path_length(from: Vector3, to: Vector3) -> float:
	var a: Variant = nav_point(from)
	var b: Variant = nav_point(to)
	if a == null or b == null:
		return -1.0
	if _component_at(from, POINT_TOLERANCE) != _component_at(to, POINT_TOLERANCE):
		return -1.0
	return NavigationBuilder.path_length(_map, a as Vector3, b as Vector3, POINT_TOLERANCE)


## The shortest bot path between two points (empty when there is none).
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if path_length(from, to) < 0.0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(_map, nav_point(from) as Vector3, nav_point(to) as Vector3, true)


## A timing entry by label, optionally within one group ("Attackers from spawn",
## "Defenders from spawn", "Rotations", "Crossings"). {} when there is none.
func timing(label: String, group: String = "") -> Dictionary:
	for entry: Dictionary in timings:
		if entry["label"] == label and (group.is_empty() or entry["group"] == group):
			return entry
	return {}


## The readout shown in the editor and appended to validation output.
func timing_text() -> String:
	if timings.is_empty():
		return "No route timings: place spawns, bombsites and callout areas with a timing role."
	var lines: Array[String] = ["Route timings (shortest path; G17 %.2f m/s, AK-47 %.2f m/s)" % [
		MapSnapping.RUN_SPEED, MapSnapping.RUN_SPEED * MapSnapping.RIFLE_MOBILITY]]
	lines.append_array(_site_setup_lines)
	var group := ""
	for entry: Dictionary in timings:
		if entry["group"] != group:
			group = str(entry["group"])
			lines.append("%s:" % group)
		if float(entry["length_min"]) < 0.0:
			lines.append("  %s — no route" % entry["label"])
			continue
		var spread := "" if is_equal_approx(float(entry["length_min"]), float(entry["length_max"])) \
			else "  (spawns %.1f–%.1f m)" % [float(entry["length_min"]), float(entry["length_max"])]
		lines.append("  %s — %.1f m · %.1f s · AK-47 %.1f s%s" % [entry["label"], float(entry["length_min"]),
			float(entry["seconds"]), float(entry["seconds_rifle"]), spread])
	return "\n".join(lines)


## Translucent mesh of the navmesh for the editor overlay: green where bots can go from a
## spawn, red for islands.
func overlay_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _polygons.is_empty():
		return mesh
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var lift := Vector3(0, 0.06, 0)
	for i: int in _polygons.size():
		var polygon := _polygons[i]
		var color := OVERLAY_REACHABLE if _reachable.has(_component[i]) or _reachable.is_empty() else OVERLAY_ISLAND
		for j: int in range(1, polygon.size() - 1):
			for index: int in [polygon[0], polygon[j], polygon[j + 1]]:
				points.append(_vertices[index] + lift)
				colors.append(color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


# --- analysis -----------------------------------------------------------------------------------

func _run(doc: MapDocument, host: Node) -> void:
	document = doc
	var started := Time.get_ticks_msec()
	var built := MapBuilder.build(doc, MapBuilder.Mode.RUNTIME)
	host.add_child(built)
	navmesh = NavigationBuilder.bake_mesh(built)
	_vertices = navmesh.get_vertices()
	for i: int in navmesh.get_polygon_count():
		_polygons.append(navmesh.get_polygon(i))
	if _polygons.is_empty():
		issues.append({"code": "no_navmesh", "text": "No walkable navigation could be baked for this map.", "position": Vector3.ZERO})
	else:
		var made := _make_map(navmesh)
		_map = made[0]
		_region = made[1]
		_find_components()
		_check_slopes()
		_check_objectives()
		var candidates := _island_candidates()
		if not candidates.is_empty():
			var human := NavigationBuilder.bake_mesh(built, HUMAN_HEIGHT, HUMAN_CLIMB)
			var human_made := _make_map(human)
			_human_map = human_made[0]
			_human_region = human_made[1]
			_classify_islands(candidates)
		_measure_routes()
	host.remove_child(built)
	built.free()
	bake_msec = Time.get_ticks_msec() - started


static func _make_map(mesh: NavigationMesh) -> Array[RID]:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, NavigationBuilder.CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, NavigationBuilder.CELL_HEIGHT)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.map_force_update(map)
	return [map, region]


## Groups polygons that share an edge into connected components and sums their areas.
func _find_components() -> void:
	var count := _polygons.size()
	var parent := PackedInt32Array()
	parent.resize(count)
	for i: int in count:
		parent[i] = i
	var edge_owner: Dictionary[String, int] = {}
	for i: int in count:
		var polygon := _polygons[i]
		for j: int in polygon.size():
			var a := _vertex_key(_vertices[polygon[j]])
			var b := _vertex_key(_vertices[polygon[(j + 1) % polygon.size()]])
			var key := a + "|" + b if a < b else b + "|" + a
			if edge_owner.has(key):
				_union(parent, i, edge_owner[key])
			else:
				edge_owner[key] = i
	_component.resize(count)
	var areas: Dictionary[int, float] = {}
	for i: int in count:
		var root := _find(parent, i)
		_component[i] = root
		areas[root] = areas.get(root, 0.0) + _polygon_area(i)
	_component_area.resize(count)
	for root: int in areas:
		_component_area[root] = areas[root]


static func _vertex_key(vertex: Vector3) -> String:
	return "%d,%d,%d" % [roundi(vertex.x * 100.0), roundi(vertex.y * 100.0), roundi(vertex.z * 100.0)]


static func _find(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var root_a := _find(parent, a)
	var root_b := _find(parent, b)
	if root_a != root_b:
		parent[root_a] = root_b


func _polygon_area(index: int) -> float:
	var polygon := _polygons[index]
	var area := 0.0
	for j: int in range(1, polygon.size() - 1):
		area += (_vertices[polygon[j]] - _vertices[polygon[0]]).cross(_vertices[polygon[j + 1]] - _vertices[polygon[0]]).length() / 2.0
	return area


func _polygon_centre(index: int) -> Vector3:
	var polygon := _polygons[index]
	var sum := Vector3.ZERO
	for vertex: int in polygon:
		sum += _vertices[vertex]
	return sum / float(polygon.size())


## Component of the polygon under [param point] (-1 when the point is off the navmesh).
func _component_at(point: Vector3, tolerance: float) -> int:
	var closest: Variant = nav_point(point, tolerance)
	if closest == null:
		return -1
	var target := closest as Vector3
	var best := -1
	var best_distance := INF
	for i: int in _polygons.size():
		var polygon := _polygons[i]
		var flat := PackedVector2Array()
		var height := 0.0
		for vertex: int in polygon:
			flat.append(Vector2(_vertices[vertex].x, _vertices[vertex].z))
			height += _vertices[vertex].y
		height /= float(polygon.size())
		var distance := absf(height - target.y)
		if not Geometry2D.is_point_in_polygon(Vector2(target.x, target.z), flat):
			distance += _polygon_centre(i).distance_to(target) + 0.5
		if distance < best_distance:
			best_distance = distance
			best = i
	return _component[best] if best >= 0 else -1


func _spawns(team: String) -> Array[Vector3]:
	var list: Array[Vector3] = []
	for spawn: Array in MapBuilder.spawn_points(document, team):
		list.append(spawn[0] as Vector3)
	return list


## Floor sample points of a zone (centre first), in world space.
static func _zone_points(piece: Dictionary) -> Array[Vector3]:
	var size: Vector3 = piece["size"]
	var transform := MapDocument.piece_transform(piece)
	var list: Array[Vector3] = []
	for fx: float in [0.0, -0.35, 0.35]:
		for fz: float in [0.0, -0.35, 0.35]:
			list.append(transform * Vector3(size.x * fx, 0.1, size.z * fz))
	return list


## First sample of the zone that lies on the navmesh (null when none does).
func _zone_nav_point(piece: Dictionary) -> Variant:
	for point: Vector3 in _zone_points(piece):
		var found: Variant = nav_point(point)
		if found != null:
			return found
	return null


func _zone_components(piece: Dictionary) -> Dictionary[int, bool]:
	var found: Dictionary[int, bool] = {}
	for point: Vector3 in _zone_points(piece):
		var component := _component_at(point, POINT_TOLERANCE)
		if component >= 0:
			found[component] = true
	return found


## Steepest stair or ramp the bot navmesh can follow. Along a slope the floor rises
## tan(angle) x cell size per cell, and a step higher than the bots' climb limit splits the
## navmesh; the margin covers rasterisation noise.
static func bot_slope_limit() -> float:
	return rad_to_deg(atan(NavigationBuilder.AGENT_MAX_CLIMB / NavigationBuilder.CELL_SIZE)) - 2.5


func _check_slopes() -> void:
	for piece: Dictionary in document.pieces:
		if PieceCatalog.kind(str(piece["type"])) not in ["stairs", "ramp"]:
			continue
		var size: Vector3 = piece["size"]
		var angle := rad_to_deg(atan2(size.y, size.z))
		if angle > bot_slope_limit():
			issues.append({"code": "steep_slope", "position": piece["position"],
				"text": "%s %s is %.0f° steep; bots can only follow %.0f° (lengthen it to %.1f m)." % [
					PieceCatalog.label(str(piece["type"])), piece["id"], angle, bot_slope_limit(),
					size.y / tan(deg_to_rad(bot_slope_limit()))]})


func _check_objectives() -> void:
	var targets: Array[Array] = []  # [label, piece, team filter]
	for site: Dictionary in document.pieces_of_type("bombsite"):
		targets.append(["bombsite %s" % site.get("props", {}).get("site", "?"), site, ""])
	for zone: Dictionary in document.pieces_of_type("buy_zone"):
		var team := str(zone.get("props", {}).get("team", ""))
		targets.append(["the %s buy zone" % team, zone, ""])
	for team: String in ["attack", "defence"]:
		var team_label := "Attacker" if team == "attack" else "Defender"
		var components: Array[int] = []
		var spawns := _spawns(team)
		for i: int in spawns.size():
			var component := _component_at(spawns[i], POINT_TOLERANCE)
			components.append(component)
			if component < 0:
				issues.append({"code": "spawn_off_navmesh", "position": spawns[i],
					"text": "%s spawn %d is not on walkable ground." % [team_label, i + 1]})
			else:
				_reachable[component] = true
		for target: Array in targets:
			var zone_components := _zone_components(target[1] as Dictionary)
			var blocked: Array[String] = []
			for i: int in components.size():
				if components[i] >= 0 and not zone_components.has(components[i]):
					blocked.append(str(i + 1))
			if not blocked.is_empty():
				issues.append({"code": "unreachable_objective", "position": (target[1] as Dictionary)["position"],
					"text": "%s spawn%s %s cannot reach %s." % [team_label, "" if blocked.size() == 1 else "s",
						", ".join(blocked), target[0]]})


## Components bots cannot reach from a spawn that are big enough and rest on playable floor.
func _island_candidates() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if _reachable.is_empty():
		return found
	var largest: Dictionary[int, int] = {}
	for i: int in _polygons.size():
		var component := _component[i]
		if _reachable.has(component) or _component_area[component] < MIN_ISLAND_AREA:
			continue
		if not largest.has(component) or _polygon_area(i) > _polygon_area(largest[component]):
			largest[component] = i
	for component: int in largest:
		var centre := _polygon_centre(largest[component])
		if _inside_solid_piece(centre):
			continue
		if PieceCatalog.is_walkable(str(_support_piece(centre).get("type", ""))):
			found.append({"component": component, "position": centre, "area": _component_area[component]})
	return found


## The face-based bake can leave sealed navmesh pockets inside solids over a floor.
func _inside_solid_piece(point: Vector3) -> bool:
	var probe := point + Vector3(0, 0.5, 0)
	for piece: Dictionary in document.pieces:
		var type := str(piece["type"])
		var kind := PieceCatalog.kind(type)
		if kind not in ["block", "ramp", "stairs", "compound", "surface"] or not MapDocument.piece_contains(piece, probe):
			continue
		var local := MapDocument.piece_transform(piece).affine_inverse() * probe
		var size: Vector3 = piece["size"]
		match kind:
			"block":
				return true
			"ramp", "stairs":
				# Both use a solid wedge that is tallest at the local -Z edge.
				if local.y < size.y * (0.5 - local.z / size.z):
					return true
			"compound":
				for part: Dictionary in PieceShapes.parts(type, size, piece["props"]):
					if _part_contains(part, local):
						return true
			"surface":
				if type == "mesh_brush" and _inside_brush(size, piece["props"], local):
					return true
	return false


## True when [param point] (brush-local) is enclosed by the brush: a ray from it crosses the
## brush's faces an odd number of times. Open brushes (a single sheet) rarely enclose anything.
static func _inside_brush(size: Vector3, props: Dictionary, point: Vector3) -> bool:
	var points := BrushGeometry.local_points(size, props)
	var faces: Variant = props.get("faces")
	if points.is_empty() or not faces is Array:
		return false
	# Slightly off vertical so the ray never runs exactly along a shared edge.
	var direction := Vector3(0.0123, 1.0, 0.0071).normalized()
	var crossings := 0
	for i: int in range(0, (faces as Array).size() - 2, 3):
		var a := points[int(faces[i])]
		var b := points[int(faces[i + 1])]
		var c := points[int(faces[i + 2])]
		if Geometry3D.ray_intersects_triangle(point, direction, a, b, c) != null:
			crossings += 1
	return crossings % 2 == 1


static func _part_contains(part: Dictionary, point: Vector3) -> bool:
	var angles: Vector3 = part["rot"]
	var rotation := Basis.from_euler(angles * (PI / 180.0))
	var local := rotation.inverse() * (point - (part["pos"] as Vector3))
	var size: Vector3 = part["size"]
	var half := size / 2.0
	if absf(local.y) >= half.y:
		return false
	if part["shape"] == "cylinder":
		var scale := lerpf(float(part.get("bottom_radius_scale", 1.0)), float(part.get("top_radius_scale", 1.0)),
			(local.y + half.y) / size.y)
		return Vector2(local.x, local.z).length_squared() < pow(half.x * scale, 2.0)
	return absf(local.x) < half.x and absf(local.z) < half.z


## The solid piece a navmesh point rests on ({} when none is found).
func _support_piece(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_top := -INF
	for piece: Dictionary in document.pieces:
		var type := str(piece["type"])
		if not PieceCatalog.is_solid(type):
			continue
		var top := (piece["position"] as Vector3).y + (piece["size"] as Vector3).y
		var sloped := PieceCatalog.kind(type) in ["ramp", "stairs"]
		var supports := MapDocument.piece_contains(piece, point + Vector3(0, -0.1, 0), 0.2) if sloped \
			else absf(top - point.y) <= 0.35 and MapDocument.piece_contains(piece, Vector3(point.x, top - 0.01, point.z))
		if supports and top > best_top:
			best = piece
			best_top = top
	return best


func _classify_islands(candidates: Array[Dictionary]) -> void:
	var home := Vector3.ZERO
	for team: String in ["attack", "defence"]:
		for spawn: Vector3 in _spawns(team):
			if _reachable.has(_component_at(spawn, POINT_TOLERANCE)):
				home = spawn
	var human_home := NavigationServer3D.map_get_closest_point(_human_map, home)
	for island: Dictionary in candidates:
		var position: Vector3 = island["position"]
		var where := MapTactical.area_name_at(document, position)
		if where.is_empty():
			where = "x %.0f, z %.0f" % [position.x, position.z]
		var human_point := NavigationServer3D.map_get_closest_point(_human_map, position)
		var by_person := human_point.distance_to(position) <= POINT_TOLERANCE \
			and NavigationBuilder.path_length(_human_map, human_home, human_point, POINT_TOLERANCE) >= 0.0
		if by_person:
			issues.append({"code": "bot_unpathable", "position": position,
				"text": "The floor at %s (%.0f m²) needs a jump or crouch that bots cannot path (bot climb limit %.1f m, height %.1f m)." % [
					where, float(island["area"]), NavigationBuilder.AGENT_MAX_CLIMB, NavigationBuilder.AGENT_HEIGHT]})
		else:
			issues.append({"code": "island", "position": position,
				"text": "Unreachable floor at %s (%.0f m²): no route from any spawn." % [where, float(island["area"])]})


func _measure_routes() -> void:
	var targets: Array[Array] = []  # [label, nav point]
	var entrances: Dictionary[String, Array] = {"entrance_a": [], "entrance_b": []}
	for role: String in ["entrance_a", "entrance_b", "mid"]:
		for area: Dictionary in MapTactical.areas_with_role(document, role):
			var point: Variant = _zone_nav_point(area)
			var suffix := "mid" if role == "mid" else "entrance %s" % role.right(1).to_upper()
			var label := "%s (%s)" % [str(area.get("props", {}).get("name", "Area")), suffix]
			targets.append([label, point])
			if entrances.has(role):
				entrances[role].append([label, point])
	var sites: Dictionary[String, Variant] = {}
	var elevations: Dictionary[String, float] = {}
	for site: Dictionary in document.pieces_of_type("bombsite"):
		var letter := str(site.get("props", {}).get("site", "?"))
		sites[letter] = _zone_nav_point(site)
		elevations[letter] = (site["position"] as Vector3).y
		targets.append(["Site %s" % letter, sites[letter]])
	for team: String in ["attack", "defence"]:
		var spawns := _spawns(team)
		if spawns.is_empty():
			continue
		var group := "Attackers from spawn" if team == "attack" else "Defenders from spawn"
		for target: Array in targets:
			var lengths: Array[float] = []
			for spawn: Vector3 in spawns:
				lengths.append(path_length(spawn, target[1] as Vector3) if target[1] != null else -1.0)
			_add_timing(group, str(target[0]), lengths)
	_site_setup_lines.clear()
	for role: String in entrances:
		var letter := role.right(1).to_upper()
		var defender := timing("Site %s" % letter, "Defenders from spawn")
		if defender.is_empty() or float(defender["seconds"]) < 0:
			continue
		var earliest := INF
		var door := ""
		for entrance: Array in entrances[role]:
			var attacker := timing(str(entrance[0]), "Attackers from spawn")
			var arrival := float(attacker.get("seconds", -1))
			if arrival >= 0 and arrival < earliest:
				earliest = arrival
				door = str(entrance[0])
		if not door.is_empty():
			var lead := earliest - float(defender["seconds"])
			_site_setup_lines.append("Site %s (elevation %+.1f m): fastest defender arrives %.1f s %s first attacker at %s (G17)." % [
				letter, elevations[letter], absf(lead), "before" if lead >= 0 else "after", door])
	var letters := sites.keys()
	letters.sort()
	for i: int in letters.size():
		for j: int in range(i + 1, letters.size()):
			var a: Variant = sites[letters[i]]
			var b: Variant = sites[letters[j]]
			_add_timing("Rotations", "Site %s ↔ Site %s" % [letters[i], letters[j]],
				[path_length(a as Vector3, b as Vector3) if a != null and b != null else -1.0])
	for a: Array in entrances["entrance_a"]:
		for b: Array in entrances["entrance_b"]:
			_add_timing("Crossings", "%s ↔ %s" % [a[0], b[0]],
				[path_length(a[1] as Vector3, b[1] as Vector3) if a[1] != null and b[1] != null else -1.0])


func _add_timing(group: String, label: String, lengths: Array[float]) -> void:
	var valid := lengths.filter(func(length: float) -> bool: return length >= 0.0)
	var shortest := -1.0
	var longest := -1.0
	if not valid.is_empty():
		shortest = valid.min()
		longest = valid.max()
	timings.append({
		"group": group, "label": label, "length_min": shortest, "length_max": longest,
		"seconds": shortest / MapSnapping.RUN_SPEED if shortest >= 0.0 else -1.0,
		"seconds_rifle": shortest / (MapSnapping.RUN_SPEED * MapSnapping.RIFLE_MOBILITY) if shortest >= 0.0 else -1.0,
	})
