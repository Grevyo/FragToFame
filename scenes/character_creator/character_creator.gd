class_name CharacterCreator
extends Control
## Developer Character Creator: build a character from the downloaded character packs on a live,
## turning 3D preview. Pick a base character, fill its slots (hair, headwear, clothing, gloves,
## shoes, accessories), colour every item channel and the skin, randomise, save and load presets,
## and keep a look as the player's own ([CosmeticProfile]).
##
## Developer mode (on by default here) shows every item whatever its unlock state; turned off, the
## lists follow [CharacterUnlocks] for the player's profile. Items that do not fit the base
## character (other packs use other skeletons and proportions) or are not installed (the ithappy
## pack is local-only) stay listed but disabled, with the reason.

const ROTATE_SPEED: float = 0.01
const AUTO_TURN_SPEED: float = 0.35
const DEFAULT_CLIP: StringName = &"Idle_Gun"
const NONE_LABEL: String = "None"

var catalog: CharacterCatalog = CharacterCatalog.shared()
## The look being edited (sanitised by the rig on every change).
var appearance: CharacterAppearance = CharacterAppearance.new()
## Every item regardless of unlock state.
var developer_mode: bool = true
var rig: CharacterRig
var back_button: Button
var randomise_button: Button
var use_button: Button
var body_list: ItemList
var clip_picker: OptionButton
var developer_toggle: CheckButton
var bots_toggle: CheckButton
var preset_name_edit: LineEdit
var preset_list: ItemList
## Per slot: the item picker (index 0 = None) and the item IDs behind its entries.
var slot_pickers: Dictionary[String, OptionButton] = {}
var slot_choices: Dictionary[String, Array] = {}

var _rng := RandomNumberGenerator.new()
var _body_ids: Array[String] = []
var _preset_ids: Array[String] = []
var _clips: Array[StringName] = []
var _status: Label
var _notes: Label
var _slot_column: VBoxContainer
var _viewport: SubViewport
var _camera: Camera3D
var _camera_target: Vector3 = Vector3(0, 1.0, 0)
var _distance: float = 3.4
var _turntable: Node3D
var _dragging: bool = false
var _auto_turn: bool = true
var _yaw: float = 0.4
var _pitch: float = -0.08


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_build()
	var start := CosmeticProfile.current().appearance
	if start.body.is_empty() or not catalog.has_body(start.body):
		start = CharacterWardrobe.default_appearance(catalog, CharacterWardrobe.first_available_body(catalog))
	show_appearance(start)
	_fill_clips()
	_refresh_presets()
	back_button.grab_focus.call_deferred()


# --- editing (public so tests can drive the screen) ------------------------------------------------

## Shows [param look] (sanitised against the catalog and the unlock gate).
func show_appearance(look: CharacterAppearance) -> PackedStringArray:
	var wanted := look.duplicate_appearance()
	var notes := CharacterWardrobe.sanitize(catalog, wanted, _allowed_gate())
	notes.append_array(rig.apply(wanted))
	appearance = rig.appearance.duplicate_appearance()
	_frame_camera()
	rig.play(_selected_clip(), 0.0)
	_refresh()
	_notes.text = "\n".join(notes)
	return notes


## Switches the base character, wearing its default items. Returns "" or why it was refused.
func select_body(body_id: String) -> String:
	if not catalog.has_body(body_id):
		return _say("Unknown base character.")
	var problem := catalog.unavailable_reason(body_id)
	if not problem.is_empty():
		_refresh()
		return _say(problem)
	if body_id != appearance.body:
		var look := CharacterWardrobe.default_appearance(catalog, body_id)
		look.skin_tone = appearance.skin_tone
		show_appearance(look)
	return _say("")


## Wears an item. Returns "" or why it was refused (does not fit, not installed, locked).
func equip_item(item_id: String) -> String:
	var problem := item_problem(item_id)
	if problem.is_empty():
		var look := appearance.duplicate_appearance()
		problem = CharacterWardrobe.equip(catalog, look, item_id)
		if problem.is_empty():
			show_appearance(look)
	_refresh()
	return _say(problem)


## Empties a slot. Returns "" or why it must stay filled.
func clear_slot(slot_id: String) -> String:
	var look := appearance.duplicate_appearance()
	var problem := CharacterWardrobe.unequip(catalog, look, slot_id)
	if problem.is_empty():
		show_appearance(look)
	_refresh()
	return _say(problem)


