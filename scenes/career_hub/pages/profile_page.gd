class_name CareerProfilePage
extends CareerPage


func get_page_title() -> String:
	return "Player Profile"


func build_page() -> void:
	add_sample_notice()
	var profile := DevSampleData.player_profile()

	var row := add_row()
	var identity := UIFactory.card(row, profile["display_name"] as String)
	var identity_rows: Array[PackedStringArray] = [
		PackedStringArray(["Player ID", profile["id"]]),
		PackedStringArray(["Age", str(profile["age"])]),
		PackedStringArray(["Nationality", profile["nationality"]]),
		PackedStringArray(["Preferred role", profile["preferred_role"]]),
		PackedStringArray(["Assigned role", profile["assigned_role"]]),
		PackedStringArray(["Team", profile["team"]]),
		PackedStringArray(["Career difficulty", profile["career_difficulty"]]),
	]
	UIFactory.key_value_grid(identity, identity_rows)

	var standing := UIFactory.card(row, "Standing")
	var standing_rows: Array[PackedStringArray] = [
		PackedStringArray(["Reputation", profile["reputation"]]),
		PackedStringArray(["Matchmaking tier", profile["matchmaking_tier"]]),
		PackedStringArray(["Matchmaking ELO", str(profile["matchmaking_elo"])]),
	]
	UIFactory.key_value_grid(standing, standing_rows)

	var attributes := UIFactory.card(self, "Perceived attributes")
	attributes.add_child(UIFactory.label(
		"These values describe what scouts and the esports world believe about this player. "
		+ "For human players they never change aim, recoil, movement or reaction time.",
		&"MutedLabel", true))
	for attribute: Dictionary in DevSampleData.perceived_attributes():
		UIFactory.rating_bar(attributes, attribute["name"] as String, attribute["value"] as int)
