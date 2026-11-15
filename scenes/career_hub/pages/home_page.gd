class_name CareerHomePage
extends CareerPage


func get_page_title() -> String:
	return "Home"


func build_page() -> void:
	add_sample_notice()
	var profile := DevSampleData.player_profile()

	var welcome := UIFactory.card(self, "Welcome back, %s" % profile["nickname"])
	welcome.add_child(UIFactory.label(
		"This is the Career Hub foundation. Navigation, layout and theming are live; the career "
		+ "world, simulation and saves arrive in later milestones.", &"MutedLabel", true))

	var row := add_row()
	var fixture := DevSampleData.next_fixture()
	var next_card := UIFactory.card(row, "Next fixture")
	var fixture_rows: Array[PackedStringArray] = [
		PackedStringArray(["Date", fixture["date"]]),
		PackedStringArray(["Competition", fixture["competition"]]),
		PackedStringArray(["Opponent", fixture["opponent"]]),
		PackedStringArray(["Format", fixture["format"]]),
	]
	UIFactory.key_value_grid(next_card, fixture_rows)

	var status_card := UIFactory.card(row, "Career status")
	var status_rows: Array[PackedStringArray] = [
		PackedStringArray(["Team", profile["team"]]),
		PackedStringArray(["Preferred role", profile["preferred_role"]]),
		PackedStringArray(["Matchmaking", "%s (%d ELO)" % [profile["matchmaking_tier"], profile["matchmaking_elo"]]]),
		PackedStringArray(["Reputation", profile["reputation"]]),
	]
	UIFactory.key_value_grid(status_card, status_rows)

	var news_card := UIFactory.card(self, "News")
	for item: Dictionary in DevSampleData.news():
		var line := UIFactory.hbox(16)
		var date_label := UIFactory.label(item["date"] as String, &"AccentLabel")
		date_label.custom_minimum_size.x = 100
		line.add_child(date_label)
		var headline := UIFactory.label(item["headline"] as String, &"", true)
		headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(headline)
		news_card.add_child(line)
