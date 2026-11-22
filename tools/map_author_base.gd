extends SceneTree
## Shared steps for the official map authoring sessions (tools/author_*.gd).
##
## Like tools/author_kilnmarket.gd, this is NOT a generator. It opens the shipped Creation
## Studio scene and performs the operations a person performs there: choose a palette piece,
## place it, edit it in the inspector, use layers and lighting, validate and save with the
## editor's Save. The last step copies the saved file into res://data/maps/official under the
## official map ID. A subclass implements [method _build] with explicit coordinates.

const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"

var studio: Node
var controller: MapEditController


## Override: the official map ID, its staging folder and the map itself.
func _official_id() -> String:
	return ""


func _build() -> void:
	pass


## Override: bump when a published map changes (the revision and content version it ships as).
func _revision() -> int:
	return 1


## Override for map-specific checks after validation (return false to fail the session).
func _check(_analysis: MapAnalysis) -> bool:
	return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var staging := "user://authoring/%s" % _official_id()
	studio = (load(STUDIO) as PackedScene).instantiate()
	root.add_child(studio)
	await process_frame
	await process_frame
	studio.set("storage", MapStorage.new(staging))
	studio.set("autosave", MapAutosave.new(staging.path_join("autosave")))
	studio.set("tactic_storage", TacticStorage.new(staging.path_join("tactics")))
	controller = studio.get("controller") as MapEditController
	(studio.get("ui") as StudioUI).confirm_dialog.hide()
	studio.call("load_template", "blank")
	studio.call("select_all")
	controller.delete_selection()

	_build()

	var report: Dictionary = studio.call("validation_report")
	var analysis := studio.get("analysis") as MapAnalysis
	print("\n== %s: %d pieces ==" % [controller.document.name, controller.document.pieces.size()])
	for error: String in report["errors"]:
		print("ERROR: ", error)
	for warning: String in report["warnings"]:
		print("Warning: ", warning)
	if analysis != null:
		for issue: Dictionary in analysis.issues:
			print("Navigation issue at ", issue["position"], ": ", issue["code"])
		print(report["timing_text"])
		print("navmesh: %d polygons, analysis %d ms" % [analysis.polygon_count(), analysis.bake_msec])
	var ok := (report["errors"] as Array).is_empty() and analysis != null and _check(analysis)
	var err: Error = studio.call("save_map")
	print("save: ", error_string(err), "  ->  ", studio.get("current_path"))
	if err == OK and ok and not OS.get_cmdline_user_args().has("--dry-run"):
		_publish(str(studio.get("current_path")), staging)
	studio.queue_free()
	await process_frame
	quit(0 if err == OK and ok else 1)


## Publishing step: the saved file is copied to the official folder under the official map ID.
func _publish(saved_path: String, staging: String) -> void:
	var doc := MapStorage.new(staging).load_path(saved_path)
	doc.map_id = _official_id()
	doc.revision = _revision()
	doc.content_version = _revision()
	doc.content_hash = doc.content_fingerprint()
	DirAccess.make_dir_recursive_absolute(OfficialMaps.DIRECTORY)
	var file := FileAccess.open(OfficialMaps.path_for(_official_id()), FileAccess.WRITE)
	file.store_string(doc.to_json() + "\n")
	file.close()
	print("published: ", OfficialMaps.path_for(_official_id()))


# --- editor operations --------------------------------------------------------------------------

func layer(layer_name: String) -> void:
	for entry: Dictionary in controller.document.layers:
		if entry["name"] == layer_name:
			studio.set("active_layer", entry["id"])
			return
	studio.set("active_layer", controller.add_layer(layer_name))


## Palette → click to place → inspector edits (size, rotation, props, material).
func put(type: String, position: Vector3, size: Vector3 = Vector3.ZERO, rotation: float = 0.0,
		props: Dictionary = {}, material: String = "") -> String:
	studio.call("_on_piece_type_selected", type)
	var id: String = studio.call("place_at", position)
	var piece := controller.document.get_piece(id)
	piece["position"] = position
	if size != Vector3.ZERO:
		piece["size"] = size
	piece["rotation_y"] = rotation
	(piece["props"] as Dictionary).merge(props, true)
	piece["material"] = material
	controller.update_piece(piece, "Edit properties")
	return id


## A box-shaped piece covering x1..x2 by z1..z2 from [param base] up by [param height].
func mass(type: String, x1: float, x2: float, z1: float, z2: float, height: float, material: String = "",
		base: float = 0.0) -> String:
	return put(type, Vector3((x1 + x2) / 2.0, base, (z1 + z2) / 2.0), Vector3(x2 - x1, height, z2 - z1), 0.0, {}, material)


