class_name CareerSpending
extends RefCounted
## What a human professional can spend their own money on. Everything here works on the career
## layer only: perceived values (what the world believes), reputation, visibility and the
## sessions a bootcamp asks you to play. Nothing changes aim, recoil, movement or reaction in a
## match: the person playing is the skill.
##
## Monthly services are charged on the first of each month ([WorldFinance]); one that can no
## longer be paid ends, with a headline. The bootcamp is a one-off purchase with a cooldown.

## id → [name, monthly fee, what it does]
const SERVICES: Dictionary[String, Array] = {
	"coach": ["Personal coach", 600, "Reviews your drills, so each session says more about you to the world."],
	"pr_agent": ["PR agent", 400, "Sells your month to the scene: the more you played and the better you did, the more your reputation grows. Hype beyond your level backfires."],
}
## How far (points) reputation may run ahead of perceived ability before PR spin turns on you.
const PR_HYPE_RANGE: float = 15.0
## Bootcamp: a week-long programme of real sessions, played by you ([CareerTraining]). Booking it
## opens the programme; what you get out of it is what you play.
const BOOTCAMP_ID: String = "bootcamp"
const BOOTCAMP_COST: int = 2500
const BOOTCAMP_COOLDOWN: int = 180
## The programme: every drill and a scrim, within [constant BOOTCAMP_DAYS] days of booking.
const BOOTCAMP_PROGRAMME: Array[StringName] = [TrainingDrills.FLICK, TrainingDrills.REACTION, TrainingDrills.TRACKING,
	TrainingDrills.MOVEMENT, TrainingDrills.SCRIM]
const BOOTCAMP_DAYS: int = 7
## Programme sessions are reviewed by the camp's staff; what finishing it does depends on how
## the week went ([CareerTraining]).
## Amateur match winnings (paid to the human for each win).
const AMATEUR_WIN_PRIZE: int = 150


static func service_name(service_id: String) -> String:
	return str(SERVICES[service_id][0]) if SERVICES.has(service_id) else service_id


static func has_service(repo: CareerRepository, player_id: String, service_id: String) -> bool:
	return repo.services(player_id).has(service_id)


## Hires a monthly service, paying the first month now. Returns "" or why not.
static func hire(repo: CareerRepository, player_id: String, service_id: String) -> String:
	if not SERVICES.has(service_id) or repo.human_profile(player_id).is_empty():
		return "That service is not available."
	if has_service(repo, player_id, service_id):
		return "You already have a %s." % service_name(service_id).to_lower()
	var fee := int(SERVICES[service_id][1])
	if repo.player_balance(player_id) < fee:
		return "You need %s for the first month." % CareerCatalog.format_money(fee)
	var day := repo.current_day()
	var ok := repo.transaction(func() -> bool:
		return repo.add_service(player_id, service_id, day) and repo.add_player_money(player_id, -fee, day, "expense",
			"%s · first month" % service_name(service_id)))
	return "" if ok else "Could not hire the service."


static func cancel(repo: CareerRepository, player_id: String, service_id: String) -> String:
	if not has_service(repo, player_id, service_id):
		return "You do not have that service."
	return "" if repo.remove_service(player_id, service_id) else "Could not cancel the service."


## Days until the bootcamp can be bought again (0 = now).
static func bootcamp_wait(repo: CareerRepository, player_id: String) -> int:
	var last := repo.last_purchase(player_id, BOOTCAMP_ID)
	return 0 if last < 0 else maxi(0, last + BOOTCAMP_COOLDOWN - repo.current_day())


## The current or latest bootcamp: {booked, active, start_day, end_day, done: Array[String],
## complete}. "Active" means booked, within its week and not yet complete.
static func bootcamp_state(repo: CareerRepository, player_id: String) -> Dictionary:
	var start := repo.last_purchase(player_id, BOOTCAMP_ID)
	if start < 0:
		return {"booked": false, "active": false, "start_day": -1, "end_day": -1, "done": [] as Array[String], "complete": false}
	var done := repo.bootcamp_done(player_id, start)
	var complete := BOOTCAMP_PROGRAMME.all(func(id: StringName) -> bool: return done.has(String(id)))
	var end_day := start + BOOTCAMP_DAYS - 1
	return {"booked": true, "active": not complete and repo.current_day() <= end_day, "start_day": start, "end_day": end_day,
		"done": done, "complete": complete}


## Books a bootcamp: opens the week's programme of sessions on the Training Ground.
static func buy_bootcamp(repo: CareerRepository, player_id: String) -> String:
	if repo.human_profile(player_id).is_empty():
		return "Only your career player can attend a bootcamp."
	var wait := bootcamp_wait(repo, player_id)
	if wait > 0:
		return "Your next bootcamp is available in %d days." % wait
	if repo.player_balance(player_id) < BOOTCAMP_COST:
		return "A bootcamp costs %s." % CareerCatalog.format_money(BOOTCAMP_COST)
	var day := repo.current_day()
	var ok := repo.transaction(func() -> bool:
		return repo.add_player_money(player_id, -BOOTCAMP_COST, day, "expense", "Bootcamp") \
			and repo.add_purchase(player_id, BOOTCAMP_ID, day))
	return "" if ok else "Could not book the bootcamp."


## Monthly: charges every service; one the human cannot pay ends. The PR agent works here.
static func monthly(repo: CareerRepository, day: int) -> bool:
	for found: Dictionary in repo.all_services():
		var player_id := str(found["player_id"])
		var service_id := str(found["service_id"])
		if not SERVICES.has(service_id):
			continue
		var fee := int(SERVICES[service_id][1])
		if repo.player_balance(player_id) < fee:
			if not repo.remove_service(player_id, service_id) or not repo.add_news(day, WorldSimulation.NEWS_CONTRACT,
					WorldSimulation.HEADLINE, "You could not pay your %s, so the service has ended." %
					service_name(service_id).to_lower(), player_id):
				return false
			continue
		if not repo.add_player_money(player_id, -fee, day, "expense", service_name(service_id)):
			return false
		if service_id == "pr_agent":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%s|pr|%d" % [player_id, day])
			var reputation := repo.reputation(player_id)
			var change := pr_effect(repo.form_since(player_id, day - 30), reputation, repo.perceived_rating(player_id), rng)
			if change != 0 and not repo.set_reputation(player_id, clampi(reputation + change, 0, 100), day):
				return false
	return true


## What a month of PR does to reputation. The agent sells the story you gave them: how much you
## played, how well ([param form] from [method CareerRepository.form_since]) and how often you
## won. It works best when your reputation lags what the world thinks of your ability; with
## nothing to sell little happens, and hype far beyond your level backfires. Pure.
static func pr_effect(form: Dictionary, reputation: int, ability: int, rng: RandomNumberGenerator) -> int:
	var maps := int(form.get("maps", 0))
	var material := 0.3
	if maps > 0:
		material = clampf(float(form.get("rating", 1.0)), 0.3, 2.0) * (0.6 + 0.4 * minf(maps / 8.0, 1.0)) \
			+ 0.5 * float(form.get("wins", 0)) / maps
	var headroom := clampf((ability - reputation) / PR_HYPE_RANGE, -1.5, 1.0)
	return roundi(material * (1.0 + headroom) * 1.2 + rng.randf_range(-0.5, 0.5))
