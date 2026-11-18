class_name CareerProfilePage
extends CareerPage

var spending_status: Label


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
	var training := UIFactory.card(self, "Training")
	training.add_child(UIFactory.label("Train for real on the training ground: drills and scrims you play yourself.", &"MutedLabel", true))
	training.add_child(link("Open the training ground", &"training", {}))
	_build_spending(session, me.id)
	PlayerView.build(self, session.repo, me.id)


## Your own money: balance, monthly services (hire / cancel) and the bootcamp.
func _build_spending(session: CareerSession, player_id: String) -> void:
	var repo := session.repo
	var card := UIFactory.card(self, "Your money · %s" % CareerCatalog.format_money(repo.player_balance(player_id)))
	card.add_child(UIFactory.label("Earn from salary, season bonuses and amateur wins (%s each). Spending only changes "
		% CareerCatalog.format_money(CareerSpending.AMATEUR_WIN_PRIZE)
		+ "how the career world sees you; it never changes how you aim or move in a match.", &"MutedLabel", true))
	spending_status = UIFactory.label("", &"WarningLabel", true)
	var active := repo.services(player_id)
	for service_id: String in CareerSpending.SERVICES:
		var entry: Array = CareerSpending.SERVICES[service_id]
		var row := UIFactory.hbox(8)
		var caption := UIFactory.label("%s · %s a month · %s" % [entry[0], CareerCatalog.format_money(int(entry[1])), entry[2]], &"", true)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var hired := active.has(service_id)
		var button := UIFactory.button("Cancel" if hired else "Hire", &"" if hired else &"AccentButton")
		button.pressed.connect(func() -> void: spend(service_id, not hired))
		row.add_child(button)
		card.add_child(row)
	var camp := UIFactory.hbox(8)
	var wait := CareerSpending.bootcamp_wait(repo, player_id)
	var camp_text := UIFactory.label("Bootcamp · %s once · game sense, teamwork, communication and utility +1, more scouting confidence%s" % [
		CareerCatalog.format_money(CareerSpending.BOOTCAMP_COST), "" if wait == 0 else " · available in %d days" % wait], &"", true)
	camp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camp.add_child(camp_text)
	var book := UIFactory.button("Book bootcamp", &"AccentButton")
	book.disabled = wait > 0
	book.pressed.connect(func() -> void: spend(CareerSpending.BOOTCAMP_ID, true))
	camp.add_child(book)
	card.add_child(camp)
	card.add_child(spending_status)


## Hires (or cancels) a service, or books the bootcamp; rebuilds the page. Returns "" or why not.
func spend(item_id: String, buy: bool) -> String:
	var problem := ""
	if item_id == CareerSpending.BOOTCAMP_ID:
		problem = App.buy_career_bootcamp()
	else:
		problem = App.hire_career_service(item_id) if buy else App.cancel_career_service(item_id)
	if not problem.is_empty():
		spending_status.text = problem
		return problem
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	build_page()
	return ""
