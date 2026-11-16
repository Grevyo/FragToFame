extends Node3D
## Creation Studio — Map Creator.
##
## Wires the MapEditController (data + undo), MapEditorView (3D), StudioUI (2D), the gizmo and the
## editor camera together and implements the Select, Place, Draw and Measure tools. Every edit is a
## public method here or on the controller, so the same operations the mouse and keyboard perform
## can be driven and tested without a window.

const GROUND_PLANE_NORMAL: Vector3 = Vector3.UP
const GHOST_COLOR: Color = Color(1.0, 0.42, 0.16, 0.65)
## Render-only offsets keep the grid and snap marker above coplanar floor surfaces.
const GRID_LIFT: float = 0.004
const CURSOR_LIFT: float = 0.012
const MESSAGE_SECONDS: float = 5.0
const AUTOSAVE_SECONDS: float = 45.0
const NAVMESH_REFRESH_DELAY: float = 0.35
const BOX_SELECT_MIN_PIXELS: float = 6.0
## New lights are placed this far above the clicked surface.
const LIGHT_PLACE_HEIGHT: float = 2.4

var controller: MapEditController
var storage: MapStorage = MapStorage.new()
var autosave: MapAutosave = MapAutosave.new()
var tactic_storage: TacticStorage = TacticStorage.new()
var tool: StudioUI.Tool = StudioUI.Tool.SELECT
var place_type: String = "floor"
## When set, the Place tool places this prefab instead of [member place_type].
var place_prefab_id: String = ""
var place_rotation: float = 0.0
var snap_size: float = 1.0
var angle_snap: float = 90.0
var snap_surface: bool = true
var snap_edge: bool = false
## Height of the build plane used when the cursor is not over a solid piece.
var build_level: float = 0.0
var current_path: String = ""
## True while the open document is an unmodified-identity official map; saving makes a copy.
var official_source: bool = false
var active_layer: String = MapDocument.DEFAULT_LAYER
var playtest_team: String = "attack"
var playtest_spawn: int = 0
var playtest_with_bots: bool = false
var measure_points: Array[Vector3] = []
var measure_result: Dictionary = {}
## Latest navigation analysis (navmesh overlay, validation and timings); null until requested.
var analysis: MapAnalysis = null
## Tactic compatibility issues found by the last save or validation.
var tactic_issues: Array[Dictionary] = []
var tactic_editor: TacticEditor
var gizmo: EditorGizmo

var _drag_active: bool = false
var _drag_before: Array[Dictionary] = []
var _drag_anchor: Vector3 = Vector3.ZERO
var _gizmo_handle: String = ""
var _gizmo_before: Array[Dictionary] = []
var _gizmo_pivot: Vector3 = Vector3.ZERO
var _gizmo_start: float = 0.0
var _box_active: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_rect: ReferenceRect
var _hover_point: Variant = null
var _draw_start: Variant = null
var _surface_points := PackedVector3Array()
var _surface_outline := MeshInstance3D.new()
var _surface_hover: Variant = null
var _place_preview: Node3D
var _ghost_material := StandardMaterial3D.new()
var _draw_box := MeshInstance3D.new()
var _message: String = ""
var _message_until: int = 0
var _autosave_left: float = AUTOSAVE_SECONDS
var _navmesh_refresh_left: float = 0.0
var _autosaved_version: int = -1
var _default_sun: Transform3D
var _default_sun_energy: float = 1.0
var _default_ambient: Array = []

@onready var camera: EditorFlyCamera = $EditorCamera
@onready var grid: EditorGrid = $Grid
@onready var cursor: MeshInstance3D = $Cursor
@onready var ghost: Node3D = $Ghost
@onready var view: MapEditorView = $MapView
@onready var ui: StudioUI = $UI/StudioUI
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	_ghost_material.albedo_color = GHOST_COLOR
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.emission_enabled = true
	_ghost_material.emission = GHOST_COLOR
	_ghost_material.emission_energy_multiplier = 0.35
	_draw_box.mesh = BoxMesh.new()
	_draw_box.material_override = _ghost_material
	_draw_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw_box.hide()
	ghost.add_child(_draw_box)
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1.0, 0.58, 0.24)
	_surface_outline.material_override = outline_material
	_surface_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface_outline)
	var environment := world_environment.environment
	_default_sun = sun.transform
	_default_sun_energy = sun.light_energy
	_default_ambient = [environment.ambient_light_source, environment.ambient_light_color, environment.ambient_light_energy]
	gizmo = EditorGizmo.new()
	gizmo.name = "Gizmo"
	add_child(gizmo)
	_box_rect = ReferenceRect.new()
	_box_rect.editor_only = false
	_box_rect.border_width = 2.0
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_rect.visible = false
	ui.get_parent().add_child(_box_rect)
	controller = MapEditController.new(_initial_document())
	var restored := _restore_session_if_any()
	view.bind(controller)
	_connect_ui()
	controller.history_changed.connect(_refresh_history)
	controller.selection_changed.connect(func(_id: String) -> void: _refresh_inspector())
	controller.piece_changed.connect(_on_piece_changed)
	controller.piece_added.connect(_invalidate_navigation)
	controller.piece_removed.connect(_invalidate_navigation)
	controller.document_replaced.connect(_on_document_replaced)
	controller.document_state_changed.connect(_on_document_state_changed)
	_build_snap_marker()
	_set_snap(ui.current_snap())
	_set_tool(StudioUI.Tool.SELECT)
	_on_document_replaced()
	if restored and controller.is_dirty():
		_autosaved_version = -1
	elif not restored:
		_offer_recovery()


func _initial_document() -> MapDocument:
	return MapTemplates.blank()


func _restore_session_if_any() -> bool:
	if App.editor_session.is_empty():
		return false
	var session := App.editor_session
	App.editor_session = {}
	var restored_controller := session.get("controller") as MapEditController
	if restored_controller == null:
		return false
	controller = restored_controller
	current_path = str(session.get("path", ""))
	official_source = bool(session.get("official", false))
	playtest_team = str(session.get("team", "attack"))
	playtest_spawn = int(session.get("spawn", 0))
	playtest_with_bots = bool(session.get("with_bots", false))
	ui.bot_playtest_check.set_pressed_no_signal(playtest_with_bots)
	active_layer = str(session.get("active_layer", MapDocument.DEFAULT_LAYER))
	ui.navmesh_check.set_pressed_no_signal(bool(session.get("show_navmesh", false)))
	var camera_transform: Variant = session.get("camera", null)
	if camera_transform is Transform3D:
		camera.set_view(camera_transform as Transform3D)
	return true


func _connect_ui() -> void:
	ui.new_requested.connect(func() -> void: _guard_unsaved(_new_map))
	ui.open_requested.connect(_open_dialog)
	ui.save_requested.connect(save_map)
	ui.validate_requested.connect(_show_validation)
	ui.playtest_requested.connect(func() -> void: playtest())
	ui.tactics_requested.connect(open_tactic_editor)
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
	ui.action_requested.connect(_on_action)