## Covers x1..x2 by z1..z2 with slabs, leaving rectangular [param holes] ([x1, x2, z1, z2]) open:
## the cut lines split the rectangle into cells, and each run of solid cells in a band
## becomes one slab.
func slab_with_holes(type: String, x1: float, x2: float, z1: float, z2: float, height: float,
		material: String, base: float, holes: Array) -> void:
	var xs: Array[float] = [x1, x2]
	var zs: Array[float] = [z1, z2]
	for hole: Array in holes:
		xs.append_array([float(hole[0]), float(hole[1])])
		zs.append_array([float(hole[2]), float(hole[3])])
	xs.sort()
	zs.sort()
	for j: int in zs.size() - 1:
		if zs[j + 1] - zs[j] < 0.01:
			continue
		var start := -1.0
		var in_run := false
		for i: int in xs.size() - 1:
			if xs[i + 1] - xs[i] < 0.01:
				continue
			var centre := Vector2((xs[i] + xs[i + 1]) / 2.0, (zs[j] + zs[j + 1]) / 2.0)
			var open := false
			for hole: Array in holes:
				open = open or (centre.x > float(hole[0]) and centre.x < float(hole[1])
					and centre.y > float(hole[2]) and centre.y < float(hole[3]))
			if not open and not in_run:
				start = xs[i]
				in_run = true
			elif open and in_run:
				mass(type, start, xs[i], zs[j], zs[j + 1], height, material, base)
				in_run = false
		if in_run:
			mass(type, start, xs[xs.size() - 1], zs[j], zs[j + 1], height, material, base)


## Draw Surface tool: a solid floor whose top follows [param outline] (Vector2 x/z corners) at
## [param top], [param thickness] deep; then the material is set in the inspector.
func surface(outline: Array, top: float, thickness: float, material: String = "") -> String:
	var points := PackedVector3Array()
	for corner: Vector2 in outline:
		points.append(Vector3(corner.x, top, corner.y))
	var id: String = studio.call("draw_surface", points, thickness)
	if id.is_empty():
		printerr("Draw Surface refused outline ", outline)
		return id
	if not material.is_empty():
		var piece := controller.document.get_piece(id)
		piece["material"] = material
		controller.update_piece(piece, "Edit properties")
	return id


## A floor of any outline with rectangular [param holes] ([x1, x2, z1, z2]) left open. Like
## [method slab_with_holes] it cuts the area into bands at the holes' edges; each solid run of
## a band is clipped to the outline and drawn with the Draw Surface tool.
## [param regions] ([outline, material] pairs, not overlapping) are parts of the same floor in
## another material: they are cut out of the base and drawn level with it, so a dirt yard or a
## flagstone square replaces the base finish instead of sitting on top of it.
func floor_shape(outline: Array, top: float, thickness: float, material: String, holes: Array = [],
		regions: Array = []) -> void:
	var shape := PackedVector2Array(outline)
	var bounds := Rect2(shape[0], Vector2.ZERO)
	for corner: Vector2 in shape:
		bounds = bounds.expand(corner)
	var xs: Array[float] = [bounds.position.x, bounds.end.x]
	var zs: Array[float] = [bounds.position.y, bounds.end.y]
	for hole: Array in holes:
		xs.append_array([float(hole[0]), float(hole[1])])
		zs.append_array([float(hole[2]), float(hole[3])])
	xs.sort()
	zs.sort()
	for j: int in zs.size() - 1:
		if zs[j + 1] - zs[j] < 0.01:
			continue
		var runs: Array[Vector2] = []
		var start := xs[0]
		var in_run := false
		for i: int in xs.size() - 1:
			if xs[i + 1] - xs[i] < 0.01:
				continue
			var centre := Vector2((xs[i] + xs[i + 1]) / 2.0, (zs[j] + zs[j + 1]) / 2.0)
			var open := false
			for hole: Array in holes:
				open = open or (centre.x > float(hole[0]) and centre.x < float(hole[1])
					and centre.y > float(hole[2]) and centre.y < float(hole[3]))
			if not open and not in_run:
				start = xs[i]
				in_run = true
			elif open and in_run:
				runs.append(Vector2(start, xs[i]))
				in_run = false
		if in_run:
			runs.append(Vector2(start, xs[xs.size() - 1]))
		for run: Vector2 in runs:
			var band := PackedVector2Array([Vector2(run.x, zs[j]), Vector2(run.y, zs[j]),
				Vector2(run.y, zs[j + 1]), Vector2(run.x, zs[j + 1])])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, shape):
				_floor_piece(piece, top, thickness, material, regions)


## Draws one band piece of a floor: the parts inside each region in that region's material, the
## rest in [param material]. Regions are applied in order, so an earlier region wins where two
## overlap.
func _floor_piece(piece: PackedVector2Array, top: float, thickness: float, material: String, regions: Array) -> void:
	var rest: Array[PackedVector2Array] = [piece]
	for region: Array in regions:
		var cutter := PackedVector2Array(region[0])
		var remaining: Array[PackedVector2Array] = []
		for part: PackedVector2Array in rest:
			for inside: PackedVector2Array in Geometry2D.intersect_polygons(part, cutter):
				_floor_surface(inside, top, thickness, str(region[1]))
			remaining.append_array(_cut(part, cutter))
		rest = remaining
	for part: PackedVector2Array in rest:
		_floor_surface(part, top, thickness, material)


