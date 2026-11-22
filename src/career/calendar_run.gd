class_name CalendarRun
extends RefCounted
## A Continue or a holiday played one day at a time, so the hub can show each day passing
## ([CareerCalendarOverlay]) instead of freezing until it is over. [method step] does one day (or,
## on a holiday that simulates the player's matches, one match); [method run_all] runs to the end
## in one go, which is what [method CareerCalendar.continue_until_event] and
## [method CareerCalendar.holiday] do. The rules for when a run stops live here.

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
## Days run so far (Continue).
var days: int = 0
## Set by the player to end the run after the current day.
var stop_requested: bool = false
## The finished run's outcome ({days, reason, ok}, plus "simulated" on a holiday); empty while running.
var outcome: Dictionary = {}


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


## Runs one day (or one simulated match). Returns true while the run goes on.
func step() -> bool:
	if is_finished():
		return false
	if kind == Kind.CONTINUE:
		_continue_step()
	else:
		_holiday_step()
	return not is_finished()


## Runs to the end and returns the outcome.
func run_all() -> Dictionary:
	while step():
		pass
	return outcome


func _continue_step() -> void:
	if stop_requested:
		outcome = {"days": days, "reason": STOPPED, "ok": days > 0}
		return
	var problem := CareerCalendar.advance_day(repo, player_id, dice)
	if not problem.is_empty():
		outcome = {"days": days, "reason": problem, "ok": days > 0}
		return
	days += 1
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


func _holiday_step() -> void:
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
		return
	var problem := CareerCalendar.advance_day(repo, player_id, dice)
	if not problem.is_empty():
		_holiday_end(problem)
		return
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