## Editor commands raised by StudioUI.action_requested.
func _on_action(action: StringName, value: Variant) -> void:
	match action:
		&"gizmo_mode":
			set_gizmo_mode(int(value) as EditorGizmo.Mode)
		&"angle_snap":
			angle_snap = float(value)
		&"snap_surface":
			snap_surface = bool(value)
		&"snap_edge":
			snap_edge = bool(value)
		&"overhead":
			set_overhead(bool(value))
		&"navmesh":
			ui.navmesh_check.set_pressed_no_signal(bool(value))
			if bool(value):
				refresh_navmesh()
			else:
				view.set_overlay(null)
		&"navmesh_refresh":
			refresh_navmesh()
		&"timings":
			show_timings()
		&"playtest_team":
			playtest_team = str(value)
			playtest_spawn = 0
			_refresh_spawn_options()
		&"playtest_spawn":
			playtest_spawn = int(value)
		&"playtest_bots":
			playtest_with_bots = bool(value)
		&"copy":
			copy_selection()
		&"paste":
			paste_at(_paste_point())
		&"duplicate":
			duplicate_selection()
		&"delete":
			controller.delete_selection()
		&"group":
			controller.group_selection()
			_refresh_inspector()
		&"ungroup":
			controller.ungroup_selection()
			_refresh_inspector()
		&"edit_brush":
			_open_brush_editor(str(value))
		&"material":
			controller.set_selection_material(str(value))
		&"layer_assign":
			controller.set_selection_layer(str(value))
		&"layer_add":
			active_layer = controller.add_layer(str(value))
			_refresh_layers()
		&"layer_visible":
			controller.set_layer_field(str((value as Array)[0]), "visible", bool((value as Array)[1]))
		&"layer_locked":
			controller.set_layer_field(str((value as Array)[0]), "locked", bool((value as Array)[1]))
		&"layer_active":
			active_layer = str(value)
			_refresh_layers()
		&"layer_remove":
			controller.remove_layer(str(value))
		&"prefab_save":
			if controller.save_prefab(str(value)).is_empty():
				flash("Select the pieces to save as a prefab first.")
		&"prefab_place":
			select_prefab(str(value))
		&"prefab_delete":
			controller.delete_prefab(str(value))
		&"lighting":
			controller.set_lighting(value as Dictionary)
		&"official_chosen":
			_guard_unsaved(load_official.bind(str(value)))
		&"recover":
			_guard_unsaved(recover_autosave.bind(str(value)))
		&"discard_recovery":
			DirAccess.remove_absolute(str(value))
		&"group_move":
			controller.move_selection((value as Vector3) - controller.selection_pivot())
		&"group_rotate":
			controller.rotate_selection(float(value))
			_refresh_inspector()


# --- file operations ----------------------------------------------------------------------------

## Saves the map. An official map is first turned into the player's own copy (new ID), so
## official content is never overwritten or shadowed.
func save_map() -> Error:
	var doc := controller.document
	var made_copy := official_source or OfficialMaps.is_official(doc.map_id)
	var old_id := doc.map_id
	var content_before := doc.content_version
	if made_copy:
		doc.map_id = Ids.generate("map")
		doc.name = "%s (copy)" % doc.name
		doc.revision = 0
		doc.content_version = 0
		doc.content_hash = ""
	var err := storage.save(doc)
	if err != OK:
		if made_copy:
			doc.map_id = old_id
			doc.name = doc.name.trim_suffix(" (copy)")
		ui.show_message("Save failed", "Could not save the map (error %d)." % err)
		return err
	official_source = false
	autosave.clear(old_id)
	autosave.clear(doc.map_id)
	current_path = storage.path_for(doc.map_id)
	controller.mark_saved()
	_autosaved_version = controller.version
	flash("Saved \"%s\" (revision %d, content v%d) to %s" % [doc.name, doc.revision, doc.content_version, current_path])
	_refresh_inspector()
	if not made_copy and doc.content_version != content_before:
		_report_tactic_issues()
	return err


func load_map(path: String) -> bool:
	var doc := storage.load_path(path)
	if doc == null:
		ui.show_message("Open failed", "Could not read %s.\nThe file may be damaged or from a newer version of the game." % path)
		return false
	_open_document(doc, path, false)
	flash("Opened \"%s\" (%d pieces)" % [doc.name, doc.pieces.size()])
	return true


## Opens an official map. It can be explored, playtested and used for tactics as shipped;
## saving creates the player's own copy.
func load_official(map_id: String) -> bool:
	var doc := OfficialMaps.load_map(map_id)
	if doc == null:
		ui.show_message("Open failed", "The official map %s could not be read." % map_id)
		return false
	_open_document(doc, OfficialMaps.path_for(map_id), true)
	flash("Opened official map \"%s\" — saving makes your own copy." % doc.name)
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
	_open_document(doc, "", false)
	flash("New map from template \"%s\"" % template_id)


func _open_document(doc: MapDocument, path: String, official: bool) -> void:
	controller.set_document(doc)
	current_path = path
	official_source = official
	_refresh_inspector()


func _new_map() -> void:
	load_template("blank")


func _open_dialog() -> void:
	ui.show_open_panel(storage.list_maps(), OfficialMaps.listing(), autosave.list())


## Runs [param action] now, or after confirmation if there are unsaved changes. Confirming
## discards the changes, including their recovery copy.
func _guard_unsaved(action: Callable) -> void:
	if controller.is_dirty():
		var map_id := controller.document.map_id
		ui.confirm("This map has unsaved changes. Discard them?", "Discard changes", func() -> void:
			autosave.clear(map_id)
			action.call())
	else:
		action.call()


# --- autosave and recovery ----------------------------------------------------------------------

## Writes a recovery copy if the map has unsaved changes. Returns true when a copy was written.
func autosave_now() -> bool:
	_autosave_left = AUTOSAVE_SECONDS
	if not controller.is_dirty():
		return false
	if autosave.write(controller.document, current_path) != OK:
		return false
	_autosaved_version = controller.version
	return true


## Replaces the open document with a recovery copy and marks it unsaved.
func recover_autosave(path: String) -> bool:
	var entry := autosave.read(path)
	if entry.is_empty():
		ui.show_message("Recovery failed", "The recovery copy could not be read.")
		return false
	var doc := entry["document"] as MapDocument
	var source := str(entry["source_path"])
	_open_document(doc, source if FileAccess.file_exists(source) else "", OfficialMaps.is_official(doc.map_id))
	controller.version = 1
	_autosaved_version = 1
	_refresh_history()
	flash("Recovered unsaved work on \"%s\". Save to keep it." % doc.name)
	return true


