extends TestSuite
## Tactical Play Creator through the existing Studio scene, with disposable map and tactic files.

const STUDIO: String = "res://scenes/creation_studio/creation_studio.tscn"
const TEST_ROOT: String = "user://tests/tactics"


func suite_name() -> String:
	return "Tactical Play Creator (Milestone 8)"


func run() -> void:
	var maps := MapStorage.new(TEST_ROOT)
	var store := TacticStorage.new(TEST_ROOT)
	var studio := spawn_scene(STUDIO)
	if studio == null:
		return
	var studio_ui := studio.get_node("UI/StudioUI") as StudioUI
	check(not bool(studio.call("open_tactic_editor")), "tactics require a saved map")
	studio_ui.message_dialog.hide()
	studio.set("storage", maps)
	check(int(studio.call("save_map")) == OK, "map is saved through the normal studio")
	var map_path := str(studio.get("current_path"))
	studio_ui.tactics_requested.emit()
	var editor := studio.get("tactic_editor") as TacticEditor
	check(editor != null and not studio_ui.visible, "Tactics opens inside the existing Studio")
	if editor == null:
		await despawn(studio)
		return
	editor.store = store
	var map_controller := studio.get("controller") as MapEditController
	var before := map_controller.document.to_json()
	check(not editor.save_tactic().is_empty(), "an unset lineup cannot be saved")

	section("Five starts, ordered routes and edits")
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var surface := Vector3(-4, 0, 4)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(surface)
	editor._unhandled_input(click)
	await wait_physics_frames(2)
	check(editor.document.slots[0].has_start and editor.document.slots[0].start.distance_to(surface) <= 0.1,
		"the viewport click places a player on the loaded map collision surface")
	for i: int in TacticDocument.SLOT_COUNT:
		editor.selected_slot = i
		var x := -4.0 + i * 2.0
		editor.edit_mode = TacticEditor.EditMode.SET_START
		check(editor.apply_point(Vector3(x, 0, 4)).is_empty(), "sets start for player %d" % (i + 1))
		editor.edit_mode = TacticEditor.EditMode.ADD_WAYPOINT
		editor.apply_point(Vector3(x, 0, 1))
		editor.apply_point(Vector3(x, 0, -2))
	editor.edit_mode = TacticEditor.EditMode.MOVE_POINT
	check(editor.apply_point(Vector3(4, 0, -3)).is_empty()
		and editor.document.slots[4].route[1] == Vector3(4, 0, -3), "moves the selected waypoint in place")
	editor.remove_waypoint()
	check(editor.document.slots[4].route == [Vector3(4, 0, 1)], "deleting a waypoint preserves remaining order")
	editor.edit_mode = TacticEditor.EditMode.ADD_WAYPOINT
	editor.apply_point(Vector3(4, 0, -4))
	editor.document.display_name = "Five routes"
	check(editor.save_tactic().is_empty(), "saves five routes")
	var path := store.path_for(editor.document.tactic_id)
	var saved := editor.document.to_dict()
	check(map_controller.document.to_json() == before, "tactics leave the map document unchanged")
	var missing := store.load_path(path, null)
	check(str(missing["error"]).contains("saved map"), "loading without the map explains what is missing")
	var wrong := MapTemplates.blank()
	check(str(store.load_path(path, wrong)["error"]).contains("different map"), "rejects the wrong map ID")
	wrong = map_controller.document.duplicate_document()
	wrong.name = "Renamed only"
	var renamed := store.load_path(path, wrong)
	check(renamed["tactic"] != null and (renamed["warnings"] as Array).is_empty(), "a cosmetic map change leaves the tactic current")
	wrong.add_piece(MapDocument.make_piece("crate", Vector3(6, 0, 6)))
	var changed := store.load_path(path, wrong)
	check(changed["tactic"] != null and str(changed["error"]).is_empty()
		and str((changed["warnings"] as Array)[0]).contains("map has changed"),
		"a changed map opens the tactic with a warning instead of refusing it")
	var malformed := saved.duplicate(true)
	malformed["format_version"] = 99
	check(TacticDocument.from_dict(malformed) == null, "rejects unknown tactic versions")
	malformed = saved.duplicate(true)
	malformed["players"][0]["waypoints"][0] = [0, "bad", 0]
	check(TacticDocument.from_dict(malformed) == null, "rejects malformed coordinates")
	malformed = saved.duplicate(true)
	malformed["players"].pop_back()
	check(TacticDocument.from_dict(malformed) == null, "rejects plans without all five slots")

	await despawn(studio)
	studio = spawn_scene(STUDIO)
	if studio == null:
		return
	studio.set("storage", maps)
	check(bool(studio.call("load_map", map_path)) and bool(studio.call("open_tactic_editor")),
		"reopens the saved map and enters Tactics in a fresh Studio")
	editor = studio.get("tactic_editor") as TacticEditor
	if editor == null:
		await despawn(studio)
		return
	editor.store = store
	check(editor.load_tactic(path).is_empty() and editor.document.to_dict() == saved,
		"reopened tactic keeps all starts and waypoint order")

	section("Preview, stop, restart and replace")
	check(editor.start_preview().is_empty(), "starts navigation preview")
	var preview := editor.preview
	if preview == null:
		await despawn(studio)
		return
	var spawned := await wait_until(func() -> bool: return preview.bots.all(func(bot: BotController) -> bool:
		return bot != null), 3.0)
	check(spawned, "five preview bots spawn on the same map geometry")
	var finished := await wait_until(func() -> bool:
		return preview.completed.all(func(count: int) -> bool: return count == 2), 8.0)
	check(finished, "all five bots walk both waypoints and report progress (%s)" % str(preview.statuses))
	var safe := preview.bots.all(func(bot: BotController) -> bool:
		return bot != null and bot.enemies.is_empty() and not bot.weapons.trigger)
	check(safe, "preview uses BotController navigation without combat")
	editor.stop_preview()
	check(editor.preview == null and not preview.is_inside_tree(), "Stop removes the navigation preview immediately")
	editor.selected_slot = 0
	editor.selected_point = 2
	editor.edit_mode = TacticEditor.EditMode.MOVE_POINT
	editor.apply_point(Vector3(-4, 0, -5))
	check(editor.save_tactic().is_empty() and FileAccess.file_exists(path + ".bak"),
		"saving the edited tactic keeps the previous version")
	var restored := store.load_path(path, maps.load_path(map_path))
	var tactic := restored["tactic"] as TacticDocument
	check(tactic != null and tactic.slots[0].route[1] == Vector3(-4, 0, -5), "updated tactic reopens")
	editor.apply_point(Vector3(90, 0, 90))
	check(editor.start_preview().is_empty(), "preview restarts after an edit")
	preview = editor.preview
	var reported := await wait_until(func() -> bool: return preview.statuses[0].contains("unreachable"), 7.0)
	check(reported and preview.completed[0] == 1, "unreachable waypoint is reported after the reachable first step")
	editor.map_creator_requested.emit()
	studio_ui = studio.get_node("UI/StudioUI") as StudioUI
	check(studio.get("tactic_editor") == null and studio_ui.visible, "returns to Map Creator with the map intact")
	await despawn(studio)
	for file: String in [path, path + ".bak", map_path]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(TEST_ROOT)
