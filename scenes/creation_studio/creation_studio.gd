extends Node3D
## Creation Studio — Map Creator (Milestone 3).
##
## Wires the MapEditController (data + undo), MapEditorView (3D), StudioUI (2D) and the editor
## camera together and implements the Select and Place tools.

const GROUND_PLANE_NORMAL: Vector3 = Vector3.UP
const RAY_LENGTH: float = 2000.0
const GHOST_COLOR: Color = Color(1.0, 0.42, 0.16, 0.35)
const MESSAGE_SECONDS: float = 5.0

var controller: MapEditController
var storage: MapStorage = MapStorage.new()
var tool: StudioUI.Tool = StudioUI.Tool.SELECT
var place_type: String = "floor"
var place_rotation: int = 0
var snap_size: float = 1.0
## Height of the build plane used when the cursor is not over a solid piece.
var build_level: float = 0.0
var current_path: String = ""

var _drag_active: bool = false
var _drag_before: Dictionary = {}
var _drag_offset: Vector3 = Vector3.ZERO
var _hover_point: Variant = null
var _ghost_half_height: float = 0.5
var _message: String = ""
var _message_until: int = 0

@onready var camera: EditorFlyCamera = $EditorCamera
@onready var grid: EditorGrid = $Grid
@onready var cursor: MeshInstance3D = $Cursor
@onready var ghost: MeshInstance3D = $Ghost
@onready var view: MapEditorView = $MapView
@onready var ui: StudioUI = $UI/StudioUI


func _ready() -> void:
	controller = MapEditController.new(_initial_document())
	_restore_session_if_any()
	view.bind(controller)
	_connect_ui()
	controller.history_changed.connect(_refresh_history)
	controller.selection_changed.connect(func(_id: String) -> void: _refresh_inspector())
	controller.piece_changed.connect(_on_piece_changed)
	controller.document_replaced.connect(func() -> void:
		_refresh_inspector()
		_refresh_history())
	_set_snap(ui.current_snap())
	_set_tool(StudioUI.Tool.SELECT)
	_refresh_history()
	_refresh_inspector()


func _initial_document() -> MapDocument:
	return MapTemplates.blank()


func _restore_session_if_any() -> void:
	if App.editor_session.is_empty():
		return
	var session := App.editor_session
	App.editor_session = {}
	var doc := MapDocument.from_dict(session.get("document", {}) as Dictionary)
	if doc == null:
		return
	controller.set_document(doc)
	current_path = str(session.get("path", ""))
	if bool(session.get("dirty", false)):
		controller.version = 1  # Keep the "unsaved changes" state across the playtest.
	var camera_transform: Variant = session.get("camera", null)
	if camera_transform is Transform3D:
		camera.set_view(camera_transform as Transform3D)


func _connect_ui() -> void:
	ui.new_requested.connect(func() -> void: _guard_unsaved(_new_map))
	ui.open_requested.connect(_open_dialog)
	ui.save_requested.connect(save_map)
	ui.validate_requested.connect(_show_validation)
	ui.playtest_requested.connect(playtest)
	ui.main_menu_requested.connect(func() -> void: _guard_unsaved(func() -> void: App.go_to(App.SCENE_MAIN_MENU)))
	ui.undo_requested.connect(func() -> void: controller.undo())
	ui.redo_requested.connect(func() -> void: controller.redo())
	ui.reset_view_requested.connect(camera.reset_view)
	ui.tool_selected.connect(_set_tool)
	ui.piece_type_selected.connect(_on_piece_type_selected)
	ui.snap_changed.connect(_set_snap)
	ui.piece_edited.connect(func(state: Dictionary) -> void: controller.update_piece(state, "Edit properties"))
	ui.metadata_edited.connect(func(n: String, a: String, d: String) -> void: controller.set_metadata(n, a, d))
	ui.map_chosen.connect(func(path: String) -> void: _guard_unsaved(load_map.bind(path)))
	ui.template_chosen.connect(func(id: String) -> void: _guard_unsaved(load_template.bind(id)))