## Why an item cannot be chosen for the current base character ("" when it can).
func item_problem(item_id: String) -> String:
	var problem := catalog.fit_problem(item_id, appearance.body)
	if problem.is_empty():
		problem = catalog.unavailable_reason(item_id)
	if problem.is_empty():
		problem = CharacterUnlocks.lock_reason(catalog, item_id, CosmeticProfile.current().owned_character_items, developer_mode)
	return problem


func set_item_colour(item_id: String, channel_id: String, colour: Color) -> void:
	var look := appearance.duplicate_appearance()
	look.set_colour(item_id, channel_id, colour)
	show_appearance(look)


## Back to the model's own colour for one channel ("" = every channel of the item).
func reset_item_colour(item_id: String, channel_id: String = "") -> void:
	var look := appearance.duplicate_appearance()
	look.clear_colour(item_id, channel_id)
	show_appearance(look)


func set_skin_tone(tone: Color) -> void:
	var look := appearance.duplicate_appearance()
	look.skin_tone = tone.to_html(false)
	show_appearance(look)


## Chooses a skin texture ("" = the pack's own). Returns "" or why it was refused.
func set_skin_texture(texture_id: String) -> String:
	if not texture_id.is_empty() and CharacterWardrobe.skin_texture_path(catalog, appearance.body, texture_id).is_empty():
		return _say("%s has no skin texture %s." % [catalog.display_name(appearance.body), texture_id])
	var look := appearance.duplicate_appearance()
	look.skin_texture = texture_id
	show_appearance(look)
	return _say("")


## A random look ([param keep_body]: on the current base character).
func randomise(keep_body: bool = false) -> void:
	show_appearance(CharacterWardrobe.randomise(catalog, _rng, appearance.body if keep_body else "", _allowed_gate()))
	_say("Randomised.")


func set_developer_mode(enabled: bool) -> void:
	developer_mode = enabled
	developer_toggle.set_pressed_no_signal(enabled)
	show_appearance(appearance)


func play_clip(clip: StringName) -> void:
	var index := _clips.find(clip)
	if index >= 0:
		clip_picker.select(index)
	rig.play(clip, 0.15)


## Saves the current look as a preset ("" id = new). Returns {id, error}.
func save_preset(preset_name: String, preset_id: String = "") -> Dictionary:
	var result := CharacterPresets.save(preset_name, appearance, preset_id)
	_say(str(result["error"]) if not str(result["error"]).is_empty() else "Saved preset \"%s\"." % preset_name.strip_edges())
	_refresh_presets()
	return result


## Shows a saved preset. Returns "" or why it could not.
func load_preset(preset_id: String) -> String:
	var look := CharacterPresets.load_preset(preset_id)
	if look == null:
		return _say("That preset could not be read.")
	var notes := show_appearance(look)
	preset_name_edit.text = CharacterPresets.preset_name(preset_id)
	_say("Loaded \"%s\"%s" % [preset_name_edit.text, " (adjusted: see notes)." if not notes.is_empty() else "."])
	return ""


func delete_preset(preset_id: String) -> Error:
	var error := CharacterPresets.delete(preset_id)
	_say("Deleted." if error == OK else "Could not delete (%s)." % error_string(error))
	_refresh_presets()
	return error


## Makes the current look the player's own and saves the profile.
func use_as_my_look() -> Error:
	var profile := CosmeticProfile.current()
	profile.set_appearance(appearance)
	var error := profile.save()
	_say("This is now your look." if error == OK else "Could not save: %s" % error_string(error))
	return error


func set_bot_models(enabled: bool) -> Error:
	var error := DevOptions.set_bot_character_models(enabled)
	bots_toggle.set_pressed_no_signal(DevOptions.bot_character_models())
	_say(("Bots in the FPS Sandbox will wear character models." if enabled else "Bots in the FPS Sandbox use the box bodies.")
		if error == OK else "Could not save the option: %s" % error_string(error))
	return error


# --- refresh ------------------------------------------------------------------------------------

func _allowed_gate() -> Callable:
	if developer_mode:
		return Callable()
	var owned := CosmeticProfile.current().owned_character_items
	return func(item_id: String) -> bool: return CharacterUnlocks.is_unlocked(catalog, item_id, owned, false)


func _say(text: String) -> String:
	if _status != null:
		_status.text = text
	return text


