class_name MapEditorSuite
extends TestSuite
## Milestone 3: map document, validation, storage, edit controller (undo/redo), builder geometry,
## Creation Studio integration and the editor -> playtest -> editor round trip.

const TEST_DIR: String = "user://test_maps"


func suite_name() -> String:
	return "Map editor"


func run() -> void:
	_test_document()
	_test_validator()
	_test_storage()
	_test_controller()
	await _test_builder_geometry()
	await _test_studio_editing()
	await _test_playtest_round_trip()


func _test_document() -> void:
	section("MapDocument")
	var doc := MapDocument.create("Doc test")
	var a := doc.add_piece(MapDocument.make_piece("wall", Vector3(1, 0, 2), 90))
	var b := doc.add_piece(MapDocument.make_piece("bombsite", Vector3(0, 0, 0)))
	check(a == "pc_1" and b == "pc_2", "piece ids are allocated sequentially")
	doc.remove_piece(a)
	var c := doc.add_piece(MapDocument.make_piece("crate", Vector3.ZERO))
	check(c == "pc_3", "piece ids are never reused")
	var copy := MapDocument.from_json(doc.to_json())
	check(copy != null and copy.pieces.size() == 2 and copy.map_id == doc.map_id, "JSON round trip keeps pieces and id")
	check(copy != null and copy.get_piece(b)["props"]["site"] == "A", "props survive the round trip")
	check(copy != null and copy.add_piece(MapDocument.make_piece("crate", Vector3.ZERO)) == "pc_4",
		"id counter survives the round trip")
	var data := doc.to_dict()
	data["format_version"] = 99
	check(MapDocument.from_dict(data) == null, "newer format version is refused")
	var bad_type := doc.to_dict()
	(bad_type["pieces"] as Array)[0]["type"] = "laser_turret"
	check(MapDocument.from_dict(bad_type) == null, "unknown piece type is refused")
	check(MapDocument.from_json("{not json") == null, "malformed JSON is refused")
	var wall := MapDocument.make_piece("wall", Vector3(0, 0, 0), 90, Vector3(4, 3, 0.3))
	var aabb := MapDocument.piece_aabb(wall)
	check(is_equal_approx(aabb.size.x, 0.3) and is_equal_approx(aabb.size.z, 4.0), "AABB swaps footprint at 90°")


func _test_validator() -> void:
	section("MapValidator")
	var empty := MapDocument.create("Empty")
	var report := MapValidator.validate(empty)
	check((report["errors"] as Array).size() >= 2, "empty map has errors (no geometry, no spawns)")
	var blank := MapTemplates.blank()
	report = MapValidator.validate(blank)
	check((report["errors"] as Array).is_empty(), "blank template is playable")
	check(not (report["warnings"] as Array).is_empty(), "blank template warns about competitive requirements")
	report = MapValidator.validate(MapTemplates.sandbox_arena())
	check((report["errors"] as Array).is_empty(), "sandbox arena template has no errors")


func _test_storage() -> void:
	section("MapStorage")
	var storage := MapStorage.new(TEST_DIR)
	_wipe_dir(TEST_DIR)
	var doc := MapTemplates.blank()
	doc.name = "Storage test"
	check(storage.save(doc) == OK, "save succeeds")
	check(doc.revision == 1, "save increments revision")
	var path := storage.path_for(doc.map_id)
	check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "file written atomically (no temp left)")
	check(storage.save(doc) == OK and FileAccess.file_exists(path + ".bak"), "second save keeps a backup")
	var loaded := storage.load_map(doc.map_id)
	check(loaded != null and loaded.name == "Storage test" and loaded.revision == 2 and loaded.pieces.size() == doc.pieces.size(),
		"load returns the saved document")
	var listing := storage.list_maps()
	check(listing.size() == 1 and listing[0]["map_id"] == doc.map_id, "list_maps finds the map")
	var corrupt := FileAccess.open(TEST_DIR.path_join("broken" + MapStorage.EXTENSION), FileAccess.WRITE)
	corrupt.store_string("{\"format\": \"something else\"}")
	corrupt.close()
	check(storage.load_path(TEST_DIR.path_join("broken" + MapStorage.EXTENSION)) == null, "corrupt file loads as null")
	check(storage.list_maps().size() == 1, "corrupt files are skipped in listings")
	check(storage.delete_map(doc.map_id) == OK and storage.load_map(doc.map_id) == null, "delete removes the map")
	DirAccess.remove_absolute(path + ".bak")
	check(storage.save(doc) == OK, "map can be saved again")
	var installed_hash := FileAccess.get_sha256(path)
	var revision := doc.revision
	DirAccess.make_dir_absolute(path + ".bak")
	doc.name = "Unpublished edit"
	check(storage.save(doc) != OK and doc.revision == revision and FileAccess.get_sha256(path) == installed_hash,
		"failed map replacement preserves the installed document and revision")
	DirAccess.remove_absolute(path + ".bak")
	var invalid := doc.to_dict()
	invalid["map_id"] = "../another_map"
	check(MapDocument.from_dict(invalid) == null and storage.path_for("../another_map").is_empty(),
		"maps reject identifiers that are unsafe for storage")
	_wipe_dir(TEST_DIR)


