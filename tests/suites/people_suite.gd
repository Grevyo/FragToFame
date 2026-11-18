extends TestSuite
## Every AI professional is a person: personality from traits, moods, relationships, goals,
## life events and interviews, and how they feed back into the market and match chemistry.

const TEST_ROOT: String = "user://tests/people"
const PROFILE: Dictionary = {"first_name": "Ilse", "last_name": "Marsh", "nickname": "Wren",
	"nation_id": "nl", "preferred_role": &"rifler", "difficulty": &"standard", "age": 20}


func suite_name() -> String:
	return "People (living world)"


func run() -> void:
	_test_personality()
	_test_moods()
	_test_voice()
	var app := tree.root.get_node("App")
	var original := app.get("career_saves") as CareerSaves
	_clean(ProjectSettings.globalize_path(TEST_ROOT))
	app.set("career_saves", CareerSaves.new(TEST_ROOT))
	await _test_world(app)
	app.call("close_career")
	app.set("career_saves", original)
	app.call("go_to", &"main_menu")
	await wait_frames(3)
	_clean(ProjectSettings.globalize_path(TEST_ROOT))


func _rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func _test_personality() -> void:
	section("Personality")
	var rng := _rng(7)
	var loyal := 0.0
	var mercenary := 0.0
	var hot := 0.0
	var calm := 0.0
	var money_drivers := 0
	for i: int in 200:
		loyal += int(CareerPeople.roll_person(rng, {&"tr_loyal": 1})["loyalty"])
		var hired := CareerPeople.roll_person(rng, {&"tr_mercenary": 1})
		mercenary += int(hired["loyalty"])
		money_drivers += 1 if hired["drive"] == "money" else 0
		hot += int(CareerPeople.roll_person(rng, {&"tr_hot_headed": 1})["temperament"])
		calm += int(CareerPeople.roll_person(rng, {&"tr_calm": 1})["temperament"])
	check(loyal / 200.0 > mercenary / 200.0 + 8.0, "loyal players are loyal, mercenaries are not (%.1f vs %.1f)" % [loyal / 200.0, mercenary / 200.0])
	check(calm / 200.0 > hot / 200.0 + 8.0, "a hot head is volatile, a calm player is not")
	check(money_drivers > 60, "mercenaries are mostly driven by money (%d of 200)" % money_drivers)
	var person := CareerPeople.roll_person(rng, {})
	check(PersonVoice.GOALS.has(str(person["goal"])) and PersonVoice.DRIVES.has(str(person["drive"]))
		and PersonVoice.BACKGROUNDS.has(str(person["background"])), "everyone has a drive, a goal and a background")
	var differs := false
	var first := CareerPeople.roll_person(rng, {})
	for i: int in 5:
		differs = differs or CareerPeople.roll_person(rng, {}) != first
	check(differs, "people differ from one another")


func _test_moods() -> void:
	section("Moods and decisions")
	var person := {"ambition": 16, "loyalty": 8, "professionalism": 10, "temperament": 10, "ego": 10, "sociability": 10,
		"drive": "money", "happiness": 0, "wants_move": 0}
	var starter := CareerPeople.mood_target(person, {"form": 20, "salary": 3000, "fair_salary": 3000, "tier": 1, "rating": 70})
	var benched := CareerPeople.mood_target(person, {"is_substitute": true, "form": -40, "salary": 1500, "fair_salary": 3000,
		"tier": 3, "rating": 80, "rivals": 2})
	check(int(starter["value"]) > 0 and int(benched["value"]) <= -30, "a benched, underpaid player in a slump is miserable (%d vs %d)" % [
		int(benched["value"]), int(starter["value"])])
	check(bool(benched["outgrown"]) and str(benched["reason"]) != "", "and knows why (%s)" % benched["reason"])
	check(CareerPeople.wants_out(person, -20, false) and not CareerPeople.wants_out(person.merged({"loyalty": 18}, true), -20, false),
		"unhappy players want out, unless they are very loyal")
	check(CareerPeople.renewal_modifier(person.merged({"wants_move": 1}, true)) < -0.4
		and CareerPeople.renewal_modifier(person.merged({"loyalty": 19, "happiness": 20}, true)) > 0.1,
		"an unsettled player turns renewals down; a loyal, happy one signs")
	check(CareerPeople.sell_modifier(person.merged({"wants_move": 1}, true)) > 0.0, "clubs sell unsettled players more readily")
	var rng := _rng(11)
	var refused := 0
	for i: int in 200:
		refused += 0 if CareerPeople.accepts_move(person.merged({"loyalty": 18, "happiness": 20}, true), 2, 2, rng) else 1
	check(refused > 100, "a loyal, happy player usually turns down a sideways move (%d of 200)" % refused)
	var steady_rng := _rng(5)
	var warm := {"sociability": 15, "temperament": 14, "ego": 5, "professionalism": 14, "happiness": 10}
	var proud := {"sociability": 7, "temperament": 4, "ego": 18, "professionalism": 6, "happiness": -10}
	check(CareerPeople.scrim_reaction(warm, 0.5, 1.3, 1.0, 0, steady_rng) > 0, "a humble, sociable teammate warms to you after a good win")
	check(CareerPeople.scrim_reaction(proud, -0.6, 1.0, 1.0, 0, steady_rng) < CareerPeople.scrim_reaction(warm, -0.6, 1.0, 1.0, 0, steady_rng),
		"a heavy loss hits a volatile teammate harder")
	check(CareerPeople.scrim_reaction(proud, 0.0, 1.6, 0.8, 0, steady_rng) < CareerPeople.scrim_reaction(warm, 0.0, 1.6, 0.8, 0, steady_rng),
		"outplaying an ego stings; outplaying a humble teammate earns respect")
	check(CareerPeople.scrim_reaction(warm, 0.8, 1.2, 1.0, 0, steady_rng) > CareerPeople.scrim_reaction(warm, 0.05, 1.2, 1.0, 0, steady_rng),
		"a big win brings people closer than a narrow one")
	var social := {"sociability": 16, "temperament": 14, "ego": 9}
	var clash := {"sociability": 3, "temperament": 4, "ego": 17}
	check(CareerPeople.compatibility(social, social) > 2.0 and CareerPeople.compatibility(clash, clash) < 0.0,
		"sociable people get on; two volatile egos clash")


