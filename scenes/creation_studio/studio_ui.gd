class_name StudioUI
extends Control
## Creation Studio interface: toolbar, options bar, piece and prefab palette, inspector, layers
## panel, status bar, open-map panel and dialogs. Pure presentation — it emits intent signals and
## never edits the document itself.

signal new_requested
signal open_requested
signal save_requested
signal validate_requested
signal playtest_requested
signal tactics_requested
signal main_menu_requested
signal undo_requested
signal redo_requested
signal reset_view_requested
signal tool_selected(tool: Tool)
signal piece_type_selected(type: String)
signal snap_changed(size: float)
signal piece_edited(state: Dictionary)
signal metadata_edited(map_name: String, author: String, description: String)
signal map_chosen(path: String)
signal template_chosen(template_id: String)
## Every other editor command, e.g. (&"gizmo_mode", 1), (&"layer_visible", ["layer_2", false]).
## The scene controller documents the full list in its _on_action.
signal action_requested(action: StringName, value: Variant)

enum Tool { SELECT, PLACE, MEASURE }

const SNAP_SIZES: Array[float] = [0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const DEFAULT_SNAP_INDEX: int = 3
const ANGLE_SNAPS: Array[float] = [5.0, 15.0, 45.0, 90.0]
const DEFAULT_ANGLE_INDEX: int = 3
const GIZMO_MODES: Array[String] = ["Move", "Rotate", "Scale"]
const SITES: Array[String] = ["A", "B", "C"]
const HINT_SITES: Array[String] = ["", "A", "B", "C"]
const TEAMS: Array[String] = ["attack", "defence"]
const DUMMY_MOTIONS: Array[String] = ["static", "strafe"]

var undo_button: Button
var redo_button: Button
var save_button: Button
var playtest_button: Button
var main_menu_button: Button
var snap_option: OptionButton
var angle_option: OptionButton
var gizmo_option: OptionButton
var team_option: OptionButton
var spawn_option: OptionButton
var surface_check: CheckBox
var edge_check: CheckBox
var overhead_check: CheckBox
var navmesh_check: CheckBox
var select_tool_button: Button
var measure_tool_button: Button
var open_panel: Control
var message_dialog: AcceptDialog
var confirm_dialog: ConfirmationDialog

var _title_label: Label
var _status_label: Label
var _cursor_label: Label
var _inspector: VBoxContainer
var _layer_list: VBoxContainer
var _prefab_list: VBoxContainer
var _prefab_name: LineEdit
var _palette_buttons: Dictionary[String, Button] = {}
var _tool_group := ButtonGroup.new()
var _open_list: VBoxContainer
var _editing_piece: Dictionary = {}
var _fields: Dictionary[String, Control] = {}
var _confirm_callback: Callable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := UIFactory.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	layout.add_child(_build_top_bar())
	layout.add_child(_build_options_bar())
	var middle := UIFactory.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(middle)
	middle.add_child(_build_palette())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(gap)
	middle.add_child(_build_inspector_panel())
	layout.add_child(_build_status_bar())
	_build_open_panel()
	_build_dialogs()


# --- public API ---------------------------------------------------------------------------------

func set_history_state(can_undo: bool, can_redo: bool, dirty: bool, map_name: String, undo_name: String) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo
	undo_button.tooltip_text = "Undo %s (Ctrl+Z)" % undo_name if can_undo else "Nothing to undo"
	_title_label.text = "%s%s" % [map_name, "  •  unsaved changes" if dirty else ""]


func set_status(text: String) -> void:
	_status_label.text = text


func set_cursor_text(text: String) -> void:
	_cursor_label.text = text


func set_active_tool(tool: Tool, piece_type: String) -> void:
	if tool == Tool.SELECT:
		select_tool_button.set_pressed_no_signal(true)
	elif tool == Tool.MEASURE:
		measure_tool_button.set_pressed_no_signal(true)
	elif _palette_buttons.has(piece_type):
		_palette_buttons[piece_type].set_pressed_no_signal(true)
	else:
		for button: BaseButton in _tool_group.get_buttons():
			button.set_pressed_no_signal(false)


func current_snap() -> float:
	return SNAP_SIZES[snap_option.selected]


func current_angle_snap() -> float:
	return ANGLE_SNAPS[angle_option.selected]


## Fills the playtest spawn list for the chosen team.
func set_spawn_count(count: int) -> void:
	var previous := spawn_option.selected
	spawn_option.clear()
	for i: int in maxi(1, count):
		spawn_option.add_item("Spawn %d" % (i + 1), i)
	spawn_option.select(clampi(previous, 0, spawn_option.item_count - 1))


func show_message(title: String, text: String) -> void:
	message_dialog.title = title
	message_dialog.dialog_text = text
	message_dialog.popup_centered(Vector2i(640, 0))


## Asks for confirmation; [param on_confirm] runs only if the user accepts.
func confirm(text: String, ok_text: String, on_confirm: Callable, title: String = "Unsaved changes") -> void:
	_confirm_callback = on_confirm
	confirm_dialog.title = title
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	confirm_dialog.popup_centered(Vector2i(460, 0))


## [param official] is [{map_id, name}], [param recovery] the autosave listing.
func show_open_panel(saved_maps: Array[Dictionary], official: Array[Dictionary] = [], recovery: Array[Dictionary] = []) -> void:
	for child: Node in _open_list.get_children():
		child.queue_free()
	if not recovery.is_empty():
		_open_list.add_child(UIFactory.label("RECOVER UNSAVED WORK (autosave)", &"SectionLabel"))
		for entry: Dictionary in recovery:
			var row := UIFactory.hbox(6)
			var when := Time.get_datetime_string_from_unix_time(int(entry["saved_at"]), true)
			var path := str(entry["path"])
			var recover := _open_button("%s   ·   %d pieces   ·   autosaved %s" % [entry["name"], int(entry["pieces"]), when],
				func() -> void: action_requested.emit(&"recover", path))
			recover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(recover)
			row.add_child(_open_button("Discard", func() -> void: action_requested.emit(&"discard_recovery", path)))
			_open_list.add_child(row)
		_open_list.add_child(HSeparator.new())
	_open_list.add_child(UIFactory.label("OFFICIAL MAPS (saving makes your own copy)", &"SectionLabel"))
	for entry: Dictionary in official:
		var map_id := str(entry["map_id"])
		_open_list.add_child(_open_button(str(entry["name"]), func() -> void: action_requested.emit(&"official_chosen", map_id)))
	_open_list.add_child(UIFactory.label("TEMPLATES", &"SectionLabel"))
	for template: Array in [["blank", "Blank map"], ["sandbox_arena", "Sandbox Arena (dev) — FPS Sandbox test map"]]:
		var template_id := str(template[0])
		_open_list.add_child(_open_button(str(template[1]), func() -> void: template_chosen.emit(template_id)))
	_open_list.add_child(HSeparator.new())
	_open_list.add_child(UIFactory.label("SAVED MAPS (user://maps)", &"SectionLabel"))
	if saved_maps.is_empty():
		_open_list.add_child(UIFactory.label("No saved maps yet.", &"MutedLabel"))
	for entry: Dictionary in saved_maps:
		var when := Time.get_datetime_string_from_unix_time(int(entry["modified"]), true)
		var path := str(entry["path"])
		_open_list.add_child(_open_button("%s   ·   %d pieces   ·   %s" % [entry["name"], int(entry["pieces"]), when],
			func() -> void: map_chosen.emit(path)))
	open_panel.visible = true


## Rebuilds the inspector: map properties (nothing selected), one piece, or a multi-selection.
func show_inspector(piece: Dictionary, doc: MapDocument, file_path: String, selection: Array[Dictionary] = []) -> void:
	_clear_inspector()
	_editing_piece = piece.duplicate(true)
	if selection.size() > 1:
		_editing_piece = {}
		_build_selection_properties(selection, doc)
	elif piece.is_empty():
		_build_map_properties(doc, file_path)
	else:
		_build_piece_properties(piece, doc)


## Refreshes field values for the currently shown piece without rebuilding (keeps focus).
func update_inspector_values(piece: Dictionary) -> void:
	if piece.is_empty() or _editing_piece.get("id", "") != piece["id"]:
		return
	_editing_piece = piece.duplicate(true)
	var p: Vector3 = piece["position"]
	var s: Vector3 = piece["size"]
	_set_spin("pos_x", p.x)
	_set_spin("pos_y", p.y)
	_set_spin("pos_z", p.z)
	_set_spin("size_x", s.x)
	_set_spin("size_y", s.y)
	_set_spin("size_z", s.z)
	_set_spin("rotation", float(piece["rotation_y"]))


## Rebuilds the layers panel. [param counts] maps layer ID to its piece count.
func show_layers(doc: MapDocument, active_layer: String, counts: Dictionary) -> void:
	for child: Node in _layer_list.get_children():
		_layer_list.remove_child(child)
		child.queue_free()
	for entry: Dictionary in doc.layers:
		var id := str(entry["id"])
		var row := UIFactory.hbox(4)
		var active := CheckBox.new()
		active.button_pressed = id == active_layer
		active.tooltip_text = "New pieces go to this layer"
		active.focus_mode = Control.FOCUS_NONE
		active.pressed.connect(func() -> void: action_requested.emit(&"layer_active", id))
		row.add_child(active)
		var name_label := UIFactory.label("%s (%d)" % [entry["name"], int(counts.get(id, 0))])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		row.add_child(_layer_toggle("Show", bool(entry["visible"]), "Show or hide in the editor only",
			func(on: bool) -> void: action_requested.emit(&"layer_visible", [id, on])))
		row.add_child(_layer_toggle("Lock", bool(entry["locked"]), "Locked pieces cannot be selected",
			func(on: bool) -> void: action_requested.emit(&"layer_locked", [id, on])))
		if id != MapDocument.DEFAULT_LAYER:
			var remove := UIFactory.button("✕")
			remove.tooltip_text = "Remove layer (pieces move to Default)"
			remove.focus_mode = Control.FOCUS_NONE
			remove.pressed.connect(func() -> void: action_requested.emit(&"layer_remove", id))
			row.add_child(remove)
		_layer_list.add_child(row)


func show_prefabs(prefabs: Array[Dictionary]) -> void:
	for child: Node in _prefab_list.get_children():
		_prefab_list.remove_child(child)
		child.queue_free()
	for entry: Dictionary in prefabs:
		var id := str(entry["id"])
		var row := UIFactory.hbox(2)
		var place := UIFactory.button(str(entry["name"]), &"SidebarButton")
		place.alignment = HORIZONTAL_ALIGNMENT_LEFT
		place.clip_text = true
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.focus_mode = Control.FOCUS_NONE
		place.tooltip_text = "Place this prefab as one unit (%d pieces)" % (entry["pieces"] as Array).size()
		place.pressed.connect(func() -> void: action_requested.emit(&"prefab_place", id))
		row.add_child(place)
		if not MapPrefabs.is_stock(id):
			var remove := UIFactory.button("✕")
			remove.focus_mode = Control.FOCUS_NONE
			remove.tooltip_text = "Delete this saved prefab"
			remove.pressed.connect(func() -> void: action_requested.emit(&"prefab_delete", id))
			row.add_child(remove)
		_prefab_list.add_child(row)


func is_editing_text() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox or (focus != null and focus.get_parent() is SpinBox)


# --- construction -------------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(8)
	bar.add_child(row)
	row.add_child(UIFactory.label("CREATION STUDIO", &"LogoLabel"))
	_title_label = UIFactory.label("", &"MutedLabel")
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_label.custom_minimum_size.x = 220
	_title_label.clip_text = true
	row.add_child(_title_label)
	row.add_child(UIFactory.expand_spacer())

	_toolbar_button(row, "New", new_requested.emit, "Start a new map (Ctrl+N)")
	_toolbar_button(row, "Open", open_requested.emit, "Open a saved, official or recovered map (Ctrl+O)")
	save_button = _toolbar_button(row, "Save", save_requested.emit, "Save to user://maps (Ctrl+S)")
	undo_button = _toolbar_button(row, "Undo", undo_requested.emit, "Undo (Ctrl+Z)")
	redo_button = _toolbar_button(row, "Redo", redo_requested.emit, "Redo (Ctrl+Y / Ctrl+Shift+Z)")
	_toolbar_button(row, "Validate", validate_requested.emit, "Check structure, reachability and route timings")
	_toolbar_button(row, "Timings", func() -> void: action_requested.emit(&"timings", null), "Route timing readout from the baked navmesh")
	team_option = _option(row, ["Attack", "Defence"], 0, "Team to playtest as",
		func(index: int) -> void: action_requested.emit(&"playtest_team", TEAMS[index]))
	spawn_option = _option(row, ["Spawn 1"], 0, "Spawn to playtest from",
		func(index: int) -> void: action_requested.emit(&"playtest_spawn", index))
	playtest_button = _toolbar_button(row, "▶ Playtest", playtest_requested.emit, "Play this map in first person (F5)")
	playtest_button.theme_type_variation = &"AccentButton"
	_toolbar_button(row, "Tactics", tactics_requested.emit, "Author five-player routes for the saved map")
	_toolbar_button(row, "View (F)", reset_view_requested.emit, "Reset camera view")
	main_menu_button = _toolbar_button(row, "◂ Menu", main_menu_requested.emit, "Return to the main menu")
	return bar


func _build_options_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(8)
	bar.add_child(row)
	_caption(row, "Gizmo")
	gizmo_option = _option(row, GIZMO_MODES, 0, "Transform gizmo: move (G), rotate (T), scale (X)",
		func(index: int) -> void: action_requested.emit(&"gizmo_mode", index))
	_caption(row, "Grid")
	var snap_names: Array[String] = []
	for size: float in SNAP_SIZES:
		snap_names.append("%s m" % format_number(size))
	snap_option = _option(row, snap_names, DEFAULT_SNAP_INDEX, "Grid size for placing, moving and scaling",
		func(index: int) -> void: snap_changed.emit(SNAP_SIZES[index]))
	_caption(row, "Angle")
	var angle_names: Array[String] = []
	for angle: float in ANGLE_SNAPS:
		angle_names.append("%d°" % int(angle))
	angle_option = _option(row, angle_names, DEFAULT_ANGLE_INDEX, "Angle snap for R and the rotate gizmo",
		func(index: int) -> void: action_requested.emit(&"angle_snap", ANGLE_SNAPS[index]))
	surface_check = _check(row, "Snap to surface", true, "Placed and moved pieces sit on the surface under them", &"snap_surface")
	edge_check = _check(row, "Snap to edge", false, "Moved pieces snap flush to nearby piece edges", &"snap_edge")
	overhead_check = _check(row, "Top view", false, "Overhead orthographic view (Tab)", &"overhead")
	navmesh_check = _check(row, "Navmesh", false, "Show the navmesh bots will use (baked on demand)", &"navmesh")
	_toolbar_button(row, "Refresh navmesh", func() -> void: action_requested.emit(&"navmesh_refresh", null),
		"Re-bake the navmesh preview after edits")
	row.add_child(UIFactory.expand_spacer())
	_toolbar_button(row, "Copy", func() -> void: action_requested.emit(&"copy", null), "Copy selection (Ctrl+C)")
	_toolbar_button(row, "Paste", func() -> void: action_requested.emit(&"paste", null), "Paste at the cursor, also into another map (Ctrl+V)")
	_toolbar_button(row, "Group", func() -> void: action_requested.emit(&"group", null), "Group selection (Ctrl+G)")
	_toolbar_button(row, "Ungroup", func() -> void: action_requested.emit(&"ungroup", null), "Ungroup selection (Ctrl+Shift+G)")
	return bar


func _caption(parent: Control, text: String) -> void:
	var label := UIFactory.label(text, &"MutedLabel")
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(label)


func _option(parent: Control, items: Array[String], selected: int, tooltip: String, handler: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.select(selected)
	option.tooltip_text = tooltip
	option.focus_mode = Control.FOCUS_NONE
	option.item_selected.connect(handler)
	parent.add_child(option)
	return option


func _check(parent: Control, text: String, pressed: bool, tooltip: String, action: StringName) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	check.tooltip_text = tooltip
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: action_requested.emit(action, on))
	parent.add_child(check)
	return check


func _toolbar_button(parent: Control, text: String, handler: Callable, tooltip: String) -> Button:
	var b := UIFactory.button(text)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _open_button(text: String, handler: Callable) -> Button:
	var b := UIFactory.button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		open_panel.visible = false
		handler.call())
	return b


