class_name TrainingSession
extends RefCounted
## The rules of one drill run, without nodes: a countdown, then the drill's own loop. The
## runtime ([code]TrainingDirector[/code]) feeds it time, shots, hits and course zones, and moves
## a target where [signal target_requested] says.

## Show the target at marker [param index] (standing and hittable).
signal target_requested(index: int)
## Hide the target.
signal target_cleared()
signal finished(result: TrainingResult)

enum Phase { COUNTDOWN, RUNNING, DONE }

var drill_id: StringName
var phase: Phase = Phase.COUNTDOWN
## Seconds left in the countdown, then seconds since the drill started.
var countdown: float = TrainingDrills.COUNTDOWN
var elapsed: float = 0.0
var marker_count: int = 0
var checkpoint_total: int = 0
var par: float = TrainingDrills.COURSE_PAR

var shots: int = 0
var hits: int = 0
var headshots: int = 0
var kills: int = 0
var damage: int = 0
## Reaction test.
var rep: int = 0
var reaction_times: Array[float] = []
var false_starts: int = 0
var misses: int = 0
## Movement course.
var course_started: bool = false
var course_time: float = 0.0
var checkpoints_reached: int = 0
var resets: int = 0
var course_finished: bool = false

var _rng: RandomNumberGenerator
var _definition: Dictionary
var _target_index: int = -1
var _target_up: bool = false
## Reaction: seconds until the target appears (>= 0 while waiting), time it has been up.
var _wait_left: float = -1.0
var _up_for: float = 0.0
## Tracking: seconds until the downed target stands again.
var _respawn_left: float = -1.0
var _result: TrainingResult


func _init(drill: StringName, markers: int, rng: RandomNumberGenerator = null, checkpoints: int = 0) -> void:
	drill_id = drill
	_definition = TrainingDrills.DRILLS.get(drill, {})
	marker_count = maxi(markers, 0)
	checkpoint_total = maxi(checkpoints, 0)
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()


func duration() -> float:
	return float(_definition.get("duration", 0.0))


## Seconds left on a timed drill (0 for untimed drills).
func time_left() -> float:
	return maxf(duration() - elapsed, 0.0) if duration() > 0.0 else 0.0


func is_target_up() -> bool:
	return _target_up


func target_index() -> int:
	return _target_index


func tick(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				phase = Phase.RUNNING
				_begin()
		Phase.RUNNING:
			elapsed += delta
			_run(delta)


func record_shot() -> void:
	if phase != Phase.RUNNING:
		return
	if drill_id == TrainingDrills.REACTION and not _target_up:
		false_starts += 1
		return
	shots += 1


func record_hit(headshot: bool, applied: int, killed: bool) -> void:
	if phase != Phase.RUNNING or not _target_up:
		return
	hits += 1
	damage += applied
	if headshot:
		headshots += 1
	match drill_id:
		TrainingDrills.FLICK:
			if killed:
				kills += 1
				_show(_next_index())
		TrainingDrills.REACTION:
			reaction_times.append(_up_for * 1000.0)
			_next_rep()
		TrainingDrills.TRACKING:
			if killed:
				kills += 1
				_hide()
				_respawn_left = TrainingDrills.TRACKING_RESPAWN


## Movement course: the player left the start pad (starts the clock).
func leave_start() -> void:
	if phase == Phase.RUNNING and drill_id == TrainingDrills.MOVEMENT and not course_started:
		course_started = true


## Movement course: checkpoint [param order] (1-based). Only the next one in order counts.
## Returns true when it counted.
func reach_checkpoint(order: int) -> bool:
	if not course_started or order != checkpoints_reached + 1:
		return false
	checkpoints_reached = order
	return true


## Movement course: the player fell and goes back to the last checkpoint.
func reset_to_checkpoint() -> void:
	if course_started:
		resets += 1


## Movement course finish pad. Counts only with every checkpoint reached.
func reach_finish() -> bool:
	if not course_started or checkpoints_reached < checkpoint_total or phase != Phase.RUNNING:
		return false
	course_finished = true
	_finish(true)
	return true


## Ends the run early (the player left); the result is marked not completed.
func abandon() -> TrainingResult:
	if phase == Phase.DONE:
		return result()
	return _finish(false)


func metrics() -> Dictionary:
	var measured := {"duration": elapsed, "shots": shots, "hits": hits, "kills": kills, "damage": damage,
		"accuracy": float(hits) / float(shots) if shots > 0 else 0.0,
		"headshot_rate": float(headshots) / float(hits) if hits > 0 else 0.0}
	match drill_id:
		TrainingDrills.FLICK, TrainingDrills.TRACKING:
			measured["duration"] = minf(elapsed, duration())
		TrainingDrills.REACTION:
			var total := 0.0
			var best := 0.0
			for ms: float in reaction_times:
				total += ms
				best = ms if best == 0.0 else minf(best, ms)
			measured.merge({"reps": rep, "reps_hit": reaction_times.size(), "average_ms": total / maxf(reaction_times.size(), 1.0),
				"best_ms": best, "false_starts": false_starts, "misses": misses}, true)
		TrainingDrills.MOVEMENT:
			measured.merge({"time": course_time, "par": par, "resets": resets, "checkpoints": checkpoints_reached,
				"checkpoint_total": checkpoint_total, "finished": course_finished}, true)
	return measured


func result() -> TrainingResult:
	return _result


func _begin() -> void:
	match drill_id:
		TrainingDrills.FLICK:
			_show(_next_index())
		TrainingDrills.TRACKING:
			_show(0)
		TrainingDrills.REACTION:
			_next_rep()


func _run(delta: float) -> void:
	match drill_id:
		TrainingDrills.FLICK, TrainingDrills.TRACKING:
			if _respawn_left >= 0.0:
				_respawn_left -= delta
				if _respawn_left < 0.0:
					_show(0)
			if elapsed >= duration():
				_finish(true)
		TrainingDrills.REACTION:
			if _wait_left >= 0.0:
				_wait_left -= delta
				if _wait_left < 0.0:
					_up_for = 0.0
					_show(_next_index())
			elif _target_up:
				_up_for += delta
				if _up_for >= TrainingDrills.REACTION_WINDOW:
					misses += 1
					_next_rep()
		TrainingDrills.MOVEMENT:
			if course_started:
				course_time += delta


func _next_rep() -> void:
	_hide()
	if rep >= int(_definition.get("reps", 0)):
		_finish(true)
		return
	rep += 1
	_wait_left = _rng.randf_range(TrainingDrills.REACTION_WAIT_MIN, TrainingDrills.REACTION_WAIT_MAX)


func _next_index() -> int:
	if marker_count <= 1:
		return 0
	var index := _rng.randi_range(0, marker_count - 2)
	return index + 1 if index >= _target_index else index


func _show(index: int) -> void:
	_target_index = index
	_target_up = true
	target_requested.emit(index)


func _hide() -> void:
	if _target_up:
		_target_up = false
		target_cleared.emit()


func _finish(done: bool) -> TrainingResult:
	_hide()
	phase = Phase.DONE
	_result = TrainingResult.make(drill_id, metrics(), done)
	finished.emit(_result)
	return _result
