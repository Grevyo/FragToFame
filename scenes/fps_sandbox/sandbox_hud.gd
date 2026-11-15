class_name SandboxHud
extends CanvasLayer
## FPS sandbox HUD: crosshair, controls hint, debug readout and the pause overlay.

signal resume_requested
signal main_menu_requested
signal return_to_editor_requested
signal host_match_requested(port: int)
signal join_match_requested(address: String, port: int)
signal leave_match_requested

var pause_overlay: Control
var resume_button: Button
var main_menu_button: Button
var editor_button: Button
var host_button: Button
var join_button: Button
var leave_button: Button
var address_edit: LineEdit
var port_edit: LineEdit

var _debug_label: Label
var _hint_panel: PanelContainer
var _title_label: Label
var _network_status: Label
var _network_badge: Label


func _ready() -> void:
	_build_crosshair()
	_build_hint()
	_build_debug()
	_build_pause_overlay()
	set_paused(false)


func set_paused(paused: bool) -> void:
	pause_overlay.visible = paused
	_hint_panel.visible = not paused
	if paused:
		resume_button.grab_focus.call_deferred()


## Shows the map title; in playtest mode also offers the return-to-editor button.
func set_mode(title: String, playtest: bool) -> void:
	_title_label.text = title
	editor_button.visible = playtest


func set_debug_text(text: String) -> void:
	_debug_label.text = text


## Updates the pause-menu network section and the always-visible network badge.
func set_network_state(active: bool, status_text: String, badge_text: String) -> void:
	_network_status.text = status_text
	_network_badge.text = badge_text
	_network_badge.visible = not badge_text.is_empty()
	host_button.disabled = active
	join_button.disabled = active
	leave_button.disabled = not active
	address_edit.editable = not active
	port_edit.editable = not active


func _port_value() -> int:
	var value := port_edit.text.strip_edges()
	return int(value) if value.is_valid_int() else MatchSession.DEFAULT_PORT


func _build_crosshair() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var gap := 4.0
	var length := 8.0
	var thickness := 2.0
	var pieces: Array[Rect2] = [
		Rect2(-thickness / 2.0, -gap - length, thickness, length),
		Rect2(-thickness / 2.0, gap, thickness, length),
		Rect2(-gap - length, -thickness / 2.0, length, thickness),
		Rect2(gap, -thickness / 2.0, length, thickness),
	]
	for piece: Rect2 in pieces:
		var r := ColorRect.new()
		r.color = Color(0.6, 1.0, 0.75, 0.95)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_CENTER)
		r.offset_left = piece.position.x
		r.offset_top = piece.position.y
		r.offset_right = piece.position.x + piece.size.x
		r.offset_bottom = piece.position.y + piece.size.y
		root.add_child(r)


func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.theme_type_variation = &"HudPanel"
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint_panel.position = Vector2(16, 16)
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIFactory.vbox(2)
	_title_label = UIFactory.label("FPS SANDBOX", &"AccentLabel")
	column.add_child(_title_label)
	column.add_child(UIFactory.label("WASD move · Mouse look · Space jump · Shift walk", &"MutedLabel"))
	column.add_child(UIFactory.label("Esc pause / release mouse · Click to recapture", &"MutedLabel"))
	_hint_panel.add_child(column)
	add_child(_hint_panel)


func _build_debug() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16
	panel.offset_top = -56
	panel.offset_bottom = -16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIFactory.vbox(2)
	_network_badge = UIFactory.label("", &"AccentLabel")
	_network_badge.visible = false
	column.add_child(_network_badge)
	_debug_label = UIFactory.label("", &"MutedLabel")
	column.add_child(_debug_label)
	panel.add_child(column)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)


func _build_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	(pause_overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	center.add_child(panel)
	var column := UIFactory.vbox(12)
	column.custom_minimum_size.x = 360
	panel.add_child(column)
	column.add_child(UIFactory.label("PAUSED", &"HeaderLabel"))
	column.add_child(UIFactory.label("The mouse is released.", &"MutedLabel"))
	resume_button = UIFactory.button("Resume", &"AccentButton")
	resume_button.pressed.connect(resume_requested.emit)
	column.add_child(resume_button)
	editor_button = UIFactory.button("Return to Creation Studio", &"AccentButton")
	editor_button.pressed.connect(return_to_editor_requested.emit)
	editor_button.visible = false
	column.add_child(editor_button)
	main_menu_button = UIFactory.button("Return to Main Menu")
	main_menu_button.pressed.connect(main_menu_requested.emit)
	column.add_child(main_menu_button)
	_build_network_section(column)


func _build_network_section(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	column.add_child(UIFactory.label("LOCAL MATCH NETWORK (DEV PROOF)", &"SectionLabel"))
	column.add_child(UIFactory.label("Position sync only. Independent of the career connection.", &"MutedLabel", true))

	var address_row := UIFactory.hbox(8)
	address_edit = LineEdit.new()
	address_edit.text = "127.0.0.1"
	address_edit.placeholder_text = "Host address"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(MatchSession.DEFAULT_PORT)
	port_edit.custom_minimum_size.x = 80
	address_row.add_child(port_edit)
	column.add_child(address_row)

	var buttons := UIFactory.hbox(8)
	host_button = UIFactory.button("Host match")
	host_button.pressed.connect(func() -> void: host_match_requested.emit(_port_value()))
	buttons.add_child(host_button)
	join_button = UIFactory.button("Join")
	join_button.pressed.connect(func() -> void:
		join_match_requested.emit(address_edit.text.strip_edges(), _port_value()))
	buttons.add_child(join_button)
	leave_button = UIFactory.button("Leave")
	leave_button.pressed.connect(leave_match_requested.emit)
	buttons.add_child(leave_button)
	column.add_child(buttons)

	_network_status = UIFactory.label("Offline", &"MutedLabel", true)
	column.add_child(_network_status)
	column.custom_minimum_size.x = 420
