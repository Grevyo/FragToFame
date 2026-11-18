extends TestSuite

const TEST_ROOT: String = "user://tests/development"
const PROFILE: Dictionary = {"first_name": "Avery", "last_name": "Shaw", "nickname": "Arc",
	"nation_id": "gb", "preferred_role": &"rifler", "difficulty": &"prospect", "age": 19}


func suite_name() -> String:
	return "Career development and scouting (Milestone 12)"


func run() -> void:
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	var local := CareerSaves.new(TEST_ROOT)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", local)
	await _check_career(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _check_career(app: Node) -> void:
	var problem: String = app.call("new_career", "Development tests", PROFILE)
	check(problem.is_empty(), "creates a disposable training and scouting career")
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	var player_id := session.human_player_id
	_check_assess()
	_check_scout_report()
	check(CareerDevelopment.current_elo(repo, player_id) == 1200,
		"starting amateur ELO reflects the career difficulty")
	var human_before := repo.perceived(player_id)
	var reputation := repo.reputation(player_id)
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"training")
	var ground := hub.get("current_page") as CareerTrainingPage
	check(ground != null and ground.drill_buttons.size() == TrainingDrills.ids().size() and ground.scrim_choice.item_count > 0,
		"the Training Ground offers every drill and a scrim")
	check(_button(hub, "Train today") == null, "there is no abstract 'train a stat today' action any more")
	var flick := TrainingResult.make(TrainingDrills.FLICK, {"kills": 50, "duration": 60.0, "accuracy": 0.7, "headshot_rate": 0.5}, true)
	var message := CareerTraining.record(repo, player_id, flick)
	var trained := repo.perceived(player_id)
	var moved := trained[&"aim"] - human_before[&"aim"]
	var gap := flick.score - human_before[&"aim"]
	check(message.begins_with("Saved") and signi(moved) == signi(gap) and absi(moved) <= absi(gap) and (moved != 0 or absi(gap) < 3),
		"a played drill is evidence: perceived aim moves toward the drill score (%d → %d, score %d)" % [human_before[&"aim"], trained[&"aim"], flick.score])
	CareerTraining.record(repo, player_id, flick)
	var sessions := repo.training_sessions(player_id)
	check(sessions.size() == 2 and signi(int(sessions[0]["evidence"])) * signi(gap) >= 0,
		"every session is recorded and counts; how much a repeat says is weighed by assess")
	trained = repo.perceived(player_id)
	check(CareerTraining.record(repo, player_id, TrainingResult.make(TrainingDrills.FLICK, {}, false)).begins_with("Session not completed")
		and repo.training_sessions(player_id).size() == 2, "an abandoned drill is not recorded")
	check(repo.abilities(player_id).is_empty() and repo.reputation(player_id) == reputation
		and int(repo.performance_totals(player_id)["matches"]) == 0,
		"training keeps true abilities, reputation and match records separate")

	section("Scout a persistent professional")
	var candidate := repo.search_players({"ai_only": true, "limit": 1})[0]
	var subject_id := str(candidate["id"])
	var abilities := repo.abilities(subject_id)
	var opinions := repo.perceived(subject_id)
	var actual := abilities[&"aim"]
	opinions[&"aim"] = actual - 12 if actual > 20 else actual + 12
	var prior := opinions[&"aim"]
	repo.set_perceived(subject_id, opinions, 30, repo.current_day())
	hub.call("navigate", &"player", {"player_id": subject_id})
	var page := hub.get("current_page") as CareerPlayerPage
	var scout := _button(page.scouting_card, "Scout player")
	check(scout != null, "an AI player's profile offers scouting")
	if scout == null:
		return
	var gap_before := _distance(opinions, abilities)
	scout.pressed.emit()
	var revised := repo.perceived(subject_id)
	var first_confidence := repo.perceived_confidence(subject_id)
	check(_distance(revised, abilities) < gap_before and absi(revised[&"aim"] - actual) < absi(prior - actual)
		and first_confidence > 30,
		"the report improves confidence and moves the estimates toward observed ability (%d → %d off; confidence 30 → %d)" % [
			gap_before, _distance(revised, abilities), first_confidence])
	check(repo.abilities(subject_id) == abilities and not revised.has(CareerCatalog.POTENTIAL),
		"scouting preserves true ability and keeps potential private")
	check(repo.last_scout_report(player_id, subject_id).get("change") == first_confidence - 30
		and not CareerDevelopment.scout(repo, player_id, subject_id).is_empty(),
		"scouting persists the report and enforces one report per day")
	check(not CareerDevelopment.scout(repo, player_id, player_id).is_empty(), "scouting refuses human profiles")

	repo.set_current_day(1)
	var id := session.save_id
	problem = app.call("load_career", id)
	session = app.get("career") as CareerSession
	check(problem.is_empty() and session != null, "the development save reopens normally")
	if session == null:
		return
	check(session.repo.perceived(player_id)[&"aim"] == trained[&"aim"]
		and session.repo.perceived_confidence(subject_id) == first_confidence
		and not session.repo.last_scout_report(player_id, subject_id).is_empty(),
		"training and scouting changes survive reopening the save")
	CareerTraining.record(session.repo, player_id, TrainingResult.make(TrainingDrills.REACTION,
		{"reps_hit": 12, "average_ms": 210.0}, true))
	check(int(session.repo.training_sessions(player_id)[0]["evidence"]) != 0
		and CareerDevelopment.scout(session.repo, player_id, subject_id).is_empty()
		and session.repo.perceived_confidence(subject_id) > first_confidence
		and session.repo.perceived_confidence(subject_id) - first_confidence <= first_confidence - 30,
		"the next career day permits another training session and report")
	await _check_bootcamp(app, session, player_id)