# --- file operations ----------------------------------------------------------------------------

func save_map() -> Error:
	var err := storage.save(controller.document)
	if err == OK:
		current_path = storage.path_for(controller.document.map_id)
		controller.mark_saved()
		flash("Saved \"%s\" (revision %d) to %s" % [controller.document.name, controller.document.revision, current_path])
		_refresh_inspector()
	else:
		ui.show_message("Save failed", "Could not save the map (error %d)." % err)
	return err


func load_map(path: String) -> bool:
	var doc := storage.load_path(path)
	if doc == null:
		ui.show_message("Open failed", "Could not read %s.\nThe file may be damaged or from a newer version of the game." % path)
		return false
	controller.set_document(doc)
	current_path = path
	flash("Opened \"%s\" (%d pieces)" % [doc.name, doc.pieces.size()])
	return true


func load_template(template_id: String) -> void:
	var doc: MapDocument
	match template_id:
		"sandbox_arena":
			doc = MapTemplates.sandbox_arena()
			doc.map_id = Ids.generate("map")  # Editing the template creates a new map.
			doc.name = "Sandbox Arena copy"
		_:
			doc = MapTemplates.blank()
	controller.set_document(doc)
	current_path = ""
	flash("New map from template \"%s\"" % template_id)


func _new_map() -> void:
	load_template("blank")


func _open_dialog() -> void:
	ui.show_open_panel(storage.list_maps())


## Runs [param action] now, or after confirmation if there are unsaved changes.
func _guard_unsaved(action: Callable) -> void:
	if controller.is_dirty():
		ui.confirm("This map has unsaved changes. Discard them?", "Discard changes", action)
	else:
		action.call()


func _show_validation() -> void:
	var report := MapValidator.validate(controller.document)
	var errors: Array[String] = report["errors"]
	var warnings: Array[String] = report["warnings"]
	var lines: Array[String] = []
	if errors.is_empty() and warnings.is_empty():
		lines.append("No problems found.")
	for e: String in errors:
		lines.append("ERROR: " + e)
	for w: String in warnings:
		lines.append("Warning: " + w)
	ui.show_message("Validation — %d error(s), %d warning(s)" % [errors.size(), warnings.size()], "\n".join(lines))


## Launches the FPS runtime on a copy of the current document. Returns false if blocked.
func playtest() -> bool:
	var report := MapValidator.validate(controller.document)
	var errors: Array[String] = report["errors"]
	if not errors.is_empty():
		ui.show_message("Cannot playtest", "Fix these first:\n" + "\n".join(errors))
		return false
	App.start_playtest(controller.document.duplicate_document(), {
		"document": controller.document.to_dict(),
		"path": current_path,
		"dirty": controller.is_dirty(),
		"camera": camera.global_transform,
	})
	return true


# --- tools --------------------------------------------------------------------------------------

func _set_tool(new_tool: StudioUI.Tool) -> void:
	_cancel_drag()
	tool = new_tool
	ghost.visible = false
	ui.set_active_tool(tool, place_type)
	_refresh_status()


func _on_piece_type_selected(type: String) -> void:
	place_type = type
	place_rotation = 0
	_set_tool(StudioUI.Tool.PLACE)
	controller.select("")
	_update_ghost_mesh()


func _set_snap(size: float) -> void:
	snap_size = size
	grid.snap_size = size
	cursor.scale = Vector3(size, 1.0, size)
	_refresh_status()


func _on_piece_changed(piece_id: String) -> void:
	if piece_id == controller.selected_id:
		ui.update_inspector_values(controller.selected_piece())


