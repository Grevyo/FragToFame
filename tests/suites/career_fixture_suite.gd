extends TestSuite
## Exercises saved career UI, fixture launches and completed matches on a disposable save.

const TEST_ROOT: String = "user://tests/career_fixtures"
const PROFILE: Dictionary = {"first_name": "Robin", "last_name": "Vale", "nickname": "Chevron",
	"nation_id": "gb", "preferred_role": &"rifler", "difficulty": &"standard", "age": 19}

var _app: Node
var _save_id: String
var _saves: CareerSaves


func suite_name() -> String:
	return "Playable career fixtures (Milestone 10)"


func run() -> void:
	_app = tree.root.get_node("App")
	var original_saves := _app.get("career_saves") as CareerSaves
	_saves = CareerSaves.new(TEST_ROOT.path_join(Ids.generate("test")))
	_app.set("career_saves", _saves)
	await _run_fixture_flow()
	_app.call("close_career")
	_app.set("career_saves", original_saves)
	_app.set("last_match_result", null)
	_app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(_saves.root))


func _run_fixture_flow() -> void:
	section("Career schema and fixture scheduling")
	var problem: String = _app.call("new_career", "Fixture test", PROFILE)
	check(problem.is_empty(), "creates an isolated career from the shipped database")
	if not problem.is_empty():
		return
	var session := _app.get("career") as CareerSession
	_save_id = session.save_id
	var player_id := session.human_player_id

	# Restore the fixture-free M9 schema on the disposable database, then load normally.
	check(session.repo.db.execute("DROP TABLE career_match_rating;")
		and session.repo.db.execute("DROP TABLE career_match_stat;")
		and session.repo.db.execute("DROP TABLE career_match_event;")
		and session.repo.db.execute("DROP TABLE career_fixture;") and session.repo.db.set_user_version(2),
		"prepares an existing v2 career")
	var backups_before := _saves.backups(_save_id).size()
	problem = _app.call("load_career", _save_id)
	session = _app.get("career") as CareerSession
	check(problem.is_empty() and session != null and session.repo.db.user_version() == CareerSchema.CURRENT_VERSION
		and session.human_player_id == player_id and _saves.backups(_save_id).size() == backups_before + 1,
		"opening v2 preserves the career and snapshots before adding fixtures")
	if not problem.is_empty():
		return
	_app.call("open_career_hub")
	await wait_frames(3)
	var schedule := _button(tree.current_scene, "Schedule amateur match")
	check(schedule != null, "Career Home offers amateur matchmaking")
	if schedule == null:
		return
	schedule.pressed.emit()
	await wait_frames(3)
	var fixture := session.repo.pending_fixture(player_id)
	check(fixture != null, "scheduling from Home persists a fixture")
	if fixture == null:
		return
	var id := fixture.setup.fixture_id
	check(fixture.scheduled_day == session.repo.current_day() and fixture.setup.max_rounds == 5,
		"early fixtures are MR5 on the current career day")
	check(fixture.setup.home_lineup.size() == 5 and fixture.setup.away_lineup.size() == 5
		and fixture.setup.home_lineup[0]["player_id"] == player_id
		and (fixture.setup.home_lineup[0]["abilities"] as Dictionary).is_empty(),
		"the fixture carries full career lineups with no simulated human abilities")
	check(str(_app.call("schedule_career_fixture")).is_empty() and session.repo.fixture_count(player_id) == 1,
		"scheduling twice keeps a single pending fixture")
	var entry := MatchResult.create(id, 5, 0, MatchResult.SOURCE_FPS_RUNTIME)
	entry.map_id = fixture.setup.map_id
	check(not CareerFixtures.record_result(session.repo, player_id, entry).is_empty()
		and session.repo.pending_fixture(player_id) != null, "an incomplete MR5 score is refused")
	entry.home_score = 6
	entry.rounds_played = 6
	entry.source = MatchResult.SOURCE_STUB
	check(not CareerFixtures.record_result(session.repo, player_id, entry).is_empty(),
		"stub results cannot resolve a playable fixture")
	entry.source = MatchResult.SOURCE_FPS_RUNTIME
	check(not CareerFixtures.record_result(session.repo, "another_profile", entry).is_empty(),
		"results must belong to the current career professional")
	entry.map_id = "map_wrong"
	check(not CareerFixtures.record_result(session.repo, player_id, entry).is_empty(),
		"results must match the scheduled map")

	section("Play, leave, reopen and restart")
	var play := _button(tree.current_scene, "Play fixture")
	check(play != null, "the pending fixture is playable from Home")
	if play == null:
		return
	play.pressed.emit()
	await wait_frames(4)
	var runtime := tree.current_scene
	var director := runtime.get("match_director") as MatchDirector
	check(director != null and director.state.setup.fixture_id == id and director.local_player_id == player_id
		and director.player.weapons.shooter_id == player_id and director.state.players.size() == 10,
		"the FPS runtime uses the scheduled fixture and keeps the real career player ID")
	if director == null:
		return
	runtime.call("_on_main_menu_requested")
	await wait_frames(3)
	check(tree.current_scene.scene_file_path.ends_with("career_hub.tscn")
		and session.repo.pending_fixture(player_id) != null and session.repo.current_day() == fixture.scheduled_day,
		"leaving mid-match returns to the hub and keeps the fixture and date")
	_app.call("load_career", _save_id)
	session = _app.get("career") as CareerSession
	check(session != null and session.repo.pending_fixture(player_id).setup.fixture_id == id,
		"the original fixture survives reopening SQLite")
	if session == null:
		return
	check(str(_app.call("start_career_fixture", id)).is_empty(), "the reopened fixture can be played")
	await wait_frames(4)
	runtime = tree.current_scene
	runtime.call("_on_practice_match_requested")
	await wait_frames(4)
	runtime = tree.current_scene
	director = runtime.get("match_director") as MatchDirector
	check(director != null and director.state.setup.fixture_id == id and director.state.rounds_played() == 0,
		"restart keeps the scheduled fixture and resets its score")
	if director == null:
		return

	section("Result, atomic calendar advance and retries")
	session.repo.set_current_day(fixture.scheduled_day)
	check(session.repo.db.execute("""CREATE TRIGGER fixture_test_block_date BEFORE UPDATE OF value ON meta
		WHEN OLD.key = 'current_day' BEGIN SELECT RAISE(ABORT, 'test date write failure'); END;"""),
		"injects a failure after the fixture result write")
	_finish_for_home(director)
	check(director.state.phase == MatchState.Phase.MATCH_END and bool(_app.call("has_unsaved_fixture_result")),
		"finishing a real rules-driven FPS match retains its result when writing fails")
	check(session.repo.pending_fixture(player_id) != null and session.repo.current_day() == fixture.scheduled_day,
		"calendar write failure rolls back both the result and day")
	check(int(session.repo.performance_totals(player_id).get("matches", -1)) == 0,
		"failed result publication also rolls back telemetry and ratings")
	check(not director.hud.play_again_button.visible and director.hud.main_menu_button.text == "Return to Career Hub",
		"career match completion offers return to the hub")
	await wait_frames(2)
	director.hud.main_menu_button.pressed.emit()
	await wait_frames(3)
	var retry := _button(tree.current_scene, "Retry saving result")
	check(retry != null, "the hub offers to retry saving the finished result")
	if retry == null:
		return
	session.repo.db.execute("DROP TRIGGER fixture_test_block_date;")
	retry.pressed.emit()
	await wait_frames(3)
	var completed := session.repo.fixture_by_id(id)
	check(completed != null and completed.result != null and completed.result.home_score == 6
		and session.repo.current_day() == fixture.scheduled_day + 1,
		"retry saves the final score and advances the date once")
	if completed == null or completed.result == null:
		return
	check(CareerFixtures.record_result(session.repo, player_id, completed.result).is_empty()
		and session.repo.current_day() == fixture.scheduled_day + 1,
		"resubmission is idempotent")
	var conflict := MatchResult.create(id, 0, 6, MatchResult.SOURCE_FPS_RUNTIME)
	conflict.map_id = completed.setup.map_id
	check(not CareerFixtures.record_result(session.repo, player_id, conflict).is_empty()
		and session.repo.fixture_by_id(id).result.home_score == 6, "a different final score cannot replace a result")
	check(not str(_app.call("start_career_fixture", id)).is_empty(), "a finished fixture cannot be replayed into the calendar")

	_app.call("load_career", _save_id)
	session = _app.get("career") as CareerSession
	completed = session.repo.fixture_by_id(id)
	check(completed.result != null and completed.result.home_score == 6 and session.repo.current_day() == 1,
		"score and calendar advancement survive closing and reopening the save")
	tree.current_scene.call("show_page", &"calendar")
	await wait_frames(2)
	check(_has_label(tree.current_scene, "6 – 0"), "Calendar displays the persisted final score")
	var counts := session.repo.performance_totals(player_id)
	var recorded_players := int(session.repo.db.scalar(
		"SELECT COUNT(*) FROM career_match_stat WHERE fixture_id = ?;", [id], 0))
	var raw_events := str(session.repo.db.scalar(
		"SELECT events_json FROM career_match_event WHERE fixture_id = ?;", [id], ""))
	check(int(counts["matches"]) == 1 and int(counts["rounds"]) == 6 and int(counts["kills"]) == 30
		and recorded_players == 10 and raw_events.contains("round_ended"),
		"raw events and calculated counts persist for both lineups")
	var history := session.repo.recent_performance(player_id)
	check(history.size() == 1 and float(history[0]["rating"]) > 0.0
		and int(history[0]["rating_version"]) == MatchStatistics.RATING_VERSION,
		"per-match performance rating occupies a separate versioned record")
	tree.current_scene.call("show_page", &"statistics")
	await wait_frames(2)
	check(_has_label(tree.current_scene, "F2F RATING") and _has_label(tree.current_scene, "30-0-0"),
		"Statistics displays the recorded fixture and calculated rating")
	check(str(_app.call("schedule_career_fixture")).is_empty()
		and session.repo.pending_fixture(player_id).scheduled_day == 1
		and session.repo.pending_fixture(player_id).setup.fixture_id != id, "the next fixture is a new match on the next day")

	section("Successful publication and practice isolation")
	var next := session.repo.pending_fixture(player_id)
	if next == null or not str(_app.call("start_career_fixture", next.setup.fixture_id)).is_empty():
		check(false, "launches the next fixture")
		return
	await wait_frames(4)
	runtime = tree.current_scene
	director = runtime.get("match_director") as MatchDirector
	if director == null:
		check(false, "the next fixture starts in the FPS scene")
		return
	_finish_for_home(director)
	await wait_frames(2)
	check(session.repo.fixture_by_id(next.setup.fixture_id).result != null and session.repo.current_day() == 2
		and not bool(_app.call("has_unsaved_fixture_result")), "completing a fixture normally publishes immediately")
	director.hud.main_menu_button.pressed.emit()
	await wait_frames(3)
	_app.call("start_practice_match")
	await wait_frames(4)
	director = tree.current_scene.get("match_director") as MatchDirector
	if director == null:
		check(false, "practice still starts")
		return
	_finish_for_home(director)
	await wait_frames(2)
	check(director.state.phase == MatchState.Phase.MATCH_END and session.repo.fixture_count(player_id) == 2
		and session.repo.current_day() == 2, "ordinary practice results leave career fixtures and date alone")


func _finish_for_home(director: MatchDirector) -> void:
	var state := director.state
	for round_index: int in state.setup.rounds_to_win():
		state.tick(state.rules.freeze_time + 0.1)
		for victim: String in state.teams[MatchState.AWAY].player_ids:
			state.record_kill(victim, director.local_player_id, WeaponCatalog.VANTA_RIFLE, false)
		state.tick(state.rules.round_end_delay + 0.1)


func _button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			return button
	return null


func _has_label(root: Node, text: String) -> bool:
	for node: Node in root.find_children("*", "Label", true, false):
		if (node as Label).text == text:
			return true
	return false


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