func _offer_recovery() -> void:
	var copies := autosave.list()
	if copies.is_empty():
		return
	var newest := copies[0]
	var path := str(newest["path"])
	ui.confirm("Unsaved work on \"%s\" was autosaved. Recover it?\n(Other recovery copies are listed under Open.)" % newest["name"],
		"Recover", func() -> void: recover_autosave(path), "Recover unsaved work")


# --- validation, navmesh and timings ------------------------------------------------------------

## Structural + navigation validation with route timings and saved-tactic compatibility:
## {"errors", "warnings", "timings", "timing_text", "tactic_warnings"}.
func validation_report() -> Dictionary:
	var report := MapAnalysis.full_validation(controller.document, self)
	analysis = report["analysis"] as MapAnalysis
	report.erase("analysis")
	tactic_issues = TacticCompatibility.scan(tactic_storage, controller.document, analysis)
	report["tactic_warnings"] = TacticCompatibility.texts(tactic_issues)
	if ui.navmesh_check.button_pressed and analysis != null:
		view.set_overlay(analysis.overlay_mesh())
	return report


func _show_validation() -> void:
	var report := validation_report()
	var errors: Array[String] = report["errors"]
	var warnings: Array[String] = report["warnings"]
	var tactic_warnings: Array[String] = report["tactic_warnings"]
	var lines: Array[String] = []
	if errors.is_empty() and warnings.is_empty() and tactic_warnings.is_empty():
		lines.append("No problems found.")
	for e: String in errors:
		lines.append("ERROR: " + e)
	for w: String in warnings:
		lines.append("Warning: " + w)
	for w: String in tactic_warnings:
		lines.append("Tactics: " + w)
	if not str(report["timing_text"]).is_empty():
		lines.append("")
		lines.append(str(report["timing_text"]))
	ui.show_message("Validation — %d error(s), %d warning(s)" % [errors.size(), warnings.size() + tactic_warnings.size()], "\n".join(lines))


## Bakes the navmesh with the bot agent settings and shows it over the map.
func refresh_navmesh(show_message: bool = true) -> MapAnalysis:
	analysis = MapAnalysis.analyse(controller.document, self)
	ui.navmesh_check.set_pressed_no_signal(true)
	view.set_overlay(analysis.overlay_mesh())
	if show_message:
		flash("Navmesh: %d polygons baked in %d ms (agent radius %.1f m, height %.1f m, climb %.1f m, slope %d°)" % [
			analysis.polygon_count(), analysis.bake_msec, NavigationBuilder.AGENT_RADIUS, NavigationBuilder.AGENT_HEIGHT,
			NavigationBuilder.AGENT_MAX_CLIMB, int(NavigationBuilder.AGENT_MAX_SLOPE)])
	return analysis


## Every geometry edit, including an undo or a live transform, invalidates the current bake.
func _invalidate_navigation(_piece_id: String = "") -> void:
	analysis = null
	_navmesh_refresh_left = NAVMESH_REFRESH_DELAY
	if view.has_overlay():
		view.set_overlay(null)


func _update_navigation_overlay(delta: float) -> void:
	if not ui.navmesh_check.button_pressed or view.has_overlay() or _drag_active or not _gizmo_handle.is_empty():
		return
	_navmesh_refresh_left -= delta
	if _navmesh_refresh_left <= 0.0:
		if analysis == null:
			refresh_navmesh(false)
		else:
			view.set_overlay(analysis.overlay_mesh())


func show_timings() -> String:
	analysis = MapAnalysis.analyse(controller.document, self)
	var text := analysis.timing_text()
	ui.show_message("Route timings", text)
	return text


## After a save that changed gameplay content: warn about saved tactics that no longer fit.
## Tactic files are never changed here.
func _report_tactic_issues() -> void:
	tactic_issues = []
	if tactic_storage.list_for_map(controller.document.map_id).is_empty():
		return
	analysis = MapAnalysis.analyse(controller.document, self)
	tactic_issues = TacticCompatibility.scan(tactic_storage, controller.document, analysis)
	if not tactic_issues.is_empty():
		ui.show_message("Saved — %d tactic step(s) need review" % tactic_issues.size(),
			"This edit affects saved tactics. Nothing was changed in them; open each in the Tactical Play Creator to fix it.\n\n"
			+ "\n".join(TacticCompatibility.texts(tactic_issues)))


## Launches the FPS runtime on a copy of the current document, as [param team] from spawn
## [param spawn_index] (defaults: the toolbar choices). Returns false if blocked.
func playtest(team: String = "", spawn_index: int = -1) -> bool:
	_cancel_drag()
	var report := MapValidator.validate(controller.document)
	var errors: Array[String] = report["errors"]
	if not errors.is_empty():
		ui.show_message("Cannot playtest", "Fix these first:\n" + "\n".join(errors))
		return false
	if not team.is_empty():
		playtest_team = team
	if spawn_index >= 0:
		playtest_spawn = spawn_index
	if camera.overhead:
		camera.set_overhead(false)
	var options := {"team": playtest_team, "spawn": playtest_spawn}
	if playtest_with_bots:
		options["bots"] = true
	var error := App.start_playtest(controller.document.duplicate_document(), {
		"controller": controller,
		"path": current_path,
		"active_layer": active_layer,
		"show_navmesh": ui.navmesh_check.button_pressed,
		"camera": camera.global_transform,
		"official": official_source,
		"team": playtest_team,
		"spawn": playtest_spawn,
		"with_bots": playtest_with_bots,
	}, options)
	if error != OK:
		flash("Could not open the playtest.")
	return error == OK


## Uses the saved (or official) revision so every tactic is bound to a known map.
func open_tactic_editor() -> bool:
	if tactic_editor != null:
		return true
	var saved: MapDocument = null
	if official_source:
		saved = OfficialMaps.load_map(controller.document.map_id)
	elif not current_path.is_empty():
		saved = storage.load_path(current_path)
	if saved == null or controller.is_dirty() or saved.content_fingerprint() != controller.document.content_fingerprint():
		ui.show_message("Save the map first", "Save or open a saved map before entering Tactical Play Creator.")
		return false
	_cancel_drag()
	controller.select("")
	cursor.hide()
	ghost.hide()
	gizmo.hide()
	ui.hide()
	tactic_editor = TacticEditor.new()
	tactic_editor.store = tactic_storage
	tactic_editor.bind(saved, camera, view)
	tactic_editor.map_creator_requested.connect(close_tactic_editor)
	tactic_editor.main_menu_requested.connect(func() -> void: App.go_to(App.SCENE_MAIN_MENU))
	ui.get_parent().add_child(tactic_editor)
	return true


func close_tactic_editor() -> void:
	if tactic_editor != null:
		tactic_editor.hide()
		tactic_editor.close_editor()
		tactic_editor = null
	ui.show()


# --- tools --------------------------------------------------------------------------------------

