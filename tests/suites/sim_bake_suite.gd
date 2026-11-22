extends TestSuite
## Baking a map's career simulation graph from inside the Creation Studio (Milestone 16 / 21 A):
## saving bakes it, the "Bake sim graph" button bakes it on demand, and both write exactly what
## tools/bake_sim_maps.gd writes, through the same SimGraphBuilder.bake_to.

const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"
const TEST_DIR: String = "user://tests/sim_bake"


func suite_name() -> String:
	return "Simulation graph bake in the Creation Studio"


func run() -> void:
	_wipe(TEST_DIR)
	_test_output_dir()
	await _test_studio_bake()
	_wipe(TEST_DIR)


func _piece(type: String, position: Vector3, size: Vector3 = Vector3.ZERO, rotation: float = 0.0, props: Dictionary = {}) -> Dictionary:
	var piece := MapDocument.make_piece(type, position, rotation, size)
	(piece["props"] as Dictionary).merge(props, true)
	return piece


## A small flat arena: one spawn per team, both sites and a mid callout area between them.
func _arena() -> MapDocument:
	var doc := MapDocument.create("Bake arena")
	doc.add_piece(_piece("floor", Vector3(0, -0.2, 0), Vector3(30, 0.2, 30)))
	doc.add_piece(_piece("spawn_attack", Vector3(0, 0, 12)))
	doc.add_piece(_piece("spawn_defence", Vector3(0, 0, -12), Vector3.ZERO, 180.0))
	doc.add_piece(_piece("bombsite", Vector3(-10, 0, -8), Vector3(6, 3, 6), 0.0, {"site": "A"}))
	doc.add_piece(_piece("bombsite", Vector3(10, 0, -8), Vector3(6, 3, 6), 0.0, {"site": "B"}))
	doc.add_piece(_piece("callout", Vector3(0, 0, 0), Vector3(8, 3, 8), 0.0, {"name": "Mid"}))
	return doc


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe(path.path_join(sub))
		dir.remove(sub)
	for file_name: String in dir.get_files():
		dir.remove(file_name)


func _test_output_dir() -> void:
	section("Where graphs go")
	var official := OfficialMaps.load_map(OfficialMaps.DEFAULT_ID)
	var local := MapDocument.create("Local")
	check(official != null and SimGraphBuilder.output_dir(official, TEST_DIR) == SimMap.OFFICIAL_DIR
		and SimGraphBuilder.output_dir(local) == SimMap.LOCAL_DIR and SimGraphBuilder.output_dir(local, TEST_DIR) == TEST_DIR,
		"official maps' graphs go to the project, every other map's to the local folder (as the command-line tool)")


func _test_studio_bake() -> void:
	section("Studio bake")
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	await wait_frames(2)
	var ui := studio.get_node("UI/StudioUI") as StudioUI
	ui.confirm_dialog.hide()
	studio.set("storage", MapStorage.new(TEST_DIR))
	studio.set("autosave", MapAutosave.new(TEST_DIR.path_join("autosave")))
	studio.set("tactic_storage", TacticStorage.new(TEST_DIR.path_join("tactics")))
	var ctl := studio.get("controller") as MapEditController
	var sim_dir := TEST_DIR.path_join("sim")

	# An unsaved map cannot be baked: the graph records the saved content.
	studio.call("_open_document", _arena(), "", false)
	ctl.version += 1  # an edit not yet saved
	var unsaved: Dictionary = studio.call("bake_sim_graph")
	check(not bool(unsaved["ok"]) and str(unsaved["error"]).contains("Save the map first") and ui.message_dialog.visible,
		"baking unsaved edits asks to save first, in a message")
	ui.message_dialog.hide()

	# Saving bakes the graph beside the saved maps.
	check(int(studio.call("save_map")) == OK and str(studio.call("sim_graph_dir")) == sim_dir,
		"the map saves; its graph belongs beside the saved maps")
	var doc := ctl.document
	var path := sim_dir.path_join(doc.map_id + ".json")
	var graph := SimMap.from_json(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check(graph != null and graph.map_id == doc.map_id and graph.content_hash == doc.content_hash
		and graph.sites().size() == 2 and not graph.spawn("attack").is_empty() and not graph.spawn("defence").is_empty()
		and graph.nodes.has(_callout_id(doc)) and graph.is_fully_connected(),
		"saving bakes the graph: both spawns, both sites and the callout area, all connected, with the map's content hash")
	check(str(studio.get("_message")).contains("simulation graph: %d places" % (graph.nodes.size() if graph != null else -1)),
		"the save message reports the places and connections")
	check(SimGraphBuilder.is_current(doc, sim_dir) and str(studio.call("_bake_after_save")).is_empty(),
		"saving again without gameplay changes leaves the current graph alone")

	# The button bakes the same graph the command-line tool's code path writes.
	studio.call("_on_action", &"bake_sim", null)
	var again: Dictionary = studio.call("bake_sim_graph", false)
	var host := Node3D.new()
	tree.root.add_child(host)
	var cli_dir := TEST_DIR.path_join("cli")
	var cli := SimGraphBuilder.bake_to(doc, host, cli_dir)
	host.free()
	check(bool(again["ok"]) and str(again["path"]) == path and int(again["places"]) == 5 and int(again["connections"]) > 0
		and str(studio.get("_message")).begins_with("Simulation graph: 5 places"),
		"the Bake sim graph button bakes on demand and reports places and connections (%s)" % again)
	check(bool(cli["ok"]) and FileAccess.get_file_as_string(path) == FileAccess.get_file_as_string(str(cli["path"])),
		"the studio writes exactly what the command-line bake writes")

	# A map without spawns and sites has nothing to simulate: reported, nothing written.
	var bare := MapDocument.create("Bare floor")
	bare.add_piece(_piece("floor", Vector3(0, -0.2, 0), Vector3(10, 0.2, 10)))
	studio.call("_open_document", bare, "", false)
	check(int(studio.call("save_map")) == OK and not FileAccess.file_exists(sim_dir.path_join(bare.map_id + ".json")),
		"saving a map without spawns and sites bakes nothing")
	var refused: Dictionary = studio.call("bake_sim_graph")
	check(not bool(refused["ok"]) and ui.message_dialog.visible and ui.message_dialog.dialog_text.contains("bombsite"),
		"the button explains what a map needs before it can be baked")
	ui.message_dialog.hide()
	await despawn(studio)


func _callout_id(doc: MapDocument) -> String:
	var areas := MapTactical.areas(doc)
	return str(areas[0]["id"]) if not areas.is_empty() else ""
