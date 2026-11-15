class_name CareerFlowSuite
extends TestSuite
## Milestone 9 (scenes): create a career from the select screen, browse the hub's real data,
## continue a saved career, and play a practice match whose bots come from a real roster.

const SELECT_SCENE: String = "res://scenes/career_select/career_select.tscn"
const TEST_ROOT: String = "user://tests/career_flow"


func suite_name() -> String:
	return "Career flow (Milestone 9)"


func run() -> void:
	var app := tree.root.get_node("App")
	_clean(TEST_ROOT)
	var original_saves: Variant = app.get("career_saves")
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	app.call("close_career")

	section("Career select")
	var select := spawn_scene(SELECT_SCENE)
	if select == null:
		return
	await wait_frames(2)
	var saves_box := select.get("saves_box") as VBoxContainer
	check(saves_box.get_child_count() == 1, "an empty save list shows a hint")
	(select.get("first_name_edit") as LineEdit).text = ""
	var invalid: String = select.call("create_career")
	check(not invalid.is_empty() and not bool(app.call("has_career")), "an incomplete form is refused (%s)" % invalid)
	(select.get("career_name_edit") as LineEdit).text = "Flow test"
	(select.get("first_name_edit") as LineEdit).text = "Rowan"
	(select.get("last_name_edit") as LineEdit).text = "Hartley"
	(select.get("nickname_edit") as LineEdit).text = "Sable"
	var form_text := _text_of(select)
	check(form_text.contains("World database") and not form_text.to_lower().contains("seed"),
		"the career form offers a world database without a seed field")
	var error: String = select.call("create_career")
	check(error.is_empty() and bool(app.call("has_career")), "creating a career opens it (%s)" % error)
	await despawn(select)
	await wait_frames(3)
	var hub := tree.current_scene
	check(hub != null and hub.scene_file_path == "res://scenes/career_hub/career_hub.tscn", "the hub opens after creation")
	if not bool(app.call("has_career")) or hub == null:
		_restore(app, original_saves)
		return
	var session := app.get("career") as CareerSession

	check(session.repo.meta_value("database_id") == "f2f_default", "the default selection uses the shipped database")

	section("Hub pages show the career database")
	hub.call("show_page", &"home")
	await wait_frames(1)
	check(_text_of(hub.get("current_page") as Node).contains("Sable"), "Home greets the human professional")
	hub.call("show_page", &"profile")
	await wait_frames(1)
	var profile_text := _text_of(hub.get("current_page") as Node)
	check(profile_text.contains("Rowan \"Sable\" Hartley") and profile_text.contains("Free agent"), "Profile shows the real player")
	hub.call("show_page", &"teams")
	await wait_frames(1)
	var teams := hub.get("current_page") as CareerTeamsPage
	check(teams.org_list.get_child_count() >= 40, "Teams lists every organisation (%d rows)" % teams.org_list.get_child_count())
	var top_org := session.repo.organisations()[0]["organisation"] as CareerRecords.OrganisationRecord
	check(teams.selected_org_id == top_org.id and _text_of(teams.detail).contains(top_org.name), "the top organisation's roster is shown")
	hub.call("show_page", &"players")
	await wait_frames(1)
	var players := hub.get("current_page") as CareerPlayersPage
	check(players.result_count == CareerPlayersPage.PAGE_SIZE, "Players lists the first page of professionals")
	players.search_edit.text = "Sable"
	players.refresh()
	check(players.result_count >= 1, "search finds the human by nickname")
	players.search_edit.text = ""
	players.free_agents_check.button_pressed = true
	await wait_frames(1)
	check(players.result_count > 0, "free agent filter")

	hub.call("show_page", &"competitions")
	await wait_frames(1)
	var competitions := hub.get("current_page") as CareerCompetitionsPage
	var competition_text := _text_of(competitions)
	check(competition_text.contains("Northstar Pro Series") and competition_text.contains("League calendar")
		and competition_text.contains("Awaiting result"), "Competitions shows the published pro league and open fixtures")
	var choice := competitions.get("_choice") as OptionButton
	for idx: int in choice.item_count:
		if choice.get_item_text(idx) == "Oceania Challenger League":
			choice.select(idx)
			choice.item_selected.emit(idx)
			break
	check(_text_of(competitions).contains("0 of 8 required organisations"), "an undersubscribed league shows its eligible field")
	for idx: int in choice.item_count:
		if choice.get_item_text(idx) == "Vanguard Masters":
			choice.select(idx)
			choice.item_selected.emit(idx)
			break
	check(_text_of(competitions).contains("Cup scheduling is pending."), "an authored cup appears with its current scheduling status")

	section("Continue a saved career")
	var save_id := session.save_id
	var human_id := session.human_player_id
	app.call("close_career")
	app.call("go_to", &"career_select")
	await wait_frames(3)
	var reselect := tree.current_scene
	check((reselect.get("saves_box") as VBoxContainer).get_child_count() == 1, "the save appears in the list")
	var continued: String = reselect.call("continue_career", save_id)
	await wait_frames(3)
	check(continued.is_empty() and (app.get("career") as CareerSession).human_player_id == human_id,
		"continuing reopens the same career")

	section("Practice against a real roster")
	session = app.get("career") as CareerSession
	var lineup := session.repo.lineup(top_org.id)
	check(int(app.call("start_practice_against", top_org.id)) == OK, "practice match starts")
	await wait_frames(4)
	await wait_physics_frames(3)
	var director := tree.current_scene.get("match_director") as MatchDirector
	check(director != null and director.squad != null, "the FPS runtime runs a bot match")
	if director != null and director.squad != null:
		var first_bot := str(lineup[0]["player_id"])
		check(director.squad.bots.has(first_bot) and director.state.get_player(first_bot).display_name == str(lineup[0]["name"]),
			"opponents are the organisation's starters (%s)" % str(lineup[0]["name"]))
		check(director.squad.skills[first_bot].label.begins_with("Rated"), "their bot skill comes from career abilities")
		check(director.state.teams[MatchState.AWAY].display_name == top_org.name, "scoreboard names the organisation")
		check(director.hud.notice_text().contains(top_org.name), "the notice explains the practice")
		var previous_id := director.state.setup.fixture_id
		director.state.teams[MatchState.HOME].score = 2
		director.hud.play_again_requested.emit()
		await wait_frames(4)
		var replay := tree.current_scene.get("match_director") as MatchDirector
		check(replay != null and replay.state.setup.away_team_id == top_org.id
			and replay.state.setup.away_lineup == lineup and replay.squad.bots.has(first_bot),
			"Play Again loads the same professional opponent and roster")
		check(replay != null and replay.state.setup.fixture_id != previous_id and replay.state.rounds_played() == 0,
			"professional replay starts a new score and fixture")
	app.call("start_practice_match", null, &"hard")
	await wait_frames(4)
	var generic := tree.current_scene.get("match_director") as MatchDirector
	if generic != null:
		var generic_id := generic.state.setup.fixture_id
		tree.current_scene.call("_on_practice_match_requested")
		await wait_frames(4)
		generic = tree.current_scene.get("match_director") as MatchDirector
		check(generic != null and generic.state.setup.away_team_id == "team_practice_bots"
			and generic.squad.skill_name == &"hard" and generic.state.setup.fixture_id != generic_id,
			"generic practice restart preserves its skill and creates a fresh match")
	else:
		check(false, "generic practice starts")
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_restore(app, original_saves)


func _restore(app: Node, original_saves: Variant) -> void:
	app.call("close_career")
	app.set("career_saves", original_saves)
	app.set("last_match_result", null)
	_clean(TEST_ROOT)


func _text_of(node: Node) -> String:
	if node == null:
		return ""
	var parts: PackedStringArray = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child: Node in node.get_children():
		parts.append(_text_of(child))
	return " ".join(parts)


func _clean(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for sub: String in DirAccess.get_directories_at(absolute):
		_clean(path.path_join(sub))
	DirAccess.remove_absolute(absolute)
