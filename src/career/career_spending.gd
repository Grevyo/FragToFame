class_name CareerSpending
extends RefCounted
## What a human professional can spend their own money on. Everything here works on the career
## layer only: perceived values (what the world believes), reputation and visibility. Nothing
## changes aim, recoil, movement or reaction in a match: the person playing is the skill.
##
## Monthly services are charged on the first of each month ([WorldFinance]); one that can no
## longer be paid ends, with a headline. The bootcamp is a one-off purchase with a cooldown.

## id → [name, monthly fee, what it does]
const SERVICES: Dictionary[String, Array] = {
	"coach": ["Personal coach", 600, "Training raises the perceived attribute by 2 instead of 1."],
	"pr_agent": ["PR agent", 400, "Reputation +1 each month while below 70, so organisations notice you sooner."],
}
const PR_REPUTATION_CAP: int = 70
const COACH_TRAINING_GAIN: int = 2
## Bootcamp: a one-off week of structured practice the scene hears about.
const BOOTCAMP_ID: String = "bootcamp"
const BOOTCAMP_COST: int = 2500
const BOOTCAMP_COOLDOWN: int = 180
const BOOTCAMP_ABILITIES: Array[StringName] = [&"game_sense", &"teamwork", &"communication", &"utility"]
const BOOTCAMP_CONFIDENCE: int = 5
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


## Buys a bootcamp: perceived teamwork-side attributes +1 and more scouting confidence.
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
		var seen := repo.perceived(player_id)
		var raised: Dictionary = {}
		for ability: StringName in BOOTCAMP_ABILITIES:
			raised[ability] = mini(int(seen.get(ability, 50)) + 1, 99)
		return repo.add_player_money(player_id, -BOOTCAMP_COST, day, "expense", "Bootcamp") \
			and repo.add_purchase(player_id, BOOTCAMP_ID, day) \
			and repo.set_perceived(player_id, raised, mini(repo.perceived_confidence(player_id) + BOOTCAMP_CONFIDENCE, 95), day))
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
		var reputation := repo.reputation(player_id)
		if service_id == "pr_agent" and reputation < PR_REPUTATION_CAP and not repo.set_reputation(player_id, reputation + 1, day):
			return false
	return true
