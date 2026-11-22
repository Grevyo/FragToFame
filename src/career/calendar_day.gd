class_name CalendarDay
extends RefCounted
## One day passing, as timed events played one at a time: first the previous day's series at
## their kick-offs (the afternoon and evening of the day being left), then the new day's morning
## in the world ([method WorldSimulation.day_phases]: finances, competitions, the market, offers,
## match bookings). The whole day is one transaction (opened by [method start], committed after
## the last event together with the new date), so stopping or failing never leaves half a day.
##
## Series involving an organisation with a human in its starting five are never simulated: those
## are the player's own matches. A benched human's organisation is simulated without them.

var repo: CareerRepository
## The day being entered.
var day: int = 0
var dice: RandomNumberGenerator
## {kind: "series"|"world", day, minute, label, ...}: "series" carries the fixture row, "world"
## the phase's work.
var events: Array[Dictionary] = []
var _next: int = 0
var _open: bool = false
var _failed: bool = false
## Series played so far this day.
var series_played: int = 0


## Opens the day's transaction and lists its events. Returns null when the transaction cannot open.
static func start(career_repo: CareerRepository, new_day: int, rng: RandomNumberGenerator) -> CalendarDay:
	if not career_repo.begin_transaction():
		return null
	var calendar_day := CalendarDay.new()
	calendar_day.repo = career_repo
	calendar_day.day = new_day
	calendar_day.dice = rng
	calendar_day._open = true
	calendar_day._list_events()
	return calendar_day


func _list_events() -> void:
	var human_org: Dictionary[String, bool] = {}
	for fixture: Dictionary in repo.unresolved_league_fixtures(day):
		var home := str(fixture["home_id"])
		var away := str(fixture["away_id"])
		for org_id: String in [home, away]:
			if not human_org.has(org_id):
				human_org[org_id] = repo.organisation_has_human_starter(org_id)
		if human_org[home] or human_org[away]:
			continue
		events.append({"kind": "series", "day": int(fixture["scheduled_day"]), "minute": int(fixture["kick_off"]),
			"label": "%s vs %s" % [fixture["home_name"], fixture["away_name"]], "detail": str(fixture["competition_name"]),
			"fixture": fixture})
	for phase: Dictionary in WorldSimulation.day_phases(day):
		events.append({"kind": "world", "day": day, "minute": int(phase["minute"]), "label": str(phase["label"]),
			"detail": "", "work": phase["work"]})


func is_finished() -> bool:
	return not _open


## False once an event (or the commit) failed; the day was rolled back.
func succeeded() -> bool:
	return not _open and not _failed


## The next event to run ({} when none is left).
func upcoming() -> Dictionary:
	return events[_next] if _next < events.size() else {}


## The event that ran last ({} before the first).
func last() -> Dictionary:
	return events[_next - 1] if _next > 0 and _next <= events.size() else {}


## Runs the next event; after the last one sets the new date and commits. Returns true while
## the day goes on.
func step() -> bool:
	if not _open:
		return false
	if _next < events.size():
		var event := events[_next]
		_next += 1
		if not _run(event):
			_close(false)
			return false
		if _next < events.size():
			return true
	_close(repo.set_current_day(day))
	return false


## Runs the whole day. Returns whether it stands.
func run_all() -> bool:
	while step():
		pass
	return succeeded()


func _run(event: Dictionary) -> bool:
	if str(event["kind"]) == "world":
		return (event["work"] as Callable).call(repo, day, dice)
	var fixture := event["fixture"] as Dictionary
	var home := str(fixture["home_id"])
	var away := str(fixture["away_id"])
	var score := CareerSeriesEngine.play_series(repo, fixture, int(fixture["scheduled_day"]), dice)
	if score.x < 0 or not repo.store_league_score(int(fixture["id"]), score.x, score.y):
		return false
	series_played += 1
	event["score"] = score
	return WorldSimulation.apply_series(repo, home, away, score, int(fixture["best_of"]), int(fixture["tier"]), day, dice)


func _close(ok: bool) -> void:
	_open = false
	_failed = not repo.end_transaction(ok)
