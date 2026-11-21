extends Control
## Main menu: entry point into the three game environments.

var career_button: Button
var sandbox_button: Button
var studio_button: Button
var controls_button: Button
var armoury_button: Button
## Developer tools (marked as such): the Character Creator.
var character_creator_button: Button
var quit_button: Button


func _ready() -> void:
	_build()
	career_button.grab_focus.call_deferred()


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var accent_strip := ColorRect.new()
	accent_strip.color = F2FTheme.ACCENT
	accent_strip.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	accent_strip.custom_minimum_size.x = 6
	accent_strip.offset_right = 6
	add_child(accent_strip)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := UIFactory.vbox(14)
	column.custom_minimum_size.x = 520
	center.add_child(column)

	var title := UIFactory.label("FRAG TO FAME", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := UIFactory.label("FPS Career Simulator", &"SubtitleLabel")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	column.add_child(gap)

	career_button = _menu_button(column, "Career Hub", _on_career_pressed)
	sandbox_button = _menu_button(column, "FPS Sandbox", _on_sandbox_pressed)
	studio_button = _menu_button(column, "Creation Studio", _on_studio_pressed)
	armoury_button = _menu_button(column, "Armoury", func() -> void: App.go_to(App.SCENE_ARMOURY))
	controls_button = _menu_button(column, "Controls", func() -> void: App.go_to(App.SCENE_CONTROLS))
	character_creator_button = _menu_button(column, "Character Creator  ·  developer tool",
		func() -> void: App.go_to(App.SCENE_CHARACTER_CREATOR))
	character_creator_button.tooltip_text = "Developer preview of the character models (not used in matches yet)"
	quit_button = _menu_button(column, "Quit", _on_quit_pressed)

	var footer := UIFactory.label("v%s  ·  %s  ·  Pre-alpha development build" % [App.VERSION, App.MILESTONE], &"MutedLabel")
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -40
	footer.offset_bottom = -16
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)


func _menu_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := UIFactory.button(text, &"MenuButtonLarge")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _on_career_pressed() -> void:
	App.open_career_hub()


func _on_sandbox_pressed() -> void:
	App.go_to(App.SCENE_MAP_SELECT)


func _on_studio_pressed() -> void:
	App.go_to(App.SCENE_CREATION_STUDIO)


func _on_quit_pressed() -> void:
	App.quit_game()
