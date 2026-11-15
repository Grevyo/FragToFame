class_name CareerCalendar
extends RefCounted
## Moves a career's date forward. Every day that passes resolves the organisation series that
## were due on it ([SeriesSimulator]) and publishes the new year's league seasons at a year
## boundary, all in one transaction with the date change.
##
## Series involving an organisation that has a human under contract are never simulated: those
## are the player's own matches (playable league series arrive once humans can sign for an
## organisation, Milestone 14).

const BLOCKED_BY_FIXTURE: String = "You have a match scheduled. Play it before moving to the next day."


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
		if not _simulate_due_series(repo, day, dice):
			return false
		for year: int in range(GameDate.year_of(previous) + 1, GameDate.year_of(day) + 1):
			if not CareerCompetitions.ensure_league_seasons(repo, year):
				return false
		return repo.set_current_day(day))


## Mean simulated ability of an organisation's five starters (perceived values for humans,
## whose real skill is never simulated). 0 when the organisation fields nobody.
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
	return total / count if count > 0 else 0.0


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
		var score := SeriesSimulator.simulate(rng, strength[home], strength[away], int(fixture["best_of"]))
		if not repo.store_league_score(int(fixture["id"]), score.x, score.y):
			return false
	return true
