class_name CareerTeamsPage
extends CareerPage


func get_page_title() -> String:
	return "Teams"


func build_page() -> void:
	add_sample_notice("Development sample data — fictional organisations, not a live database.")
	var card := UIFactory.card(self, "Organisations")
	var rows: Array[PackedStringArray] = []
	for team: Dictionary in DevSampleData.teams():
		rows.append(PackedStringArray([
			team["name"], team["region"], team["tier"], str(team["ladder"]), team["id"],
		]))
	UIFactory.table(card, PackedStringArray(["Organisation", "Region", "Tier", "Ladder rating", "ID"]), rows)
