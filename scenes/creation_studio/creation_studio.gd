extends Node3D
## Creation Studio shell (Milestone 1): fly camera, grid, snapped ground cursor and the editor
## UI frame that the Map Creator (Milestone 3) will fill in. No editing operations exist yet.

const SNAP_SIZES: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const DEFAULT_SNAP_INDEX: int = 2
const GROUND_PLANE: Plane = Plane(Vector3.UP, 0.0)

const PLANNED_TOOLS: Array[String] = [
	"Select", "Move", "Rotate", "Floor", "Wall", "Door", "Stairs", "Prop",
	"Bombsite", "Spawn", "Buy zone", "Callout",
]

var snap_size: float = SNAP_SIZES[DEFAULT_SNAP_INDEX]
var cursor_cell: Vector3 = Vector3.ZERO
var main_menu_button: Button
var snap_option: OptionButton

var _status_label: Label
var _cursor_label: Label

@onready var camera: EditorFlyCamera = $EditorCamera
@onready var grid: EditorGrid = $Grid
@onready var cursor: MeshInstance3D = $Cursor
@onready var ui: CanvasLayer = $UI


func _ready() -> void:
	_build_ui()
	set_snap_size(snap_size)


func set_snap_size(size: float) -> void:
	snap_size = size
	grid.snap_size = size
	cursor.scale = Vector3(size, 1.0, size)


## Returns the snapped grid-cell centre under a screen position, or null if the ray misses.
func ground_cell_at(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit: Variant = GROUND_PLANE.intersects_ray(origin, direction)
	if hit == null:
		return null
	var point := hit as Vector3
	var half := snap_size / 2.0
	return Vector3(snappedf(point.x - half, snap_size) + half, 0.0, snappedf(point.z - half, snap_size) + half)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var cell: Variant = null if camera.is_looking else ground_cell_at(mouse)
	cursor.visible = cell != null
	if cell != null:
		cursor_cell = cell as Vector3
		cursor.position = cursor_cell + Vector3(0, 0.011, 0)
		_cursor_label.text = "Cursor  x %.2f   z %.2f" % [cursor_cell.x, cursor_cell.z]
	else:
		_cursor_label.text = "Cursor  —"
	var p := camera.position
	_status_label.text = "Camera  %.1f, %.1f, %.1f   ·   Fly speed %.1f m/s   ·   Snap %s m   ·   %s" % [
		p.x, p.y, p.z, camera.fly_speed, _format_snap(snap_size),
		"LOOKING (RMB held)" if camera.is_looking else "Hold RMB to look/fly",
	]


func _format_snap(size: float) -> String:
	return ("%.2f" % size).rstrip("0").rstrip(".")


# --- UI ---------------------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var layout := UIFactory.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layout)

	layout.add_child(_build_top_bar())

	var middle := UIFactory.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(middle)
	middle.add_child(_build_tool_panel())
	var viewport_gap := Control.new()
	viewport_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(viewport_gap)
	middle.add_child(_build_inspector_panel())

	layout.add_child(_build_status_bar())


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	var row := UIFactory.hbox(16)
	bar.add_child(row)
	row.add_child(UIFactory.label("CREATION STUDIO", &"LogoLabel"))
	var mode := UIFactory.label("Map Creator · foundation shell", &"MutedLabel")
	mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mode)
	row.add_child(UIFactory.expand_spacer())

	var snap_label := UIFactory.label("Grid snap", &"MutedLabel")
	snap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(snap_label)
	snap_option = OptionButton.new()
	for i: int in SNAP_SIZES.size():
		snap_option.add_item("%s m" % _format_snap(SNAP_SIZES[i]), i)
	snap_option.select(DEFAULT_SNAP_INDEX)
	snap_option.item_selected.connect(func(index: int) -> void: set_snap_size(SNAP_SIZES[index]))
	row.add_child(snap_option)

	var reset := UIFactory.button("Reset view (F)")
	reset.pressed.connect(camera.reset_view)
	row.add_child(reset)

	main_menu_button = UIFactory.button("◂  Main Menu")
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	row.add_child(main_menu_button)
	return bar


func _build_tool_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SidebarPanel"
	panel.custom_minimum_size.x = 200
	var column := UIFactory.vbox(6)
	panel.add_child(column)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override(&"margin_left", 16)
	header_margin.add_theme_constant_override(&"margin_right", 16)
	var header := UIFactory.vbox(4)
	header.add_child(UIFactory.label("TOOLS", &"SectionLabel"))
	header.add_child(UIFactory.label("Planned for Milestone 3", &"WarningLabel"))
	header_margin.add_child(header)
	column.add_child(header_margin)
	for tool_name: String in PLANNED_TOOLS:
		var b := UIFactory.button(tool_name, &"SidebarButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = true
		b.tooltip_text = "%s — not implemented yet (Milestone 3: Basic runtime map editing)" % tool_name
		column.add_child(b)
	return panel


func _build_inspector_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.custom_minimum_size.x = 280
	var column := UIFactory.vbox(10)
	panel.add_child(column)
	column.add_child(UIFactory.label("INSPECTOR", &"SectionLabel"))
	column.add_child(UIFactory.label("Nothing selected.", &"MutedLabel"))
	column.add_child(HSeparator.new())
	column.add_child(UIFactory.label("CONTROLS", &"SectionLabel"))
	for line: String in [
		"Hold RMB — look around",
		"RMB + WASD — fly",
		"RMB + E / Q — up / down",
		"RMB + Shift — fly faster",
		"RMB + wheel — change fly speed",
		"Wheel — dolly forward / back",
		"F — reset view",
	]:
		column.add_child(UIFactory.label(line, &"MutedLabel"))
	column.add_child(HSeparator.new())
	_cursor_label = UIFactory.label("Cursor  —")
	column.add_child(_cursor_label)
	return panel


func _build_status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBarPanel"
	_status_label = UIFactory.label("", &"MutedLabel")
	bar.add_child(_status_label)
	return bar


func _on_main_menu_pressed() -> void:
	App.go_to(App.SCENE_MAIN_MENU)
