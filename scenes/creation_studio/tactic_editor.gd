class_name TacticEditor
extends Control
## Tactical mode uses the Studio's camera and map geometry. It edits only a tactic document.

signal map_creator_requested
signal main_menu_requested

enum EditMode { SET_START, ADD_WAYPOINT, MOVE_POINT }

var document: TacticDocument
var store := TacticStorage.new()
var preview: TacticPreview
var selected_slot: int = 0
var selected_point: int = 0
var edit_mode: EditMode = EditMode.SET_START
var dirty: bool = false

var _map: MapDocument
var _camera: EditorFlyCamera
var _map_view: MapEditorView
var _marker_root: Node3D
var _name_edit: LineEdit
var _mode_picker: OptionButton
var _point_list: ItemList
var _delete_button: Button
var _stop_button: Button
var _progress_labels: Array[Label] = []
var _status: Label
var _open_dialog: FileDialog
var _confirm_dialog: ConfirmationDialog
var _after_confirmation: Callable
var _click_pending: bool = false
var _click: Vector2


func bind(map: MapDocument, camera: EditorFlyCamera, map_view: MapEditorView) -> void:
	_map = map
	_camera = camera
	_map_view = map_view
	document = TacticDocument.create(map)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_root = Node3D.new()
	_marker_root.name = "TacticMarkers"
	_map_view.add_child(_marker_root)
	_build_controls()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if preview != null:
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT and click.pressed and not _camera.is_looking:
		_click = click.position
		_click_pending = true
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not _click_pending:
		return
	_click_pending = false
	var origin := _camera.project_ray_origin(_click)
	var direction := _camera.project_ray_normal(_click)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * MapEditorView.PICK_DISTANCE,
		Hitscan.LAYER_WORLD)
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos(deg_to_rad(NavigationBuilder.AGENT_MAX_SLOPE)):
		_status.text = "Click a floor, ramp or other walkable surface."
		return
	_status.text = apply_point(hit["position"] as Vector3)


## Sets a start, appends a waypoint, or relocates the selected point. Returns an error or "".
func apply_point(point: Vector3) -> String:
	if not TacticDocument.is_valid_point(point):
		return "This position is outside the editing area."
	var slot := document.slots[selected_slot]
	if edit_mode != EditMode.SET_START and not slot.has_start:
		return "Set this player's start position first."
	stop_preview()
	match edit_mode:
		EditMode.SET_START:
			slot.start = point
			slot.has_start = true
			selected_point = 0
		EditMode.ADD_WAYPOINT:
			if slot.route.size() >= TacticDocument.MAX_WAYPOINTS:
				return "This player has reached the waypoint limit."
			slot.route.append(point)
			selected_point = slot.route.size()
		EditMode.MOVE_POINT:
			if selected_point == 0:
				slot.start = point
			else:
				slot.route[selected_point - 1] = point
	dirty = true
	_refresh()
	return ""


func remove_waypoint() -> void:
	if selected_point < 1:
		return
	stop_preview()
	document.slots[selected_slot].route.remove_at(selected_point - 1)
	selected_point -= 1
	dirty = true
	_refresh()


func save_tactic() -> String:
	var problem := store.save(document, _map)
	if problem.is_empty():
		dirty = false
		_status.text = "Saved %s." % document.display_name
	else:
		_status.text = problem
	return problem


func load_tactic(path: String) -> String:
	var result := store.load_path(path, _map)
	var problem := str(result["error"])
	if not problem.is_empty():
		_status.text = problem
		return problem
	_set_document(result["tactic"] as TacticDocument)
	_status.text = "Opened %s." % document.display_name
	return ""


func start_preview() -> String:
	var problem := document.validate()
	if problem.is_empty():
		problem = document.compatibility_error(_map)
	if not problem.is_empty():
		_status.text = problem
		return problem
	stop_preview()
	preview = TacticPreview.new()
	preview.name = "TacticPreview"
	preview.status_changed.connect(_show_progress)
	_map_view.add_child(preview)
	preview.begin(document, _map_view)
	_stop_button.disabled = false
	_status.text = "Preview started. Stop to edit or click Preview to restart."
	return ""


