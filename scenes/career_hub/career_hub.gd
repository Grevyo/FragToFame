extends Control
## Career Hub: persistent sidebar navigation plus a page host.
##
## Add a section by writing a CareerPage subclass and adding an entry to PAGES.

signal page_changed(page_id: StringName)

const PAGES: Array[Dictionary] = [
	{"id": &"home", "label": "Home", "script": preload("res://scenes/career_hub/pages/home_page.gd")},
	{"id": &"profile", "label": "Player Profile", "script": preload("res://scenes/career_hub/pages/profile_page.gd")},
	{"id": &"teams", "label": "Teams", "script": preload("res://scenes/career_hub/pages/teams_page.gd")},
	{"id": &"competitions", "label": "Competitions", "script": preload("res://scenes/career_hub/pages/competitions_page.gd")},
	{"id": &"calendar", "label": "Calendar", "script": preload("res://scenes/career_hub/pages/calendar_page.gd")},
	{"id": &"statistics", "label": "Statistics", "script": preload("res://scenes/career_hub/pages/statistics_page.gd")},
	{"id": &"coop", "label": "Co-op (Dev)", "script": preload("res://scenes/career_hub/pages/coop_page.gd")},
]

const DEFAULT_PAGE: StringName = &"home"

var current_page_id: StringName = &""
var current_page: CareerPage
var main_menu_button: Button

var _nav_buttons: Dictionary[StringName, Button] = {}
var _nav_group := ButtonGroup.new()
var _page_title: Label
var _page_holder: MarginContainer
var _scroll: ScrollContainer


func _ready() -> void:
	_build_layout()
	show_page(DEFAULT_PAGE)


static func page_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in PAGES:
		ids.append(entry["id"] as StringName)
	return ids


## Displays the page with [param page_id]. Returns false if no such page exists.
func show_page(page_id: StringName) -> bool:
	var entry := _find_page(page_id)
	if entry.is_empty():
		push_error("CareerHub: unknown page '%s'" % page_id)
		return false
	if current_page != null:
		_page_holder.remove_child(current_page)
		current_page.queue_free()
	var script := entry["script"] as GDScript
	var page := script.new() as CareerPage
	page.build_page()
	_page_holder.add_child(page)
	current_page = page
	current_page_id = page_id
	_page_title.text = page.get_page_title()
	_nav_buttons[page_id].set_pressed_no_signal(true)
	_scroll.scroll_vertical = 0
	page_changed.emit(page_id)
	return true


func _find_page(page_id: StringName) -> Dictionary:
	for entry: Dictionary in PAGES:
		if entry["id"] == page_id:
			return entry
	return {}


func _build_layout() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"BackgroundPanel"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := UIFactory.hbox(0)
	background.add_child(root)
	root.add_child(_build_sidebar())

	var main := UIFactory.vbox(0)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	main.add_child(_build_top_bar())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_scroll)

	_page_holder = MarginContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		_page_holder.add_theme_constant_override(side, 28)
	_scroll.add_child(_page_holder)


func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.theme_type_variation = &"SidebarPanel"
	sidebar.custom_minimum_size.x = 260

	var column := UIFactory.vbox(2)
	sidebar.add_child(column)

	var logo_margin := MarginContainer.new()
	logo_margin.add_theme_constant_override(&"margin_left", 20)
	logo_margin.add_theme_constant_override(&"margin_bottom", 18)
	var logo_box := UIFactory.vbox(0)
	logo_box.add_child(UIFactory.label("FRAG TO FAME", &"LogoLabel"))
	logo_box.add_child(UIFactory.label("CAREER HUB", &"SectionLabel"))
	logo_margin.add_child(logo_box)
	column.add_child(logo_margin)

	for entry: Dictionary in PAGES:
		var page_id := entry["id"] as StringName
		var b := UIFactory.button(entry["label"] as String, &"SidebarButton")
		b.toggle_mode = true
		b.button_group = _nav_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_page.bind(page_id))
		column.add_child(b)
		_nav_buttons[page_id] = b

	column.add_child(UIFactory.expand_spacer())

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override(&"margin_left", 16)
	footer_margin.add_theme_constant_override(&"margin_right", 16)
	main_menu_button = UIFactory.button("◂  Main Menu")
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	footer_margin.add_child(main_menu_button)
	column.add_child(footer_margin)
	return sidebar


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(16)
	bar.add_child(row)

	_page_title = UIFactory.label("", &"HeaderLabel")
	row.add_child(_page_title)
	row.add_child(UIFactory.expand_spacer())

	var badge := PanelContainer.new()
	badge.theme_type_variation = &"DevBadgePanel"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(UIFactory.label("DEVELOPMENT SAMPLE DATA — no career database yet", &"WarningLabel"))
	badge.tooltip_text = DevSampleData.NOTICE
	row.add_child(badge)
	return bar


func _on_main_menu_pressed() -> void:
	App.go_to(App.SCENE_MAIN_MENU)
