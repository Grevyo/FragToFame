class_name CareerNewsPage
extends CareerPage
## The world news log: signings, releases, contract extensions, retirements, rookie classes and
## season openings, newest first. Filter by how important a story is.

const PAGE_SIZE: int = 60
const FILTERS: Array[Array] = [["All stories", 1], ["Notable", 2], ["Headlines", 3]]

var min_importance: int = 1
var list_card: VBoxContainer


func get_page_title() -> String:
	return "News"


func build_page() -> void:
	if add_no_career_notice():
		return
	var filters := add_row(8)
	for entry: Array in FILTERS:
		var importance := int(entry[1])
		var button := UIFactory.button(str(entry[0]), &"AccentButton" if importance == min_importance else &"")
		button.pressed.connect(func() -> void: show_importance(importance))
		filters.add_child(button)
	list_card = UIFactory.card(self, "World news")
	story_table(list_card, career().repo.news(PAGE_SIZE, min_importance), "Nothing has happened yet. Move the calendar on.")


## Rebuilds the page showing stories at or above [param importance].
func show_importance(importance: int) -> void:
	min_importance = importance
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	build_page()


## "Hot (+48)" style label for an organisation's form value (-100..100).
static func form_label(form: int) -> String:
	var word := "Neutral"
	if form >= 40:
		word = "Hot"
	elif form >= 12:
		word = "Good"
	elif form <= -40:
		word = "Poor"
	elif form <= -12:
		word = "Shaky"
	return "%s (%+d)" % [word, form]


## Adds a date / story table to [param card] (shared with the Calendar and Home pages).
static func add_stories(card: VBoxContainer, stories: Array[Dictionary], empty_text: String) -> void:
	if stories.is_empty():
		card.add_child(UIFactory.label(empty_text, &"MutedLabel", true))
		return
	var rows: Array[PackedStringArray] = []
	for story: Dictionary in stories:
		var marker := "★ " if int(story["importance"]) >= WorldSimulation.HEADLINE else ""
		rows.append(PackedStringArray([GameDate.format(int(story["day"])), marker + str(story["headline"])]))
	UIFactory.table(card, PackedStringArray(["Date", "Story"]), rows)
