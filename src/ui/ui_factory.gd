class_name UIFactory
extends RefCounted
## Small helpers for building consistently themed UI in code.


static func label(text: String, variation: StringName = &"", autowrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	return b


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", separation)
	return box


static func expand_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Adds a card panel to [param parent] and returns its inner content container.
static func card(parent: Control, title: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := vbox(10)
	panel.add_child(content)
	if title != "":
		content.add_child(label(title, &"CardTitleLabel"))
		content.add_child(HSeparator.new())
	return content


## Adds a two-column key/value grid. Each row is [key, value].
static func key_value_grid(parent: Control, rows: Array[PackedStringArray]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 32)
	grid.add_theme_constant_override(&"v_separation", 6)
	for row: PackedStringArray in rows:
		grid.add_child(label(row[0], &"MutedLabel"))
		grid.add_child(label(row[1]))
	parent.add_child(grid)
	return grid


## Adds a simple table. Every row must have as many cells as [param headers].
static func table(parent: Control, headers: PackedStringArray, rows: Array[PackedStringArray]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for header: String in headers:
		grid.add_child(_cell(header.to_upper(), &"TableHeaderPanel", &"SectionLabel"))
	for row: PackedStringArray in rows:
		for value: String in row:
			grid.add_child(_cell(value, &"TableRowPanel", &""))
	parent.add_child(grid)
	return grid


## Adds a stat tile (caption + big value) to [param parent].
static func stat_tile(parent: Control, caption: String, value: String) -> VBoxContainer:
	var content := card(parent)
	content.add_child(label(caption.to_upper(), &"SectionLabel"))
	content.add_child(label(value, &"StatValueLabel"))
	return content


## Adds a labelled 0–100 bar row.
static func rating_bar(parent: Control, caption: String, value: int) -> void:
	var row := hbox(16)
	var caption_label := label(caption, &"MutedLabel")
	caption_label.custom_minimum_size.x = 220
	row.add_child(caption_label)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var value_label := label(str(value))
	value_label.custom_minimum_size.x = 36
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	parent.add_child(row)


static func _cell(text: String, panel_variation: StringName, label_variation: StringName) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = panel_variation
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(label(text, label_variation))
	return panel
