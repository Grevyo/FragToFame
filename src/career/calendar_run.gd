class_name CalendarRun
extends RefCounted
## A Continue or a holiday played one event at a time, so the hub can show the days and the
## hours passing ([CareerCalendarOverlay]) instead of freezing until it is over. Each day is a
## [CalendarDay] (series at their kick-offs, then the world's morning); [method step] runs one of
## its events (or, on a holiday that simulates the player's matches, one match); [method run_all]
## runs to the end in one go, which is what [method CareerCalendar.continue_until_event] and
## [method CareerCalendar.holiday] do. The rules for when a run stops live here, and are only
## checked between days.

enum Kind { CONTINUE, HOLIDAY }

const STOPPED: String = "You stopped the calendar."

var kind: Kind = Kind.CONTINUE
var repo: CareerRepository
var player_id: String = ""
var dice: RandomNumberGenerator
## Day the run started on, and (holiday) the last day it may reach.
var start_day: int = 0
var target_day: int = 0
## Holiday: 0 stops at the next inbox message.
var requested_days: int = 0
var simulate_matches: bool = false
## Maps of the player's own matches simulated on a holiday.
var simulated: int = 0
## Days run so far.
var days: int = 0
## Series simulated so far.
var series_played: int = 0
## Set by the player to end the run before the next day starts.
var stop_requested: bool = false
## The finished run's outcome ({days, reason, ok}, plus "simulated" on a holiday); empty while running.
var outcome: Dictionary = {}
## The day being played, or null between days.
var _day: CalendarDay = null
## What happened last: {day, minute, label, detail, kind} ({} before anything has).
var _now: Dictionary = {}


static func continue_run(career_repo: CareerRepository, human_id: String, rng: RandomNumberGenerator = null) -> CalendarRun:
	var run := CalendarRun.new()
	run.kind = Kind.CONTINUE
	run._setup(career_repo, human_id, rng)
	return run


## [param length] > 0 runs that many days; 0 runs until the next inbox message (a headline); -1
## runs to the end of the year. [param simulate_own] (development) simulates the player's matches
## instead of stopping for them.
static func holiday_run(career_repo: CareerRepository, human_id: String, length: int, simulate_own: bool,
		rng: RandomNumberGenerator = null) -> CalendarRun:
	var run := CalendarRun.new()
	run.kind = Kind.HOLIDAY
	run._setup(career_repo, human_id, rng)
	run.requested_days = length
	run.simulate_matches = simulate_own
	run.target_day = run.start_day + length
	if length == 0:
		run.target_day = run.start_day + CareerCalendar.HOLIDAY_INBOX_LIMIT
	elif length < 0:
		run.target_day = GameDate.make(GameDate.year_of(run.start_day) + 1, 1, 1) - 1
	return run


## A run that cannot start ([param reason]); already finished.
static func refused(reason: String, holiday: bool) -> CalendarRun:
	var run := CalendarRun.new()
	run.kind = Kind.HOLIDAY if holiday else Kind.CONTINUE
	run.outcome = {"days": 0, "reason": reason, "ok": false}
	if holiday:
		run.outcome["simulated"] = 0
	return run


func _setup(career_repo: CareerRepository, human_id: String, rng: RandomNumberGenerator) -> void:
	repo = career_repo
	player_id = human_id
	dice = rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	start_day = repo.current_day()


func is_finished() -> bool:
	return not outcome.is_empty()


## Days the run is allowed to go (for a progress bar); 0 when open-ended.
func planned_days() -> int:
	if kind == Kind.CONTINUE:
		return CareerCalendar.CONTINUE_LIMIT
	return target_day - start_day if requested_days != 0 else 0


## What happened last: {day, minute, label, detail, kind ("series", "world", "match")}; {}
## before the first event.
func now() -> Dictionary:
	return _now


## Runs one event. Returns true while the run goes on.
func step() -> bool:
	if is_finished():
		return false
	if _day != null:
		_step_day()
	elif kind == Kind.CONTINUE:
		_start_continue_day()
	else:
		_start_holiday_day()
	return not is_finished()


## Runs to the end and returns the outcome.
func run_all() -> Dictionary:
	while step():
		pass
	return outcome


