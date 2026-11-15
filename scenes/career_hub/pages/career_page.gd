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


## A warning-coloured note telling the user the page shows placeholder data.
func add_sample_notice(text: String = DevSampleData.NOTICE) -> void:
	add_child(UIFactory.label(text, &"WarningLabel", true))


## Adds an HBox row whose children can expand side by side, and returns it.
func add_row(separation: int = 18) -> HBoxContainer:
	var row := UIFactory.hbox(separation)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	return row
