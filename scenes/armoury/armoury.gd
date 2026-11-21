class_name Armoury
extends Control
## Armoury: pick a weapon, inspect it, choose its Coat and put Magnets in its five slots, then
## save. Knife looks are listed after the guns: each takes a Coat (no Magnets), and one of them is
## the knife the player carries. Edits are made on a draft and only reach the player's
## CosmeticProfile on Save.
##
## Coats are listed from CoatLibrary. There are none shipped yet, so the list shows the factory
## finish and any Coat the player imported from a kit export.

const ROTATE_SPEED: float = 0.01
const MAGNET_ICON: int = 64

var draft: CosmeticProfile
var weapon_id: StringName = &""
var selected_slot: int = 0
var visual: WeaponVisual
var back_button: Button
var save_button: Button
var weapon_list: ItemList
var coat_list: ItemList
var slot_buttons: Array[Button] = []
var magnet_buttons: Dictionary[String, Button] = {}
var remove_magnet_button: Button
## "Carry this knife" (shown for knife looks only).
var knife_button: Button
## Everything about Magnet slots (hidden for knives, which take none).
var magnet_section: VBoxContainer
var confirm_dialog: ConfirmationDialog
var import_dialog: FileDialog

var _weapon_ids: Array[StringName] = []
var _coat_ids: Array[String] = []
var _saved: Dictionary = {}
var _status: Label
var _title: Label
var _coat_note: Label
var _viewport: SubViewport
var _camera: Camera3D
var _turntable: Node3D
var _dragging: bool = false
var _yaw: float = 1.2
var _pitch: float = 0.15


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft = CosmeticProfile.new()
	_load_draft()
	_build()
	for id: StringName in WeaponModels.all_ids():
		_weapon_ids.append(id)
		weapon_list.add_item(_list_label(id))
	select_weapon(_weapon_ids[0])
	back_button.grab_focus.call_deferred()


func _load_draft() -> void:
	_saved = CosmeticProfile.current().to_dict()["weapons"]
	draft.weapons.clear()
	for id: StringName in WeaponModels.all_ids():
		draft.weapons[String(id)] = CosmeticProfile.current().loadout(id)
	draft.set_knife(CosmeticProfile.current().equipped_knife())


func is_dirty() -> bool:
	if draft.equipped_knife() != CosmeticProfile.current().equipped_knife():
		return true
	for id: StringName in WeaponModels.all_ids():
		if draft.loadout(id) != CosmeticProfile.current().loadout(id):
			return true
	return false


## Shows a weapon in the preview with the draft's Coat and Magnets.
func select_weapon(id: StringName) -> bool:
	if not WeaponModels.has_model(id):
		return false
	weapon_id = id
	weapon_list.select(_weapon_ids.find(id))
	visual.setup(id)
	_camera.size = maxf(visual.size.z * 1.25, 0.34 if WeaponModels.has_slots(id) else 0.2)
	_title.text = WeaponModels.display_name(id)
	magnet_section.visible = WeaponModels.has_slots(id)
	knife_button.visible = WeaponModels.is_knife(id)
	_refresh_coats()
	if not WeaponModels.has_slots(id):
		_yaw = PI / 2.0
		_pitch = 0.1
	select_slot(0)
	return true


## Makes the selected knife look the one the player carries. Returns "" or why it was refused.
func equip_knife() -> String:
	var problem := draft.set_knife(weapon_id)
	_status.text = problem
	_refresh()
	return problem


## Chooses the Magnet slot to edit (0–4) and turns the weapon to show it.
func select_slot(slot: int) -> void:
	selected_slot = clampi(slot, 0, WeaponModels.SLOT_COUNT - 1)
	var slots := WeaponModels.slots(weapon_id)
	if WeaponModels.has_slots(weapon_id) and selected_slot < slots.size():
		_yaw = PI / 2.0 if (slots[selected_slot]["normal"] as Vector3).x < 0.0 else -PI / 2.0
		_pitch = 0.1
	_refresh()


## Puts a Magnet in the selected slot. Returns "" or why it was refused.
func set_magnet(magnet_id: String) -> String:
	var problem := draft.set_magnet(weapon_id, selected_slot, magnet_id)
	_status.text = problem
	_refresh()
	return problem


func clear_magnet() -> void:
	set_magnet("")


## Equips a Coat ("" = factory finish). Returns "" or why it was refused.
func set_coat(coat_id: String) -> String:
	var problem := draft.set_coat(weapon_id, coat_id)
	_status.text = problem
	_refresh()
	return problem