func _set_tool(new_tool: StudioUI.Tool) -> void:
	_cancel_drag()
	tool = new_tool
	ghost.visible = false
	if tool != StudioUI.Tool.PLACE:
		place_prefab_id = ""
	if tool != StudioUI.Tool.MEASURE:
		clear_measure()
	_draw_box.visible = not _draw_piece_type().is_empty()
	if _place_preview != null:
		_place_preview.visible = tool == StudioUI.Tool.PLACE
	ui.set_active_tool(tool, place_type if place_prefab_id.is_empty() else "")
	_refresh_status()


func _on_piece_type_selected(type: String) -> void:
	place_type = type
	place_prefab_id = ""
	place_rotation = 0.0
	_set_tool(StudioUI.Tool.PLACE)
	controller.select("")
	_update_ghost_mesh()


## Arms the Place tool with a saved or stock prefab.
func select_prefab(prefab_id: String) -> bool:
	if MapPrefabs.find(controller.document, prefab_id).is_empty():
		return false
	place_prefab_id = prefab_id
	place_rotation = 0.0
	_set_tool(StudioUI.Tool.PLACE)
	controller.select("")
	_update_ghost_mesh()
	return true


func _set_snap(size: float) -> void:
	snap_size = size
	grid.snap_size = size
	_refresh_status()


func set_gizmo_mode(mode: EditorGizmo.Mode) -> void:
	gizmo.set_mode(mode)
	ui.gizmo_option.select(int(mode))


## Switches to the overhead orthographic view (or back), centred on the selection or the map.
func set_overhead(enabled: bool) -> void:
	var focus := controller.selection_pivot() if not controller.selection.is_empty() \
		else MapSnapping.bounds(controller.document.pieces).get_center()
	camera.set_overhead(enabled, focus)
	ui.overhead_check.set_pressed_no_signal(enabled)


func _on_piece_changed(piece_id: String) -> void:
	_invalidate_navigation(piece_id)
	if piece_id == controller.selected_id and controller.selection.size() == 1:
		ui.update_inspector_values(controller.selected_piece())


func _on_document_replaced() -> void:
	_cancel_draw()
	_cancel_surface()
	_invalidate_navigation()
	tactic_issues = []
	measure_points.clear()
	if controller.document.layer(active_layer).is_empty():
		active_layer = MapDocument.DEFAULT_LAYER
	_autosaved_version = controller.version
	_apply_lighting()
	_refresh_inspector()
	_refresh_history()
	_refresh_layers()
	_refresh_prefabs()
	_refresh_spawn_options()


func _on_document_state_changed(key: String) -> void:
	match key:
		"lighting":
			_apply_lighting()
		"layers":
			if controller.document.layer(active_layer).is_empty():
				active_layer = MapDocument.DEFAULT_LAYER
			_refresh_layers()
		"prefabs":
			_refresh_prefabs()
	if controller.selection.is_empty() and not ui.is_editing_text():
		_refresh_inspector()


func _apply_lighting() -> void:
	var environment := world_environment.environment
	sun.transform = _default_sun
	sun.light_energy = _default_sun_energy
	sun.light_color = Color.WHITE
	environment.ambient_light_source = _default_ambient[0]
	environment.ambient_light_color = _default_ambient[1]
	environment.ambient_light_energy = _default_ambient[2]
	MapLighting.apply(controller.document.lighting, sun, environment)


## Snapped grid intersection at the clicked height. Surface snapping uses a solid top only
## when the snapped intersection still lies on that surface.
func placement_point(screen_position: Vector2, exclude: Array[String] = []) -> Variant:
	if snap_surface:
		var origin := camera.project_ray_origin(screen_position)
		var direction := camera.project_ray_normal(screen_position)
		var hit := view.pick(origin, direction, true, exclude)
		if not hit.is_empty():
			var aabb: AABB = hit["aabb"]
			var point: Vector3 = hit["point"]
			if is_equal_approx(point.y, aabb.end.y):
				var snapped := MapSnapping.snap_position(point, snap_size)
				var piece := controller.document.get_piece(str(hit["piece_id"]))
				var local := MapDocument.piece_transform(piece).affine_inverse() * snapped
				var half := (piece["size"] as Vector3) / 2.0
				if absf(local.x) <= half.x + 0.001 and absf(local.z) <= half.z + 0.001:
					return snapped
	return _snapped_point_on_plane(screen_position, build_level)


func _snapped_point_on_plane(screen_position: Vector2, height: float) -> Variant:
	var point: Variant = _point_on_plane(screen_position, height)
	return MapSnapping.snap_position(point as Vector3, snap_size) if point != null else null


func _placement_base(anchor: Vector3, height: float) -> Vector3:
	if not place_prefab_id.is_empty():
		return anchor
	if PieceCatalog.kind(place_type) == "light":
		anchor.y += LIGHT_PLACE_HEIGHT
	else:
		anchor.y = MapSnapping.piece_base_y(place_type, anchor.y, height)
	return anchor


## Places the current piece type or prefab at a snapped [param world_position] anchor.
## Returns the new piece's ID (the first piece's for a prefab).
func place_at(world_position: Vector3) -> String:
	if not place_prefab_id.is_empty():
		var ids := controller.place_prefab(place_prefab_id, world_position, place_rotation)
		if not ids.is_empty():
			controller.update_pieces(_on_active_layer(controller.selected_pieces()), "Place on layer")
		return ids[0] if not ids.is_empty() else ""
	var height := PieceCatalog.default_size(place_type).y
	var piece := MapDocument.make_piece(place_type, _placement_base(world_position, height), place_rotation)
	piece["layer"] = active_layer
	return controller.add_piece(piece)


func _draw_piece_type() -> String:
	match tool:
		StudioUI.Tool.DRAW_FLOOR:
			return "floor"
		StudioUI.Tool.DRAW_WALL:
			return "wall"
		StudioUI.Tool.DRAW_BLOCK:
			return "block"
	return ""


func _draw_layer_is_editable() -> bool:
	return controller.document.is_layer_visible(active_layer) and not controller.document.is_layer_locked(active_layer)


func _begin_draw(screen_position: Vector2) -> void:
	if not _draw_layer_is_editable():
		flash("Choose a visible, unlocked layer to draw on.")
		return
	_draw_start = placement_point(screen_position)


## Locks the starting elevation so dragging across existing geometry keeps the brush level.
func _cursor_anchor(screen_position: Vector2) -> Variant:
	if _draw_start != null:
		return _snapped_point_on_plane(screen_position, (_draw_start as Vector3).y)
	return placement_point(screen_position)


func _draw_piece_at(screen_position: Vector2) -> Dictionary:
	if _draw_start == null:
		return {}
	var endpoint: Variant = _cursor_anchor(screen_position)
	if endpoint == null:
		return {}
	var dimensions := ui.draw_dimensions(tool)
	return MapSnapping.drawn_piece(_draw_piece_type(), _draw_start as Vector3, endpoint as Vector3, dimensions.x, dimensions.y)