## [param part] minus [param cutter] as simple polygons. Where the cutter would leave a hole (it
## sits wholly inside the part), the part is first split in two through the cutter.
func _cut(part: PackedVector2Array, cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces := Geometry2D.clip_polygons(part, cutter)
	var result: Array[PackedVector2Array] = []
	if not pieces.any(func(p: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(p)):
		result.assign(pieces)
		return result
	var middle := 0.0
	for corner: Vector2 in cutter:
		middle += corner.x / cutter.size()
	for half: PackedVector2Array in _halves(part, middle):
		result.append_array(_cut(half, cutter))
	return result


## [param polygon] without corners closer than 2 cm to the previous one or lying on a straight
## run (clipping leaves both).
static func _clean(polygon: PackedVector2Array) -> PackedVector2Array:
	var kept := PackedVector2Array()
	for corner: Vector2 in polygon:
		if kept.is_empty() or kept[-1].distance_to(corner) > 0.02:
			kept.append(corner)
	if kept.size() > 1 and kept[0].distance_to(kept[-1]) <= 0.02:
		kept.remove_at(kept.size() - 1)
	var result := PackedVector2Array()
	for i: int in kept.size():
		var before := kept[posmod(i - 1, kept.size())]
		var after := kept[(i + 1) % kept.size()]
		if absf((kept[i] - before).cross(after - kept[i])) > 0.0004:
			result.append(kept[i])
	return result


## [param polygon] cut by the vertical line x = [param at].
func _halves(polygon: PackedVector2Array, at: float) -> Array[PackedVector2Array]:
	var low := INF
	var high := -INF
	for corner: Vector2 in polygon:
		low = minf(low, corner.y)
		high = maxf(high, corner.y)
	var left := PackedVector2Array([Vector2(-1e4, low - 1), Vector2(at, low - 1), Vector2(at, high + 1), Vector2(-1e4, high + 1)])
	var right := PackedVector2Array([Vector2(at, low - 1), Vector2(1e4, low - 1), Vector2(1e4, high + 1), Vector2(at, high + 1)])
	var result: Array[PackedVector2Array] = []
	result.append_array(Geometry2D.intersect_polygons(polygon, left))
	result.append_array(Geometry2D.intersect_polygons(polygon, right))
	return result


## One floor surface; outlines over the Draw Surface point limit are halved until they fit.
func _floor_surface(polygon: PackedVector2Array, top: float, thickness: float, material: String) -> void:
	if absf(_area(polygon)) <= 0.05:
		return
	polygon = _clean(polygon)
	if polygon.size() < 3:
		return
	if polygon.size() <= PolygonSurface.MAX_POINTS:
		var corners := PackedVector3Array()
		for corner: Vector2 in polygon:
			corners.append(Vector3(corner.x, top, corner.y))
		if not PolygonSurface.piece(corners, thickness).is_empty():
			surface(Array(polygon), top, thickness, material)
			return
		# Clipping can leave outlines that touch themselves; convex parts always draw.
		var parts := Geometry2D.decompose_polygon_in_convex(polygon)
		if parts.size() > 1 or (parts.size() == 1 and parts[0].size() != polygon.size()):
			for part: PackedVector2Array in parts:
				_floor_surface(part, top, thickness, material)
			return
		surface(Array(polygon), top, thickness, material)
		return
	var low := INF
	var high := -INF
	for corner: Vector2 in polygon:
		low = minf(low, corner.x)
		high = maxf(high, corner.x)
	for half: PackedVector2Array in _halves(polygon, (low + high) / 2.0):
		_floor_surface(half, top, thickness, material)


## Brush tool: an upright block whose footprint is [param outline] (Vector2 x/z corners).
func prism(outline: Array, base: float, height: float, material: String = "") -> void:
	var shape := PackedVector2Array(outline)
	var count := shape.size()
	var vertices: Array = []
	for level: float in [base, base + height]:
		for corner: Vector2 in shape:
			vertices.append([corner.x, level, corner.y])
	var faces: Array = []
	for index: int in Geometry2D.triangulate_polygon(shape):
		faces.append(index + count)
	for i: int in count:
		var next := (i + 1) % count
		faces.append_array([i, next, next + count, i, next + count, i + count])
	var rows: Array = [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}]
	if (studio.call("draw_brushes", rows) as Array).is_empty():
		printerr("Brush refused outline ", outline)


## A gable roof over x1..x2 by z1..z2 drawn with the brush tool, its ridge along X (or Z).
func gable(x1: float, x2: float, z1: float, z2: float, eave: float, ridge: float, material: String,
		along_x: bool = true) -> void:
	var vertices: Array = [[x1, eave, z1], [x2, eave, z1], [x2, eave, z2], [x1, eave, z2]]
	var faces: Array = [0, 1, 2, 0, 2, 3]
	if along_x:
		var zm := (z1 + z2) / 2.0
		vertices.append_array([[x1, ridge, zm], [x2, ridge, zm]])
		faces.append_array([0, 4, 5, 0, 5, 1, 3, 2, 5, 3, 5, 4, 0, 3, 4, 1, 5, 2])
	else:
		var xm := (x1 + x2) / 2.0
		vertices.append_array([[xm, ridge, z1], [xm, ridge, z2]])
		faces.append_array([0, 4, 5, 0, 5, 3, 1, 2, 5, 1, 5, 4, 0, 1, 4, 3, 5, 2])
	if (studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}]) as Array).is_empty():
		printerr("Brush refused roof ", [x1, x2, z1, z2])