func _test_controller() -> void:
	section("MapEditController")
	var ctl := MapEditController.new(MapDocument.create("Ctl"))
	var events: Array[String] = []
	ctl.piece_added.connect(func(id: String) -> void: events.append("add:" + id))
	ctl.piece_removed.connect(func(id: String) -> void: events.append("remove:" + id))
	ctl.piece_changed.connect(func(id: String) -> void: events.append("change:" + id))

	var id := ctl.add_piece(MapDocument.make_piece("block", Vector3(2, 0, 2)))
	check(ctl.document.pieces.size() == 1 and ctl.selected_id == id, "add places and selects the piece")
	check(ctl.is_dirty() and ctl.can_undo(), "add marks dirty and is undoable")
	ctl.undo()
	check(ctl.document.pieces.is_empty() and ctl.selected_id == "", "undo removes the piece and its selection")
	ctl.redo()
	check(ctl.document.pieces.size() == 1 and ctl.document.get_piece(id)["type"] == "block", "redo restores it with the same id")

	var other := ctl.add_piece(MapDocument.make_piece("crate", Vector3(0, 0, 0)))
	ctl.move_piece(id, Vector3(5, 0, 5))
	check(ctl.document.get_piece(id)["position"] == Vector3(5, 0, 5), "move updates position")
	ctl.rotate_piece(id)
	ctl.rotate_piece(id)
	check(int(ctl.document.get_piece(id)["rotation_y"]) == 180, "rotate twice = 180°")
	ctl.undo()
	check(int(ctl.document.get_piece(id)["rotation_y"]) == 90, "undo rotation one step")

	ctl.delete_piece(id)
	check(ctl.document.index_of(id) < 0, "delete removes the piece")
	ctl.undo()
	check(ctl.document.index_of(id) == 0, "undo delete restores it at its original index")

	var dup := ctl.duplicate_piece(other, Vector3(1, 0, 0))
	check(dup != other and ctl.document.get_piece(dup)["position"] == Vector3(1, 0, 0), "duplicate copies with offset")

	var before := ctl.document.get_piece(other)
	for x: int in [1, 2, 3]:
		var state := before.duplicate(true)
		state["position"] = Vector3(x, 0, 0)
		ctl.preview_piece(state)
	ctl.commit_preview(before, ctl.document.get_piece(other), "Move")
	check(ctl.document.get_piece(other)["position"] == Vector3(3, 0, 0), "drag preview ends at final position")
	ctl.undo()
	check(ctl.document.get_piece(other)["position"] == Vector3.ZERO, "a whole drag is a single undo step")

	ctl.mark_saved()
	check(not ctl.is_dirty(), "mark_saved clears dirty")
	ctl.set_metadata("Renamed", "Me", "")
	check(ctl.is_dirty() and ctl.document.name == "Renamed", "metadata edits mark dirty")
	check(events.has("add:" + id) and events.has("remove:" + id) and events.has("change:" + id), "controller emits change signals")
	var temp := MapEditController.new(MapTemplates.blank())
	var probe: WeakRef = weakref(temp)
	temp.add_piece(MapDocument.make_piece("crate", Vector3.ZERO))
	temp.undo()
	temp = null
	check(probe.get_ref() == null, "controller with history is freed (no UndoRedo reference cycle)")


func _test_builder_geometry() -> void:
	section("MapBuilder geometry (physics raycasts)")
	var world := Node3D.new()
	world.name = "BuilderTestWorld"
	tree.root.add_child(world)
	var doc := MapTemplates.sandbox_arena()
	var runtime := MapBuilder.build(doc, MapBuilder.Mode.RUNTIME)
	world.add_child(runtime)
	var spawn_node: Node3D = null
	for child: Node in runtime.get_children():
		if str(child.get_meta(&"piece_type", "")) == "spawn_attack":
			spawn_node = child as Node3D
	check(spawn_node != null and spawn_node.get_child_count() == 0, "runtime spawns are invisible points")
	var editor_spawn := MapBuilder.build_piece(doc.pieces_of_type("spawn_attack")[0], MapBuilder.Mode.EDITOR)
	check(editor_spawn.get_child_count() > 0, "editor spawns are visible")
	editor_spawn.free()
	await wait_physics_frames(2)
	var space := world.get_world_3d().direct_space_state
	check(absf(_ground_height(space, Vector3(0, 10, 0)) - 0.0) < 0.05, "floor top is at y = 0")
	check(absf(_ground_height(space, Vector3(14, 10, 4)) - 1.5) < 0.1, "ramp is half height at its middle")
	check(absf(_ground_height(space, Vector3(14, 10, 0)) - 2.7) < 0.1, "ramp rises toward -Z (high end at the platform)")
	check(absf(_ground_height(space, Vector3(14, 10, -5)) - 3.0) < 0.05, "platform top at y = 3")
	check(absf(_ground_height(space, Vector3(21.5, 10, -5)) - 1.5) < 0.15, "stairs slope is half height at its middle")
	check(absf(_ground_height(space, Vector3(23, 10, -5)) - 0.6) < 0.15, "rotated stairs rise toward the platform")
	world.queue_free()
	await wait_frames(1)


