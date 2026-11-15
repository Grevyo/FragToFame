class_name CareerCalendarPage
extends CareerPage


func get_page_title() -> String:
	return "Calendar"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var card := UIFactory.card(self, "Fixtures · %s" % GameDate.format(session.repo.current_day()))
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
