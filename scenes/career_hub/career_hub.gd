extends Control
## Career Hub: a manager-game shell. A sidebar of main headings, a top bar with Back / Forward,
## the page title, the date, Holiday and Continue (top right), and a page host.
##
## Every page is opened by route ({page id, args}) and kept in a history, so pages link into
## each other: Teams → a team → its squad → a player → compare, matches, news, and Back again.
## Add a page by writing a CareerPage subclass and adding an entry to PAGES ("group" is the
## sidebar heading; pages without a group are reached through links only).

signal page_changed(page_id: StringName)

const PAGES: Array[Dictionary] = [
	{"id": &"home", "label": "Home", "group": "CAREER", "script": preload("res://scenes/career_hub/pages/home_page.gd")},
	{"id": &"inbox", "label": "Inbox", "group": "CAREER", "script": preload("res://scenes/career_hub/pages/inbox_page.gd")},
	{"id": &"calendar", "label": "Calendar", "group": "CAREER", "script": preload("res://scenes/career_hub/pages/calendar_page.gd")},
	{"id": &"profile", "label": "My Profile", "group": "ME", "script": preload("res://scenes/career_hub/pages/profile_page.gd")},
	{"id": &"training", "label": "Training", "group": "ME", "script": preload("res://scenes/career_hub/pages/training_page.gd")},
	{"id": &"my_team", "label": "My Team", "group": "ME", "script": preload("res://scenes/career_hub/pages/team_page.gd")},
	{"id": &"competitions", "label": "Competitions", "group": "WORLD", "script": preload("res://scenes/career_hub/pages/competitions_page.gd")},
	{"id": &"teams", "label": "Teams", "group": "WORLD", "script": preload("res://scenes/career_hub/pages/teams_page.gd")},
	{"id": &"players", "label": "Players", "group": "WORLD", "script": preload("res://scenes/career_hub/pages/players_page.gd")},
	{"id": &"news", "label": "News", "group": "WORLD", "script": preload("res://scenes/career_hub/pages/news_page.gd")},
	{"id": &"statistics", "label": "Statistics", "group": "DATA", "script": preload("res://scenes/career_hub/pages/statistics_page.gd")},
	{"id": &"coop", "label": "Co-op (Dev)", "group": "DATA", "script": preload("res://scenes/career_hub/pages/coop_page.gd")},
	# Reached through links.
	{"id": &"team", "label": "Team", "group": "", "script": preload("res://scenes/career_hub/pages/team_page.gd")},
	{"id": &"player", "label": "Player", "group": "", "script": preload("res://scenes/career_hub/pages/player_page.gd")},
	{"id": &"compare", "label": "Compare players", "group": "", "script": preload("res://scenes/career_hub/pages/compare_page.gd")},
	{"id": &"series", "label": "Match report", "group": "", "script": preload("res://scenes/career_hub/pages/series_page.gd")},
	{"id": &"match_view", "label": "Round by round", "group": "", "script": preload("res://scenes/career_hub/pages/match_view_page.gd")},
]

const DEFAULT_PAGE: StringName = &"home"
const HISTORY_LIMIT: int = 60
## Holiday lengths offered (label, days; 0 = until the next inbox message).
const HOLIDAY_OPTIONS: Array[Array] = [["Until the next inbox message", 0], ["1 week", 7], ["2 weeks", 14],
	["1 month", 30], ["3 months", 91], ["6 months", 182], ["Until the end of the year", -1]]

var current_page_id: StringName = &""
var current_page: CareerPage
var main_menu_button: Button
var continue_button: Button
var holiday_button: Button
var back_button: Button
var forward_button: Button
## Why the last Continue / Holiday stopped (shown under the top bar).
var status_label: Label
var holiday_panel: PopupPanel
var holiday_choice: OptionButton
var holiday_simulate: CheckBox

## Sidebar groups the player collapsed (kept for the session, across page and scene changes).
static var collapsed_groups: Dictionary[String, bool] = {}

var _history: Array[Dictionary] = []
var _history_index: int = -1
var _nav_buttons: Dictionary[StringName, Button] = {}
var _nav_group := ButtonGroup.new()
var _group_boxes: Dictionary[String, VBoxContainer] = {}
var _group_headings: Dictionary[String, Button] = {}
var _date_label: Label
var _page_title: Label
var _page_holder: MarginContainer
var _scroll: ScrollContainer


func _ready() -> void:
	add_to_group(&"career_hub")
	_build_layout()
	show_page(DEFAULT_PAGE)
	grant_character_unlocks()


## Character items earned by what the human has done in this career, added to the player's
## cosmetic profile when the hub opens (after every match). Returns the items newly granted.
func grant_character_unlocks() -> Array[String]:
	var granted: Array[String] = []
	if App.career == null or App.career.repo == null or App.career.human_player_id.is_empty() 			or not is_player_save(App.career.repo.db.path):
		return granted
	var profile := CosmeticProfile.current()
	var catalog := CharacterCatalog.shared()
	granted = CharacterUnlocks.grant_earned(catalog, profile.owned_character_items,
		CareerUnlockProgress.of(App.career.repo, App.career.human_player_id))
	if granted.is_empty():
		return granted
	profile.save()
	var names: PackedStringArray = []
	for item_id: String in granted:
		names.append(catalog.display_name(item_id))
	var notice := AcceptDialog.new()
	notice.title = "Character items unlocked"
	notice.dialog_text = "Earned in your career, now in the Character Creator:
