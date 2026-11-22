class_name CareerCalendar
extends RefCounted
## Moves a career's date forward one day at a time. Each day that passes is a [CalendarDay]:
## the series that were due before it at their kick-offs, round by round ([CareerSeriesEngine]),
## then the living world's morning ([WorldSimulation]: market, development, retirements, rookies,
## new seasons and news), all in one transaction with the date change.

const BLOCKED_BY_FIXTURE: String = "You have a match scheduled. Play it before moving to the next day."
## Continue never runs further than this without stopping.
const CONTINUE_LIMIT: int = 31
const MATCH_DAY: String = "Match day: your scheduled match is today."
const QUIET_MONTH: String = "A month passed with nothing that needs you."
## A holiday "until the next inbox message" ends after this many days at the latest.
const HOLIDAY_INBOX_LIMIT: int = 365


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
			var calendar_day := CalendarDay.start(repo, today, dice)
			if calendar_day == null or not calendar_day.run_all():
				return false
		return true)


## FM-style Continue: advances day by day until something needs the player — their match is
## due, a headline story breaks (contract news, a new year, their league starting) — or
## [constant CONTINUE_LIMIT] days pass. Returns {days: int, reason: String, ok: bool}; ok is
## false when not even one day could pass (reason says why).
## The hub runs the same [CalendarRun] a day at a time to show the days passing.
static func continue_until_event(repo: CareerRepository, player_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	return CalendarRun.continue_run(repo, player_id, rng).run_all()


## Holiday: runs days on its own. [param days] > 0 runs that many days; 0 runs until the next
## inbox message (a headline); -1 runs to the end of the year. The player's own match stops it,
## unless [param simulate_matches] (development) simulates the match instead. Returns
## {days, reason, ok, simulated}.
static func holiday(repo: CareerRepository, player_id: String, days: int, simulate_matches: bool,
		rng: RandomNumberGenerator = null) -> Dictionary:
	return CalendarRun.holiday_run(repo, player_id, days, simulate_matches, rng).run_all()


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
