class_name CareerTrainingPage
extends CareerPage
## The training ground: drills you play yourself in the FPS (flick, reaction, tracking, the
## movement course) and 5v5 scrims. Shows your bests and recent sessions.

## The drill buttons by drill id (tests press them).
var drill_buttons: Dictionary[StringName, Button] = {}
var scrim_choice: OptionButton
var status_label: Label
## The bootcamp card's text (tests read it); null when no bootcamp was ever booked.
var bootcamp_label: Label

var _scrim_ids: Array[String] = []


func get_page_title() -> String:
	return "Training Ground"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var intro := UIFactory.card(self, "Real training")
	intro.add_child(UIFactory.label("Every session is played by you in the FPS. Your scores are recorded, and every session is evidence the world uses to judge you. How much a run says depends on how it went: whether it fits your record or looks like a fluke, how sure the world already is, how often you ran it today and whether a coach reviewed it. Scrims with your team change how your teammates feel about you. Training never changes how you aim or move: you get better by practising.",
		&"MutedLabel", true))
	status_label = UIFactory.label("", &"WarningLabel", true)
	intro.add_child(status_label)
	_bootcamp_card(repo, session.human_player_id)
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
		var runs := repo.training_count(session.human_player_id, String(drill), today)
		if runs > 0:
			card.add_child(UIFactory.label("Run %d time%s today: another run says less about you than the first." % [runs, "" if runs == 1 else "s"],
				&"MutedLabel", true))
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


## The booked bootcamp: what is done, what is left and the days remaining.
func _bootcamp_card(repo: CareerRepository, human_id: String) -> void:
	var camp := CareerSpending.bootcamp_state(repo, human_id)
	if not bool(camp["booked"]):
		return
	var done := camp["done"] as Array
	var total := CareerSpending.BOOTCAMP_PROGRAMME.size()
	if not bool(camp["active"]) and repo.current_day() > int(camp["end_day"]) + 30:
		return
	var card := UIFactory.card(self, "Bootcamp")
	var text := ""
	if bool(camp["complete"]):
		text = "Bootcamp complete: all %d sessions played." % total
	elif bool(camp["active"]):
		var left := int(camp["end_day"]) - repo.current_day() + 1
		text = "%d of %d sessions done · %d day%s left (until %s). Programme sessions are reviewed by the camp's staff, so they say more about you; the week is judged as a whole when you finish." % [
			done.size(), total, left, "" if left == 1 else "s", GameDate.format(int(camp["end_day"]))]
	else:
		text = "Your bootcamp ended with %d of %d sessions played." % [done.size(), total]
	bootcamp_label = UIFactory.label(text, &"" if bool(camp["active"]) else &"MutedLabel", true)
	card.add_child(bootcamp_label)
	var items: PackedStringArray = []
	for drill: StringName in CareerSpending.BOOTCAMP_PROGRAMME:
		items.append("%s %s" % ["✓" if done.has(String(drill)) else "○", TrainingDrills.drill_name(drill)])
	card.add_child(UIFactory.label("  ·  ".join(items), &"MutedLabel", true))
	if not bool(camp["active"]):
		return
	var row := UIFactory.hbox(8)
	for drill: StringName in CareerSpending.BOOTCAMP_PROGRAMME:
		if done.has(String(drill)) or drill == TrainingDrills.SCRIM:
			continue
		var start := UIFactory.button("Start %s" % TrainingDrills.drill_name(drill).to_lower(), &"AccentButton")
		var drill_id := drill
		start.pressed.connect(func() -> void: start_drill(drill_id))
		row.add_child(start)
	card.add_child(row)
	if not done.has(String(TrainingDrills.SCRIM)):
		card.add_child(UIFactory.label("Play the scrim from the scrim card below.", &"MutedLabel", true))


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
			("%+d %s" % [evidence, CareerCatalog.ability_name(TrainingDrills.ability(drill)).to_lower()] if evidence != 0 else "")
				+ (" · bootcamp" if int(entry.get("bootcamp", 0)) == 1 else "")]))
	if rows.is_empty():
		card.add_child(UIFactory.label("No sessions yet. Start a drill above.", &"MutedLabel"))
		return
	UIFactory.table(card, PackedStringArray(["Date", "Session", "Score", "Measured", "World's view"]), rows)