" + ", ".join(names)
	add_child(notice)
	notice.popup_centered.call_deferred(Vector2i(460, 0))
	return granted


## Whether a career database is one of the player's own saves (user://careers). Careers made
## elsewhere (tests, tools) never grant items to the player's profile.
static func is_player_save(database_path: String) -> bool:
	return not database_path.is_empty() and ProjectSettings.globalize_path(database_path).simplify_path() 		.begins_with(ProjectSettings.globalize_path(CareerSaves.ROOT).simplify_path() + "/")


static func page_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in PAGES:
		ids.append(entry["id"] as StringName)
	return ids


## Displays the page with [param page_id] (no arguments). Returns false if no such page exists.
func show_page(page_id: StringName) -> bool:
	return navigate(page_id, {})


## Opens a route and records it in the history. Returns false if no such page exists.
func navigate(page_id: StringName, route_args: Dictionary = {}) -> bool:
	if _find_page(page_id).is_empty():
		push_error("CareerHub: unknown page '%s'" % page_id)
		return false
	_history.resize(_history_index + 1)
	_history.append({"page": page_id, "args": route_args.duplicate()})
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()
	_history_index = _history.size() - 1
	return _open(_history[_history_index])


func can_go_back() -> bool:
	return _history_index > 0


func go_back() -> bool:
	if not can_go_back():
		return false
	_history_index -= 1
	return _open(_history[_history_index])


func go_forward() -> bool:
	if _history_index >= _history.size() - 1:
		return false
	_history_index += 1
	return _open(_history[_history_index])


## Rebuilds the current page (after the date moved).
func refresh() -> void:
	if _history_index >= 0:
		_open(_history[_history_index])


## Top-bar Continue: runs days until something needs the player, then refreshes the page.
func continue_on() -> Dictionary:
	var outcome := App.continue_career()
	status_label.text = str(outcome["reason"]) if not bool(outcome["ok"]) else "%d day%s · %s" % [
		int(outcome["days"]), "" if int(outcome["days"]) == 1 else "s", outcome["reason"]]
	refresh()
	return outcome


## Holiday: [param days] > 0 runs that many days, 0 runs until the next inbox message, -1 to the
## end of the year. [param simulate_matches] (development) simulates your matches instead of
## stopping for them.
func go_on_holiday(days: int, simulate_matches: bool) -> Dictionary:
	var outcome := App.holiday_career(days, simulate_matches)
	status_label.text = "Holiday: %s" % outcome["reason"]
	if holiday_panel != null:
		holiday_panel.hide()
	refresh()
	return outcome


func _open(route: Dictionary) -> bool:
	var page_id := route["page"] as StringName
	var entry := _find_page(page_id)
	if entry.is_empty():
		return false
	if current_page != null:
		_page_holder.remove_child(current_page)
		current_page.queue_free()
	var script := entry["script"] as GDScript
	var page := script.new() as CareerPage
	page.args = (route["args"] as Dictionary).merged({"_page": String(page_id)}, true)
	page.build_page()
	_page_holder.add_child(page)
	current_page = page
	current_page_id = page_id
	_page_title.text = page.get_page_title()
	# set_pressed_no_signal does not release the other buttons in the group, so do it explicitly.
	for id: StringName in _nav_buttons:
		_nav_buttons[id].set_pressed_no_signal(id == page_id)
	back_button.disabled = not can_go_back()
	forward_button.disabled = _history_index >= _history.size() - 1
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
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override(&"margin_left", 28)
	status_margin.add_theme_constant_override(&"margin_top", 6)
	status_label = UIFactory.label("", &"WarningLabel", true)
	status_margin.add_child(status_label)
	main.add_child(status_margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_scroll)

	_page_holder = MarginContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		_page_holder.add_theme_constant_override(side, 28)
	_scroll.add_child(_page_holder)
	_build_holiday_panel()


