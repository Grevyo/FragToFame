class_name PlayerView
extends RefCounted
## Shared player detail cards (profile page and the player browser). Shows the public layers
## only: identity, contract, reputation, perceived attributes and traits. True simulated
## abilities stay hidden — scouting (Milestone 12) is how the world learns them.


## [param stacked] puts the cards under each other (narrow columns such as the player browser).
static func build(parent: Control, repo: CareerRepository, player_id: String, stacked: bool = false) -> void:
	var player := repo.get_player(player_id)
	if player == null:
		return
	var today := repo.current_day()
	var row: BoxContainer = UIFactory.vbox(18) if stacked else UIFactory.hbox(18)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var identity := UIFactory.card(row, player.display_name())
	var contract := repo.active_contract(player.id)
	var team := "Free agent"
	var contract_text := "—"
	if contract != null:
		var org := repo.get_organisation(contract.organisation_id)
		team = org.name if org != null else contract.organisation_id
		contract_text = "%s%s · until %s · %s/month" % [CareerCatalog.role_name(contract.role),
			" (substitute)" if contract.is_substitute else "", GameDate.format(contract.end_day),
			CareerCatalog.format_money(contract.monthly_salary)]
	var identity_rows: Array[PackedStringArray] = [
		PackedStringArray(["Player ID", player.id]),
		PackedStringArray(["Age", str(player.age(today))]),
		PackedStringArray(["Nationality", CareerCatalog.nation_name(player.nation_id)]),
		PackedStringArray(["Preferred role", CareerCatalog.role_name(player.preferred_role)]),
		PackedStringArray(["Team", team]),
		PackedStringArray(["Contract", contract_text]),
		PackedStringArray(["Type", "Human professional" if player.is_human else "AI professional"]),
	]
	UIFactory.key_value_grid(identity, identity_rows)

	var standing := UIFactory.card(row, "Standing")
	var reputation := repo.reputation(player.id)
	var counts := repo.performance_totals(player.id)
	var recorded_matches := int(counts.get("matches", 0))
	var standing_rows: Array[PackedStringArray] = [
		PackedStringArray(["Reputation", "%s (%d)" % [CareerCatalog.reputation_label(reputation), reputation]]),
		PackedStringArray(["Perceived rating", str(repo.perceived_rating(player.id))]),
		PackedStringArray(["Scouting confidence", "%d%%" % repo.perceived_confidence(player.id)]),
		PackedStringArray(["Recorded matches", str(recorded_matches)]),
	]
	if recorded_matches > 0:
		standing_rows.append(PackedStringArray(["F2F performance rating", "%.2f" % MatchStatistics.rating(counts)]))
	UIFactory.key_value_grid(standing, standing_rows)
	var honour_list := repo.honours(player.id)
	if not honour_list.is_empty():
		standing.add_child(HSeparator.new())
		standing.add_child(UIFactory.label("HONOURS", &"SectionLabel"))
		for honour: Dictionary in honour_list:
			standing.add_child(UIFactory.label("%s · %s %s · %s" % [WorldSeasons.ordinal(int(honour["position"])),
				honour["competition_name"], GameDate.format_year(GameDate.make(int(honour["season_year"]), 1, 1)),
				honour["org_name"]], &"", true))
	var trait_list := repo.traits(player.id)
	if not trait_list.is_empty():
		standing.add_child(HSeparator.new())
		standing.add_child(UIFactory.label("TRAITS", &"SectionLabel"))
		for trait_id: StringName in trait_list:
			var line := UIFactory.label("%s %s — %s" % [TraitLibrary.trait_name(trait_id),
				"●".repeat(trait_list[trait_id]), TraitLibrary.describe(trait_id)], &"", true)
			standing.add_child(line)

	_add_sim_form(parent, repo, player.id)
	var attributes := UIFactory.card(parent, "Perceived attributes")
	attributes.add_child(UIFactory.label(
		"What scouts and the esports world believe about this player — not their true ability. "
		+ ("For human players these never change aim, recoil, movement or reaction time."
			if player.is_human else "Low scouting confidence means these may be well off."),
		&"MutedLabel", true))
	var seen := repo.perceived(player.id)
	for ability: StringName in CareerCatalog.ABILITIES:
		if seen.has(ability):
			UIFactory.rating_bar(attributes, CareerCatalog.ability_name(ability), seen[ability])


## Form in simulated series (the world's matches nobody played), kept apart from recorded
## statistics: the last 90 days and morale.
static func _add_sim_form(parent: Control, repo: CareerRepository, player_id: String) -> void:
	var form := repo.sim_form(player_id, repo.current_day() - 90)
	if int(form.get("maps", 0)) == 0:
		return
	var card := UIFactory.card(parent, "Simulated form · last 90 days")
	card.add_child(UIFactory.label("From series the match engine simulated round by round. These lines are separate from the statistics of matches you play.",
		&"MutedLabel", true))
	var maps := int(form["maps"])
	var morale := repo.morale(player_id)
	UIFactory.key_value_grid(card, [
		PackedStringArray(["Maps", "%d (%d won)" % [maps, int(form["won"])]]),
		PackedStringArray(["Average rating", "%.2f (best %.2f)" % [float(form["rating"]), float(form["best"])]]),
		PackedStringArray(["Kills – deaths", "%d – %d (%.2f per round)" % [int(form["kills"]), int(form["deaths"]),
			float(form["kills"]) / maxf(float(form["rounds"]), 1.0)]]),
		PackedStringArray(["Assists", str(int(form["assists"]))]),
		PackedStringArray(["Opening kills", str(int(form["opening_kills"]))]),
		PackedStringArray(["Clutches won", str(int(form["clutch_wins"]))]),
		PackedStringArray(["Morale", "%+d · %s" % [morale, "flying" if morale >= 10 else ("confident" if morale >= 4
			else ("low" if morale <= -10 else ("shaky" if morale <= -4 else "settled")))]]),
	] as Array[PackedStringArray])
