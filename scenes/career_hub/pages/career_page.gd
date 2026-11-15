class_name CareerPage
extends VBoxContainer
## Base class for Career Hub pages. Subclasses override [method get_page_title] and
## [method build_page]. Pages read view data only; they never own career state.


func _init() -> void:
	add_theme_constant_override(&"separation", 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func get_page_title() -> String:
	return "Untitled"


## Builds the page's controls. Called once, before the page is added to the tree.
func build_page() -> void:
	pass


## The open career, or null (pages must render without one, e.g. in tests).
func career() -> CareerSession:
	return App.career if App.has_career() else null


## Shows "no career open" with a way to open one. Returns true when there is no career.
func add_no_career_notice() -> bool:
	if career() != null:
		return false
	var card := UIFactory.card(self, "No career open")
	card.add_child(UIFactory.label("Create or continue a career to see the world's organisations and players.",
		&"MutedLabel", true))
	var open := UIFactory.button("Open careers", &"AccentButton")
	open.pressed.connect(func() -> void: App.go_to(App.SCENE_CAREER_SELECT))
	card.add_child(open)
	return true


## A warning-coloured note telling the user the page shows placeholder data.
func add_sample_notice(text: String = DevSampleData.NOTICE) -> void:
	add_child(UIFactory.label(text, &"WarningLabel", true))


## Adds an HBox row whose children can expand side by side, and returns it.
func add_row(separation: int = 18) -> HBoxContainer:
	var row := UIFactory.hbox(separation)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	return row