## World point where a new piece would be placed for the given screen position, or null.
## Stacks on top of solid pieces; otherwise uses the build plane at [member build_level].
func placement_point(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var y := build_level
	var hit := view.pick(origin, direction, true)
	if not hit.is_empty():
		var aabb: AABB = hit["aabb"]
		var point: Vector3 = hit["point"]
		if is_equal_approx(point.y, aabb.end.y):
			y = aabb.end.y
	var plane := Plane(GROUND_PLANE_NORMAL, y)
	var ground: Variant = plane.intersects_ray(origin, direction)
	if ground == null:
		return null
	var g := ground as Vector3
	return Vector3(snappedf(g.x, snap_size), y, snappedf(g.z, snap_size))


## Places the current piece type at [param world_position] (already snapped). Returns its ID.
func place_at(world_position: Vector3) -> String:
	var piece := MapDocument.make_piece(place_type, world_position, place_rotation)
	return controller.add_piece(piece)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	_hover_point = null if camera.is_looking else placement_point(mouse)
	cursor.visible = _hover_point != null and tool == StudioUI.Tool.SELECT
	ghost.visible = _hover_point != null and tool == StudioUI.Tool.PLACE
	if _hover_point != null:
		var p := _hover_point as Vector3
		cursor.position = p + Vector3(0, 0.011, 0)
		ghost.position = p + Vector3(0, _ghost_half_height, 0)
		ghost.rotation_degrees.y = place_rotation
		ui.set_cursor_text("Cursor  x %s  y %s  z %s" % [StudioUI.format_number(p.x), StudioUI.format_number(p.y), StudioUI.format_number(p.z)])
	else:
		ui.set_cursor_text("Cursor —")
	grid.position.y = build_level
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_on_left_press(button.position)
		else:
			_end_drag()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _drag_active:
		_update_drag(motion.position)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not ui.is_editing_text():
		if _handle_key(key):
			get_viewport().set_input_as_handled()


func _on_left_press(screen_position: Vector2) -> void:
	if camera.is_looking:
		return
	if tool == StudioUI.Tool.PLACE:
		var point: Variant = placement_point(screen_position)
		if point != null:
			place_at(point as Vector3)
			controller.select("")
		return
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit := view.pick(origin, direction)
	if hit.is_empty():
		controller.select("")
		return
	controller.select(str(hit["piece_id"]))
	_begin_drag(screen_position)


func _begin_drag(screen_position: Vector2) -> void:
	_drag_before = controller.selected_piece()
	if _drag_before.is_empty():
		return
	var piece_position: Vector3 = _drag_before["position"]
	var plane_point: Variant = _point_on_plane(screen_position, piece_position.y)
	if plane_point == null:
		return
	_drag_offset = piece_position - (plane_point as Vector3)
	_drag_active = true


func _update_drag(screen_position: Vector2) -> void:
	var piece_position: Vector3 = _drag_before["position"]
	var plane_point: Variant = _point_on_plane(screen_position, piece_position.y)
	if plane_point == null:
		return
	var target := (plane_point as Vector3) + _drag_offset
	var state := _drag_before.duplicate(true)
	state["position"] = Vector3(snappedf(target.x, snap_size), piece_position.y, snappedf(target.z, snap_size))
	controller.preview_piece(state)


func _end_drag() -> void:
	if not _drag_active:
		return
	_drag_active = false
	var after := controller.document.get_piece(str(_drag_before["id"]))
	controller.commit_preview(_drag_before, after, "Move")


func _cancel_drag() -> void:
	if _drag_active:
		_drag_active = false
		controller.cancel_preview(_drag_before)


func _point_on_plane(screen_position: Vector2, height: float) -> Variant:
	var plane := Plane(GROUND_PLANE_NORMAL, height)
	return plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _handle_key(key: InputEventKey) -> bool:
	var ctrl := key.ctrl_pressed or key.meta_pressed
	var code := key.physical_keycode
	if ctrl:
		match code:
			KEY_Z:
				if key.shift_pressed:
					controller.redo()
				else:
					controller.undo()
				return true
			KEY_Y:
				controller.redo()
				return true
			KEY_S:
				save_map()
				return true
			KEY_D:
				if not controller.selected_id.is_empty():
					controller.duplicate_piece(controller.selected_id, Vector3(snap_size, 0, snap_size))
				return true
			KEY_N:
				_guard_unsaved(_new_map)
				return true
			KEY_O:
				_open_dialog()
				return true
		return false
	if key.echo and not (code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]):
		return false
	match code:
		KEY_1:
			_set_tool(StudioUI.Tool.SELECT)
		KEY_2:
			_on_piece_type_selected(place_type)
		KEY_ESCAPE:
			if _drag_active:
				_cancel_drag()
			elif tool == StudioUI.Tool.PLACE:
				_set_tool(StudioUI.Tool.SELECT)
			else:
				controller.select("")
		KEY_DELETE, KEY_BACKSPACE:
			if not controller.selected_id.is_empty():
				controller.delete_piece(controller.selected_id)
		KEY_R:
			var step := -MapDocument.ROTATION_STEP if key.shift_pressed else MapDocument.ROTATION_STEP
			if tool == StudioUI.Tool.PLACE:
				place_rotation = posmod(place_rotation + step, 360)
				_update_ghost_mesh()
			elif not controller.selected_id.is_empty():
				controller.rotate_piece(controller.selected_id, step)
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			_nudge(code)
		KEY_F5:
			playtest()
		_:
			return false
	return true


