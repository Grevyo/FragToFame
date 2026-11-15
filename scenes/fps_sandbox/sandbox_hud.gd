class_name SandboxHud
extends CanvasLayer
## FPS sandbox HUD: dynamic crosshair + hit marker, weapon/ammo and health panels, training
## stats, kill feed, death overlay, controls hint, debug readout and the pause overlay.

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
var _crosshair: Crosshair
var _weapon_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _reload_bar: ProgressBar
var _health_label: Label
var _health_bar: ProgressBar
var _stats_label: Label
var _feed: VBoxContainer
var death_overlay: Control
var _death_label: Label


## Draws four crosshair lines whose gap follows weapon spread, plus a fading hit marker.
class Crosshair extends Control:
	const LENGTH: float = 8.0
	const THICKNESS: float = 2.0
	const COLOR := Color(0.6, 1.0, 0.75, 0.95)
	var gap: float = 4.0
	var hit_time: float = 0.0
	var hit_color: Color = Color.WHITE

	func _process(delta: float) -> void:
		hit_time = maxf(hit_time - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var t := THICKNESS / 2.0
		draw_rect(Rect2(c.x - t, c.y - gap - LENGTH, THICKNESS, LENGTH), COLOR)
		draw_rect(Rect2(c.x - t, c.y + gap, THICKNESS, LENGTH), COLOR)
		draw_rect(Rect2(c.x - gap - LENGTH, c.y - t, LENGTH, THICKNESS), COLOR)
		draw_rect(Rect2(c.x + gap, c.y - t, LENGTH, THICKNESS), COLOR)
		if hit_time > 0.0:
			var color := Color(hit_color, clampf(hit_time / 0.25, 0.0, 1.0))
			for direction: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + direction * 6.0, c + direction * 13.0, color, 2.0)


func _ready() -> void:
	_build_crosshair()
	_build_hint()
	_build_debug()
	_build_combat_panels()
	_build_death_overlay()
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


## Weapon panel: name, magazine / reserve ammo and reload progress (negative = not reloading).
func set_weapon(weapon_name: String, ammo: int, reserve: int, reload_progress: float) -> void:
	_weapon_label.text = weapon_name
	_ammo_label.text = str(ammo)
	_ammo_label.theme_type_variation = &"WarningLabel" if ammo == 0 else &"StatValueLabel"
	_reserve_label.text = "/ %d" % reserve
	_reload_bar.visible = reload_progress >= 0.0
	_reload_bar.value = maxf(reload_progress, 0.0)


func set_health(current: int, maximum: int) -> void:
	_health_label.text = str(current)
	_health_bar.max_value = maximum
	_health_bar.value = current


## Crosshair gap in pixels from the centre.
func set_crosshair_gap(pixels: float) -> void:
	_crosshair.gap = clampf(pixels, 3.0, 120.0)


func crosshair_gap() -> float:
	return _crosshair.gap


func show_hit_marker(headshot: bool, killed: bool) -> void:
	_crosshair.hit_time = 0.25
	_crosshair.hit_color = Color("ff4a4a") if killed else (Color("ffd166") if headshot else Color.WHITE)


func set_training_stats(text: String) -> void:
	_stats_label.text = text


## Adds a line to the kill feed (top right); lines expire after a few seconds.
func push_feed(text: String) -> void:
	var line := UIFactory.label(text, &"AccentLabel")
	_feed.add_child(line)
	while _feed.get_child_count() > 5:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(4.0).timeout.connect(_expire_feed_line.bind(line.get_instance_id()))


func feed_count() -> int:
	return _feed.get_child_count()


func _expire_feed_line(line_id: int) -> void:
	var line := instance_from_id(line_id) as Node
	if line != null and is_instance_valid(line):
		line.queue_free()


## Death overlay with the respawn countdown; [param seconds_left] < 0 hides it.
func set_death_state(seconds_left: float, cause: String = "") -> void:
	death_overlay.visible = seconds_left >= 0.0
	if seconds_left >= 0.0:
		_death_label.text = "%s\nRespawning in %.1f s" % [cause, seconds_left]


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
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)


func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.theme_type_variation = &"HudPanel"
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint_panel.position = Vector2(16, 16)
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIFactory.vbox(2)
	_title_label = UIFactory.label("FPS SANDBOX", &"AccentLabel")
	column.add_child(_title_label)
	column.add_child(UIFactory.label("WASD move · Mouse look · Space jump · Shift walk · Ctrl/C crouch", &"MutedLabel"))
	column.add_child(UIFactory.label("LMB fire · R reload · 1 rifle · 2 pistol · 3 SMG · wheel switch", &"MutedLabel"))
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


func _build_combat_panels() -> void:
	# Weapon (bottom right).
	var weapon_panel := PanelContainer.new()
	weapon_panel.theme_type_variation = &"HudPanel"
	weapon_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_panel.offset_left = -260
	weapon_panel.offset_top = -96
	weapon_panel.offset_right = -16
	weapon_panel.offset_bottom = -16
	weapon_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	weapon_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var weapon_column := UIFactory.vbox(2)
	_weapon_label = UIFactory.label("", &"SectionLabel")
	weapon_column.add_child(_weapon_label)
	var ammo_row := UIFactory.hbox(6)
	_ammo_label = UIFactory.label("0", &"StatValueLabel")
	ammo_row.add_child(_ammo_label)
	_reserve_label = UIFactory.label("/ 0", &"MutedLabel")
	_reserve_label.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(_reserve_label)
	weapon_column.add_child(ammo_row)
	_reload_bar = ProgressBar.new()
	_reload_bar.max_value = 1.0
	_reload_bar.show_percentage = false
	_reload_bar.custom_minimum_size.y = 6
	_reload_bar.visible = false
	weapon_column.add_child(_reload_bar)
	weapon_panel.add_child(weapon_column)
	add_child(weapon_panel)

	# Health (bottom centre).
	var health_panel := PanelContainer.new()
	health_panel.theme_type_variation = &"HudPanel"
	health_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	health_panel.offset_left = -120
	health_panel.offset_right = 120
	health_panel.offset_top = -76
	health_panel.offset_bottom = -16
	health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_row := UIFactory.hbox(12)
	health_row.add_child(UIFactory.label("HP", &"SectionLabel"))
	_health_label = UIFactory.label("100", &"StatValueLabel")
	health_row.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_health_bar.custom_minimum_size.y = 8
	_health_bar.value = 100
	health_row.add_child(_health_bar)
	health_panel.add_child(health_row)
	add_child(health_panel)

	# Training stats + kill feed (top right).
	var right := UIFactory.vbox(6)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -420
	right.offset_right = -16
	right.offset_top = 16
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"HudPanel"
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_label = UIFactory.label("", &"MutedLabel")
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_panel.add_child(_stats_label)
	right.add_child(stats_panel)
	_feed = UIFactory.vbox(2)
	right.add_child(_feed)
	add_child(right)


func _build_death_overlay() -> void:
	death_overlay = ColorRect.new()
	(death_overlay as ColorRect).color = Color(0.35, 0.02, 0.02, 0.35)
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.add_child(center)
	var column := UIFactory.vbox(8)
	var title := UIFactory.label("ELIMINATED", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_death_label = UIFactory.label("", &"SubtitleLabel")
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_death_label)
	center.add_child(column)
	death_overlay.visible = false
	add_child(death_overlay)


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
