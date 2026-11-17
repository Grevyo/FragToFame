class_name CareerTeamsPage
extends CareerPage
## Organisations of the career world and their rosters. A practice match can be started against
## any organisation; its bots play from the players' simulated abilities.

var selected_org_id: String = ""
var org_list: VBoxContainer
var detail: VBoxContainer
var practice_button: Button


func get_page_title() -> String:
	return "Teams"


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	var row := add_row()
	var list_card := UIFactory.card(row, "Organisations")
	list_card.custom_minimum_size.x = 380
	list_card.get_parent().size_flags_horizontal = Control.SIZE_FILL
	org_list = UIFactory.vbox(2)
	list_card.add_child(org_list)
	var current_tier := 0
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if org.tier != current_tier:
			current_tier = org.tier
			org_list.add_child(UIFactory.label(CareerCatalog.tier_name(org.tier).to_upper(), &"SectionLabel"))
		var b := UIFactory.button("%s  ·  %s" % [org.name, CareerCatalog.region_name(org.region_id)], &"SidebarButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_organisation.bind(org.id))
		org_list.add_child(b)
	detail = UIFactory.vbox(18)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var first := repo.organisations()
	if not first.is_empty():
		show_organisation((first[0]["organisation"] as CareerRecords.OrganisationRecord).id)


func show_organisation(org_id: String) -> void:
	for child: Node in detail.get_children():
		child.queue_free()
	var repo := career().repo
	var org := repo.get_organisation(org_id)
	if org == null:
		return
	selected_org_id = org_id
	var info := UIFactory.card(detail, org.name)
	var info_rows: Array[PackedStringArray] = [
		PackedStringArray(["Short name", org.short_name]),
		PackedStringArray(["Region", CareerCatalog.region_name(org.region_id)]),
		PackedStringArray(["Tier", CareerCatalog.tier_name(org.tier)]),
		PackedStringArray(["Reputation", str(repo.organisation_reputation(org.id))]),
		PackedStringArray(["Form", CareerNewsPage.form_label(repo.organisation_form(org.id))]),
		PackedStringArray(["Balance", CareerCatalog.format_money(repo.organisation_balance(org.id))
			if repo.has_finances(org.id) else "Opens on the next day"]),
		PackedStringArray(["Monthly income", CareerCatalog.format_money(WorldFinance.monthly_income(org.tier,
			repo.organisation_reputation(org.id)))]),
		PackedStringArray(["Monthly wages", CareerCatalog.format_money(repo.wage_bill(org.id))]),
		PackedStringArray(["Founded", GameDate.format_year(org.founded_day)]),
		PackedStringArray(["ID", org.id]),
	]
	UIFactory.key_value_grid(info, info_rows)
	practice_button = UIFactory.button("Practice match vs %s (MR3, bots)" % org.short_name, &"AccentButton")
	practice_button.pressed.connect(func() -> void: App.start_practice_against(org_id))
	info.add_child(practice_button)
	info.add_child(UIFactory.label("Career fixtures are played from Home.",
		&"MutedLabel", true))

	var roster_card := UIFactory.card(detail, "Roster")
	var rows: Array[PackedStringArray] = []
	var today := repo.current_day()
	for entry: Dictionary in repo.roster(org_id):
		var player := entry["player"] as CareerRecords.PlayerRecord
		var contract := entry["contract"] as CareerRecords.ContractRecord
		rows.append(PackedStringArray([player.nickname, "%s %s" % [player.first_name, player.last_name],
			CareerCatalog.role_name(contract.role) + (" (sub)" if contract.is_substitute else ""),
			str(player.age(today)), CareerCatalog.nation_name(player.nation_id), str(entry["rating"]),
			GameDate.format(contract.end_day)]))
	UIFactory.table(roster_card, PackedStringArray(["Nickname", "Name", "Role", "Age", "Nation",
		"Rating (perceived)", "Contract until"]), rows)