func _build_palette() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SidebarPanel"
	panel.custom_minimum_size.x = 220
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := UIFactory.vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_padded_label("TOOLS", &"SectionLabel"))
	select_tool_button = _palette_button(column, "Select / move  (1)")
	select_tool_button.pressed.connect(func() -> void: tool_selected.emit(Tool.SELECT))
	select_tool_button.set_pressed_no_signal(true)
	measure_tool_button = _palette_button(column, "Measure  (M)")
	measure_tool_button.tooltip_text = "Click two points: distance, height and run time"
	measure_tool_button.pressed.connect(func() -> void: tool_selected.emit(Tool.MEASURE))

	for group: String in PieceCatalog.GROUP_ORDER:
		column.add_child(_padded_label(group.to_upper(), &"SectionLabel"))
		for type: String in PieceCatalog.types_in_group(group):
			var b := _palette_button(column, PieceCatalog.label(type))
			b.tooltip_text = "Place %s (click in the viewport)" % PieceCatalog.label(type)
			b.pressed.connect(func() -> void: piece_type_selected.emit(type))
			_palette_buttons[type] = b

	column.add_child(_padded_label("PREFABS", &"SectionLabel"))
	_prefab_list = UIFactory.vbox(2)
	column.add_child(_prefab_list)
	_prefab_name = LineEdit.new()
	_prefab_name.placeholder_text = "New prefab name"
	column.add_child(_prefab_name)
	var save_prefab := UIFactory.button("Save selection as prefab")
	save_prefab.focus_mode = Control.FOCUS_NONE
	save_prefab.tooltip_text = "Stores the selected pieces in this map as a reusable prefab"
	save_prefab.pressed.connect(func() -> void:
		action_requested.emit(&"prefab_save", _prefab_name.text)
		_prefab_name.clear())
	column.add_child(save_prefab)

	column.add_child(_padded_label("SHORTCUTS", &"SectionLabel"))
	for line: String in [
		"LMB  select / place / drag",
		"Shift+LMB  add or remove",
		"Drag on empty space  box select",
		"Alt+LMB  one piece of a group",
		"RMB hold  look · +WASD fly",
		"Wheel  dolly · RMB+wheel speed",
		"G / T / X  move / rotate / scale gizmo",
		"R  rotate by angle snap · Shift+R back",
		"Arrows  nudge · PgUp/PgDn height",
		"Ctrl+C / V / D  copy / paste / duplicate",
		"Ctrl+A  select all · Del  delete",
		"Ctrl+G  group · Ctrl+Shift+G ungroup",
		"Ctrl+Z / Ctrl+Y  undo / redo",
		"Tab  top view · M  measure",
		"Ctrl+S  save · F5  playtest",
		"Esc  select tool / deselect",
	]:
		column.add_child(_padded_label(line, &"MutedLabel"))
	return panel