## Opens the next day (the first event runs on the next step). Returns false when it could not.
func _open_day() -> bool:
	_day = CalendarDay.start(repo, repo.current_day() + 1, dice)
	return _day != null


func _step_day() -> void:
	var before := _day.series_played
	var going := _day.step()
	series_played += _day.series_played - before
	var event := _day.last()
	if not event.is_empty():
		_now = {"day": int(event["day"]), "minute": int(event["minute"]), "label": str(event["label"]),
			"detail": str(event["detail"]), "kind": str(event["kind"])}
		if event.has("score"):
			var score: Vector2i = event["score"]
			_now["score"] = [score.x, score.y]
	if going:
		return
	var finished_ok := _day.succeeded()
	_day = null
	if not finished_ok:
		_fail("Could not advance the calendar: %s" % repo.db.last_error)
		return
	days += 1
	_now = {"day": repo.current_day(), "minute": 13 * 60, "label": "", "detail": "", "kind": "world"}
	if kind == Kind.CONTINUE:
		_end_of_continue_day()
	else:
		_end_of_holiday_day()


func _fail(reason: String) -> void:
	if kind == Kind.CONTINUE:
		outcome = {"days": days, "reason": reason, "ok": days > 0}
	else:
		_holiday_end(reason)


func _start_continue_day() -> void:
	if stop_requested:
		outcome = {"days": days, "reason": STOPPED, "ok": days > 0}
		return
	var pending := repo.pending_fixture(player_id)
	if pending != null and pending.scheduled_day <= repo.current_day():
		outcome = {"days": days, "reason": CareerCalendar.BLOCKED_BY_FIXTURE, "ok": days > 0}
		return
	if not _open_day():
		_fail("Could not advance the calendar: %s" % repo.db.last_error)
		return
	_step_day()


func _end_of_continue_day() -> void:
	var today := repo.current_day()
	var pending := repo.pending_fixture(player_id)
	if pending != null and pending.scheduled_day <= today:
		outcome = {"days": days, "reason": CareerCalendar.MATCH_DAY, "ok": true}
		return
	var headlines := repo.news_on(today, WorldSimulation.HEADLINE)
	if not headlines.is_empty():
		outcome = {"days": days, "reason": str(headlines[0]["headline"]), "ok": true}
	elif days >= CareerCalendar.CONTINUE_LIMIT:
		outcome = {"days": days, "reason": CareerCalendar.QUIET_MONTH, "ok": true}


func _start_holiday_day() -> void:
	if stop_requested:
		_holiday_end(STOPPED)
		return
	if repo.current_day() >= target_day:
		_holiday_end("Back from holiday.")
		return
	var pending := repo.pending_fixture(player_id)
	if pending != null and pending.scheduled_day <= repo.current_day():
		if not simulate_matches:
			_holiday_end(CareerCalendar.MATCH_DAY)
			return
		var played := CareerMatchSimulator.simulate_pending(repo, player_id, dice)
		if not bool(played["ok"]):
			_holiday_end(str(played["message"]))
			return
		simulated += int(played["maps"])
		_now = {"day": repo.current_day(), "minute": pending.kick_off, "label": "%s vs %s" % [pending.setup.home_team_name,
			pending.setup.away_team_name], "detail": "Your match (simulated)", "kind": "match"}
		return
	if not _open_day():
		_holiday_end("Could not advance the calendar: %s" % repo.db.last_error)
		return
	_step_day()


func _end_of_holiday_day() -> void:
	if requested_days == 0:
		var headlines := repo.news_on(repo.current_day(), WorldSimulation.HEADLINE)
		if not headlines.is_empty():
			_holiday_end(str(headlines[0]["headline"]))
			return
	if repo.current_day() >= target_day:
		_holiday_end("Back from holiday.")


func _holiday_end(reason: String) -> void:
	var passed := repo.current_day() - start_day
	var text := "%d day%s · %s" % [passed, "" if passed == 1 else "s", reason]
	if simulated > 0:
		text += " (%d of your maps simulated)" % simulated
	outcome = {"days": passed, "reason": text, "ok": passed > 0 or simulated > 0, "simulated": simulated}
