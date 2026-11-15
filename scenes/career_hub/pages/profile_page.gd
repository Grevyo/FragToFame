class_name CareerProfilePage
extends CareerPage


func get_page_title() -> String:
	return "Player Profile"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var me := session.human()
	if me == null:
		add_child(UIFactory.label("This career has no human professional.", &"WarningLabel"))
		return
	_build_training(session, me.id)
	PlayerView.build(self, session.repo, me.id)


func _build_training(session: CareerSession, player_id: String) -> void:
	var card := UIFactory.card(self, "Training")
	var completed := session.repo.development_today(player_id, CareerDevelopment.TRAINING)
	if not completed.is_empty():
		var ability := StringName(str(completed["focus"]))
		card.add_child(UIFactory.label("Practised %s today · perceived attribute +%d" % [
			CareerCatalog.ability_name(ability), int(completed["change"])], &"AccentLabel", true))
		return

	card.add_child(UIFactory.label(
		"Choose one focus to practise today. Training updates the career world's opinion of your ability.",
		&"MutedLabel", true))
	var row := UIFactory.hbox()
	card.add_child(row)
	var focus := OptionButton.new()
	for ability: StringName in CareerCatalog.ABILITIES:
		focus.add_item(CareerCatalog.ability_name(ability))
	row.add_child(focus)
	var train := UIFactory.button("Train today", &"AccentButton")
	row.add_child(train)
	var status := UIFactory.label("", &"WarningLabel", true)
	card.add_child(status)
	train.pressed.connect(func() -> void:
		var problem := CareerDevelopment.train(session.repo, player_id, CareerCatalog.ABILITIES[focus.selected])
		if not problem.is_empty():
			status.text = problem
			return
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		build_page())