func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.theme_type_variation = &"SidebarPanel"
	sidebar.custom_minimum_size.x = 240

	var column := UIFactory.vbox(2)
	sidebar.add_child(column)

	var logo_margin := MarginContainer.new()
	logo_margin.add_theme_constant_override(&"margin_left", 20)
	logo_margin.add_theme_constant_override(&"margin_bottom", 10)
	var logo_box := UIFactory.vbox(0)
	logo_box.add_child(UIFactory.label("FRAG TO FAME", &"LogoLabel"))
	logo_box.add_child(UIFactory.label("CAREER HUB", &"SectionLabel"))
	logo_margin.add_child(logo_box)
	column.add_child(logo_margin)

	var group := ""
	var group_box: VBoxContainer
	for entry: Dictionary in PAGES:
		if str(entry["group"]).is_empty():
			continue
		if str(entry["group"]) != group:
			group = str(entry["group"])
			var heading_margin := MarginContainer.new()
			heading_margin.add_theme_constant_override(&"margin_top", 8)
			var heading := UIFactory.button("", &"SidebarHeadingButton")
			heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
			heading.tooltip_text = "Show or hide %s" % group.capitalize()
			var group_id := group
			heading.pressed.connect(func() -> void: toggle_group(group_id))
			heading_margin.add_child(heading)
			column.add_child(heading_margin)
			group_box = UIFactory.vbox(2)
			column.add_child(group_box)
			_group_boxes[group] = group_box
			_group_headings[group] = heading
		var page_id := entry["id"] as StringName
		var b := UIFactory.button(entry["label"] as String, &"SidebarButton")
		b.toggle_mode = true
		b.button_group = _nav_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: navigate(page_id, {}))
		group_box.add_child(b)
		_nav_buttons[page_id] = b
	for id: String in _group_boxes:
		_show_group(id)

	column.add_child(UIFactory.expand_spacer())

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override(&"margin_left", 16)
	footer_margin.add_theme_constant_override(&"margin_right", 16)
	main_menu_button = UIFactory.button("◂  Main Menu")
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	footer_margin.add_child(main_menu_button)
	column.add_child(footer_margin)
	return sidebar


## Expands or collapses a sidebar heading's pages. Returns true when the group is now open.
func toggle_group(group: String) -> bool:
	if not _group_boxes.has(group):
		return false
	collapsed_groups[group] = not bool(collapsed_groups.get(group, false))
	_show_group(group)
	return not collapsed_groups[group]


func _show_group(group: String) -> void:
	var collapsed := bool(collapsed_groups.get(group, false))
	_group_boxes[group].visible = not collapsed
	_group_headings[group].text = "%s  %s" % ["▸" if collapsed else "▾", group]


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(12)
	bar.add_child(row)

	back_button = UIFactory.button("◂")
	back_button.tooltip_text = "Back"
	back_button.pressed.connect(func() -> void: go_back())
	row.add_child(back_button)
	forward_button = UIFactory.button("▸")
	forward_button.tooltip_text = "Forward"
	forward_button.pressed.connect(func() -> void: go_forward())
	row.add_child(forward_button)
	_page_title = UIFactory.label("", &"HeaderLabel")
	row.add_child(_page_title)
	row.add_child(UIFactory.expand_spacer())

	if App.has_career():
		_date_label = UIFactory.label("", &"AccentLabel")
		_date_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_date_label)
		_refresh_date()
		App.career_day_changed.connect(_refresh_date)
		holiday_button = UIFactory.button("Holiday")
		holiday_button.tooltip_text = "Go on holiday: until your next inbox message or for a set time."
		holiday_button.pressed.connect(_show_holiday)
		row.add_child(holiday_button)
		continue_button = UIFactory.button("Continue  ▸", &"AccentButton")
		continue_button.tooltip_text = "Run days until something needs you."
		continue_button.pressed.connect(func() -> void: continue_on())
		row.add_child(continue_button)
	else:
		var badge := PanelContainer.new()
		badge.theme_type_variation = &"DevBadgePanel"
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.add_child(UIFactory.label("NO CAREER OPEN", &"WarningLabel"))
		row.add_child(badge)
	return bar


func _build_holiday_panel() -> void:
	holiday_panel = PopupPanel.new()
	var box := UIFactory.vbox(10)
	box.custom_minimum_size = Vector2(360, 0)
	holiday_panel.add_child(box)
	box.add_child(UIFactory.label("HOLIDAY", &"SectionLabel"))
	box.add_child(UIFactory.label("Days pass on their own. Your own matches still stop the holiday so you can play them.",
		&"MutedLabel", true))
	holiday_choice = OptionButton.new()
	for option: Array in HOLIDAY_OPTIONS:
		holiday_choice.add_item(str(option[0]))
	box.add_child(holiday_choice)
	holiday_simulate = CheckBox.new()
	holiday_simulate.text = "Simulate my matches (development)"
	holiday_simulate.visible = OS.is_debug_build()
	box.add_child(holiday_simulate)
	var go_button := UIFactory.button("Go on holiday", &"AccentButton")
	go_button.pressed.connect(func() -> void:
		go_on_holiday(int(HOLIDAY_OPTIONS[holiday_choice.selected][1]), holiday_simulate.button_pressed))
	box.add_child(go_button)
	add_child(holiday_panel)


func _show_holiday() -> void:
	holiday_panel.popup_centered()


func _refresh_date() -> void:
	if _date_label == null or not App.has_career():
		return
	var repo := App.career.repo
	_date_label.text = "%s  ·  %s" % [repo.meta_value("save_name", "Career"), GameDate.format(repo.current_day())]


func _on_main_menu_pressed() -> void:
	App.go_to(App.SCENE_MAIN_MENU)
