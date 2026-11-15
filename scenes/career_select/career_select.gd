extends Control
## Continues a saved career or starts one from a world database.

signal career_opened(save_id: String)

var saves_box: VBoxContainer
var status_label: Label
## New-career form fields (exposed for tests).
var career_name_edit: LineEdit
var first_name_edit: LineEdit
var last_name_edit: LineEdit
var nickname_edit: LineEdit
var nation_option: OptionButton
var role_option: OptionButton
var difficulty_option: OptionButton
var age_spin: SpinBox
var create_button: Button
var back_button: Button

var _nation_ids: Array[String] = []
var _database_option: OptionButton
var _database_paths: Array[String] = []
var _import_dialog: FileDialog
var _replace_dialog: ConfirmationDialog
var _replacement_source: String
var _restore_button: Button


func _ready() -> void:
	_build()
	refresh_saves()


func refresh_saves() -> void:
	for child: Node in saves_box.get_children():
		child.queue_free()
	var saves := App.career_saves.list_saves()
	if saves.is_empty():
		saves_box.add_child(UIFactory.label("No careers yet — create one on the right.", &"MutedLabel", true))
		return
	for summary: Dictionary in saves:
		var row := UIFactory.hbox(12)
		var info := UIFactory.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UIFactory.label(str(summary["name"]), &"CardTitleLabel"))
		var detail := "%s · %s" % [str(summary["human"]), GameDate.format(int(summary["current_day"]))]
		if not str(summary["error"]).is_empty():
			detail = str(summary["error"])
		if int(summary["schema"]) > CareerSchema.CURRENT_VERSION:
			detail = "Made by a newer version of the game"
		info.add_child(UIFactory.label(detail, &"MutedLabel"))
		row.add_child(info)
		var open := UIFactory.button("Continue", &"AccentButton")
		open.pressed.connect(continue_career.bind(str(summary["save_id"])))
		row.add_child(open)
		saves_box.add_child(row)


## Opens a saved career and goes to the Career Hub. Returns "" or the error shown.
func continue_career(save_id: String) -> String:
	var error := App.load_career(save_id)
	if not error.is_empty():
		_show_error("Could not open the career: %s" % error, save_id)
		return error
	career_opened.emit(save_id)
	App.go_to(App.SCENE_CAREER_HUB)
	return ""


## Creates a career from the form. Returns "" or the error shown.
func create_career() -> String:
	var profile := form_profile()
	status_label.text = "Starting the career…"
	var database_path := _database_paths[_database_option.selected] if _database_option.selected >= 0 else ""
	var error := App.new_career(career_name_edit.text, profile, database_path)
	if not error.is_empty():
		_show_error(error)
		return error
	career_opened.emit(App.career.save_id)
	App.go_to(App.SCENE_CAREER_HUB)
	return ""


func form_profile() -> Dictionary:
	return {
		"first_name": first_name_edit.text,
		"last_name": last_name_edit.text,
		"nickname": nickname_edit.text,
		"nation_id": _nation_ids[nation_option.selected] if nation_option.selected >= 0 else "",
		"preferred_role": CareerCatalog.ROLES[role_option.selected] if role_option.selected >= 0 else &"",
		"difficulty": CareerCatalog.DIFFICULTIES.keys()[difficulty_option.selected] if difficulty_option.selected >= 0 else &"",
		"age": int(age_spin.value),
	}


