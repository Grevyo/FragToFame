class_name CareerHomePage
extends CareerPage


func get_page_title() -> String:
	return "Home"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var me := session.human()
	var today := repo.current_day()

	var welcome := UIFactory.card(self, "Welcome, %s" % (me.nickname if me != null else "professional"))
	welcome.add_child(UIFactory.label(
		"Your career world is live: every organisation, player, contract and opinion below comes from "
		+ "this save's database. Fixtures, the advancing calendar and match statistics arrive in the next "
		+ "milestones.", &"MutedLabel", true))

	var row := add_row()
	var status_card := UIFactory.card(row, "Career status")
	var contract := repo.active_contract(me.id) if me != null else null
	var team := "Free agent"
	if contract != null:
		team = "%s (%s)" % [repo.get_organisation(contract.organisation_id).name, CareerCatalog.role_name(contract.role)]
	var reputation := repo.reputation(me.id) if me != null else 0
	var profile := repo.human_profile(me.id) if me != null else {}
	var status_rows: Array[PackedStringArray] = [
		PackedStringArray(["Date", GameDate.format(today)]),
		PackedStringArray(["Team", team]),
		PackedStringArray(["Preferred role", CareerCatalog.role_name(me.preferred_role) if me != null else "—"]),
		PackedStringArray(["Reputation", "%s (%d)" % [CareerCatalog.reputation_label(reputation), reputation]]),
		PackedStringArray(["Difficulty", CareerCatalog.DIFFICULTY_NAMES.get(StringName(str(profile.get("difficulty", ""))), "—")]),
	]
	UIFactory.key_value_grid(status_card, status_rows)

	var world_card := UIFactory.card(row, "The world")
	var world_rows: Array[PackedStringArray] = [
		PackedStringArray(["Organisations", str(repo.organisation_count())]),
		PackedStringArray(["Active professionals", str(repo.player_count(false))]),
		PackedStringArray(["Free agents", str(repo.search_players({"free_agents": true, "limit": 100000}).size())]),
		PackedStringArray(["Next fixture", "None yet — career fixtures arrive in Milestone 10"]),
	]
	UIFactory.key_value_grid(world_card, world_rows)

	var top := UIFactory.card(self, "Top organisations")
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.organisations().slice(0, 6):
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		rows.append(PackedStringArray([org.name, CareerCatalog.region_name(org.region_id),
			CareerCatalog.tier_name(org.tier), str(entry["reputation"])]))
	UIFactory.table(top, PackedStringArray(["Organisation", "Region", "Tier", "Reputation"]), rows)