## A hipped roof over x1..x2 by z1..z2 (ridge along X, the ends sloping in as far as the sides).
func hip(x1: float, x2: float, z1: float, z2: float, eave: float, ridge: float, material: String) -> void:
	var zm := (z1 + z2) / 2.0
	var inset := minf((z2 - z1) / 2.0, (x2 - x1) / 2.0 - 0.1)
	var vertices: Array = [[x1, eave, z1], [x2, eave, z1], [x2, eave, z2], [x1, eave, z2],
		[x1 + inset, ridge, zm], [x2 - inset, ridge, zm]]
	var faces: Array = [0, 1, 2, 0, 2, 3, 0, 1, 5, 0, 5, 4, 3, 4, 5, 3, 5, 2, 0, 4, 3, 1, 2, 5]
	if (studio.call("draw_brushes", [{"vertices": vertices, "faces": faces, "two_sided": true, "material": material}]) as Array).is_empty():
		printerr("Brush refused hipped roof ", [x1, x2, z1, z2])


## A straight wall from [param a] to [param b] (x/z), placed and turned in the inspector, with
## [param gaps] ([from, to] metres from [param a]) left open. Ends at corners overlap by half the
## thickness so joined walls close.
func wall_line(a: Vector2, b: Vector2, height: float, base: float, material: String, gaps: Array = [],
		type: String = "wall", thickness: float = 0.6) -> void:
	var length := a.distance_to(b)
	var along := (b - a) / length
	var yaw := rad_to_deg(atan2(-along.y, along.x))
	var cuts: Array[float] = [0.0]
	for gap: Array in gaps:
		cuts.append_array([float(gap[0]), float(gap[1])])
	cuts.append(length)
	for i: int in range(0, cuts.size(), 2):
		var from := cuts[i] - (thickness / 2.0 if i == 0 else 0.0)
		var to := cuts[i + 1] + (thickness / 2.0 if i + 1 == cuts.size() - 1 else 0.0)
		if to - from < 0.05:
			continue
		var centre := a + along * (from + to) / 2.0
		put(type, Vector3(centre.x, base, centre.y), Vector3(to - from, height, thickness), yaw, {}, material)


## Walls round a closed [param outline]; [param gaps] maps an edge index (edge i runs from corner
## i to corner i + 1) to its gaps, and [param skip] lists edges left without a wall.
func walls_around(outline: Array, height: float, base: float, material: String, gaps: Dictionary = {},
		skip: Array = [], type: String = "wall", thickness: float = 0.6) -> void:
	for i: int in outline.size():
		if i in skip:
			continue
		wall_line(outline[i], outline[(i + 1) % outline.size()], height, base, material,
			gaps.get(i, []), type, thickness)


static func _area(shape: PackedVector2Array) -> float:
	var total := 0.0
	for i: int in shape.size():
		var next := shape[(i + 1) % shape.size()]
		total += shape[i].x * next.y - next.x * shape[i].y
	return total / 2.0


func area(area_name: String, x1: float, x2: float, z1: float, z2: float, role: String = "", base: float = 0.0) -> String:
	return put("callout", Vector3((x1 + x2) / 2.0, base, (z1 + z2) / 2.0), Vector3(x2 - x1, 3.0, z2 - z1), 0.0,
		{"name": area_name, "role": role})


func anchor(anchor_name: String, kind: String, position: Vector3) -> String:
	return put("tactical_anchor", position, Vector3.ZERO, 0.0, {"name": anchor_name, "kind": kind})


func hint(type: String, position: Vector3, facing: float, site: String) -> String:
	return put(type, position, Vector3.ZERO, facing, {"site": site})


func lamp(position: Vector3, energy: float = 1.8, light_range: float = 9.0, color: String = "ffd9a0") -> String:
	return put("light_lamp", position, Vector3.ZERO, 0.0, {"energy": energy, "range": light_range, "color": color})