## The bootcamp is a programme of sessions you play: booking alone changes nothing.
func _check_bootcamp(app: Node, session: CareerSession, player_id: String) -> void:
	section("Bootcamp: a week of real sessions")
	var repo := session.repo
	repo.add_player_money(player_id, CareerSpending.BOOTCAMP_COST * 2, repo.current_day(), "income", "Test: bootcamp funds")
	var seen := repo.perceived(player_id)
	check(CareerSpending.buy_bootcamp(repo, player_id).is_empty() and repo.perceived(player_id) == seen,
		"booking a bootcamp changes nothing on its own")
	var camp := CareerSpending.bootcamp_state(repo, player_id)
	check(bool(camp["active"]) and (camp["done"] as Array).is_empty()
		and int(camp["end_day"]) == repo.current_day() + CareerSpending.BOOTCAMP_DAYS - 1, "it opens a week-long programme")
	var reaction := TrainingResult.make(TrainingDrills.REACTION, {"reps_hit": 15, "average_ms": 180.0}, true)
	var message := CareerTraining.record(repo, player_id, reaction)
	var first := repo.training_sessions(player_id, 1)[0]
	check(message.contains("bootcamp session 1 of %d" % CareerSpending.BOOTCAMP_PROGRAMME.size()) and int(first["bootcamp"]) == 1,
		"a programme session counts for the bootcamp and is reviewed by its staff (%s)" % message)
	check(not CareerTraining.record(repo, player_id, reaction).contains("bootcamp")
		and int(repo.training_sessions(player_id, 1)[0]["bootcamp"]) == 0, "repeating a done item does not count twice")
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"training")
	var ground := hub.get("current_page") as CareerTrainingPage
	check(ground != null and ground.bootcamp_label != null and ground.bootcamp_label.text.begins_with("1 of 5"),
		"the Training Ground shows the bootcamp's progress")
	CareerTraining.record(repo, player_id, TrainingResult.make(TrainingDrills.FLICK, {"kills": 40, "duration": 60.0, "accuracy": 0.6}, true))
	repo.set_current_day(repo.current_day() + 3)
	CareerTraining.record(repo, player_id, TrainingResult.make(TrainingDrills.TRACKING, {"damage": 900, "duration": 30.0, "accuracy": 0.6}, true))
	CareerTraining.record(repo, player_id, TrainingResult.make(TrainingDrills.MOVEMENT, {"finished": true, "time": 26.0, "par": 30.0}, true))
	message = CareerTraining.record(repo, player_id, TrainingResult.make(TrainingDrills.SCRIM,
		{"won": true, "score_for": 9, "score_against": 5, "opponent": "Test", "kills": 14, "deaths": 9}, true))
	camp = CareerSpending.bootcamp_state(repo, player_id)
	check(bool(camp["complete"]) and not bool(camp["active"]) and message.contains("bootcamp complete"),
		"playing every drill and a scrim within the week completes it (%s)" % message)
	check(message.contains("week") and repo.news(5).any(func(n: Dictionary) -> bool: return str(n["headline"]).contains("complete a bootcamp")),
		"finishing it is judged on how the week went and makes news")
	check(CareerSpending.buy_bootcamp(repo, player_id).contains("days"), "the next bootcamp waits for its cooldown")
	repo.set_current_day(repo.current_day() + CareerSpending.BOOTCAMP_COOLDOWN)
	check(CareerSpending.buy_bootcamp(repo, player_id).is_empty(), "a later bootcamp can be booked")
	repo.set_current_day(repo.current_day() + CareerSpending.BOOTCAMP_DAYS)
	camp = CareerSpending.bootcamp_state(repo, player_id)
	check(not bool(camp["active"]) and not bool(camp["complete"]) and (camp["done"] as Array).is_empty()
		and not CareerTraining.record(repo, player_id, reaction).contains("bootcamp"),
		"an unplayed bootcamp lapses after its week")


