class_name CareerCalendarPage
extends CareerPage
## Today's date, Next day and Continue (runs days until something needs you), the latest world
## news, the week's organisation series across every league, and the player's own fixtures.

const WEEK: int = 7
const NEWS_SHOWN: int = 8

var advance_button: Button
var continue_button: Button
## Development option, shown while a match is pending (debug builds only).
var simulate_button: Button
var status_label: Label
## Outcome of the last Next day / Continue, kept across the rebuild that follows it.
var _last_status: String = ""


func get_page_title() -> String:
	return "Calendar"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var today := repo.current_day()

	var day_card := UIFactory.card(self, "Today · %s" % GameDate.format(today))
	day_card.add_child(UIFactory.label("Each day resolves other organisations' series and moves the world on: "
		+ "signings, releases, development and news. Continue keeps going until something needs you. "
		+ "Your own scheduled match has to be played first.", &"MutedLabel", true))
	var buttons := UIFactory.hbox(8)
	advance_button = UIFactory.button("Next day", &"AccentButton")
	advance_button.pressed.connect(advance_day)
	buttons.add_child(advance_button)
	continue_button = UIFactory.button("Continue")
	continue_button.pressed.connect(continue_shown)
	buttons.add_child(continue_button)
	if OS.is_debug_build() and session.repo.pending_fixture(session.human_player_id) != null:
		simulate_button = UIFactory.button("Simulate match (dev)")
		simulate_button.tooltip_text = "Development option: resolve your match like a world series and keep testing days."
		simulate_button.pressed.connect(simulate_match)
		buttons.add_child(simulate_button)
	day_card.add_child(buttons)
	status_label = UIFactory.label(_last_status, &"WarningLabel", true)
	day_card.add_child(status_label)

	var news_card := UIFactory.card(self, "World news")
	story_table(news_card, repo.news(NEWS_SHOWN), "No news yet. Move the calendar on.")

	_series_card("Series this week", repo.league_fixtures_between(today, today + WEEK - 1))
	_series_card("Recent results", repo.league_fixtures_between(today - WEEK, today - 1))
	_own_fixtures(session)


## Advances the calendar and rebuilds the page. Returns "" or the reason it was refused.
func advance_day() -> String:
	var problem := App.advance_career_day()
	if not problem.is_empty():
		status_label.text = problem
		return problem
	_last_status = ""
	_rebuild()
	return ""


## Continue: advances until an event and rebuilds the page with why it stopped. Returns the
## outcome ({days, reason, ok}).
func continue_on() -> Dictionary:
	var run := App.begin_continue()
	run.run_all()
	return _continued(run)


## Continue with each day shown on the calendar overlay ([CareerCalendarOverlay]).
func continue_shown() -> void:
	var run := App.begin_continue()
	await CareerCalendarOverlay.play(self, run)
	_continued(run)


func _continued(run: CalendarRun) -> Dictionary:
	var outcome := App.finish_calendar_run(run)
	var days := int(outcome["days"])
	if days == 0:
		status_label.text = str(outcome["reason"])
		return outcome
	_last_status = "%d day%s passed. %s" % [days, "" if days == 1 else "s", outcome["reason"]]
	_rebuild()
	return outcome


## Development option: simulates the pending match, then rebuilds with the score.
func simulate_match() -> Dictionary:
	var outcome := App.simulate_career_fixture()
	if not bool(outcome["ok"]):
		status_label.text = str(outcome["message"])
		return outcome
	_last_status = str(outcome["message"])
	_rebuild()
	return outcome


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	build_page()


func _series_card(title: String, fixtures: Array[Dictionary]) -> void:
	var card := UIFactory.card(self, title)
	if fixtures.is_empty():
		card.add_child(UIFactory.label("No league series on these days.", &"MutedLabel"))
		return
	var rows: Array[Array] = []
	for fixture: Dictionary in fixtures:
		var score := "Preview" if fixture["home_maps"] == null else "%d – %d" % [
			int(fixture["home_maps"]), int(fixture["away_maps"])]
		rows.append([GameDate.format_at(int(fixture["scheduled_day"]), int(fixture["kick_off"])), str(fixture["competition_name"]),
			cell_team(str(fixture["home_id"]), str(fixture["home_name"])), cell_team(str(fixture["away_id"]), str(fixture["away_name"])),
			cell_link(score, &"series", {"series_id": int(fixture["id"])}), map_summary(int(fixture["id"]))])
	link_table(card, PackedStringArray(["Date", "Competition", "Home", "Away", "Maps", "Map scores · MVP"]), rows)


## "9–6, 7–9, 12–10 · MVP Vex" for a simulated series ("" when it was not simulated).
func map_summary(series_id: int) -> String:
	var maps := career().repo.sim_maps(series_id)
	if maps.is_empty():
		return ""
	var scores: PackedStringArray = []
	var mvps: Dictionary[String, int] = {}
	for map: Dictionary in maps:
		scores.append("%d–%d" % [int(map["home_rounds"]), int(map["away_rounds"])])
		if map["mvp_name"] != null:
			mvps[str(map["mvp_name"])] = mvps.get(str(map["mvp_name"]), 0) + 1
	var mvp := ""
	for name: String in mvps:
		if mvp.is_empty() or mvps[name] > mvps[mvp]:
			mvp = name
	return ", ".join(scores) + ("" if mvp.is_empty() else " · MVP %s" % mvp)


func _own_fixtures(session: CareerSession) -> void:
	var card := UIFactory.card(self, "Your fixtures")
	var rows: Array[PackedStringArray] = []
	for fixture: CareerFixture in session.repo.fixtures(session.human_player_id):
		var setup := fixture.setup
		var result := fixture.result
		rows.append(PackedStringArray([GameDate.format_at(fixture.scheduled_day, fixture.kick_off), setup.competition,
			"%s vs %s" % [setup.home_team_name, setup.away_team_name], "MR%d" % setup.max_rounds,
			"Scheduled" if result == null else "%d – %d" % [result.home_score, result.away_score]]))
	if rows.is_empty():
		card.add_child(UIFactory.label("Schedule your first amateur match from Home.", &"MutedLabel"))
	else:
		UIFactory.table(card, PackedStringArray(["Date", "Event", "Teams", "Format", "Result"]), rows)