func spot(position: Vector3, energy: float = 4.0, light_range: float = 12.0, angle: float = 55.0,
		color: String = "fff1d6") -> String:
	return put("light_spot", position, Vector3.ZERO, 0.0, {"energy": energy, "range": light_range, "angle": angle, "color": color})


## Five spawns per team in a row along X, and each team's buy zone around them.
func spawns(team: String, centre: Vector3, facing: float, buy_size: Vector3) -> void:
	var type := "spawn_attack" if team == "attack" else "spawn_defence"
	for x: float in [0.0, -2.0, 2.0, -4.0, 4.0]:
		put(type, centre + Vector3(x, 0, 0), Vector3.ZERO, facing)
	put("buy_zone", centre, buy_size, 0.0, {"team": team})


func seconds(analysis: MapAnalysis, label: String, group: String = "") -> float:
	return float(analysis.timing(label, group)["seconds"])


# --- facade dressing ------------------------------------------------------------------------------
# What a person does by hand along every street: walk each wall that faces open, walkable ground
# and dress it with a plinth, a cornice, windows on every storey, now and then a door, lamps and
# whatever the map's own style adds. Every step is an ordinary placed piece.

## Types that hide a wall face when they stand right in front of it.
const DRESS_OCCLUDERS: Array[String] = ["building", "wall", "wall_adobe", "wall_plaster", "wall_stone",
	"wall_battlement", "tower_round", "block", "platform", "roof"]


## Oriented footprint of a piece: centre, half size, yaw (radians), base and top.
func footprint(piece: Dictionary) -> Dictionary:
	var size: Vector3 = piece["size"]
	var position: Vector3 = piece["position"]
	return {"centre": Vector2(position.x, position.z), "half": Vector2(size.x, size.z) / 2.0,
		"yaw": deg_to_rad(float(piece["rotation_y"])), "base": position.y, "top": position.y + size.y,
		"type": str(piece["type"]), "id": str(piece["id"])}


## Whether the x/z point (and height [param y]) lies inside the footprint, grown by [param margin].
static func inside_footprint(fp: Dictionary, point: Vector2, y: float, margin: float = 0.0) -> bool:
	if y < float(fp["base"]) - margin or y > float(fp["top"]) + margin:
		return false
	var d: Vector2 = point - (fp["centre"] as Vector2)
	var yaw := float(fp["yaw"])
	var local := Vector2(d.x * cos(yaw) - d.y * sin(yaw), d.x * sin(yaw) + d.y * cos(yaw))
	var half: Vector2 = fp["half"]
	return absf(local.x) <= half.x + margin and absf(local.y) <= half.y + margin


## World corners of a footprint, in order round the outline.
static func footprint_corners(fp: Dictionary) -> Array[Vector2]:
	var yaw := float(fp["yaw"])
	var half: Vector2 = fp["half"]
	var result: Array[Vector2] = []
	for local: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		result.append((fp["centre"] as Vector2) + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw)))
	return result


## Deterministic small hash for picking variations.
static func pick_at(point: Vector2, salt: int = 0) -> int:
	var h := (int(round(point.x * 10.0)) * 73856093) ^ (int(round(point.y * 10.0)) * 19349663) ^ (salt * 83492791)
	return absi(h) % 100003


## Dresses every exposed face of the pieces of [param types] (see the style keys in
## [method dress_run]). A face is exposed where the ground in front of it is walkable floor inside
## [param region] and nothing solid stands within 1.2 m of it.
func dress_facades(style: Dictionary, region: Rect2, types: Array = ["building"]) -> void:
	var solids: Array[Dictionary] = []
	var occluders: Array[Dictionary] = []
	var floors: Array[Dictionary] = []
	_dress_context(solids, occluders, floors)
	var targets: Array[Dictionary] = []
	for fp: Dictionary in solids:
		if str(fp["type"]) in types:
			targets.append(fp)
	for fp: Dictionary in targets:
		var corners := footprint_corners(fp)
		for i: int in 4:
			var a := corners[i]
			var b := corners[(i + 1) % 4]
			var mid := (a + b) / 2.0
			var facing := (b - a).orthogonal().normalized()
			if facing.dot(mid - (fp["centre"] as Vector2)) < 0.0:
				facing = -facing
			var along := Vector2(facing.y, -facing.x)
			var start := a if (b - a).dot(along) > 0.0 else b
			_dress_face(fp, start, along, facing, a.distance_to(b), style, region, occluders, floors, solids)


