extends Control
## Map select for the FPS Sandbox: pick an official map, the development arena or one of your
## saved maps, then load it into the FPS runtime.

var storage: MapStorage = MapStorage.new()
var back_button: Button
## One button per offered map, keyed by map ID.
var map_buttons: Dictionary[String, Button] = {}

var _list: VBoxContainer


func _ready() -> void:
	_build()
	refresh()


## Rebuilds the list (official maps, the dev arena, then saved maps, newest first).
func refresh() -> void:
	map_buttons.clear()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_list.add_child(UIFactory.label("OFFICIAL MAPS", &"SectionLabel"))
	for entry: Dictionary in OfficialMaps.listing():
		_add_map(str(entry["map_id"]), str(entry["name"]), "Official competitive map")
	_list.add_child(UIFactory.label("DEVELOPMENT", &"SectionLabel"))
	_add_map(MapTemplates.SANDBOX_ARENA_ID, "Sandbox Arena (dev)", "Movement and shooting test arena with target dummies")
	_list.add_child(UIFactory.label("YOUR MAPS (Creation Studio)", &"SectionLabel"))
	var saved := storage.list_maps()
	if saved.is_empty():
		_list.add_child(UIFactory.label("No saved maps yet. Build one in the Creation Studio.", &"MutedLabel"))
	for entry: Dictionary in saved:
		_add_map(str(entry["map_id"]), str(entry["name"]), "%d pieces  ·  saved %s" % [int(entry["pieces"]),
			Time.get_datetime_string_from_unix_time(int(entry["modified"]), true)])
	var first: Button = map_buttons.values()[0] if not map_buttons.is_empty() else back_button
	first.grab_focus.call_deferred()


## Loads the map into the FPS Sandbox. Returns false (and stays here) if it cannot be read.
func play(map_id: String) -> bool:
	var doc := OfficialMaps.find_map(map_id, storage)
	if doc == null:
		return false
	return App.start_sandbox(doc) == OK


func _add_map(map_id: String, title: String, detail: String) -> void:
	var button := UIFactory.button("%s\n%s" % [title, detail], &"MenuButtonLarge")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void:
		if not play(map_id):
			button.text = "%s\nThis map could not be loaded." % title
			button.disabled = true)
	_list.add_child(button)
	map_buttons[map_id] = button


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := UIFactory.vbox(14)
	column.custom_minimum_size.x = 640
	center.add_child(column)
	column.add_child(UIFactory.label("FPS SANDBOX", &"HeaderLabel"))
	column.add_child(UIFactory.label("Choose a map to walk and shoot on. Practice matches start from the pause menu.", &"MutedLabel", true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 520
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = UIFactory.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	back_button = UIFactory.button("◂ Back to main menu")
	back_button.pressed.connect(func() -> void: App.go_to(App.SCENE_MAIN_MENU))
	column.add_child(back_button)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		App.go_to(App.SCENE_MAIN_MENU)
		get_viewport().set_input_as_handled()