func _palette_button(parent: Control, text: String) -> Button:
	var b := UIFactory.button(text, &"SidebarButton")
	b.toggle_mode = true
	b.button_group = _tool_group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _padded_label(text: String, variation: StringName) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_child(UIFactory.label(text, variation))
	return margin


func _build_inspector_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.custom_minimum_size.x = 320
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	column.add_child(UIFactory.label("INSPECTOR", &"SectionLabel"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_inspector = UIFactory.vbox(8)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)
	column.add_child(HSeparator.new())
	column.add_child(UIFactory.label("LAYERS (editor only)", &"SectionLabel"))
	var layer_scroll := ScrollContainer.new()
	layer_scroll.custom_minimum_size.y = 130
	layer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(layer_scroll)
	_layer_list = UIFactory.vbox(2)
	_layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_scroll.add_child(_layer_list)
	var layer_row := UIFactory.hbox(6)
	var layer_name := LineEdit.new()
	layer_name.placeholder_text = "New layer name"
	layer_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_row.add_child(layer_name)
	var add_layer := UIFactory.button("Add")
	add_layer.focus_mode = Control.FOCUS_NONE
	add_layer.pressed.connect(func() -> void:
		action_requested.emit(&"layer_add", layer_name.text)
		layer_name.clear())
	layer_row.add_child(add_layer)
	column.add_child(layer_row)
	column.add_child(HSeparator.new())
	_cursor_label = UIFactory.label("Cursor —", &"MutedLabel")
	column.add_child(_cursor_label)
	return panel


func _layer_toggle(text: String, pressed: bool, tooltip: String, handler: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	check.tooltip_text = tooltip
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(handler)
	return check


func _build_status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	_status_label = UIFactory.label("", &"MutedLabel")
	_status_label.clip_text = true
	bar.add_child(_status_label)
	return bar


func _build_open_panel() -> void:
	open_panel = ColorRect.new()
	(open_panel as ColorRect).color = Color(0, 0, 0, 0.55)
	open_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_panel.visible = false
	add_child(open_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_panel.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	center.add_child(panel)
	var column := UIFactory.vbox(10)
	column.custom_minimum_size = Vector2(620, 0)
	panel.add_child(column)
	var header := UIFactory.hbox(8)
	header.add_child(UIFactory.label("Open map", &"HeaderLabel"))
	header.add_child(UIFactory.expand_spacer())
	var close := UIFactory.button("Close")
	close.pressed.connect(func() -> void: open_panel.visible = false)
	header.add_child(close)
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_open_list = UIFactory.vbox(6)
	_open_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_open_list)


func _build_dialogs() -> void:
	message_dialog = AcceptDialog.new()
	message_dialog.dialog_autowrap = true
	add_child(message_dialog)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_autowrap = true
	confirm_dialog.title = "Unsaved changes"
	confirm_dialog.confirmed.connect(func() -> void:
		if _confirm_callback.is_valid():
			_confirm_callback.call())
	add_child(confirm_dialog)


# --- inspector forms ----------------------------------------------------------------------------

func _clear_inspector() -> void:
	_fields.clear()
	for child: Node in _inspector.get_children():
		_inspector.remove_child(child)
		child.queue_free()


func _build_map_properties(doc: MapDocument, file_path: String) -> void:
	_inspector.add_child(UIFactory.label("Map properties", &"CardTitleLabel"))
	_inspector.add_child(UIFactory.label("Nothing selected. Click a piece to edit it.", &"MutedLabel", true))
	var name_edit := _line_field("Name", doc.name)
	var author_edit := _line_field("Author", doc.author)
	var description_edit := _line_field("Description", doc.description)
	var submit := func() -> void:
		metadata_edited.emit(name_edit.text.strip_edges(), author_edit.text.strip_edges(), description_edit.text.strip_edges())
	for edit: LineEdit in [name_edit, author_edit, description_edit]:
		edit.text_submitted.connect(submit.unbind(1))
		edit.focus_exited.connect(submit)
	var info: Array[PackedStringArray] = [
		PackedStringArray(["Map ID", doc.map_id]),
		PackedStringArray(["Pieces", str(doc.pieces.size())]),
		PackedStringArray(["Revision", str(doc.revision)]),
		PackedStringArray(["Content version", str(doc.content_version)]),
		PackedStringArray(["File", file_path if not file_path.is_empty() else "not saved yet"]),
	]
	UIFactory.key_value_grid(_inspector, info)

	_inspector.add_child(UIFactory.label("LIGHTING", &"SectionLabel"))
	var settings := MapLighting.normalised(doc.lighting)
	var spins: Dictionary[String, SpinBox] = {}
	var emit_lighting := func() -> void:
		var next := settings.duplicate()
		for key: String in spins:
			next[key] = spins[key].value
		action_requested.emit(&"lighting", next)
	for row: Array in [["Sun direction (°)", "sun_yaw", 5.0], ["Sun height (°)", "sun_pitch", 5.0],
			["Sun strength", "sun_energy", 0.1], ["Ambient light", "ambient_energy", 0.05]]:
		var key := str(row[1])
		var spin := _number_row(str(row[0]), float(settings[key]), MapLighting.LIMITS[key].x, MapLighting.LIMITS[key].y, float(row[2]))
		spin.value_changed.connect(emit_lighting.unbind(1))
		spins[key] = spin
	var reset := UIFactory.button("Use default lighting")
	reset.disabled = doc.lighting.is_empty()
	reset.pressed.connect(func() -> void: action_requested.emit(&"lighting", {}))
	_inspector.add_child(reset)


func _build_selection_properties(selection: Array[Dictionary], doc: MapDocument) -> void:
	_inspector.add_child(UIFactory.label("%d pieces selected" % selection.size(), &"CardTitleLabel"))
	var pivot := MapSnapping.pivot(selection)
	_inspector.add_child(UIFactory.label("GROUP POSITION (pivot)", &"SectionLabel"))
	var row := UIFactory.hbox(6)
	var spins: Array[SpinBox] = []
	var emit_move := func() -> void:
		action_requested.emit(&"group_move", Vector3(spins[0].value, spins[1].value, spins[2].value))
	for value: float in [pivot.x, pivot.y, pivot.z]:
		var spin := _spin(value, -256.0, 256.0, 0.05)
		spin.value_changed.connect(emit_move.unbind(1))
		spins.append(spin)
		row.add_child(spin)
	_inspector.add_child(row)
	var turn := _number_row("Rotate group by (°)", 0.0, -360.0, 360.0, 5.0)
	var apply_turn := UIFactory.button("Apply rotation")
	apply_turn.pressed.connect(func() -> void: action_requested.emit(&"group_rotate", turn.value))
	_inspector.add_child(apply_turn)
	_material_field("")
	_layer_field(doc, "")
	for entry: Array in [["Duplicate (Ctrl+D)", &"duplicate"], ["Delete (Del)", &"delete"],
			["Group (Ctrl+G)", &"group"], ["Ungroup", &"ungroup"]]:
		var b := UIFactory.button(str(entry[0]))
		var action: StringName = entry[1]
		b.pressed.connect(func() -> void: action_requested.emit(action, null))
		_inspector.add_child(b)


func _build_piece_properties(piece: Dictionary, doc: MapDocument) -> void:
	var type := str(piece["type"])
	var kind := PieceCatalog.kind(type)
	_inspector.add_child(UIFactory.label(PieceCatalog.label(type), &"CardTitleLabel"))
	var group := str(piece.get("group", ""))
	_inspector.add_child(UIFactory.label("%s  ·  %s%s" % [piece["id"], kind, "  ·  " + group if not group.is_empty() else ""], &"MutedLabel"))
	var p: Vector3 = piece["position"]
	_inspector.add_child(UIFactory.label("POSITION (bottom centre)", &"SectionLabel"))
	_vector_row(["pos_x", "pos_y", "pos_z"], p, -256.0, 256.0)

	var rotation := _number_row("Rotation (°)", float(piece["rotation_y"]), 0.0, 360.0, 5.0)
	rotation.value_changed.connect(func(value: float) -> void: _edit("rotation_y", MapDocument.normalise_rotation(value)))
	_fields["rotation"] = rotation

	if PieceCatalog.is_resizable(type):
		_inspector.add_child(UIFactory.label("SIZE (width · height · depth)", &"SectionLabel"))
		_vector_row(["size_x", "size_y", "size_z"], piece["size"] as Vector3, MapValidator.MIN_SIZE, 128.0)
	if PieceCatalog.is_solid(type):
		_material_field(str(piece.get("material", "")))
	_layer_field(doc, str(piece.get("layer", MapDocument.DEFAULT_LAYER)))

	var props: Dictionary = piece.get("props", {})
	match type:
		"bombsite":
			_option_prop("Site", "site", SITES, str(props.get("site", "A")))
		"buy_zone":
			_option_prop("Team", "team", TEAMS, str(props.get("team", "attack")))
		"target_dummy":
			_option_prop("Motion", "motion", DUMMY_MOTIONS, str(props.get("motion", "static")))
		"callout":
			_text_prop("Area name", "name", str(props.get("name", "")))
			_option_prop("Timing role", "role", MapTactical.AREA_ROLES, str(props.get("role", "")))
			_inspector.add_child(UIFactory.label("Area ID %s — tactics refer to this ID." % piece["id"], &"MutedLabel", true))
		"tactical_anchor":
			_text_prop("Anchor name", "name", str(props.get("name", "")))
			_option_prop("Anchor kind", "kind", MapTactical.ANCHOR_KINDS, str(props.get("kind", "default")))
		"ai_cover", "ai_hold", "ai_angle":
			_option_prop("Bombsite", "site", HINT_SITES, str(props.get("site", "")))
		"light_lamp", "light_spot":
			_number_prop("Brightness", "energy", float(props.get("energy", 1.5)), 0.0, 16.0, 0.1)
			_number_prop("Range (m)", "range", float(props.get("range", 8.0)), 1.0, 60.0, 0.5)
			_text_prop("Colour (hex)", "color", str(props.get("color", "ffffff")))
			if type == "light_spot":
				_number_prop("Cone angle (°)", "angle", float(props.get("angle", 40.0)), 5.0, 85.0, 1.0)
		"doorway", "double_door", "arch", "wall_window":
			_number_prop("Opening width (m)", "opening_width", float(props.get("opening_width", 1.4)), PieceShapes.MIN_OPENING, 16.0, 0.1)
			_number_prop("Opening height (m)", "opening_height", float(props.get("opening_height", 2.2)), 1.0, 16.0, 0.1)
			if type == "wall_window":
				_number_prop("Sill height (m)", "sill_height", float(props.get("sill_height", 1.0)), 0.2, 8.0, 0.1)


func _material_field(current: String) -> void:
	_inspector.add_child(UIFactory.label("MATERIAL", &"SectionLabel"))
	var ids := MapMaterials.ids()
	var option := OptionButton.new()
	option.add_item("Piece default")
	for id: String in ids:
		option.add_item(MapMaterials.label(id))
	option.select(ids.find(current) + 1)
	option.item_selected.connect(func(index: int) -> void:
		action_requested.emit(&"material", "" if index == 0 else ids[index - 1]))
	_inspector.add_child(option)


func _layer_field(doc: MapDocument, current: String) -> void:
	_inspector.add_child(UIFactory.label("LAYER", &"SectionLabel"))
	var option := OptionButton.new()
	if current.is_empty():
		option.add_item("(move selection to…)")
	for entry: Dictionary in doc.layers:
		option.add_item(str(entry["name"]))
		if entry["id"] == current:
			option.select(option.item_count - 1)
	var offset := 1 if current.is_empty() else 0
	option.item_selected.connect(func(index: int) -> void:
		if index >= offset:
			action_requested.emit(&"layer_assign", str(doc.layers[index - offset]["id"])))
	_inspector.add_child(option)


func _spin(value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = min_value < 0.0
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.select_all_on_focus = true
	return spin


func _vector_row(keys: Array[String], value: Vector3, min_value: float, max_value: float) -> void:
	var row := UIFactory.hbox(6)
	var components: Array[float] = [value.x, value.y, value.z]
	for i: int in 3:
		var spin := _spin(components[i], min_value, max_value, 0.05)
		var key := keys[i]
		spin.value_changed.connect(func(_v: float) -> void: _edit_vector(key))
		_fields[key] = spin
		row.add_child(spin)
	_inspector.add_child(row)


## A captioned SpinBox on its own row (caller connects value_changed).
func _number_row(caption: String, value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	_inspector.add_child(UIFactory.label(caption.to_upper(), &"SectionLabel"))
	var spin := _spin(value, min_value, max_value, step)
	spin.allow_greater = false
	spin.allow_lesser = false
	_inspector.add_child(spin)
	return spin


func _number_prop(caption: String, prop: String, value: float, min_value: float, max_value: float, step: float) -> void:
	var spin := _number_row(caption, value, min_value, max_value, step)
	spin.value_changed.connect(func(next: float) -> void: _edit_prop(prop, next))


func _text_prop(caption: String, prop: String, value: String) -> void:
	var edit := _line_field(caption, value)
	var submit := func() -> void: _edit_prop(prop, edit.text.strip_edges())
	edit.text_submitted.connect(submit.unbind(1))
	edit.focus_exited.connect(submit)


func _line_field(caption: String, value: String) -> LineEdit:
	_inspector.add_child(UIFactory.label(caption.to_upper(), &"SectionLabel"))
	var edit := LineEdit.new()
	edit.text = value
	_inspector.add_child(edit)
	return edit


func _option_prop(caption: String, prop: String, options: Array[String], current: String) -> void:
	_inspector.add_child(UIFactory.label(caption.to_upper(), &"SectionLabel"))
	var option := OptionButton.new()
	for item: String in options:
		option.add_item(item if not item.is_empty() else "(none)")
	option.select(maxi(0, options.find(current)))
	option.item_selected.connect(func(index: int) -> void: _edit_prop(prop, options[index]))
	_inspector.add_child(option)


func _set_spin(key: String, value: float) -> void:
	var spin := _fields.get(key, null) as SpinBox
	if spin != null and not is_equal_approx(spin.value, value):
		spin.set_value_no_signal(value)


func _spin_value(key: String, fallback: float) -> float:
	var spin := _fields.get(key, null) as SpinBox
	return spin.value if spin != null else fallback


func _edit_vector(key: String) -> void:
	if _editing_piece.is_empty():
		return
	var state := _editing_piece.duplicate(true)
	if key.begins_with("pos"):
		var p: Vector3 = state["position"]
		state["position"] = Vector3(_spin_value("pos_x", p.x), _spin_value("pos_y", p.y), _spin_value("pos_z", p.z))
	else:
		var s: Vector3 = state["size"]
		state["size"] = Vector3(_spin_value("size_x", s.x), _spin_value("size_y", s.y), _spin_value("size_z", s.z))
	_editing_piece = state
	piece_edited.emit(state)


func _edit(key: String, value: Variant) -> void:
	if _editing_piece.is_empty():
		return
	var state := _editing_piece.duplicate(true)
	state[key] = value
	_editing_piece = state
	piece_edited.emit(state)


func _edit_prop(prop: String, value: Variant) -> void:
	if _editing_piece.is_empty():
		return
	var state := _editing_piece.duplicate(true)
	var props: Dictionary = (state.get("props", {}) as Dictionary).duplicate(true)
	if props.get(prop) == value:
		return
	props[prop] = value
	state["props"] = props
	_editing_piece = state
	piece_edited.emit(state)


static func format_number(value: float) -> String:
	return ("%.3f" % value).rstrip("0").rstrip(".")
