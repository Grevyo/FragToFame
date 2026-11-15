class_name CareerPlayersPage
extends CareerPage
## Database browser for every professional: search, filter by role/region/free agency, ranked by
## perceived rating; select a player to see their public profile.

const PAGE_SIZE: int = 40

var search_edit: LineEdit
var role_option: OptionButton
var region_option: OptionButton
var free_agents_check: CheckBox
var results: VBoxContainer
var detail: VBoxContainer
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

	var row := add_row()
	var list_card := UIFactory.card(row, "Professionals (by perceived rating)")
	list_card.custom_minimum_size.x = 460
	list_card.get_parent().size_flags_horizontal = Control.SIZE_FILL
	results = UIFactory.vbox(2)
	list_card.add_child(results)
	detail = UIFactory.vbox(18)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
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
	for entry: Dictionary in found:
		var team := str(entry["organisation_name"]) if entry["organisation_name"] != null else "Free agent"
		var b := UIFactory.button("%d   %s  ·  %s  ·  %s%s" % [int(entry["rating"]), str(entry["nickname"]),
			CareerCatalog.role_name(StringName(str(entry["preferred_role"]))), team,
			"  ·  YOU" if int(entry["is_human"]) == 1 else ""], &"SidebarButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_player.bind(str(entry["id"])))
		results.add_child(b)


func show_player(player_id: String) -> void:
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	var session := career()
	var player := session.repo.get_player(player_id)
	if player == null:
		return
	if not player.is_human and player.status == "active":
		_build_scouting(session, player_id)
	PlayerView.build(detail, session.repo, player_id, true)


func _build_scouting(session: CareerSession, subject_id: String) -> void:
	var card := UIFactory.card(detail, "Scouting report")
	var report := session.repo.last_scout_report(session.human_player_id, subject_id)
	if not report.is_empty():
		card.add_child(UIFactory.label("Last report · %s · confidence +%d" % [
			GameDate.format(int(report["day"])), int(report["change"])], &"MutedLabel", true))
	if not session.repo.development_today(session.human_player_id, CareerDevelopment.SCOUTING).is_empty():
		card.add_child(UIFactory.label("Today's scouting report is complete.", &"MutedLabel", true))
		return
	var scout := UIFactory.button("Scout player", &"AccentButton")
	var status := UIFactory.label("", &"WarningLabel", true)
	card.add_child(scout)
	card.add_child(status)
	scout.pressed.connect(func() -> void:
		var problem := CareerDevelopment.scout(session.repo, session.human_player_id, subject_id)
		if not problem.is_empty():
			status.text = problem
			return
		refresh()
		show_player(subject_id))