func _ground_height(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 50.0)
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -999.0


func _test_studio_editing() -> void:
	section("Creation Studio editing")
	var studio := spawn_scene("res://scenes/creation_studio/creation_studio.tscn")
	if studio == null:
		return
	await wait_frames(2)
	var ctl := studio.get("controller") as MapEditController
	var view := studio.get_node("MapView") as MapEditorView
	var start_pieces := ctl.document.pieces.size()
	check(view.node_count() == start_pieces, "view shows every document piece")

	studio.call("_on_piece_type_selected", "wall")
	check(studio.get("tool") == StudioUI.Tool.PLACE, "choosing a piece switches to the place tool")
	var id: String = studio.call("place_at", Vector3(3, 0, -2))
	await wait_frames(1)
	check(ctl.document.pieces.size() == start_pieces + 1 and view.node_for(id) != null, "placing adds a piece and its node")

	var screen_centre := tree.root.get_visible_rect().size / 2.0
	var camera := studio.get_node("EditorCamera") as EditorFlyCamera
	var origin := camera.project_ray_origin(screen_centre)
	var direction := camera.project_ray_normal(screen_centre)
	var target := origin + direction * 10.0
	ctl.move_piece(id, Vector3(snappedf(target.x, 1.0), 0, snappedf(target.z, 1.0)))
	var hit := view.pick(origin, direction)
	check(not hit.is_empty(), "picking finds geometry under the screen centre")

	studio.call("_set_tool", StudioUI.Tool.SELECT)
	ctl.select(id)
	studio.call("_handle_key", _key(KEY_R))
	check(int(ctl.document.get_piece(id)["rotation_y"]) == 90, "R rotates the selection")
	studio.call("_handle_key", _key(KEY_RIGHT))
	check((ctl.document.get_piece(id)["position"] as Vector3).x == snappedf(target.x, 1.0) + 1.0, "arrow key nudges by the snap size")
	studio.call("_handle_key", _key(KEY_DELETE))
	await wait_frames(1)
	check(ctl.document.index_of(id) < 0 and view.node_for(id) == null, "Delete removes the piece and its node")
	studio.call("_handle_key", _key(KEY_Z, true))
	await wait_frames(1)
	check(ctl.document.index_of(id) >= 0 and view.node_for(id) != null, "Ctrl+Z restores it")

	var storage := MapStorage.new(TEST_DIR)
	studio.set("storage", storage)
	check(studio.call("save_map") == OK and not ctl.is_dirty(), "save from the studio clears the dirty flag")
	var path: String = studio.get("current_path")
	studio.call("load_template", "sandbox_arena")
	check(ctl.document.pieces.size() > 20, "opening a template replaces the document")
	check(studio.call("load_map", path) and ctl.document.index_of(id) >= 0, "re-opening the saved file restores the edit")
	_wipe_dir(TEST_DIR)
	await despawn(studio)


func _test_playtest_round_trip() -> void:
	section("Editor -> playtest -> editor")
	App.go_to(App.SCENE_CREATION_STUDIO)
	await wait_frames(3)
	var studio := tree.current_scene
	var ctl := studio.get("controller") as MapEditController
	studio.call("_on_piece_type_selected", "crate_large")
	var crate_id: String = studio.call("place_at", Vector3(2, 0, 2))
	ctl.set_metadata("Round trip map", "", "")
	var piece_count := ctl.document.pieces.size()
	var started: bool = studio.call("playtest")
	await wait_frames(3)
	check(started and App.is_playtesting(), "playtest starts")
	var runtime := tree.current_scene
	check(runtime != null and runtime.scene_file_path == App.SCENE_PATHS[App.SCENE_FPS_SANDBOX], "FPS runtime is active")
	var level := runtime.get_node("Level") as SandboxLevel
	check(level.document.name == "Round trip map" and level.document.index_of(crate_id) >= 0, "runtime loaded the edited map")
	var player := runtime.get_node("Player") as FirstPersonController
	var spawn: Array = level.spawn_point("attack")
	check(player.global_position.distance_to(spawn[0] as Vector3) < 0.5, "player starts at the map's spawn")
	var hud := runtime.get_node("Hud") as SandboxHud
	check(hud.editor_button.visible, "playtest offers Return to Creation Studio")

	App.end_playtest()
	await wait_frames(3)
	var back := tree.current_scene
	var restored := back.get("controller") as MapEditController
	check(not App.is_playtesting(), "playtest flag cleared")
	check(restored != null and restored.document.pieces.size() == piece_count and restored.document.index_of(crate_id) >= 0,
		"editor restores the map after the playtest")
	check(restored != null and restored.is_dirty(), "unsaved state survives the playtest")

	var empty := MapDocument.create("No spawns")
	restored.set_document(empty)
	var blocked: bool = back.call("playtest")
	check(not blocked and not App.is_playtesting(), "invalid map cannot be playtested")
	App.go_to(App.SCENE_MAIN_MENU)
	await wait_frames(3)


func _key(code: Key, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event


func _wipe_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
