class_name CareerPage
extends VBoxContainer
## Base class for Career Hub pages. Subclasses override [method get_page_title] and
## [method build_page]. Pages read view data only; they never own career state.
##
## Pages are opened by route ({page id, args}) through the hub's history, so any page can link
## to any other: [method go] navigates, [method link] makes a clickable name, and
## [method link_table] is a table whose cells can be links.

## The route arguments this page was opened with (e.g. {"org_id": ...}).
var args: Dictionary = {}


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


## Opens another page through the hub (keeps history for Back).
func go(page_id: StringName, route_args: Dictionary = {}) -> void:
	var hub := hub_node()
	if hub != null:
		hub.call("navigate", page_id, route_args)


func hub_node() -> Node:
	if is_inside_tree():
		return get_tree().get_first_node_in_group(&"career_hub")
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(&"career_hub") if tree != null else null


## A clickable name that opens [param page_id] with [param route_args].
func link(text: String, page_id: StringName, route_args: Dictionary) -> LinkButton:
	var button := LinkButton.new()
	button.text = text
	button.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	button.theme_type_variation = &"NavLink"
	button.pressed.connect(func() -> void: go(page_id, route_args))
	return button


## Link to a player's page.
func player_link(player_id: String, text: String) -> LinkButton:
	return link(text, &"player", {"player_id": player_id})


## Link to an organisation's page.
func team_link(org_id: String, text: String) -> LinkButton:
	return link(text, &"team", {"org_id": org_id})


## A table whose cells are Strings, or link cells from [method cell_link] / [method cell_player] /
## [method cell_team].
func link_table(parent: Control, headers: PackedStringArray, rows: Array[Array]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for header: String in headers:
		grid.add_child(_panel(UIFactory.label(header.to_upper(), &"SectionLabel"), &"TableHeaderPanel"))
	for row: Array in rows:
		for value: Variant in row:
			if value is Dictionary:
				var cell: Dictionary = value
				grid.add_child(_panel(link(str(cell["text"]), cell["page"] as StringName, cell["args"]), &"TableRowPanel"))
			else:
				grid.add_child(_panel(UIFactory.label(str(value), &""), &"TableRowPanel"))
	parent.add_child(grid)
	return grid


static func cell_link(text: String, page_id: StringName, route_args: Dictionary) -> Dictionary:
	return {"text": text, "page": page_id, "args": route_args}


static func cell_player(player_id: String, text: String) -> Dictionary:
	return cell_link(text, &"player", {"player_id": player_id})


static func cell_team(org_id: String, text: String) -> Dictionary:
	return cell_link(text, &"team", {"org_id": org_id})


## A row of tab buttons (FM-style sub-navigation). Each tab re-opens this page with
## {tab: id} merged into its args; the active one is highlighted.
func add_tabs(tabs: Array[Array], active: String) -> HBoxContainer:
	var row := add_row(6)
	var page_id := StringName(str(args.get("_page", "")))
	for entry: Array in tabs:
		var tab_id := str(entry[0])
		var button := UIFactory.button(str(entry[1]), &"AccentButton" if tab_id == active else &"")
		button.pressed.connect(func() -> void: go(page_id, args.merged({"tab": tab_id}, true)))
		row.add_child(button)
	return row


## A news table whose player and organisation columns link to their pages.
func story_table(parent: Control, stories: Array[Dictionary], empty_text: String) -> void:
	if stories.is_empty():
		parent.add_child(UIFactory.label(empty_text, &"MutedLabel", true))
		return
	var repo := career().repo if career() != null else null
	var rows: Array[Array] = []
	for story: Dictionary in stories:
		var marker := "★ " if int(story.get("importance", 1)) >= WorldSimulation.HEADLINE else ""
		var who: Variant = ""
		if story.get("player_id") != null and repo != null:
			var player := repo.get_player(str(story["player_id"]))
			if player != null:
				who = cell_player(player.id, player.nickname)
		var team: Variant = ""
		if story.get("organisation_id") != null and repo != null:
			var org := repo.get_organisation(str(story["organisation_id"]))
			if org != null:
				team = cell_team(org.id, org.short_name)
		rows.append([GameDate.format(int(story["day"])), marker + str(story["headline"]), who, team])
	link_table(parent, PackedStringArray(["Date", "Story", "Player", "Team"]), rows)


static var _map_names: Dictionary[String, String] = {}


## Display name of a map id (cached; development maps fall back to their id).
static func map_name(map_id: String) -> String:
	if _map_names.is_empty():
		for entry: Dictionary in OfficialMaps.listing():
			_map_names[str(entry["map_id"])] = str(entry["name"])
	return _map_names.get(map_id, map_id)


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


static func _panel(content: Control, variation: StringName) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel
