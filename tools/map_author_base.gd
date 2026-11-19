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