## Dresses the outer faces of a brush building drawn from [param outline] (Vector2 x/z corners),
## standing up to [param top].
func dress_outline(outline: Array, top: float, style: Dictionary, region: Rect2) -> void:
	var solids: Array[Dictionary] = []
	var occluders: Array[Dictionary] = []
	var floors: Array[Dictionary] = []
	_dress_context(solids, occluders, floors)
	var centre := Vector2.ZERO
	for corner: Vector2 in outline:
		centre += corner / float(outline.size())
	var fp := {"id": "outline", "top": top}
	for i: int in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var facing := (b - a).orthogonal().normalized()
		if facing.dot((a + b) / 2.0 - centre) < 0.0:
			facing = -facing
		var along := Vector2(facing.y, -facing.x)
		var start := a if (b - a).dot(along) > 0.0 else b
		_dress_face(fp, start, along, facing, a.distance_to(b), style, region, occluders, floors, solids)


## The solid pieces now in the map, those that hide a wall face, and the floors to stand on.
func _dress_context(solids: Array[Dictionary], occluders: Array[Dictionary], floors: Array[Dictionary]) -> void:
	for piece: Dictionary in controller.document.pieces:
		var type := str(piece["type"])
		if not PieceCatalog.is_solid(type) or type == "mesh_brush":
			continue
		var fp := footprint(piece)
		solids.append(fp)
		if type in DRESS_OCCLUDERS and float(fp["top"]) - float(fp["base"]) > 1.0:
			occluders.append(fp)
		if PieceCatalog.is_walkable(type) and PieceCatalog.kind(type) not in ["stairs", "ramp"]:
			floors.append(fp)


## Highest walkable floor top under the point, no higher than [param ceiling]; NAN for none.
static func ground_under(point: Vector2, ceiling: float, floors: Array[Dictionary]) -> float:
	var best := NAN
	for fp: Dictionary in floors:
		var top := float(fp["top"])
		if top <= ceiling and inside_footprint(fp, point, top) and (is_nan(best) or top > best):
			best = top
	return best


func _dress_face(fp: Dictionary, start: Vector2, along: Vector2, facing: Vector2, length: float, style: Dictionary,
		region: Rect2, occluders: Array[Dictionary], floors: Array[Dictionary], solids: Array[Dictionary]) -> void:
	var top := float(fp["top"])
	var min_height := float(style.get("min_height", 2.6))
	var run_start := -1.0
	var run_ground := NAN
	var steps := int(floor(length))
	for s: int in steps + 1:
		var ground := NAN
		if s < steps:
			var at := start + along * (float(s) + 0.5)
			var near := at + facing * 0.4
			var far := at + facing * 1.2
			ground = ground_under(near, top - min_height, floors)
			# Only walls that stand on that ground: a lintel over a doorway is not a wall to dress.
			var level_ok := not is_nan(ground) and ground >= float(style.get("min_ground", -INF)) \
				and ground <= float(style.get("max_ground", INF))
			if level_ok and region.has_point(near) and float(fp.get("base", -INF)) <= ground + 0.3:
				for other: Dictionary in occluders:
					if other["id"] == fp["id"]:
						continue
					if inside_footprint(other, near, ground + 1.5) or inside_footprint(other, far, ground + 1.5):
						ground = NAN
						break
			else:
				ground = NAN
		var same := (is_nan(ground) and is_nan(run_ground)) or (not is_nan(ground) and not is_nan(run_ground)
			and absf(ground - run_ground) < 0.05)
		if not same:
			if not is_nan(run_ground):
				dress_run(start + along * run_start, along, facing, float(s) - run_start, run_ground, top, style, solids)
			run_start = float(s)
			run_ground = ground


