class_name CareerInboxPage
extends CareerPage
## What needs you and what is about you: your next match, open offers, stories about you or
## your team, and the world's headlines. Holiday "until the next inbox message" stops on a new
## headline here.


func get_page_title() -> String:
	return "Inbox"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var repo := session.repo
	var needs := UIFactory.card(self, "Needs you")
	var anything := false
	var fixture := repo.pending_fixture(session.human_player_id)
	if fixture != null:
		anything = true
		var row := UIFactory.hbox(8)
		row.add_child(UIFactory.label("Match · %s vs %s · %s" % [fixture.setup.home_team_name, fixture.setup.away_team_name,
			GameDate.format(fixture.scheduled_day)], &"", true))
		row.add_child(link("Play it from Home", &"home", {}))
		needs.add_child(row)
	for offer: Dictionary in repo.offers(session.human_player_id, true):
		anything = true
		var row := UIFactory.hbox(8)
		row.add_child(team_link(str(offer["organisation_id"]), str(offer["org_name"])))
		row.add_child(UIFactory.label("· %s · open until %s" % [str(offer["kind"]).capitalize(),
			GameDate.format(int(offer["expires_day"]))], &"MutedLabel"))
		row.add_child(link("Answer on Home", &"home", {}))
		needs.add_child(row)
	if not anything:
		needs.add_child(UIFactory.label("Nothing needs you. Continue or go on holiday.", &"MutedLabel", true))
	var contract := repo.active_contract(session.human_player_id)
	var about := UIFactory.card(self, "About you and your team")
	story_table(about, repo.news_about(session.human_player_id, contract.organisation_id if contract != null else "", 15),
		"No stories about you yet.")
	var headlines := UIFactory.card(self, "Headlines")
	story_table(headlines, repo.news(20, WorldSimulation.HEADLINE), "No headlines yet.")
	headlines.add_child(link("All news", &"news", {}))