func _nudge(code: Key) -> void:
	var offset := Vector3.ZERO
	match code:
		KEY_LEFT:
			offset.x = -snap_size
		KEY_RIGHT:
			offset.x = snap_size
		KEY_UP:
			offset.z = -snap_size
		KEY_DOWN:
			offset.z = snap_size
		KEY_PAGEUP:
			offset.y = snap_size
		KEY_PAGEDOWN:
			offset.y = -snap_size
	if tool == StudioUI.Tool.SELECT and not controller.selected_id.is_empty():
		var piece := controller.selected_piece()
		controller.move_piece(controller.selected_id, (piece["position"] as Vector3) + offset)
	elif offset.y != 0.0:
		build_level += offset.y


func _update_ghost_mesh() -> void:
	var piece := MapDocument.make_piece(place_type, Vector3.ZERO, 0)
	var size: Vector3 = piece["size"]
	var mesh := BoxMesh.new()
	mesh.size = size
	ghost.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = GHOST_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = material
	_ghost_half_height = size.y / 2.0  # Pieces use a bottom-centre origin; the box mesh is centred.


# --- refresh ------------------------------------------------------------------------------------

func _refresh_history() -> void:
	ui.set_history_state(controller.can_undo(), controller.can_redo(), controller.is_dirty(),
		controller.document.name, controller.undo_action_name())


func _refresh_inspector() -> void:
	ui.show_inspector(controller.selected_piece(), controller.document, current_path)


## Shows a transient message in the status bar.
func flash(text: String) -> void:
	_message = text
	_message_until = Time.get_ticks_msec() + int(MESSAGE_SECONDS * 1000.0)


func _refresh_status() -> void:
	var tool_text := "Select" if tool == StudioUI.Tool.SELECT else "Place %s (R rotates, %d°)" % [PieceCatalog.label(place_type), place_rotation]
	var p := camera.position
	ui.set_status("%s   ·   %d pieces   ·   Snap %s m   ·   Build height %s m   ·   Camera %.0f, %.0f, %.0f   ·   %s" % [
		tool_text, controller.document.pieces.size(), StudioUI.format_number(snap_size),
		StudioUI.format_number(build_level), p.x, p.y, p.z,
		"LOOKING (RMB held)" if camera.is_looking else "Hold RMB to fly",
	] + ("   ·   " + _message if Time.get_ticks_msec() < _message_until else ""))