func _refresh() -> void:
	for index: int in _body_ids.size():
		var body_id := _body_ids[index]
		var available := catalog.is_available(body_id)
		body_list.set_item_text(index, "%s%s" % [catalog.display_name(body_id), "" if available else "  (not installed)"])
		body_list.set_item_disabled(index, not available)
		body_list.set_item_tooltip(index, str(catalog.body(body_id).get("note", "")) if available else catalog.unavailable_reason(body_id))
	var at := _body_ids.find(appearance.body)
	if at >= 0:
		body_list.select(at)
	_rebuild_slots()


func _rebuild_slots() -> void:
	for child: Node in _slot_column.get_children():
		_slot_column.remove_child(child)
		child.queue_free()
	slot_pickers.clear()
	slot_choices.clear()
	if appearance.body.is_empty():
		_slot_column.add_child(UIFactory.label("No base character is installed.", &"WarningLabel", true))
		return
	_add_skin_section()
	for slot_id: String in catalog.body_slots(appearance.body):
		_add_slot_section(slot_id)


func _add_skin_section() -> void:
	var skin: Dictionary = catalog.body(appearance.body).get("skin", {})
	_slot_column.add_child(UIFactory.label("SKIN", &"SectionLabel"))
	var row := UIFactory.hbox(6)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(48, 28)
	picker.color = Color.from_string(appearance.skin_tone, Color("c9b48a")) if not appearance.skin_tone.is_empty() \
		else Color.from_string(str((skin.get("tones", ["#c9b48a"]) as Array)[0]), Color("c9b48a"))
	picker.tooltip_text = "Skin tone"
	picker.popup_closed.connect(func() -> void: set_skin_tone(picker.color))
	row.add_child(picker)
	for tone: Variant in skin.get("tones", []):
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.tooltip_text = str(tone)
		var style := StyleBoxFlat.new()
		style.bg_color = Color.from_string(str(tone), Color.WHITE)
		swatch.add_theme_stylebox_override(&"normal", style)
		swatch.add_theme_stylebox_override(&"hover", style)
		swatch.pressed.connect(func() -> void: set_skin_tone(Color.from_string(str(tone), Color.WHITE)))
		row.add_child(swatch)
	_slot_column.add_child(row)
	var textures := CharacterWardrobe.skin_textures(catalog, appearance.body)
	if not textures.is_empty():
		var texture_picker := OptionButton.new()
		var ids: Array[String] = [""]
		texture_picker.add_item("Skin texture: pack default")
		for entry: Dictionary in textures:
			ids.append(str(entry["id"]))
			texture_picker.add_item("Skin texture: %s" % entry.get("label", entry["id"]))
		texture_picker.select(maxi(0, ids.find(appearance.skin_texture)))
		texture_picker.item_selected.connect(func(index: int) -> void: set_skin_texture(ids[index]))
		_slot_column.add_child(texture_picker)


func _add_slot_section(slot_id: String) -> void:
	_slot_column.add_child(HSeparator.new())
	var required := catalog.is_required(appearance.body, slot_id)
	_slot_column.add_child(UIFactory.label(catalog.slot_label(slot_id).to_upper() + ("  ·  required" if required else ""), &"SectionLabel"))
	var cover := CharacterWardrobe.covered_by(catalog, appearance, slot_id)
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choices: Array[String] = [""]
	picker.add_item(NONE_LABEL if not required else "%s (required)" % NONE_LABEL)
	picker.set_item_disabled(0, required and cover.is_empty())
	for item_id: String in catalog.items_for(slot_id):
		var problem := item_problem(item_id)
		var mode := catalog.fit_mode(item_id, appearance.body)
		var suffix := ""
		if not problem.is_empty():
			suffix = "  (doesn't fit)" if mode.is_empty() else ("  (not installed)" if not catalog.is_available(item_id) else "  (locked)")
		elif mode == CharacterCatalog.FIT_HEAD:
			suffix = "  (adapted)"
		picker.add_item(catalog.display_name(item_id) + suffix)
		var index := picker.item_count - 1
		picker.set_item_disabled(index, not problem.is_empty())
		picker.set_item_tooltip(index, problem if not problem.is_empty() else
			("Fitted from %s's head." % catalog.display_name(catalog.native_body(item_id)) if mode == CharacterCatalog.FIT_HEAD else ""))
		choices.append(item_id)
	picker.select(maxi(0, choices.find(appearance.item_in(slot_id))))
	picker.item_selected.connect(func(index: int) -> void: _on_item_picked(slot_id, choices[index]))
	slot_pickers[slot_id] = picker
	slot_choices[slot_id] = choices
	_slot_column.add_child(picker)
	if not cover.is_empty():
		_slot_column.add_child(UIFactory.label("Covered by %s." % catalog.display_name(cover), &"MutedLabel", true))
	var worn := appearance.item_in(slot_id)
	if not worn.is_empty():
		_add_colour_rows(worn)