## Dresses one straight run of wall facing [param facing], [param length] m from [param from],
## standing on [param ground] up to [param top]. Style keys (all optional):
## plinth / cornice / beams / pipes: materials; window, door, lamp: {type, size, props, materials};
## window_every (m), first_sill (m above ground), storey (m between rows), lit (0..1 share of
## windows lit from inside), blank (0..1 share left blank), frame (lit window frame material),
## door_chance (0..1), lamp_every (m), lamp_y, extra: Callable(run Dictionary).
func dress_run(from: Vector2, along: Vector2, facing: Vector2, length: float, ground: float, top: float,
		style: Dictionary, solids: Array[Dictionary] = []) -> void:
	if length < 1.5:
		return
	var pick := pick_at(from + along * length * 0.5, int(top * 10.0))
	var yaw := rad_to_deg(atan2(facing.x, facing.y))
	var door_at := -1.0
	var door_width := float(((style["door"] as Dictionary)["size"] as Vector3).x) if style.has("door") else 0.0
	var wants_door := float(pick % 100) / 100.0 < float(style.get("door_chance", 0.5))
	if style.has("door") and length >= maxf(5.0, door_width + 2.0) and wants_door:
		# Whole door inside the run, so it never spills into an opening beside the wall.
		door_at = clampf(snappedf(length * (0.3 + 0.4 * float(pick % 7) / 6.0), 0.5),
			door_width / 2.0 + 0.5, length - door_width / 2.0 - 0.5)
		var probe := from + along * door_at + facing * 0.8
		for other: Dictionary in solids:
			if inside_footprint(other, probe, ground + 0.6):
				door_at = -1.0
				break
	var door_half := 0.0
	if door_at > 0.0:
		door_half = float(((style["door"] as Dictionary)["size"] as Vector3).x) / 2.0 + 0.3
	if style.has("plinth"):
		var plinth_h := float(style.get("plinth_h", 0.55))
		if door_at > 0.0:
			band(from, along, facing, 0.0, door_at - door_half, ground, plinth_h, 0.12, str(style["plinth"]), yaw)
			band(from, along, facing, door_at + door_half, length, ground, plinth_h, 0.12, str(style["plinth"]), yaw)
		else:
			band(from, along, facing, 0.0, length, ground, plinth_h, 0.12, str(style["plinth"]), yaw)
	if style.has("cornice"):
		var cornice_h := float(style.get("cornice_h", 0.4))
		band(from, along, facing, 0.0, length, top - cornice_h, cornice_h, 0.22, str(style["cornice"]), yaw)
	if style.has("window"):
		_dress_windows(from, along, facing, length, ground, top, style, pick, yaw, door_at, door_half, solids)
	if door_at > 0.0:
		var door: Dictionary = style["door"]
		var door_materials: Array = door.get("materials", ["wood_dark"])
		fixture(str(door.get("type", "door")), from, along, facing, door_at, ground, door["size"] as Vector3,
			door.get("props", {}) as Dictionary, str(door_materials[pick % door_materials.size()]), yaw)
	if style.has("lamp") and float(style.get("lamp_every", 0.0)) > 0.0:
		var lamp_def: Dictionary = style["lamp"]
		var lamp_y := ground + float(style.get("lamp_y", 2.4))
		var lamp_type := str(lamp_def["type"])
		var lamp_size: Vector3 = lamp_def["size"]
		var lamp_props: Dictionary = lamp_def.get("props", {})
		var lamp_material := str(lamp_def.get("material", "metal_dark"))
		if door_at > 0.0:
			fixture(lamp_type, from, along, facing, door_at + door_half + 0.3, lamp_y, lamp_size, lamp_props, lamp_material, yaw)
		var every_lamp := float(style["lamp_every"])
		var post := every_lamp / 2.0
		while post <= length - 1.0:
			if door_at < 0.0 or absf(post - door_at) > 3.0:
				fixture(lamp_type, from, along, facing, post, lamp_y, lamp_size, lamp_props, lamp_material, yaw)
			post += every_lamp
	if style.has("beams") and pick % 3 == 0 and length >= 3.0:
		var beam := 0.8
		while beam <= length - 0.6:
			var at := from + along * beam + facing * 0.3
			put("block", Vector3(at.x, top - 1.1, at.y), Vector3(0.18, 0.18, 0.6), yaw, {}, str(style["beams"]))
			beam += 1.4
	if style.has("pipes") and top - ground >= 4.0:
		for t: float in [0.25, length - 0.25]:
			var at := from + along * t + facing * 0.12
			put("column", Vector3(at.x, ground, at.y), Vector3(0.14, top - ground - 0.2, 0.14), 0.0, {}, str(style["pipes"]))
	if style.has("extra"):
		(style["extra"] as Callable).call({"from": from, "along": along, "facing": facing, "length": length,
			"ground": ground, "top": top, "pick": pick, "yaw": yaw, "door_at": door_at})


## Windows in rows, one row per storey, centred on the run and clear of the door.
func _dress_windows(from: Vector2, along: Vector2, facing: Vector2, length: float, ground: float, top: float,
		style: Dictionary, pick: int, yaw: float, door_at: float, door_half: float, solids: Array[Dictionary]) -> void:
	var window: Dictionary = style["window"]
	var size: Vector3 = window["size"]
	var every := float(style.get("window_every", 4.0))
	var storey := float(style.get("storey", 3.0))
	if length < size.x + 1.0:
		return
	var slots := window_slots(length, every, size.x)
	var count := int(slots.x)
	var offset := slots.y
	var sill := ground + float(style.get("first_sill", 1.0))
	var materials: Array = window.get("materials", ["wood_dark"])
	var row := 0
	while sill + size.y <= top - 0.5:
		for k: int in count:
			var t := offset + every * float(k)
			if door_at > 0.0 and row == 0 and absf(t - door_at) < door_half + size.x / 2.0 + 0.2:
				continue
			var h := (pick + k * 31 + row * 17) % 100
			if float(h) / 100.0 < float(style.get("blank", 0.15)):
				continue
			if fixture_blocked(solids, from + along * t + facing * 0.2, sill + size.y / 2.0, size.x / 2.0 + 0.15):
				continue
			if float((h * 7 + 13) % 100) / 100.0 < float(style.get("lit", 0.0)):
				lit_window(from, along, facing, t, sill, size, yaw, str(style.get("frame", "wood_dark")))
			else:
				fixture(str(window.get("type", "window")), from, along, facing, t, sill, size,
					window.get("props", {}) as Dictionary, str(materials[(pick + k) % materials.size()]), yaw)
		sill += storey
		row += 1


