class_name CareerCalendar
extends RefCounted
## Moves a career's date forward one day at a time. Each day that passes first resolves the
## organisation series that were due before it ([SeriesSimulator], feeding form and reputation),
## then runs the living world for that day ([WorldSimulation]: market, development, retirements,
## rookies, new seasons and news), all in one transaction with the date change.
##
## Series involving an organisation that has a human under contract are never simulated: those
## are the player's own matches (playable league series arrive once humans can sign for an
## organisation, Milestone 14).

const BLOCKED_BY_FIXTURE: String = "You have a match scheduled. Play it before moving to the next day."
## Continue never runs further than this without stopping.
const CONTINUE_LIMIT: int = 31
const MATCH_DAY: String = "Match day: your scheduled match is today."
const QUIET_MONTH: String = "A month passed with nothing that needs you."


## Advances one day for the human [param player_id]. Refused while that player has an
## unplayed fixture due today or earlier (a calendar conflict). Returns "" or the reason.
static func advance_day(repo: CareerRepository, player_id: String, rng: RandomNumberGenerator = null) -> String:
	var pending := repo.pending_fixture(player_id)
	if pending != null and pending.scheduled_day <= repo.current_day():
		return BLOCKED_BY_FIXTURE
	if not advance_to(repo, repo.current_day() + 1, rng):
		return "Could not advance the calendar: %s" % repo.db.last_error
	return ""


## Sets the date to [param day] (never backwards), resolving everything due on the days that
## passed. Joins an enclosing transaction (fixture results call it while saving the score).
static func advance_to(repo: CareerRepository, day: int, rng: RandomNumberGenerator = null) -> bool:
	var previous := repo.current_day()
	if day <= previous:
		return true
	var dice := rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	return repo.transaction(func() -> bool:
		for today: int in range(previous + 1, day + 1):
			if not _simulate_due_series(repo, today, dice) or not WorldSimulation.simulate_day(repo, today, dice):
				return false
		return repo.set_current_day(day))


## FM-style Continue: advances day by day until something needs the player — their match is
## due, a headline story breaks (contract news, a new year, their league starting) — or
## [constant CONTINUE_LIMIT] days pass. Returns {days: int, reason: String, ok: bool}; ok is
## false when not even one day could pass (reason says why).
static func continue_until_event(repo: CareerRepository, player_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var dice := rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	var days := 0
	while days < CONTINUE_LIMIT:
		var problem := advance_day(repo, player_id, dice)
		if not problem.is_empty():
			return {"days": days, "reason": problem, "ok": days > 0}
		days += 1
		var today := repo.current_day()
		var pending := repo.pending_fixture(player_id)
		if pending != null and pending.scheduled_day <= today:
			return {"days": days, "reason": MATCH_DAY, "ok": true}
		var headlines := repo.news_on(today, WorldSimulation.HEADLINE)
		if not headlines.is_empty():
			return {"days": days, "reason": str(headlines[0]["headline"]), "ok": true}
	return {"days": days, "reason": QUIET_MONTH, "ok": true}


## Mean simulated ability of an organisation's five starters (perceived values for humans,
## whose real skill is never simulated) plus its form bonus. 0 when the organisation fields nobody.
static func organisation_strength(repo: CareerRepository, org_id: String) -> float:
	var total := 0.0
	var count := 0
	for entry: Dictionary in repo.lineup(org_id):
		var values: Dictionary = entry["abilities"]
		if bool(entry["is_human"]):
			total += repo.perceived_rating(str(entry["player_id"]))
			count += 1
			continue
		for value: Variant in values.values():
			total += float(value)
			count += 1
	return total / count + WorldSimulation.form_bonus(repo, org_id) if count > 0 else 0.0


static func _simulate_due_series(repo: CareerRepository, before_day: int, rng: RandomNumberGenerator) -> bool:
	var strength: Dictionary[String, float] = {}
	var human_org: Dictionary[String, bool] = {}
	for fixture: Dictionary in repo.unresolved_league_fixtures(before_day):
		var home := str(fixture["home_id"])
		var away := str(fixture["away_id"])
		for org_id: String in [home, away]:
			if not strength.has(org_id):
				strength[org_id] = organisation_strength(repo, org_id)
				human_org[org_id] = repo.organisation_has_human(org_id)
		if human_org[home] or human_org[away]:
			continue
		var best_of := int(fixture["best_of"])
		var score := SeriesSimulator.simulate(rng, strength[home], strength[away], best_of)
		if not repo.store_league_score(int(fixture["id"]), score.x, score.y):
			return false
		if not WorldSimulation.apply_series(repo, home, away, score, best_of, int(fixture["tier"]), before_day, rng):
			return false
		# Form moved: later series on the same jump see it.
		strength.erase(home)
		strength.erase(away)
	return true