## Stores a kit export as a custom Coat for the current weapon and equips it in the draft.
func import_coat(png_path: String) -> String:
	var result := CoatLibrary.import_png(weapon_id, png_path, png_path.get_file().get_basename().replace("_", " "))
	if not str(result["error"]).is_empty():
		_status.text = str(result["error"])
		return _status.text
	_refresh_coats()
	return set_coat(str(result["id"]))


## Writes the draft to the player's profile. Returns OK or an error.
func save() -> Error:
	var profile := CosmeticProfile.current()
	for id: StringName in WeaponModels.all_ids():
		profile.weapons[String(id)] = draft.loadout(id)
	profile.set_knife(draft.equipped_knife())
	var err := profile.save()
	_status.text = "Saved." if err == OK else "Could not save: %s" % error_string(err)
	_refresh()
	return err


func revert() -> void:
	_load_draft()
	_refresh()


func _refresh() -> void:
	var loadout := draft.loadout(weapon_id)
	visual.apply_loadout(loadout)
	visual.show_slot_markers(WeaponModels.has_slots(weapon_id), selected_slot)
	for index: int in _weapon_ids.size():
		weapon_list.set_item_text(index, _list_label(_weapon_ids[index]))
	var carried := draft.equipped_knife() == weapon_id
	knife_button.disabled = carried
	knife_button.text = "Carried in matches" if carried else "Carry this knife"
	var magnets: Array = loadout["magnets"]
	var slots := WeaponModels.slots(weapon_id)
	for slot: int in slot_buttons.size():
		var side := "left" if slot < slots.size() and (slots[slot]["normal"] as Vector3).x < 0.0 else "right"
		var magnet := str(magnets[slot])
		slot_buttons[slot].text = "Slot %d · %s side\n%s" % [slot + 1, side, MagnetCatalog.display_name(magnet) if not magnet.is_empty() else "Empty"]
		slot_buttons[slot].set_pressed_no_signal(slot == selected_slot)
	remove_magnet_button.disabled = str(magnets[selected_slot]).is_empty()
	var coat := str(loadout["coat"])
	coat_list.select(maxi(0, _coat_ids.find(coat)))
	save_button.disabled = not is_dirty()
	save_button.text = "Save customisation" if is_dirty() else "Saved"


## A list entry: the weapon's name, or "Knife · name" (with a mark on the knife carried).
func _list_label(id: StringName) -> String:
	if not WeaponModels.is_knife(id):
		return WeaponModels.display_name(id)
	return "Knife · %s%s" % [WeaponModels.display_name(id), "  ✓" if draft.equipped_knife() == id else ""]


func _refresh_coats() -> void:
	coat_list.clear()
	_coat_ids = [""]
	coat_list.add_item("Factory finish")
	for coat: Dictionary in CoatLibrary.coats_for(weapon_id):
		_coat_ids.append(str(coat["id"]))
		coat_list.add_item("%s  ·  %s%s" % [coat["name"], str(coat["rarity"]).capitalize(),
			"  ·  custom" if coat["source"] == CoatLibrary.SOURCE_CUSTOM else ""])
	var pixels := WeaponModels.coat_size(weapon_id)
	_coat_note.text = ("No Coats for this %s yet. " % ("knife" if WeaponModels.is_knife(weapon_id) else "weapon") if _coat_ids.size() == 1 else "") \
		+ "Coats are %d x %d PNGs made with the %s kit (%d paint zones)." % [pixels.x, pixels.y,
			WeaponModels.info(weapon_id)["kit"], WeaponModels.zone_names(weapon_id).size()]


func _process(_delta: float) -> void:
	if _turntable != null:
		_turntable.rotation = Vector3(_pitch, _yaw, 0.0)