func stop_preview() -> void:
	if preview == null:
		return
	_map_view.remove_child(preview)
	preview.queue_free()
	preview = null
	_stop_button.disabled = true
	_refresh_progress()


func close_editor() -> void:
	stop_preview()
	_marker_root.queue_free()
	queue_free()


func _set_document(tactic: TacticDocument) -> void:
	stop_preview()
	document = tactic
	_name_edit.text = tactic.display_name
	selected_point = 0
	dirty = false
	edit_mode = EditMode.SET_START
	_mode_picker.select(EditMode.SET_START)
	_refresh()


func _refresh() -> void:
	var slot := document.slots[selected_slot]
	_point_list.clear()
	_point_list.add_item("Start" if slot.has_start else "Start · unset")
	if slot.has_start:
		_point_list.set_item_tooltip(0, str(slot.start))
	for i: int in slot.route.size():
		var point := slot.route[i]
		_point_list.add_item("%d    %.1f, %.1f, %.1f" % [i + 1, point.x, point.y, point.z])
	_point_list.select(selected_point)
	_delete_button.disabled = selected_point < 1
	_refresh_progress()
	_draw_routes()


func _refresh_progress() -> void:
	for i: int in document.slots.size():
		var slot := document.slots[i]
		var text := "%d waypoints" % slot.route.size() if slot.has_start else "Start unset"
		_show_progress(i, preview.statuses[i] if preview != null else text)


func _show_progress(slot: int, text: String) -> void:
	_progress_labels[slot].text = "Player %d  ·  %s" % [slot + 1, text]


func _draw_routes() -> void:
	for child: Node in _marker_root.get_children():
		_marker_root.remove_child(child)
		child.queue_free()
	for i: int in document.slots.size():
		var slot := document.slots[i]
		if not slot.has_start:
			continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = TacticPreview.COLORS[i]
		_add_marker(slot.start, "P%d" % (i + 1), 0.24, material)
		if slot.route.is_empty():
			continue
		var line := ImmediateMesh.new()
		line.surface_begin(Mesh.PRIMITIVE_LINES, material)
		var previous := slot.start
		for j: int in slot.route.size():
			var point := slot.route[j]
			line.surface_add_vertex(previous + Vector3.UP * 0.13)
			line.surface_add_vertex(point + Vector3.UP * 0.13)
			previous = point
			var label := "%d" % (j + 1) if i == selected_slot else ""
			_add_marker(point, label, 0.18 if i == selected_slot and selected_point == j + 1 else 0.10, material)
		line.surface_end()
		var instance := MeshInstance3D.new()
		instance.mesh = line
		_marker_root.add_child(instance)


func _add_marker(point: Vector3, text: String, radius: float, material: StandardMaterial3D) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	marker.mesh = mesh
	marker.material_override = material
	marker.position = point + Vector3.UP * radius
	_marker_root.add_child(marker)
	if not text.is_empty():
		var label := Label3D.new()
		label.text = text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = material.albedo_color
		label.pixel_size = 0.007
		label.position.y = radius + 0.2
		marker.add_child(label)


