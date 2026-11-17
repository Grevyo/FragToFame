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
	check(CareerDevelopment.current_elo(repo, player_id) == 1200,
		"starting amateur ELO reflects the career difficulty")
	var human_before := repo.perceived(player_id)
	var reputation := repo.reputation(player_id)
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("show_page", &"profile")
	var train := _button(hub, "Train today")
	check(train != null, "Player Profile offers a daily training action")
	if train == null:
		return
	train.pressed.emit()
	var trained := repo.perceived(player_id)
	var training := repo.development_today(player_id, CareerDevelopment.TRAINING)
	check(trained[&"aim"] == human_before[&"aim"] + 1 and training.get("focus") == "aim",
		"training changes the selected perceived ability and records the day")
	check(not CareerDevelopment.train(repo, player_id, &"aim").is_empty()
		and _button(hub, "Train today") == null, "training can run once per career day")
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
	scout.pressed.emit()
	var revised := repo.perceived(subject_id)
	check(absi(revised[&"aim"] - actual) == absi(prior - actual) - 4
		and repo.perceived_confidence(subject_id) == 42,
		"the report improves confidence and moves the estimate toward observed ability")
	check(repo.abilities(subject_id) == abilities and not revised.has(CareerCatalog.POTENTIAL),
		"scouting preserves true ability and keeps potential private")
	check(repo.last_scout_report(player_id, subject_id).get("change") == 12
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
		and session.repo.perceived_confidence(subject_id) == 42
		and not session.repo.last_scout_report(player_id, subject_id).is_empty(),
		"training and scouting changes survive reopening the save")
	check(CareerDevelopment.train(session.repo, player_id, &"aim").is_empty()
		and CareerDevelopment.scout(session.repo, player_id, subject_id).is_empty()
		and session.repo.perceived_confidence(subject_id) == 54,
		"the next career day permits another training session and report")


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
