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
	# Band edges at each region's top and bottom, so no band piece ever encloses a whole region
	# (cutting one out would leave a piece with a hole, which a drawn surface cannot be).
	for region: Array in regions:
		for corner: Vector2 in region[0]:
			zs.append(corner.y)
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
## rest in [param material].
func _floor_piece(piece: PackedVector2Array, top: float, thickness: float, material: String, regions: Array) -> void:
	var rest: Array[PackedVector2Array] = [piece]
	for region: Array in regions:
		var cutter := PackedVector2Array(region[0])
		var remaining: Array[PackedVector2Array] = []
		for part: PackedVector2Array in rest:
			for inside: PackedVector2Array in Geometry2D.intersect_polygons(part, cutter):
				if absf(_area(inside)) > 0.05:
					surface(Array(inside), top, thickness, str(region[1]))
			for outside: PackedVector2Array in Geometry2D.clip_polygons(part, cutter):
				if Geometry2D.is_polygon_clockwise(outside):
					printerr("Floor region would leave a hole in a band piece: ", region[0])
				else:
					remaining.append(outside)
		rest = remaining
	for part: PackedVector2Array in rest:
		if absf(_area(part)) > 0.05:
			surface(Array(part), top, thickness, material)


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