func _finish_draw(screen_position: Vector2) -> void:
	var piece := _draw_piece_at(screen_position)
	_cancel_draw()
	if piece.is_empty() or not _draw_layer_is_editable():
		return
	piece["layer"] = active_layer
	controller.add_pieces([piece], "Draw %s" % str(piece["type"]))


func _cancel_draw() -> void:
	if _draw_start != null:
		_draw_start = null
		ghost.hide()


func _preview_draw(screen_position: Vector2) -> void:
	var piece := _draw_piece_at(screen_position)
	ghost.visible = not piece.is_empty()
	if piece.is_empty():
		return
	var size := piece["size"] as Vector3
	(_draw_box.mesh as BoxMesh).size = size
	_draw_box.position.y = size.y * 0.5 + CURSOR_LIFT
	ghost.position = piece["position"]
	ghost.rotation_degrees.y = float(piece["rotation_y"])
	ui.set_cursor_text("%s  %s × %s × %s m" % [PieceCatalog.label(str(piece["type"])),
		StudioUI.format_number(size.x), StudioUI.format_number(size.y), StudioUI.format_number(size.z)])


## Builds a brush through the normal editor history. Vertices and faces are local map geometry.
func draw_brush(vertices: Array, faces: Array, two_sided: bool = false, piece_id: String = "") -> String:
	var piece := BrushGeometry.piece(vertices, faces, two_sided)
	if piece.is_empty():
		return ""
	var mesh := BrushGeometry.mesh(piece["size"], piece["props"])
	if mesh == null:
		return ""
	if piece_id.is_empty():
		if not _draw_layer_is_editable():
			return ""
		piece["layer"] = active_layer
		return controller.add_piece(piece)
	var existing := controller.document.get_piece(piece_id)
	if existing.is_empty() or not view.is_pickable(existing) or str(existing["type"]) != "mesh_brush":
		return ""
	for key: String in ["id", "layer", "group", "material"]:
		piece[key] = existing[key]
	controller.update_piece(piece, "Edit brush geometry")
	return piece_id


## Adds a measured set of brush shapes on the active layer as one editor operation.
func draw_brushes(rows: Array) -> Array[String]:
	if not _draw_layer_is_editable():
		return []
	var pieces: Array[Dictionary] = []
	for row: Variant in rows:
		if not row is Dictionary or not row.get("vertices") is Array or not row.get("faces") is Array:
			return []
		var material := str(row.get("material", ""))
		if not material.is_empty() and not MapMaterials.has_material(material):
			return []
		var piece := BrushGeometry.piece(row["vertices"], row["faces"], row.get("two_sided", false) == true)
		if piece.is_empty():
			return []
		piece["layer"] = active_layer
		piece["material"] = material
		pieces.append(piece)
	return controller.add_pieces(pieces, "Draw brushes")


