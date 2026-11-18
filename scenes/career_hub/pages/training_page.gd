class_name CareerTrainingPage
extends CareerPage
## The training ground: drills you play yourself in the FPS (flick, reaction, tracking, the
## movement course) and 5v5 scrims. Shows your bests and recent sessions.

## The drill buttons by drill id (tests press them).
var drill_buttons: Dictionary[StringName, Button] = {}
var scrim_choice: OptionButton
var status_label: Label

var _scrim_ids: Array[String] = []


func get_page_title() -> String:
	return "Training Ground"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var intro := UIFactory.card(self, "Real training")
	intro.add_child(UIFactory.label("Every session is played by you in the FPS. Your scores are recorded; the first session of each drill a day is evidence the world uses to judge you. Training never changes how you aim or move: you get better by practising.",
		&"MutedLabel", true))
	status_label = UIFactory.label("", &"WarningLabel", true)
	intro.add_child(status_label)
	var bests := repo.training_bests(session.human_player_id)
	var today := repo.current_day()
	var row := add_row()
	var column := 0
	for drill: StringName in TrainingDrills.ids():
		if column == 2:
			row = add_row()
			column = 0
		column += 1
		var entry := TrainingDrills.DRILLS[drill]
		var card := UIFactory.card(row, str(entry["name"]))
		card.add_child(UIFactory.label(str(entry["summary"]), &"MutedLabel", true))
		var best: Dictionary = bests.get(String(drill), {})
		card.add_child(UIFactory.label("Best %d / 100 · %d sessions · speaks to %s" % [int(best.get("best", 0)), int(best.get("sessions", 0)),
			CareerCatalog.ability_name(entry["ability"] as StringName).to_lower()] if not best.is_empty()
			else "Not tried yet · speaks to %s" % CareerCatalog.ability_name(entry["ability"] as StringName).to_lower(), &"", true))
		if repo.training_evidence_today(session.human_player_id, String(drill), today):
			card.add_child(UIFactory.label("Today's evidence is in; more sessions still count for your record.", &"MutedLabel", true))
		var start := UIFactory.button("Start %s" % str(entry["name"]).to_lower(), &"AccentButton")
		var drill_id := drill
		start.pressed.connect(func() -> void: start_drill(drill_id))
		card.add_child(start)
		drill_buttons[drill] = start
	_scrim_card(repo, session.human_player_id)
	_history(repo, session.human_player_id)


## Opens a drill in the FPS runtime. Returns "" or why not.
func start_drill(drill: StringName) -> String:
	var error := App.start_training(drill, true)
	if error != OK:
		status_label.text = "Could not open the training ground: %s." % error_string(error)
		return status_label.text
	return ""


func _scrim_card(repo: CareerRepository, human_id: String) -> void:
	var card := UIFactory.card(self, "Scrim · 5v5 practice match")
	var contract := repo.active_contract(human_id)
	var tier := 4
	if contract != null:
		var own := repo.get_organisation(contract.organisation_id)
		tier = own.tier if own != null else 4
	card.add_child(UIFactory.label(("Your team's players line up beside you as bots." if contract != null
		else "Practice partners line up beside you as bots.") + " MR8 on the default map. The result is kept with your training, not your fixtures.",
		&"MutedLabel", true))
	scrim_choice = OptionButton.new()
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if absi(org.tier - tier) > 1 or (contract != null and org.id == contract.organisation_id):
			continue
		scrim_choice.add_item("%s · %s" % [org.name, CareerCatalog.tier_name(org.tier)])
		_scrim_ids.append(org.id)
	var row := UIFactory.hbox(8)
	row.add_child(scrim_choice)
	var start := UIFactory.button("Start scrim", &"AccentButton")
	start.disabled = _scrim_ids.is_empty()
	start.pressed.connect(func() -> void:
		var error := App.start_scrim(_scrim_ids[maxi(scrim_choice.selected, 0)])
		if error != OK:
			status_label.text = "Could not start the scrim: %s." % error_string(error))
	row.add_child(start)
	card.add_child(row)


func _history(repo: CareerRepository, human_id: String) -> void:
	var card := UIFactory.card(self, "Recent sessions")
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in repo.training_sessions(human_id, 25):
		var drill := StringName(str(entry["drill_id"]))
		var evidence := int(entry["evidence"])
		rows.append(PackedStringArray([GameDate.format(int(entry["day"])), TrainingDrills.drill_name(drill),
			"—" if drill == TrainingDrills.SCRIM else str(int(entry["score"])), TrainingDrills.describe(drill, entry["metrics"] as Dictionary),
			"%+d %s" % [evidence, CareerCatalog.ability_name(TrainingDrills.ability(drill)).to_lower()] if evidence != 0 else ""]))
	if rows.is_empty():
		card.add_child(UIFactory.label("No sessions yet. Start a drill above.", &"MutedLabel"))
		return
	UIFactory.table(card, PackedStringArray(["Date", "Session", "Score", "Measured", "World's view"]), rows)