func _show_error(text: String, save_id: String = "") -> void:
	status_label.text = text
	if is_instance_valid(_restore_button):
		_restore_button.queue_free()
		_restore_button = null
	if not save_id.is_empty() and not App.career_saves.backups(save_id).is_empty():
		_restore_button = UIFactory.button("Restore the latest backup")
		_restore_button.pressed.connect(func() -> void:
			var problem := App.career_saves.restore_latest_backup(save_id)
			_show_error("Backup restored — press Continue again." if problem.is_empty() else problem,
				"" if problem.is_empty() else save_id)
			if problem.is_empty():
				refresh_saves())
		status_label.get_parent().add_child(_restore_button)


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	add_child(margin)
	var column := UIFactory.vbox(18)
	margin.add_child(column)
	var header := UIFactory.hbox(16)
	header.add_child(UIFactory.label("CAREERS", &"HeaderLabel"))
	header.add_child(UIFactory.expand_spacer())
	back_button = UIFactory.button("◂  Main Menu")
	back_button.pressed.connect(func() -> void: App.go_to(App.SCENE_MAIN_MENU))
	header.add_child(back_button)
	column.add_child(header)
	status_label = UIFactory.label("", &"WarningLabel", true)
	column.add_child(status_label)

	var row := UIFactory.hbox(24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var saves_card := UIFactory.card(row, "Continue a career")
	saves_box = UIFactory.vbox(10)
	saves_card.add_child(saves_box)

	var form := UIFactory.card(row, "New career")
	form.add_child(UIFactory.label("Create your professional in the selected world database. Each career "
		+ "has its own save for players, teams and competitions.", &"MutedLabel", true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	form.add_child(grid)
	career_name_edit = _line(grid, "Career name", "My career")
	first_name_edit = _line(grid, "First name", "")
	last_name_edit = _line(grid, "Last name", "")
	nickname_edit = _line(grid, "Nickname", "")
	nation_option = _option(grid, "Nationality")
	var nations := CareerCatalog.NATIONS.keys()
	nations.sort_custom(func(a: String, b: String) -> bool: return CareerCatalog.nation_name(a) < CareerCatalog.nation_name(b))
	for nation_id: String in nations:
		_nation_ids.append(nation_id)
		nation_option.add_item(CareerCatalog.nation_name(nation_id))
	nation_option.select(_nation_ids.find("gb"))
	role_option = _option(grid, "Preferred role")
	for role: StringName in CareerCatalog.ROLES:
		role_option.add_item(CareerCatalog.role_name(role))
	role_option.select(0)
	difficulty_option = _option(grid, "Career difficulty")
	for difficulty: StringName in CareerCatalog.DIFFICULTIES:
		difficulty_option.add_item(CareerCatalog.DIFFICULTY_NAMES[difficulty])
	difficulty_option.select(1)
	grid.add_child(UIFactory.label("Age", &"MutedLabel"))
	age_spin = SpinBox.new()
	age_spin.min_value = 16
	age_spin.max_value = 30
	age_spin.value = 18
	grid.add_child(age_spin)
	_database_option = _option(grid, "World database")
	var import_button := UIFactory.button("Import world template")
	form.add_child(import_button)
	_import_dialog = FileDialog.new()
	_import_dialog.title = "Import a world template"
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.filters = PackedStringArray(["*.f2fdb ; Frag to Fame world templates"])
	add_child(_import_dialog)
	import_button.pressed.connect(func() -> void: _import_dialog.popup_centered_ratio())
	_import_dialog.file_selected.connect(func(path: String) -> void: _import_world(path))
	_replace_dialog = ConfirmationDialog.new()
	_replace_dialog.title = "Replace imported world template?"
	_replace_dialog.confirmed.connect(func() -> void: _import_world(_replacement_source, true))
	add_child(_replace_dialog)
	_refresh_databases()
	create_button = UIFactory.button("Create career", &"AccentButton")
	create_button.pressed.connect(func() -> void: create_career())
	form.add_child(create_button)


func _refresh_databases(selected_path: String = "") -> void:
	_database_option.clear()
	_database_paths.clear()
	for entry: Dictionary in App.career_saves.databases.list():
		if not str(entry["error"]).is_empty():
			continue
		_database_paths.append(str(entry["path"]))
		_database_option.add_item(str(entry["name"]))
	var selected := _database_paths.find(selected_path)
	if selected < 0:
		selected = _database_paths.find(WorldDatabases.default_path())
	if selected >= 0:
		_database_option.select(selected)


func _import_world(path: String, confirmed: bool = false) -> void:
	var result := App.career_saves.databases.import_database(path, confirmed)
	if bool(result["requires_confirmation"]):
		_replacement_source = path
		_replace_dialog.dialog_text = "Replace '%s' for future careers? The previous file is kept as a backup." % result["name"]
		_replace_dialog.popup_centered()
	elif not str(result["error"]).is_empty():
		_show_error(str(result["error"]))
	else:
		_refresh_databases(str(result["path"]))
		_show_error("Imported %s." % result["name"])


func _line(grid: GridContainer, caption: String, value: String) -> LineEdit:
	grid.add_child(UIFactory.label(caption, &"MutedLabel"))
	var edit := LineEdit.new()
	edit.text = value
	edit.max_length = 24
	edit.custom_minimum_size.x = 280
	grid.add_child(edit)
	return edit


func _option(grid: GridContainer, caption: String) -> OptionButton:
	grid.add_child(UIFactory.label(caption, &"MutedLabel"))
	var option := OptionButton.new()
	grid.add_child(option)
	return option