func _test_voice() -> void:
	section("Voice")
	var rng := _rng(3)
	for topic: String in PersonVoice.ANSWERS:
		for tone: String in (PersonVoice.ANSWERS[topic] as Dictionary):
			check(not (PersonVoice.ANSWERS[topic][tone] as Array).is_empty(), "%s answers exist in a %s voice" % [topic, tone])
	var fiery := {"ego": 10, "temperament": 3}
	var humble := {"ego": 4, "temperament": 14}
	check(PersonVoice.tone(fiery) == "fiery" and PersonVoice.tone(humble) == "humble", "temperament and ego set the voice")
	var said := PersonVoice.answer(humble, "new_club", "Old Club", "New Club", rng)
	check(not said.is_empty() and not said.contains("%"), "answers fill in the clubs (%s)" % said)
	check(PersonVoice.descriptors({"ambition": 18, "loyalty": 3}) == PackedStringArray(["Driven", "Restless"])
		and PersonVoice.descriptors({}) == PackedStringArray(["Balanced"]), "descriptors read like a scouting report")


func _test_world(app: Node) -> void:
	section("People in a career")
	var problem: String = app.call("new_career", "People tests", PROFILE)
	check(problem.is_empty(), "creates a career")
	if not problem.is_empty():
		return
	var session := app.get("career") as CareerSession
	var repo := session.repo
	check(repo.players_without_person().is_empty() and repo.person(session.human_player_id).is_empty(),
		"every AI professional starts as a person; the human has no person row")
	var day := repo.current_day()
	var rng := _rng(99)
	for month: int in 8:
		day += 30
		check(CareerPeople.monthly(repo, day, rng), "month %d of moods, relationships and life runs" % (month + 1))
	var bonds := repo.relationships()
	var friends := 0
	var rivals := 0
	for key: String in bonds:
		friends += 1 if bonds[key] >= CareerPeople.FRIEND_LEVEL else 0
		rivals += 1 if bonds[key] <= CareerPeople.RIVAL_LEVEL else 0
	check(bonds.size() > 100, "teammates form relationships (%d pairs)" % bonds.size())
	check(friends > 0 and rivals > 0 and friends + rivals < bonds.size() / 2,
		"some become friends (%d), some rivals (%d); most just get along" % [friends, rivals])
	var spread := repo.db.rows("SELECT MIN(happiness) AS low, MAX(happiness) AS high, SUM(wants_move) AS unsettled FROM person;")[0]
	check(int(spread["high"]) - int(spread["low"]) >= 20, "moods differ from person to person (%d to %d, %d want a move)" % [
		int(spread["low"]), int(spread["high"]), int(spread["unsettled"])])
	var any_player := str(repo.contracted_players().filter(func(c: Dictionary) -> bool: return int(c["is_human"]) == 0)[0]["player_id"])
	var contract := repo.active_contract(any_player)
	check(CareerPeople.interview(repo, any_player, contract.organisation_id, "star", "Rivals", WorldSimulation.MINOR, day, rng)
		and repo.news_about(any_player, "", 5).any(func(n: Dictionary) -> bool: return str(n["kind"]) == WorldSimulation.NEWS_INTERVIEW),
		"players give interviews in their own voice")
	var lineup := repo.lineup(contract.organisation_id)
	var team := CareerSeriesEngine.sim_team(repo, contract.organisation_id, lineup)
	for i: int in team.players.size():
		for j: int in range(i + 1, team.players.size()):
			repo.set_relationship(team.players[i].id, team.players[j].id, 80, day)
	var close := CareerSeriesEngine.sim_team(repo, contract.organisation_id, lineup)
	for i: int in team.players.size():
		for j: int in range(i + 1, team.players.size()):
			repo.set_relationship(team.players[i].id, team.players[j].id, -80, day)
	var split := CareerSeriesEngine.sim_team(repo, contract.organisation_id, lineup)
	check(close.chemistry > 5.0 and split.chemistry < -5.0, "friends coordinate better in matches; rivals worse")
	app.call("open_career_hub")
	await wait_frames(3)
	var hub := tree.current_scene
	hub.call("navigate", &"player", {"player_id": any_player})
	await wait_frames(1)
	var text := _text_of(hub.get("current_page") as Node)
	check(text.contains("The person") and text.contains("Career goal") and text.contains("Relationships"),
		"a player's page shows who they are")
	hub.call("navigate", &"team", {"org_id": contract.organisation_id, "tab": "squad"})
	await wait_frames(1)
	check(_text_of(hub.get("current_page") as Node).contains("Dressing room"), "the squad shows the dressing room")


func _text_of(node: Node) -> String:
	if node == null:
		return ""
	var parts: PackedStringArray = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	elif node is LinkButton:
		parts.append((node as LinkButton).text)
	for child: Node in node.get_children():
		parts.append(_text_of(child))
	return " ".join(parts)


func _clean(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_clean(folder.path_join(child))
	DirAccess.remove_absolute(folder)
