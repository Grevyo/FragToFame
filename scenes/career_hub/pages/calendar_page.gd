class_name CareerCalendarPage
extends CareerPage
## Today's date, moving to the next day, the week's organisation series across every league, and
## the player's own fixtures.

const WEEK: int = 7

var advance_button: Button
var status_label: Label


func get_page_title() -> String:
	return "Calendar"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var today := repo.current_day()

	var day_card := UIFactory.card(self, "Today · %s" % GameDate.format(today))
	day_card.add_child(UIFactory.label("Moving to the next day resolves every other organisation's series "
		+ "that were due. Your own scheduled match has to be played first.", &"MutedLabel", true))
	advance_button = UIFactory.button("Advance to next day", &"AccentButton")
	advance_button.pressed.connect(advance_day)
	day_card.add_child(advance_button)
	status_label = UIFactory.label("", &"WarningLabel", true)
	day_card.add_child(status_label)

	_series_card("Series this week", repo.league_fixtures_between(today, today + WEEK - 1))
	_series_card("Recent results", repo.league_fixtures_between(today - WEEK, today - 1))
	_own_fixtures(session)


## Advances the calendar and rebuilds the page. Returns "" or the reason it was refused.
func advance_day() -> String:
	var problem := App.advance_career_day()
	if not problem.is_empty():
		status_label.text = problem
		return problem
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	build_page()
	return ""


func _series_card(title: String, fixtures: Array[Dictionary]) -> void:
	var card := UIFactory.card(self, title)
	if fixtures.is_empty():
		card.add_child(UIFactory.label("No league series on these days.", &"MutedLabel"))
		return
	var rows: Array[PackedStringArray] = []
	for fixture: Dictionary in fixtures:
		var score := "Scheduled" if fixture["home_maps"] == null else "%d – %d" % [
			int(fixture["home_maps"]), int(fixture["away_maps"])]
		rows.append(PackedStringArray([GameDate.format(int(fixture["scheduled_day"])), str(fixture["competition_name"]),
			"%s vs %s" % [fixture["home_name"], fixture["away_name"]], score]))
	UIFactory.table(card, PackedStringArray(["Date", "Competition", "Series", "Maps"]), rows)


func _own_fixtures(session: CareerSession) -> void:
	var card := UIFactory.card(self, "Your fixtures")
	var rows: Array[PackedStringArray] = []
	for fixture: CareerFixture in session.repo.fixtures(session.human_player_id):
		var setup := fixture.setup
		var result := fixture.result
		rows.append(PackedStringArray([GameDate.format(fixture.scheduled_day), setup.competition,
			"%s vs %s" % [setup.home_team_name, setup.away_team_name], "MR%d" % setup.max_rounds,
			"Scheduled" if result == null else "%d – %d" % [result.home_score, result.away_score]]))
	if rows.is_empty():
		card.add_child(UIFactory.label("Schedule your first amateur match from Home.", &"MutedLabel"))
	else:
		UIFactory.table(card, PackedStringArray(["Date", "Event", "Teams", "Format", "Result"]), rows)