func _open_brush_editor(piece_id: String) -> void:
	var initial := {"vertices": [[0, 0, 0], [4, 0, 0], [4, 1, 4], [0, 1, 4]],
		"faces": [0, 1, 2, 0, 2, 3], "two_sided": false}
	var piece := controller.document.get_piece(piece_id)
	if not piece.is_empty():
		var props: Dictionary = piece["props"]
		var transform := MapDocument.piece_transform(piece)
		var vertices: Array = []
		for point: Vector3 in BrushGeometry.local_points(piece["size"], props):
			var world := transform * point
			vertices.append([world.x, world.y, world.z])
		initial = {"vertices": vertices, "faces": props["faces"], "two_sided": props["two_sided"]}
	var dialog := AcceptDialog.new()
	dialog.title = "Brush geometry"
	dialog.dialog_hide_on_ok = false
	var content := UIFactory.vbox(8)
	dialog.add_child(content)
	content.add_child(UIFactory.label("Vertices use map coordinates in metres. Each face is three zero-based vertex indices, clockwise from the visible side.", &"MutedLabel", true))
	var input := TextEdit.new()
	input.custom_minimum_size = Vector2(560, 310)
	input.text = JSON.stringify(initial, "\t")
	content.add_child(input)
	var error := UIFactory.label("", &"WarningLabel", true)
	content.add_child(error)
	dialog.confirmed.connect(func() -> void:
		var values: Variant = JSON.parse_string(input.text)
		if not values is Dictionary or not values.get("vertices") is Array or not values.get("faces") is Array:
			error.text = "Enter a JSON object with vertices and faces."
			return
		if draw_brush(values["vertices"], values["faces"], values.get("two_sided", false) == true, piece_id).is_empty():
			error.text = "Check the geometry and make sure the target layer is visible and unlocked."
			return
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## Commits one polygon through the same document and history used by the other drawing tools.
func draw_surface(points: PackedVector3Array, thickness: float = 0.2) -> String:
	if not _draw_layer_is_editable():
		flash("Choose a visible, unlocked layer to draw on.")
		return ""
	var piece := PolygonSurface.piece(points, thickness)
	if piece.is_empty():
		flash("A surface needs at least three corners with an outline that does not cross itself.")
		return ""
	piece["layer"] = active_layer
	return controller.add_piece(piece)


func _add_surface_corner(button: InputEventMouseButton) -> void:
	if not _draw_layer_is_editable():
		flash("Choose a visible, unlocked layer to draw on.")
		return
	var point: Variant = _surface_point_at(button.position, button.alt_pressed)
	if point == null or (not _surface_points.is_empty() and _surface_points[-1].is_equal_approx(point as Vector3)):
		return
	if _surface_points.size() >= PolygonSurface.MAX_POINTS:
		flash("Finish this surface before adding more corners.")
		return
	_surface_points.append(point)
	_refresh_surface_outline(null)


func _surface_point_at(screen_position: Vector2, force_grid: bool) -> Variant:
	return _snapped_point_on_plane(screen_position, build_level) if force_grid else placement_point(screen_position)


func _cancel_surface() -> void:
	_surface_points.clear()
	_surface_hover = null
	_surface_outline.mesh = null


func _refresh_surface_outline(hover: Variant) -> void:
	_surface_hover = hover
	var points := _surface_points.duplicate()
	if hover != null and points.size() < PolygonSurface.MAX_POINTS:
		points.append(hover)
	if points.size() < 2:
		_surface_outline.mesh = null
		return
	var outline := ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: Vector3 in points:
		outline.surface_add_vertex(point + Vector3.UP * CURSOR_LIFT)
	if points.size() > 2:
		outline.surface_add_vertex(points[0] + Vector3.UP * CURSOR_LIFT)
	outline.surface_end()
	_surface_outline.mesh = outline


func _on_active_layer(pieces: Array[Dictionary]) -> Array[Dictionary]:
	for piece: Dictionary in pieces:
		piece["layer"] = active_layer
	return pieces


# --- selection ----------------------------------------------------------------------------------

## Click selection at a screen position. Selects the whole group of the piece hit; with
## [param additive] (Shift) toggles it in the selection; with [param single] (Alt) picks only
## the piece itself. Returns the piece ID hit, or "".
func click_select(screen_position: Vector2, additive: bool = false, single: bool = false) -> String:
	var hit := view.pick(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit.is_empty():
		if not additive:
			controller.select("")
		return ""
	var id := str(hit["piece_id"])
	var ids: Array[String] = [id]
	if not single:
		ids = controller.group_members(id)
	if additive:
		controller.toggle_selection(ids)
	elif not controller.is_selected(id) or single:
		controller.select_many(ids)
	return id


## Box selection: every pickable piece whose centre is inside the screen rectangle.
func box_select(rect: Rect2, additive: bool = false) -> int:
	var ids := view.pieces_in_rect(camera, rect)
	if additive:
		var merged := controller.selection.duplicate()
		for id: String in ids:
			if not merged.has(id):
				merged.append(id)
		ids = merged
	controller.select_many(ids)
	return controller.selection.size()


func select_all() -> void:
	var ids: Array[String] = []
	for piece: Dictionary in controller.document.pieces:
		if view.is_pickable(piece):
			ids.append(str(piece["id"]))
	controller.select_many(ids)


func copy_selection() -> int:
	var count := MapClipboard.copy(controller.selected_pieces())
	if count > 0:
		flash("Copied %d piece(s). Paste here or in another map." % count)
	return count


## Pastes the clipboard so its pivot lands on [param world_position]. Returns the new IDs.
func paste_at(world_position: Vector3) -> Array[String]:
	if not MapClipboard.has_content():
		flash("Nothing to paste.")
		return []
	return controller.place_relative(_on_active_layer(MapClipboard.contents()), world_position, 0.0, "Paste")


func duplicate_selection() -> Array[String]:
	return controller.duplicate_selection(Vector3(snap_size, 0, snap_size))


## Rotates the selection around its pivot by [param degrees] (snapped to the angle snap).
func rotate_selection(degrees: float) -> bool:
	return controller.rotate_selection(degrees)


func _paste_point() -> Vector3:
	if _hover_point != null:
		return _hover_point as Vector3
	var ahead := camera.global_position - camera.global_transform.basis.z * 10.0
	return Vector3(snappedf(ahead.x, snap_size), build_level, snappedf(ahead.z, snap_size))


# --- measuring ----------------------------------------------------------------------------------

## Adds a measuring point; the second point completes a measurement. Returns the result
## (see MapSnapping.measure) or {} while only one point is set.
func add_measure_point(point: Vector3) -> Dictionary:
	if measure_points.size() >= 2:
		measure_points.clear()
	measure_points.append(point)
	if measure_points.size() < 2:
		measure_result = {}
		view.set_measure(null, null)
		flash("Measure: click the second point.")
		return {}
	measure_result = MapSnapping.measure(measure_points[0], measure_points[1])
	var text := MapSnapping.measure_text(measure_result)
	view.set_measure(measure_points[0], measure_points[1], text)
	flash("Measured " + text)
	return measure_result


func clear_measure() -> void:
	measure_points.clear()
	measure_result = {}
	view.set_measure(null, null)


## World point under the cursor for measuring: the surface hit, else the build plane.
func _surface_point(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit := view.pick(origin, direction, true)
	if not hit.is_empty():
		return hit["point"]
	return Plane(GROUND_PLANE_NORMAL, build_level).intersects_ray(origin, direction)


# --- gizmo --------------------------------------------------------------------------------------

## Starts a gizmo drag on a handle ("x", "y", "z" or "ring"). Returns false with no selection.
func gizmo_begin(handle: String) -> bool:
	if controller.selection.is_empty() or not gizmo.handles().has(handle):
		return false
	_gizmo_handle = handle
	_gizmo_before = controller.selected_pieces()
	_gizmo_pivot = controller.selection_pivot()
	return true


## Previews the drag at [param value]: metres along the axis (move, scale) or degrees (rotate),
## snapped to the grid size or the angle snap. Nothing is recorded until [method gizmo_end].
func gizmo_apply(value: float) -> void:
	if _gizmo_handle.is_empty():
		return
	match gizmo.mode:
		EditorGizmo.Mode.MOVE:
			controller.preview_pieces(MapSnapping.moved(_gizmo_before, EditorGizmo.AXES[_gizmo_handle] * snappedf(value, snap_size)))
		EditorGizmo.Mode.ROTATE:
			controller.preview_pieces(MapSnapping.rotated(_gizmo_before, _gizmo_pivot, snappedf(value, angle_snap)))
		EditorGizmo.Mode.SCALE:
			var states: Array[Dictionary] = []
			var grow := EditorGizmo.AXES[_gizmo_handle].abs() * snappedf(value, snap_size)
			for before: Dictionary in _gizmo_before:
				var state := before.duplicate(true)
				if PieceCatalog.is_resizable(str(state["type"])):
					state["size"] = ((state["size"] as Vector3) + grow).maxf(MapValidator.MIN_SIZE)
				states.append(state)
			controller.preview_pieces(states)


func gizmo_end() -> void:
	if _gizmo_handle.is_empty():
		return
	_gizmo_handle = ""
	controller.commit_previews(_gizmo_before, ["Move", "Rotate", "Scale"][gizmo.mode])
	_refresh_inspector()


func gizmo_cancel() -> void:
	if not _gizmo_handle.is_empty():
		_gizmo_handle = ""
		controller.cancel_previews(_gizmo_before)


func _update_gizmo() -> void:
	gizmo.visible = tool == StudioUI.Tool.SELECT and not controller.selection.is_empty() and tactic_editor == null
	if not gizmo.visible:
		return
	var single := controller.selection.size() == 1
	var pivot := _gizmo_pivot if not _gizmo_handle.is_empty() and gizmo.mode != EditorGizmo.Mode.MOVE else \
		((controller.selected_piece()["position"] as Vector3) if single else controller.selection_pivot())
	var yaw := float(controller.selected_piece()["rotation_y"]) if single and gizmo.mode == EditorGizmo.Mode.SCALE else 0.0
	var reach := camera.size * 0.1 if camera.overhead else camera.global_position.distance_to(pivot) * 0.14
	gizmo.place(pivot, yaw, clampf(reach, 0.8, 30.0))


# --- frame and input ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if tactic_editor != null:
		return
	var mouse := get_viewport().get_mouse_position()
	_hover_point = null if camera.is_looking else _cursor_anchor(mouse)
	cursor.visible = _hover_point != null
	if _draw_start == null or camera.is_looking:
		ghost.visible = _hover_point != null and tool == StudioUI.Tool.PLACE
	if _hover_point != null:
		var p := _hover_point as Vector3
		_update_snap_marker(p)
		if tool == StudioUI.Tool.PLACE:
			_update_place_ghost(p)
		ui.set_cursor_text("Cursor  x %s  y %s  z %s%s" % [StudioUI.format_number(p.x), StudioUI.format_number(p.y),
			StudioUI.format_number(p.z), _area_suffix(p)])
	else:
		ui.set_cursor_text("Cursor —")
	if _draw_start != null and not camera.is_looking:
		_preview_draw(mouse)
	if tool == StudioUI.Tool.DRAW_SURFACE and not _surface_points.is_empty():
		var hover: Variant = null if camera.is_looking or get_viewport().gui_get_hovered_control() != null \
			else _surface_point_at(mouse, Input.is_key_pressed(KEY_ALT))
		if hover != _surface_hover:
			_refresh_surface_outline(hover)
	grid.position.y = build_level + GRID_LIFT
	_update_gizmo()
	_update_navigation_overlay(delta)
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		if controller.version != _autosaved_version:
			autosave_now()
		_autosave_left = AUTOSAVE_SECONDS
	_refresh_status()


func _area_suffix(point: Vector3) -> String:
	var area := MapTactical.area_name_at(controller.document, point)
	return "" if area.is_empty() else "   ·   %s" % area


## Capture the end of a stroke even on a panel, where GUI events bypass _unhandled_input.
func _input(event: InputEvent) -> void:
	if _draw_start == null:
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return
	if camera.is_looking or get_viewport().gui_get_hovered_control() != null:
		_cancel_draw()
	else:
		_finish_draw(button.position)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if tactic_editor != null:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_on_left_press(button)
		else:
			_on_left_release(button)
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if not _gizmo_handle.is_empty():
			gizmo_apply(_wrapped_delta(gizmo.handle_value(camera, motion.position, _gizmo_handle) - _gizmo_start))
		elif _drag_active:
			_update_drag(motion.position)
		elif _box_active:
			_update_box(motion.position)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not ui.is_editing_text():
		if _handle_key(key):
			get_viewport().set_input_as_handled()


## Ring values wrap at ±180°; keep the drag delta continuous.
func _wrapped_delta(value: float) -> float:
	return wrapf(value, -180.0, 180.0) if _gizmo_handle == "ring" else value


func _on_left_press(button: InputEventMouseButton) -> void:
	if camera.is_looking:
		return
	var screen_position := button.position
	match tool:
		StudioUI.Tool.DRAW_SURFACE:
			_add_surface_corner(button)
			return
		StudioUI.Tool.DRAW_FLOOR, StudioUI.Tool.DRAW_WALL, StudioUI.Tool.DRAW_BLOCK:
			_begin_draw(screen_position)
			return
		StudioUI.Tool.PLACE:
			var point: Variant = placement_point(screen_position)
			if point != null:
				place_at(point as Vector3)
				controller.select("")
			return
		StudioUI.Tool.MEASURE:
			var point: Variant = _surface_point(screen_position)
			if point != null:
				add_measure_point(point as Vector3)
			return
	var handle := gizmo.handle_at(camera, screen_position)
	if not handle.is_empty() and gizmo_begin(handle):
		_gizmo_start = gizmo.handle_value(camera, screen_position, handle)
		return
	var hit_id := click_select(screen_position, button.shift_pressed, button.alt_pressed)
	if hit_id.is_empty():
		_box_active = true
		_box_start = screen_position
	elif not button.shift_pressed and controller.is_selected(hit_id):
		_begin_drag(screen_position)


func _on_left_release(button: InputEventMouseButton) -> void:
	if not _gizmo_handle.is_empty():
		gizmo_end()
	elif _drag_active:
		_end_drag()
	elif _box_active:
		_box_active = false
		_box_rect.visible = false
		var rect := Rect2(_box_start, button.position - _box_start).abs()
		if rect.size.length() >= BOX_SELECT_MIN_PIXELS:
			box_select(rect, button.shift_pressed)


func _update_box(screen_position: Vector2) -> void:
	var rect := Rect2(_box_start, screen_position - _box_start).abs()
	_box_rect.visible = rect.size.length() >= BOX_SELECT_MIN_PIXELS
	_box_rect.position = rect.position
	_box_rect.size = rect.size


func _begin_drag(screen_position: Vector2) -> void:
	_drag_before = controller.selected_pieces()
	if _drag_before.is_empty():
		return
	var plane_point: Variant = _point_on_plane(screen_position, (controller.selected_piece()["position"] as Vector3).y)
	if plane_point == null:
		return
	_drag_anchor = plane_point as Vector3
	_drag_active = true


func _update_drag(screen_position: Vector2) -> void:
	var primary := _drag_before[_drag_before.size() - 1]
	var plane_point: Variant = _point_on_plane(screen_position, (primary["position"] as Vector3).y)
	if plane_point == null:
		return
	controller.preview_pieces(MapSnapping.moved(_drag_before, drag_offset((plane_point as Vector3) - _drag_anchor, screen_position)))


## The offset a drag of [param delta] metres applies to the dragged pieces: snapped to the grid,
## then (if enabled) raised onto the surface under the cursor and pulled flush to nearby edges.
func drag_offset(delta: Vector3, screen_position: Variant = null) -> Vector3:
	var offset := Vector3(snappedf(delta.x, snap_size), 0.0, snappedf(delta.z, snap_size))
	if _drag_before.is_empty():
		return offset
	var ids: Array[String] = []
	for piece: Dictionary in _drag_before:
		ids.append(str(piece["id"]))
	var primary := _drag_before[_drag_before.size() - 1]
	if snap_surface and screen_position is Vector2 and not PieceCatalog.is_walkable(str(primary["type"])) \
			and PieceCatalog.is_solid(str(primary["type"])):
		var hit := view.pick(camera.project_ray_origin(screen_position as Vector2),
			camera.project_ray_normal(screen_position as Vector2), true, ids)
		if not hit.is_empty() and is_equal_approx((hit["point"] as Vector3).y, (hit["aabb"] as AABB).end.y):
			offset.y = (hit["aabb"] as AABB).end.y - MapSnapping.bounds(_drag_before).position.y
	if snap_edge:
		var moved_box := MapSnapping.bounds(_drag_before)
		moved_box.position += offset
		offset += MapSnapping.edge_offset(controller.document, moved_box, ids)
	return offset


func _end_drag() -> void:
	if not _drag_active:
		return
	_drag_active = false
	controller.commit_previews(_drag_before, "Move")


func _cancel_drag() -> void:
	_cancel_draw()
	_cancel_surface()
	if _drag_active:
		_drag_active = false
		controller.cancel_previews(_drag_before)
	gizmo_cancel()
	_box_active = false
	if _box_rect != null:
		_box_rect.visible = false


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
			KEY_Y:
				controller.redo()
			KEY_S:
				save_map()
			KEY_D:
				duplicate_selection()
			KEY_C:
				copy_selection()
			KEY_X:
				if copy_selection() > 0:
					controller.delete_selection()
			KEY_V:
				paste_at(_paste_point())
			KEY_A:
				select_all()
			KEY_G:
				if key.shift_pressed:
					controller.ungroup_selection()
				else:
					controller.group_selection()
				_refresh_inspector()
			KEY_N:
				_guard_unsaved(_new_map)
			KEY_O:
				_open_dialog()
			_:
				return false
		return true
	if key.echo and not (code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]):
		return false
	match code:
		KEY_1:
			_set_tool(StudioUI.Tool.SELECT)
		KEY_2:
			_on_piece_type_selected(place_type)
		KEY_3:
			_set_tool(StudioUI.Tool.DRAW_FLOOR)
		KEY_4:
			_set_tool(StudioUI.Tool.DRAW_WALL)
		KEY_5:
			_set_tool(StudioUI.Tool.DRAW_BLOCK)
		KEY_6:
			_set_tool(StudioUI.Tool.DRAW_SURFACE)
		KEY_ENTER, KEY_KP_ENTER:
			if tool != StudioUI.Tool.DRAW_SURFACE:
				return false
			if not draw_surface(_surface_points).is_empty():
				_cancel_surface()
		KEY_M:
			_set_tool(StudioUI.Tool.MEASURE)
		KEY_G:
			set_gizmo_mode(EditorGizmo.Mode.MOVE)
		KEY_T:
			set_gizmo_mode(EditorGizmo.Mode.ROTATE)
		KEY_X:
			set_gizmo_mode(EditorGizmo.Mode.SCALE)
		KEY_TAB:
			set_overhead(not camera.overhead)
		KEY_ESCAPE:
			if not _surface_points.is_empty():
				_cancel_surface()
			elif _drag_active or not _gizmo_handle.is_empty() or _box_active or _draw_start != null:
				_cancel_drag()
			elif tool != StudioUI.Tool.SELECT:
				_set_tool(StudioUI.Tool.SELECT)
			else:
				controller.select("")
		KEY_BACKSPACE:
			if tool != StudioUI.Tool.DRAW_SURFACE:
				controller.delete_selection()
			elif not _surface_points.is_empty():
				_surface_points.remove_at(_surface_points.size() - 1)
				_refresh_surface_outline(null)
		KEY_DELETE:
			controller.delete_selection()
		KEY_R:
			var step := -angle_snap if key.shift_pressed else angle_snap
			if tool == StudioUI.Tool.PLACE:
				place_rotation = MapDocument.normalise_rotation(place_rotation + step)
			else:
				rotate_selection(step)
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
	if tool == StudioUI.Tool.SELECT and not controller.selection.is_empty():
		controller.move_selection(offset)
	elif offset.y != 0.0:
		build_level += offset.y


func _build_snap_marker() -> void:
	var marker := ImmediateMesh.new()
	marker.surface_begin(Mesh.PRIMITIVE_LINES)
	for point: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		marker.surface_add_vertex(point)
	marker.surface_end()
	cursor.mesh = marker


func _update_snap_marker(point: Vector3) -> void:
	cursor.position = point + Vector3.UP * CURSOR_LIFT
	var reach := camera.size * 0.011 if camera.overhead else camera.global_position.distance_to(point) * 0.014
	cursor.scale = Vector3.ONE * maxf(reach, 0.05)


func _update_place_ghost(anchor: Vector3) -> void:
	ghost.position = _placement_base(anchor, PieceCatalog.default_size(place_type).y)
	ghost.rotation_degrees.y = place_rotation


func _update_ghost_mesh() -> void:
	if _place_preview != null:
		_place_preview.free()
	var pieces: Array[Dictionary] = []
	if place_prefab_id.is_empty():
		pieces.append(MapDocument.make_piece(place_type, Vector3.ZERO))
	else:
		pieces.assign(MapPrefabs.find(controller.document, place_prefab_id).get("pieces", []) as Array)
	_place_preview = MapBuilder.build_preview(pieces, _ghost_material)
	_place_preview.position.y = CURSOR_LIFT
	ghost.add_child(_place_preview)


# --- refresh ------------------------------------------------------------------------------------

func _refresh_history() -> void:
	ui.set_history_state(controller.can_undo(), controller.can_redo(), controller.is_dirty(),
		controller.document.name, controller.undo_action_name())
	ui.update_texture_choice(controller.selected_pieces())


func _refresh_inspector() -> void:
	var single := controller.selected_piece() if controller.selection.size() == 1 else {}
	ui.show_inspector(single, controller.document, current_path, controller.selected_pieces())


func _refresh_layers() -> void:
	var counts: Dictionary = {}
	for piece: Dictionary in controller.document.pieces:
		counts[piece["layer"]] = int(counts.get(piece["layer"], 0)) + 1
	ui.show_layers(controller.document, active_layer, counts)


func _refresh_prefabs() -> void:
	ui.show_prefabs(MapPrefabs.all(controller.document))
	if not place_prefab_id.is_empty():
		if MapPrefabs.find(controller.document, place_prefab_id).is_empty():
			_set_tool(StudioUI.Tool.SELECT)
		else:
			_update_ghost_mesh()


func _refresh_spawn_options() -> void:
	ui.team_option.select(StudioUI.TEAMS.find(playtest_team))
	ui.set_spawn_count(MapBuilder.spawn_points(controller.document, playtest_team).size())
	playtest_spawn = clampi(playtest_spawn, 0, maxi(0, ui.spawn_option.item_count - 1))
	ui.spawn_option.select(playtest_spawn)


## Shows a transient message in the status bar.
func flash(text: String) -> void:
	_message = text
	_message_until = Time.get_ticks_msec() + int(MESSAGE_SECONDS * 1000.0)


func _refresh_status() -> void:
	var tool_text := "Select (%d selected)" % controller.selection.size()
	if tool == StudioUI.Tool.MEASURE:
		tool_text = "Measure"
	elif tool == StudioUI.Tool.PLACE:
		var what := PieceCatalog.label(place_type) if place_prefab_id.is_empty() \
			else str(MapPrefabs.find(controller.document, place_prefab_id).get("name", "prefab"))
		tool_text = "Place %s (R rotates, %s°)" % [what, StudioUI.format_number(place_rotation)]
	elif tool == StudioUI.Tool.DRAW_SURFACE:
		tool_text = "Surface (%d corners) · Enter finish · Alt use grid height" % _surface_points.size()
	elif not _draw_piece_type().is_empty():
		tool_text = "Draw %s (drag on the grid)" % _draw_piece_type()
	var p := camera.position
	ui.set_status("%s   ·   %d pieces   ·   Grid %s m   ·   Angle %d°   ·   Build height %s m   ·   Camera %.0f, %.0f, %.0f   ·   %s" % [
		tool_text, controller.document.pieces.size(), StudioUI.format_number(snap_size), int(angle_snap),
		StudioUI.format_number(build_level), p.x, p.y, p.z,
		"TOP VIEW" if camera.overhead else ("LOOKING (RMB held)" if camera.is_looking else "Hold RMB to fly"),
	] + ("   ·   Updating navmesh…" if ui.navmesh_check.button_pressed and analysis == null else "")
		+ ("   ·   " + _message if Time.get_ticks_msec() < _message_until else ""))