## Whether a lamp, sign or prop already on the wall sits within [param margin] of the point.
static func fixture_blocked(solids: Array[Dictionary], point: Vector2, y: float, margin: float) -> bool:
	for other: Dictionary in solids:
		if str(other["type"]) not in DRESS_OCCLUDERS and inside_footprint(other, point, y, margin):
			return true
	return false


## Where the windows of a run go: x = how many, y = the first one's distance from the run start
## (then one every [param every] m), centred and each clear of the run's ends. Style extras use it
## to put posts and stanchions between the windows.
static func window_slots(length: float, every: float, width: float) -> Vector2:
	var count := int(floor((length - 1.0) / every)) + 1
	var offset := (length - float(count - 1) * every) / 2.0
	while count > 1 and offset < width / 2.0 + 0.3:
		count -= 1
		offset = (length - float(count - 1) * every) / 2.0
	return Vector2(count, offset)


## A thin band along a run, [param depth] proud of the wall, turned to the wall.
func band(from: Vector2, along: Vector2, facing: Vector2, t1: float, t2: float, base: float, height: float,
		depth: float, material: String, yaw: float) -> void:
	if t2 - t1 < 0.05:
		return
	var centre := from + along * ((t1 + t2) / 2.0) + facing * (depth / 2.0)
	put("block", Vector3(centre.x, base, centre.y), Vector3(t2 - t1, height, depth), yaw, {}, material)


## A fixture (window, door, lamp: back on its -Z face) against the wall at [param t] along a run.
func fixture(type: String, from: Vector2, along: Vector2, facing: Vector2, t: float, y: float, size: Vector3,
		props: Dictionary, material: String, yaw: float) -> void:
	var at := from + along * t + facing * (size.z / 2.0 - 0.03)
	put(type, Vector3(at.x, y, at.y), size, yaw, props, material)


## A window lit from inside: a glowing pane in a frame (the pane is emissive lamp glass).
func lit_window(from: Vector2, along: Vector2, facing: Vector2, t: float, sill: float, size: Vector3, yaw: float,
		frame: String) -> void:
	var w := size.x
	band(from, along, facing, t - w * 0.42, t + w * 0.42, sill + 0.08, size.y - 0.16, 0.05, "lamp_glass", yaw)
	band(from, along, facing, t - w / 2.0, t + w / 2.0, sill, 0.08, 0.14, frame, yaw)
	band(from, along, facing, t - w / 2.0, t + w / 2.0, sill + size.y - 0.08, 0.08, 0.12, frame, yaw)
	for side: float in [-1.0, 1.0]:
		band(from, along, facing, t + side * w * 0.46 - 0.04, t + side * w * 0.46 + 0.04, sill + 0.08, size.y - 0.16, 0.1, frame, yaw)
	band(from, along, facing, t - 0.03, t + 0.03, sill + 0.08, size.y - 0.16, 0.08, frame, yaw)


## A string of pennants from [param a] to [param b] sagging [param sag] m in the middle: a cord,
## and one brush of two-sided triangles for each colour (taken in turn along the string).
func bunting(a: Vector3, b: Vector3, sag: float, colours: Array, spacing: float = 0.6) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var along := Vector3(flat.x, 0, flat.y).normalized()
	var count := maxi(int(flat.length() / spacing), 2)
	var groups: Array = []
	for colour: Variant in colours:
		groups.append([[], []])
	var cord_vertices: Array = []
	var cord_faces: Array = []
	for i: int in count + 1:
		var t := float(i) / float(count)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		if i < count:
			var t2 := float(i + 1) / float(count)
			var q := a.lerp(b, t2) + Vector3.DOWN * sag * 4.0 * t2 * (1.0 - t2)
			var first := cord_vertices.size()
			for v: Vector3 in [p, q, q + Vector3.DOWN * 0.04, p + Vector3.DOWN * 0.04]:
				cord_vertices.append([v.x, v.y, v.z])
			cord_faces.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
		if i == 0 or i == count:
			continue
		var group: Array = groups[i % colours.size()]
		var vertices: Array = group[0]
		var n := vertices.size()
		for v: Vector3 in [p - along * 0.17, p + along * 0.17, p + Vector3.DOWN * 0.38]:
			vertices.append([v.x, v.y, v.z])
		(group[1] as Array).append_array([n, n + 1, n + 2])
	var rows: Array = [{"vertices": cord_vertices, "faces": cord_faces, "two_sided": true, "material": "metal_dark"}]
	for k: int in colours.size():
		var group: Array = groups[k]
		if not (group[1] as Array).is_empty():
			rows.append({"vertices": group[0], "faces": group[1], "two_sided": true, "material": str(colours[k])})
	studio.call("draw_brushes", rows)
