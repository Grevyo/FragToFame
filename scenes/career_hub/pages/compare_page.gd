class_name CareerComparePage
extends CareerPage
## Two players side by side ({a, b}): perceived attributes, standing and simulated form. A search
## picks the second player.

var search_edit: LineEdit
var results: VBoxContainer
var player_a: CareerRecords.PlayerRecord
var player_b: CareerRecords.PlayerRecord


func get_page_title() -> String:
	if player_a != null and player_b != null:
		return "%s vs %s" % [player_a.nickname, player_b.nickname]
	return "Compare players"


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	player_a = repo.get_player(str(args.get("a", "")))
	player_b = repo.get_player(str(args.get("b", "")))
	if player_a == null:
		var empty := UIFactory.card(self, "Compare players")
		empty.add_child(UIFactory.label("Open a player and press Compare… to pick who to compare them with.", &"MutedLabel", true))
		empty.add_child(link("Browse players", &"players", {}))
		return
	_picker()
	if player_b != null:
		_comparison(repo)


func _picker() -> void:
	var card := UIFactory.card(self, "Compare %s with…" % player_a.nickname if player_b == null else "Compare with someone else")
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Nickname or name"
	search_edit.text_changed.connect(func(_t: String) -> void: search())
	card.add_child(search_edit)
	results = UIFactory.vbox(2)
	card.add_child(results)


## Lists players matching the search box, each opening the comparison.
func search() -> void:
	for child: Node in results.get_children():
		results.remove_child(child)
		child.queue_free()
	var text := search_edit.text.strip_edges()
	if text.length() < 2:
		return
	for entry: Dictionary in career().repo.find_players(text):
		if str(entry["id"]) == player_a.id:
			continue
		var caption := str(entry["nickname"]) + ("  ·  " + str(entry["org"]) if entry["org"] != null else "  ·  free agent")
		results.add_child(link(caption, &"compare", {"a": player_a.id, "b": str(entry["id"])}))


func _comparison(repo: CareerRepository) -> void:
	var today := repo.current_day()
	var rows: Array[Array] = [["Player", cell_player(player_a.id, player_a.display_name()),
		cell_player(player_b.id, player_b.display_name())]]
	rows.append(["Team", _team_cell(repo, player_a.id), _team_cell(repo, player_b.id)])
	rows.append(["Age", str(player_a.age(today)), str(player_b.age(today))])
	rows.append(["Nation", CareerCatalog.nation_name(player_a.nation_id), CareerCatalog.nation_name(player_b.nation_id)])
	rows.append(["Role", CareerCatalog.role_name(player_a.preferred_role), CareerCatalog.role_name(player_b.preferred_role)])
	rows.append(["Reputation", str(repo.reputation(player_a.id)), str(repo.reputation(player_b.id))])
	rows.append(["Perceived rating", str(repo.perceived_rating(player_a.id)), str(repo.perceived_rating(player_b.id))])
	rows.append(["Scouting confidence", "%d%%" % repo.perceived_confidence(player_a.id), "%d%%" % repo.perceived_confidence(player_b.id)])
	var form_a := repo.sim_form(player_a.id, today - 90)
	var form_b := repo.sim_form(player_b.id, today - 90)
	for key: Array in [["Maps (90 days)", "maps"], ["Rating (90 days)", "rating"], ["Kills (90 days)", "kills"],
			["Deaths (90 days)", "deaths"], ["Opening kills", "opening_kills"], ["Clutches won", "clutch_wins"]]:
		var field := str(key[1])
		rows.append([str(key[0]), _form_value(form_a, field), _form_value(form_b, field)])
	rows.append(["Morale", "%+d" % repo.morale(player_a.id), "%+d" % repo.morale(player_b.id)])
	var card := UIFactory.card(self, "Side by side")
	card.add_child(UIFactory.label("Perceived values are what the world believes, not true ability.", &"MutedLabel", true))
	link_table(card, PackedStringArray(["", player_a.nickname, player_b.nickname]), rows)
	var attributes := UIFactory.card(self, "Perceived attributes")
	var seen_a := repo.perceived(player_a.id)
	var seen_b := repo.perceived(player_b.id)
	var attribute_rows: Array[PackedStringArray] = []
	for ability: StringName in CareerCatalog.ABILITIES:
		var a := int(seen_a.get(ability, 0))
		var b := int(seen_b.get(ability, 0))
		attribute_rows.append(PackedStringArray([CareerCatalog.ability_name(ability), _marked(a, b), _marked(b, a)]))
	UIFactory.table(attributes, PackedStringArray(["Attribute", player_a.nickname, player_b.nickname]), attribute_rows)
	var swap := UIFactory.button("Swap sides")
	var a_id := player_a.id
	var b_id := player_b.id
	swap.pressed.connect(func() -> void: go(&"compare", {"a": b_id, "b": a_id}))
	add_child(swap)


func _team_cell(repo: CareerRepository, player_id: String) -> Variant:
	var contract := repo.active_contract(player_id)
	if contract == null:
		return "Free agent"
	var org := repo.get_organisation(contract.organisation_id)
	return cell_team(contract.organisation_id, org.short_name if org != null else contract.organisation_id)


static func _form_value(form: Dictionary, field: String) -> String:
	if field == "rating":
		return "%.2f" % float(form["rating"]) if int(form["maps"]) > 0 else "—"
	return str(int(form[field]))


## The value, with a marker when it is the higher of the two.
static func _marked(value: int, other: int) -> String:
	return "%d  ▲" % value if value > other else str(value)
