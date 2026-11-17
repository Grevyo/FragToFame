class_name CareerPlayersPage
extends CareerPage
## Database browser for every professional: search, filter by role/region/free agency, ranked by
## perceived rating. Each name opens the player's page; each team its team page.

const PAGE_SIZE: int = 40

var search_edit: LineEdit
var role_option: OptionButton
var region_option: OptionButton
var free_agents_check: CheckBox
var results: VBoxContainer
var result_count: int = 0

var _region_ids: Array[String] = []


func get_page_title() -> String:
	return "Players"


func build_page() -> void:
	if add_no_career_notice():
		return
	var filters := UIFactory.card(self, "Find players")
	var bar := UIFactory.hbox(12)
	filters.add_child(bar)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Name or nickname"
	search_edit.custom_minimum_size.x = 240
	search_edit.text_changed.connect(func(_t: String) -> void: refresh())
	bar.add_child(search_edit)
	role_option = OptionButton.new()
	role_option.add_item("Any role")
	for role: StringName in CareerCatalog.ROLES:
		role_option.add_item(CareerCatalog.role_name(role))
	role_option.item_selected.connect(func(_i: int) -> void: refresh())
	bar.add_child(role_option)
	region_option = OptionButton.new()
	region_option.add_item("Any region")
	for region_id: String in CareerCatalog.REGIONS:
		_region_ids.append(region_id)
		region_option.add_item(CareerCatalog.REGIONS[region_id])
	region_option.item_selected.connect(func(_i: int) -> void: refresh())
	bar.add_child(region_option)
	free_agents_check = CheckBox.new()
	free_agents_check.text = "Free agents only"
	free_agents_check.toggled.connect(func(_on: bool) -> void: refresh())
	bar.add_child(free_agents_check)

	var list_card := UIFactory.card(self, "Professionals (by perceived rating)")
	results = UIFactory.vbox(2)
	list_card.add_child(results)
	refresh()


func filter() -> Dictionary:
	var f := {"limit": PAGE_SIZE}
	if not search_edit.text.strip_edges().is_empty():
		f["text"] = search_edit.text
	if role_option.selected > 0:
		f["role"] = String(CareerCatalog.ROLES[role_option.selected - 1])
	if region_option.selected > 0:
		f["region"] = _region_ids[region_option.selected - 1]
	if free_agents_check.button_pressed:
		f["free_agents"] = true
	return f


func refresh() -> void:
	for child: Node in results.get_children():
		child.queue_free()
	var found := career().repo.search_players(filter())
	result_count = found.size()
	if found.is_empty():
		results.add_child(UIFactory.label("No players match.", &"MutedLabel"))
		return
	var rows: Array[Array] = []
	for entry: Dictionary in found:
		var team: Variant = "Free agent" if entry["organisation_name"] == null else cell_team(str(entry["organisation_id"]),
			str(entry["organisation_name"]))
		rows.append([str(int(entry["rating"])), cell_player(str(entry["id"]), str(entry["nickname"])
			+ ("  (you)" if int(entry["is_human"]) == 1 else "")),
			CareerCatalog.role_name(StringName(str(entry["preferred_role"]))), team])
	link_table(results, PackedStringArray(["Rating", "Player", "Role", "Team"]), rows)
