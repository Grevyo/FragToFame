class_name CareerCompetitionsPage
extends CareerPage


func get_page_title() -> String:
	return "Competitions"


func build_page() -> void:
	add_sample_notice()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	for competition: Dictionary in DevSampleData.competitions():
		var card := UIFactory.card(grid, competition["name"] as String)
		var rows: Array[PackedStringArray] = [
			PackedStringArray(["Type", competition["type"]]),
			PackedStringArray(["Format", competition["format"]]),
			PackedStringArray(["Status", competition["status"]]),
		]
		UIFactory.key_value_grid(card, rows)