func _add_colour_rows(item_id: String) -> void:
	for channel: Dictionary in catalog.colour_channels(item_id):
		var channel_id := str(channel["id"])
		var row := UIFactory.hbox(6)
		var label := UIFactory.label("%s%s" % [channel.get("label", channel_id), "  · team %s" % channel["team"] if channel.has("team") else ""], &"MutedLabel")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(48, 24)
		picker.color = appearance.colour(item_id, channel_id, rig.factory_colour(item_id, channel_id))
		picker.tooltip_text = "Colour of %s" % str(channel.get("label", channel_id)).to_lower()
		picker.popup_closed.connect(func() -> void: set_item_colour(item_id, channel_id, picker.color))
		row.add_child(picker)
		var reset := UIFactory.button("↺")
		reset.tooltip_text = "Back to the model's own colour"
		reset.disabled = not appearance.has_colour(item_id, channel_id)
		reset.pressed.connect(func() -> void: reset_item_colour(item_id, channel_id))
		row.add_child(reset)
		_slot_column.add_child(row)


func _on_item_picked(slot_id: String, item_id: String) -> void:
	if item_id.is_empty():
		clear_slot(slot_id)
	else:
		equip_item(item_id)


func _refresh_presets() -> void:
	preset_list.clear()
	_preset_ids.clear()
	for entry: Dictionary in CharacterPresets.list():
		_preset_ids.append(str(entry["id"]))
		preset_list.add_item(str(entry["name"]))


func _selected_preset() -> String:
	var selected := preset_list.get_selected_items()
	return _preset_ids[selected[0]] if not selected.is_empty() else ""


func _selected_clip() -> StringName:
	return _clips[clip_picker.selected] if clip_picker.selected >= 0 and clip_picker.selected < _clips.size() else DEFAULT_CLIP


func _frame_camera() -> void:
	var height := maxf(rig.top_height(), 1.0)
	_camera_target = Vector3(0, height * 0.5, 0)
	_distance = clampf(height * 2.4, 1.5, 6.5)


# --- preview ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _turntable == null:
		return
	if _auto_turn and not _dragging:
		_yaw += AUTO_TURN_SPEED * delta
	_turntable.rotation = Vector3(0.0, _yaw, 0.0)
	var offset := Vector3(0, sin(-_pitch), cos(_pitch)) * _distance
	_camera.position = _camera_target + offset
	_camera.look_at(_camera_target)