func _build_controls() -> void:
	var root := UIFactory.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := PanelContainer.new()
	top.theme_type_variation = &"TopBarPanel"
	root.add_child(top)
	var toolbar := UIFactory.hbox()
	top.add_child(toolbar)
	toolbar.add_child(UIFactory.label("TACTICAL PLAY CREATOR", &"LogoLabel"))
	_name_edit = LineEdit.new()
	_name_edit.text = document.display_name
	_name_edit.max_length = TacticDocument.MAX_NAME_LENGTH
	_name_edit.placeholder_text = "Tactic name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(value: String) -> void:
		document.display_name = value
		dirty = true)
	toolbar.add_child(_name_edit)
	_add_button(toolbar, "New", func() -> void: _guard_unsaved(_new_tactic))
	_add_button(toolbar, "Open", _choose_file)
	_add_button(toolbar, "Save", func() -> void: save_tactic())
	_add_button(toolbar, "Preview", func() -> void: start_preview()).theme_type_variation = &"AccentButton"
	_stop_button = _add_button(toolbar, "Stop", func() -> void:
		stop_preview()
		_status.text = "Preview stopped.")
	_stop_button.disabled = true
	_add_button(toolbar, "Map Creator", func() -> void: _guard_unsaved(map_creator_requested.emit))
	_add_button(toolbar, "Menu", func() -> void: _guard_unsaved(main_menu_requested.emit))

	var middle := UIFactory.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)
	var side := PanelContainer.new()
	side.theme_type_variation = &"SidebarPanel"
	side.custom_minimum_size.x = 330
	middle.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var panel := UIFactory.vbox(10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.add_child(UIFactory.label("%s  ·  revision %d" % [_map.name, _map.revision], &"AccentLabel", true))
	panel.add_child(UIFactory.label("Select a player and a tool, then click a walkable surface. Hold RMB to fly.", &"MutedLabel", true))
	var slots := OptionButton.new()
	for i: int in TacticDocument.SLOT_COUNT:
		slots.add_item("Player %d" % (i + 1))
	slots.item_selected.connect(func(index: int) -> void:
		selected_slot = index
		selected_point = 0
		edit_mode = EditMode.SET_START
		_mode_picker.select(edit_mode)
		_refresh())
	panel.add_child(slots)
	_mode_picker = OptionButton.new()
	for tool_name: String in ["Set start", "Add waypoint", "Move selected point"]:
		_mode_picker.add_item(tool_name)
	_mode_picker.item_selected.connect(func(index: int) -> void: edit_mode = index as EditMode)
	panel.add_child(_mode_picker)
	_point_list = ItemList.new()
	_point_list.custom_minimum_size.y = 180
	_point_list.item_selected.connect(func(index: int) -> void:
		selected_point = index
		_delete_button.disabled = index == 0
		_draw_routes())
	panel.add_child(_point_list)
	_delete_button = _add_button(panel, "Remove selected waypoint", remove_waypoint)

	panel.add_child(HSeparator.new())
	for i: int in TacticDocument.SLOT_COUNT:
		var label := UIFactory.label("", &"MutedLabel", true)
		label.add_theme_color_override(&"font_color", TacticPreview.COLORS[i])
		panel.add_child(label)
		_progress_labels.append(label)
	_status = UIFactory.label("", &"WarningLabel", true)
	panel.add_child(_status)
	_open_dialog = FileDialog.new()
	_open_dialog.title = "Open tactic"
	_open_dialog.access = FileDialog.ACCESS_USERDATA
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = PackedStringArray(["*.f2ftactic.json ; Frag to Fame tactics"])
	_open_dialog.file_selected.connect(func(path: String) -> void:
		_guard_unsaved(func() -> void: load_tactic(path)))
	add_child(_open_dialog)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Unsaved tactic"
	_confirm_dialog.dialog_text = "Discard the unsaved changes to this tactic?"
	_confirm_dialog.ok_button_text = "Discard changes"
	_confirm_dialog.confirmed.connect(func() -> void: _after_confirmation.call())
	add_child(_confirm_dialog)


func _choose_file() -> void:
	if DirAccess.dir_exists_absolute(store.directory):
		_open_dialog.current_dir = store.directory
	_open_dialog.popup_centered_ratio(0.65)


func _new_tactic() -> void:
	_set_document(TacticDocument.create(_map))
	_status.text = ""


func _guard_unsaved(action: Callable) -> void:
	if dirty:
		_after_confirmation = action
		_confirm_dialog.popup_centered()
	else:
		action.call()


func _add_button(parent: Control, caption: String, action: Callable) -> Button:
	var button := UIFactory.button(caption)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