func _on_preview_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
	elif button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := 1.0 / 1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
		_camera.size = clampf(_camera.size * factor, 0.08, 2.0)
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw += motion.relative.x * ROTATE_SPEED
		_pitch = clampf(_pitch + motion.relative.y * ROTATE_SPEED, -1.2, 1.2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		_leave()
		get_viewport().set_input_as_handled()


func _leave() -> void:
	if is_dirty():
		confirm_dialog.popup_centered(Vector2i(420, 0))
	else:
		App.go_to(App.SCENE_MAIN_MENU)


# --- construction -------------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := UIFactory.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var bar_row := UIFactory.hbox(8)
	bar.add_child(bar_row)
	bar_row.add_child(UIFactory.label("ARMOURY", &"LogoLabel"))
	_title = UIFactory.label("", &"HeaderLabel")
	bar_row.add_child(_title)
	bar_row.add_child(UIFactory.expand_spacer())
	_status = UIFactory.label("", &"AccentLabel")
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_status)
	var revert_button := UIFactory.button("Revert")
	revert_button.tooltip_text = "Discard unsaved changes"
	revert_button.pressed.connect(revert)
	bar_row.add_child(revert_button)
	save_button = UIFactory.button("Saved", &"AccentButton")
	save_button.pressed.connect(func() -> void: save())
	bar_row.add_child(save_button)
	back_button = UIFactory.button("◂ Menu")
	back_button.pressed.connect(_leave)
	bar_row.add_child(back_button)
	layout.add_child(bar)

	var middle := UIFactory.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(middle)

	var left := PanelContainer.new()
	left.theme_type_variation = &"SidebarPanel"
	left.custom_minimum_size.x = 220
	var left_column := UIFactory.vbox(8)
	left.add_child(left_column)
	left_column.add_child(UIFactory.label("WEAPONS", &"SectionLabel"))
	weapon_list = ItemList.new()
	weapon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapon_list.item_selected.connect(func(index: int) -> void: select_weapon(_weapon_ids[index]))
	left_column.add_child(weapon_list)
	middle.add_child(left)

	middle.add_child(_build_preview())

	var right := PanelContainer.new()
	right.theme_type_variation = &"CardPanel"
	right.custom_minimum_size.x = 400
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var column := UIFactory.vbox(8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	knife_button = UIFactory.button("Carry this knife", &"AccentButton")
	knife_button.tooltip_text = "Everyone carries one knife; this chooses which one you see"
	knife_button.pressed.connect(func() -> void: equip_knife())
	column.add_child(knife_button)
	column.add_child(UIFactory.label("COAT", &"SectionLabel"))
	coat_list = ItemList.new()
	coat_list.custom_minimum_size.y = 110
	coat_list.item_selected.connect(func(index: int) -> void: set_coat(_coat_ids[index]))
	column.add_child(coat_list)
	_coat_note = UIFactory.label("", &"MutedLabel", true)
	column.add_child(_coat_note)
	var import_button := UIFactory.button("Import a Coat PNG made with the kit…")
	import_button.pressed.connect(func() -> void: import_dialog.popup_centered_ratio(0.6))
	column.add_child(import_button)
	magnet_section = UIFactory.vbox(8)
	column.add_child(magnet_section)
	magnet_section.add_child(HSeparator.new())
	magnet_section.add_child(UIFactory.label("MAGNET SLOTS", &"SectionLabel"))
	var group := ButtonGroup.new()
	for slot: int in WeaponModels.SLOT_COUNT:
		var button := UIFactory.button("Slot %d" % (slot + 1), &"SidebarButton")
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: select_slot(slot))
		magnet_section.add_child(button)
		slot_buttons.append(button)
	remove_magnet_button = UIFactory.button("Remove Magnet from this slot")
	remove_magnet_button.pressed.connect(clear_magnet)
	magnet_section.add_child(remove_magnet_button)
	magnet_section.add_child(UIFactory.label("MAGNETS (click to apply to the selected slot)", &"SectionLabel"))
	var grid := GridContainer.new()
	grid.columns = 5
	for magnet_id: String in MagnetCatalog.ids():
		var button := Button.new()
		button.icon = MagnetCatalog.texture(magnet_id)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(MAGNET_ICON + 8, MAGNET_ICON + 8)
		button.tooltip_text = MagnetCatalog.display_name(magnet_id)
		button.pressed.connect(func() -> void: set_magnet(magnet_id))
		grid.add_child(button)
		magnet_buttons[magnet_id] = button
	magnet_section.add_child(grid)
	middle.add_child(right)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Unsaved customisation"
	confirm_dialog.dialog_text = "Leave without saving your changes?"
	confirm_dialog.ok_button_text = "Discard changes"
	confirm_dialog.confirmed.connect(func() -> void: App.go_to(App.SCENE_MAIN_MENU))
	add_child(confirm_dialog)
	import_dialog = FileDialog.new()
	import_dialog.title = "Import a Coat PNG"
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = PackedStringArray(["*.png ; Coat texture exported from a kit"])
	import_dialog.file_selected.connect(func(path: String) -> void: import_coat(path))
	add_child(import_dialog)


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.tooltip_text = "Drag to turn the weapon · wheel to zoom"
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
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0, 0, 3)
	_camera.size = 1.2
	_viewport.add_child(_camera)
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	visual = WeaponVisual.new()
	_turntable.add_child(visual)
	return container
