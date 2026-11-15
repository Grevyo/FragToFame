class_name CareerCalendarPage
extends CareerPage


func get_page_title() -> String:
	return "Calendar"


func build_page() -> void:
	add_sample_notice("Development sample data — the in-game calendar does not advance yet.")
	var card := UIFactory.card(self, "Upcoming — January, Year 1")
	var rows: Array[PackedStringArray] = []
	for item: Dictionary in DevSampleData.calendar():
		rows.append(PackedStringArray([item["date"], item["event"], item["detail"]]))
	UIFactory.table(card, PackedStringArray(["Date", "Event", "Detail"]), rows)
