class_name SandboxHud
extends CanvasLayer
## FPS sandbox HUD: crosshair, controls hint, debug readout and the pause overlay.

signal resume_requested
signal main_menu_requested

var pause_overlay: Control
var resume_button: Button
var main_menu_button: Button

var _debug_label: Label
var _hint_panel: PanelContainer


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


func set_debug_text(text: String) -> void:
	_debug_label.text = text


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
	column.add_child(UIFactory.label("FPS SANDBOX", &"AccentLabel"))
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
	_debug_label = UIFactory.label("", &"MutedLabel")
	panel.add_child(_debug_label)
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
	main_menu_button = UIFactory.button("Return to Main Menu")
	main_menu_button.pressed.connect(main_menu_requested.emit)
	column.add_child(main_menu_button)