## Total distance between two ability maps (over the first's abilities, potential excluded).
func _distance(seen: Dictionary, truth: Dictionary) -> int:
	var total := 0
	for ability: StringName in CareerCatalog.ABILITIES:
		if seen.has(ability) and truth.has(ability):
			total += absi(int(seen[ability]) - int(truth[ability]))
	return total


## Scouting learns as much as there is to watch.
func _check_scout_report() -> void:
	section("How much a scouting report learns")
	var truth: Dictionary = {}
	var seen: Dictionary = {}
	for ability: StringName in CareerCatalog.ABILITIES:
		truth[ability] = 70
		seen[ability] = 50
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var watched := CareerDevelopment.scout_report(seen, truth, 30, 14, 1, rng)
	var unseen := CareerDevelopment.scout_report(seen, truth, 30, 0, 0, rng)
	check(_distance(watched["revised"], truth) < _distance(unseen["revised"], truth) and int(watched["gain"]) > int(unseen["gain"]),
		"a regular on a big stage is read better than a player nobody has watched (%d vs %d off)" % [
			_distance(watched["revised"], truth), _distance(unseen["revised"], truth)])
	check(int(CareerDevelopment.scout_report(seen, truth, 80, 14, 1, rng)["gain"]) < int(watched["gain"]),
		"a report adds less confidence when the world is already sure")


## Evidence comes from how a session went, not from fixed steps.
func _check_assess() -> void:
	section("How much a session says")
	var record: Array[int] = [60, 62, 58, 61]
	var first := CareerTraining.assess(80, 60, 40, record, 0, false)
	var third := CareerTraining.assess(80, 60, 40, record, 2, false)
	check(int(first["change"]) > int(third["change"]) and int(third["change"]) >= 0, "a third run today says less than the first (%d vs %d)" % [
		int(first["change"]), int(third["change"])])
	var steady := CareerTraining.assess(66, 60, 40, record, 0, false)
	var fluke := CareerTraining.assess(95, 60, 40, record, 0, false)
	check(float(steady["trust"]) > float(fluke["trust"]), "a run that fits your record is trusted more than a fluke")
	check(int(CareerTraining.assess(80, 60, 40, record, 0, true)["change"]) > int(first["change"]),
		"a reviewed run (coach or bootcamp) is believed more")
	check(int(CareerTraining.assess(80, 60, 85, record, 0, false)["change"]) < int(first["change"]),
		"a world that is already sure of you moves less")
	check(int(CareerTraining.assess(61, 60, 40, record, 0, false)["confidence"]) > 0
		and int(CareerTraining.assess(20, 60, 40, [20, 22] as Array[int], 0, false)["confidence"]) < 0,
		"a run that confirms the world's view raises its confidence; one that contradicts it lowers it")
	check(int(CareerTraining.assess(40, 60, 40, record, 0, false)["change"]) < 0, "a poor run lowers the world's view")
	check(int(CareerTraining.assess(70, 60, 40, record, 0, false)["change"]) != int(CareerTraining.assess(90, 60, 40, [88, 90] as Array[int], 0, false)["change"]),
		"how far the view moves depends on the run, not a fixed step")


func _button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			return button
	return null


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
