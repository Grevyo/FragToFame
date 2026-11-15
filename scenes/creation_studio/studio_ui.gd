class_name StudioUI
extends Control
## Creation Studio interface: toolbar, piece palette, inspector, status bar, open-map panel and
## dialogs. Pure presentation — it emits intent signals and never edits the document itself.

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

enum Tool { SELECT, PLACE }

const SNAP_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const DEFAULT_SNAP_INDEX: int = 2
const SITES: Array[String] = ["A", "B", "C"]
const TEAMS: Array[String] = ["attack", "defence"]
const DUMMY_MOTIONS: Array[String] = ["static", "strafe"]
const ROTATIONS: Array[int] = [0, 90, 180, 270]

var undo_button: Button
var redo_button: Button
var save_button: Button
var playtest_button: Button
var main_menu_button: Button
var snap_option: OptionButton
var select_tool_button: Button
var open_panel: Control
var message_dialog: AcceptDialog
var confirm_dialog: ConfirmationDialog

var _title_label: Label
var _status_label: Label
var _cursor_label: Label
var _inspector: VBoxContainer
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
	elif _palette_buttons.has(piece_type):
		_palette_buttons[piece_type].set_pressed_no_signal(true)


func current_snap() -> float:
	return SNAP_SIZES[snap_option.selected]


func show_message(title: String, text: String) -> void:
	message_dialog.title = title
	message_dialog.dialog_text = text
	message_dialog.popup_centered(Vector2i(520, 0))


## Asks for confirmation; [param on_confirm] runs only if the user accepts.
func confirm(text: String, ok_text: String, on_confirm: Callable) -> void:
	_confirm_callback = on_confirm
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	confirm_dialog.popup_centered(Vector2i(460, 0))