func _on_preview_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			_auto_turn = false
	elif button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_distance = clampf(_distance * (1.0 / 1.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.6, 8.0)
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_auto_turn = not _auto_turn
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw += motion.relative.x * ROTATE_SPEED
		_pitch = clampf(_pitch + motion.relative.y * ROTATE_SPEED, -1.0, 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		App.go_to(App.SCENE_MAIN_MENU)
		get_viewport().set_input_as_handled()


# --- construction -------------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := UIFactory.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	layout.add_child(_build_top_bar())
	var middle := UIFactory.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(middle)
	middle.add_child(_build_left())
	middle.add_child(_build_preview())
	middle.add_child(_build_right())


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(8)
	bar.add_child(row)
	row.add_child(UIFactory.label("CHARACTER CREATOR", &"LogoLabel"))
	var badge := PanelContainer.new()
	badge.theme_type_variation = &"DevBadgePanel"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(UIFactory.label("DEVELOPER TOOL", &"WarningLabel"))
	badge.tooltip_text = "Character models are being tested: matches still use the box bodies unless the bot option is on"
	row.add_child(badge)
	row.add_child(UIFactory.expand_spacer())
	_status = UIFactory.label("", &"AccentLabel")
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)
	randomise_button = UIFactory.button("Randomise")
	randomise_button.tooltip_text = "A random base character and outfit"
	randomise_button.pressed.connect(func() -> void: randomise(false))
	row.add_child(randomise_button)
	var outfit_button := UIFactory.button("Randomise outfit")
	outfit_button.tooltip_text = "Random items on this base character"
	outfit_button.pressed.connect(func() -> void: randomise(true))
	row.add_child(outfit_button)
	use_button = UIFactory.button("Use as my look", &"AccentButton")
	use_button.tooltip_text = "Store this look in your profile"
	use_button.pressed.connect(func() -> void: use_as_my_look())
	row.add_child(use_button)
	back_button = UIFactory.button("◂ Menu")
	back_button.pressed.connect(func() -> void: App.go_to(App.SCENE_MAIN_MENU))
	row.add_child(back_button)
	return bar


func _build_left() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SidebarPanel"
	panel.custom_minimum_size.x = 260
	var column := UIFactory.vbox(8)
	panel.add_child(column)
	column.add_child(UIFactory.label("BASE CHARACTER", &"SectionLabel"))
	body_list = ItemList.new()
	body_list.custom_minimum_size.y = 120
	body_list.auto_height = true
	for body_id: String in catalog.body_ids():
		_body_ids.append(body_id)
		body_list.add_item(catalog.display_name(body_id))
	body_list.item_selected.connect(func(index: int) -> void: select_body(_body_ids[index]))
	column.add_child(body_list)
	column.add_child(UIFactory.label("ANIMATION", &"SectionLabel"))
	clip_picker = OptionButton.new()
	column.add_child(clip_picker)
	column.add_child(HSeparator.new())
	developer_toggle = CheckButton.new()
	developer_toggle.text = "Developer mode: every item"
	developer_toggle.tooltip_text = "Show every item whatever its unlock state (off: only what this profile has unlocked)"
	developer_toggle.button_pressed = developer_mode
	developer_toggle.toggled.connect(set_developer_mode)
	column.add_child(developer_toggle)
	bots_toggle = CheckButton.new()
	bots_toggle.text = "Bots wear character models"
	bots_toggle.tooltip_text = "Developer preview: bots in the FPS Sandbox get random looks in their team colours (hitboxes unchanged)"
	bots_toggle.button_pressed = DevOptions.bot_character_models()
	bots_toggle.toggled.connect(func(on: bool) -> void: set_bot_models(on))
	column.add_child(bots_toggle)
	column.add_child(HSeparator.new())
	column.add_child(UIFactory.label("PRESETS", &"SectionLabel"))
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "Preset name"
	column.add_child(preset_name_edit)
	var save_row := UIFactory.hbox(6)
	var save_new := UIFactory.button("Save new")
	save_new.pressed.connect(func() -> void: save_preset(preset_name_edit.text))
	save_row.add_child(save_new)
	var overwrite := UIFactory.button("Overwrite selected")
	overwrite.pressed.connect(func() -> void:
		if not _selected_preset().is_empty():
			save_preset(preset_name_edit.text, _selected_preset()))
	save_row.add_child(overwrite)
	column.add_child(save_row)
	preset_list = ItemList.new()
	preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preset_list.item_activated.connect(func(index: int) -> void: load_preset(_preset_ids[index]))
	column.add_child(preset_list)
	var preset_row := UIFactory.hbox(6)
	var load_button := UIFactory.button("Load")
	load_button.pressed.connect(func() -> void:
		if not _selected_preset().is_empty():
			load_preset(_selected_preset()))
	preset_row.add_child(load_button)
	var delete_button := UIFactory.button("Delete")
	delete_button.pressed.connect(func() -> void:
		if not _selected_preset().is_empty():
			delete_preset(_selected_preset()))
	preset_row.add_child(delete_button)
	column.add_child(preset_row)
	_notes = UIFactory.label("", &"MutedLabel", true)
	column.add_child(_notes)
	return panel


func _build_right() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.custom_minimum_size.x = 380
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_slot_column = UIFactory.vbox(6)
	_slot_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slot_column)
	return panel


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.tooltip_text = "Drag to turn · wheel to zoom · right-click to stop or start turning"
	container.gui_input.connect(_on_preview_input)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)
	var environment := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.1, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.shadow_enabled = true
	_viewport.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.011
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.17, 0.2)
	floor_mesh.material_override = floor_material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	_viewport.add_child(_camera)
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	rig = CharacterRig.new()
	_turntable.add_child(rig)
	clip_picker.item_selected.connect(func(index: int) -> void: rig.play(_clips[index], 0.15))
	return container


## Lists the animation clips (known once the rig has built a body).
func _fill_clips() -> void:
	_clips.clear()
	clip_picker.clear()
	for clip: String in rig.clips():
		_clips.append(StringName(clip))
	for clip: StringName in _clips:
		clip_picker.add_item(String(clip).replace("_", " "))
	clip_picker.select(_clips.find(DEFAULT_CLIP))