func show_open_panel(saved_maps: Array[Dictionary]) -> void:
	for child: Node in _open_list.get_children():
		child.queue_free()
	_open_list.add_child(UIFactory.label("TEMPLATES", &"SectionLabel"))
	for template: Array in [["blank", "Blank map"], ["sandbox_arena", "Sandbox Arena (dev) — FPS Sandbox test map"]]:
		var b := UIFactory.button(str(template[1]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var template_id := str(template[0])
		b.pressed.connect(func() -> void:
			open_panel.visible = false
			template_chosen.emit(template_id))
		_open_list.add_child(b)
	_open_list.add_child(HSeparator.new())
	_open_list.add_child(UIFactory.label("SAVED MAPS (user://maps)", &"SectionLabel"))
	if saved_maps.is_empty():
		_open_list.add_child(UIFactory.label("No saved maps yet.", &"MutedLabel"))
	for entry: Dictionary in saved_maps:
		var when := Time.get_datetime_string_from_unix_time(int(entry["modified"]), true)
		var b := UIFactory.button("%s   ·   %d pieces   ·   %s" % [entry["name"], int(entry["pieces"]), when])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := str(entry["path"])
		b.pressed.connect(func() -> void:
			open_panel.visible = false
			map_chosen.emit(path))
		_open_list.add_child(b)
	open_panel.visible = true


## Rebuilds the inspector for [param piece], or shows map properties when it is empty.
func show_inspector(piece: Dictionary, doc: MapDocument, file_path: String) -> void:
	_clear_inspector()
	_editing_piece = piece.duplicate(true)
	if piece.is_empty():
		_build_map_properties(doc, file_path)
	else:
		_build_piece_properties(piece)


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
	var rotation_option := _fields.get("rotation", null) as OptionButton
	if rotation_option != null:
		rotation_option.select(ROTATIONS.find(int(piece["rotation_y"])))


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
	_toolbar_button(row, "Open", open_requested.emit, "Open a saved map or template (Ctrl+O)")
	save_button = _toolbar_button(row, "Save", save_requested.emit, "Save to user://maps (Ctrl+S)")
	undo_button = _toolbar_button(row, "Undo", undo_requested.emit, "Undo (Ctrl+Z)")
	redo_button = _toolbar_button(row, "Redo", redo_requested.emit, "Redo (Ctrl+Y / Ctrl+Shift+Z)")
	_toolbar_button(row, "Validate", validate_requested.emit, "Check the map for problems")
	playtest_button = _toolbar_button(row, "▶ Playtest", playtest_requested.emit, "Play this map in first person (F5)")
	playtest_button.theme_type_variation = &"AccentButton"
	_toolbar_button(row, "Tactics", tactics_requested.emit, "Author five-player routes for the saved map")

	var snap_label := UIFactory.label("Snap", &"MutedLabel")
	snap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(snap_label)
	snap_option = OptionButton.new()
	for i: int in SNAP_SIZES.size():
		snap_option.add_item("%s m" % format_number(SNAP_SIZES[i]), i)
	snap_option.select(DEFAULT_SNAP_INDEX)
	snap_option.item_selected.connect(func(index: int) -> void: snap_changed.emit(SNAP_SIZES[index]))
	row.add_child(snap_option)
	_toolbar_button(row, "View (F)", reset_view_requested.emit, "Reset camera view")
	main_menu_button = _toolbar_button(row, "◂ Menu", main_menu_requested.emit, "Return to the main menu")
	return bar


func _toolbar_button(parent: Control, text: String, handler: Callable, tooltip: String) -> Button:
	var b := UIFactory.button(text)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _build_palette() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SidebarPanel"
	panel.custom_minimum_size.x = 210
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

	for group: String in PieceCatalog.GROUP_ORDER:
		column.add_child(_padded_label(group.to_upper(), &"SectionLabel"))
		for type: String in PieceCatalog.types_in_group(group):
			var b := _palette_button(column, PieceCatalog.label(type))
			b.tooltip_text = "Place %s (click in the viewport)" % PieceCatalog.label(type)
			b.pressed.connect(func() -> void: piece_type_selected.emit(type))
			_palette_buttons[type] = b

	column.add_child(_padded_label("SHORTCUTS", &"SectionLabel"))
	for line: String in [
		"LMB  select / place / drag",
		"RMB hold  look · +WASD fly",
		"RMB + E / Q  up / down",
		"Wheel  dolly · RMB+wheel speed",
		"R  rotate 90° · Shift+R back",
		"Arrows  nudge · PgUp/PgDn height",
		"Del  delete · Ctrl+D duplicate",
		"Ctrl+Z / Ctrl+Y  undo / redo",
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
	panel.custom_minimum_size.x = 300
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
	_cursor_label = UIFactory.label("Cursor —", &"MutedLabel")
	column.add_child(_cursor_label)
	return panel


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
		PackedStringArray(["File", file_path if not file_path.is_empty() else "not saved yet"]),
	]
	UIFactory.key_value_grid(_inspector, info)


func _build_piece_properties(piece: Dictionary) -> void:
	var type := str(piece["type"])
	_inspector.add_child(UIFactory.label(PieceCatalog.label(type), &"CardTitleLabel"))
	_inspector.add_child(UIFactory.label("%s  ·  %s" % [piece["id"], PieceCatalog.kind(type)], &"MutedLabel"))
	var p: Vector3 = piece["position"]
	_inspector.add_child(UIFactory.label("POSITION (bottom centre)", &"SectionLabel"))
	_vector_row(["pos_x", "pos_y", "pos_z"], p, -256.0, 256.0)

	_inspector.add_child(UIFactory.label("ROTATION", &"SectionLabel"))
	var rotation_option := OptionButton.new()
	for r: int in ROTATIONS:
		rotation_option.add_item("%d°" % r)
	rotation_option.select(ROTATIONS.find(int(piece["rotation_y"])))
	rotation_option.item_selected.connect(func(index: int) -> void: _edit("rotation_y", ROTATIONS[index]))
	_fields["rotation"] = rotation_option
	_inspector.add_child(rotation_option)

	if PieceCatalog.is_resizable(type):
		_inspector.add_child(UIFactory.label("SIZE (width · height · depth)", &"SectionLabel"))
		_vector_row(["size_x", "size_y", "size_z"], piece["size"] as Vector3, MapValidator.MIN_SIZE, 128.0)

	var props: Dictionary = piece.get("props", {})
	match type:
		"bombsite":
			_inspector.add_child(UIFactory.label("SITE", &"SectionLabel"))
			_option_prop("site", SITES, str(props.get("site", "A")))
		"buy_zone":
			_inspector.add_child(UIFactory.label("TEAM", &"SectionLabel"))
			_option_prop("team", TEAMS, str(props.get("team", "attack")))
		"target_dummy":
			_inspector.add_child(UIFactory.label("MOTION", &"SectionLabel"))
			_option_prop("motion", DUMMY_MOTIONS, str(props.get("motion", "static")))
		"callout":
			var name_edit := _line_field("Callout name", str(props.get("name", "")))
			var submit := func() -> void: _edit_prop("name", name_edit.text.strip_edges())
			name_edit.text_submitted.connect(submit.unbind(1))
			name_edit.focus_exited.connect(submit)


func _vector_row(keys: Array[String], value: Vector3, min_value: float, max_value: float) -> void:
	var row := UIFactory.hbox(6)
	var components: Array[float] = [value.x, value.y, value.z]
	for i: int in 3:
		var spin := SpinBox.new()
		spin.min_value = min_value
		spin.max_value = max_value
		spin.step = 0.05
		spin.allow_greater = true
		spin.allow_lesser = min_value < 0.0
		spin.value = components[i]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.select_all_on_focus = true
		var key := keys[i]
		spin.value_changed.connect(func(_v: float) -> void: _edit_vector(key))
		_fields[key] = spin
		row.add_child(spin)
	_inspector.add_child(row)


func _line_field(caption: String, value: String) -> LineEdit:
	_inspector.add_child(UIFactory.label(caption.to_upper(), &"SectionLabel"))
	var edit := LineEdit.new()
	edit.text = value
	_inspector.add_child(edit)
	return edit


func _option_prop(prop: String, options: Array[String], current: String) -> void:
	var option := OptionButton.new()
	for item: String in options:
		option.add_item(item)
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
	return ("%.2f" % value).rstrip("0").rstrip(".")
