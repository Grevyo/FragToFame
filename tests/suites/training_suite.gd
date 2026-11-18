class_name TrainingSuite
extends TestSuite
## Real training: drill rules and scoring (pure), the training maps, and a drill running in the
## FPS runtime with its result handed out (never written by the runtime).

const FPS_SANDBOX_SCENE: String = "res://scenes/fps_sandbox/fps_sandbox.tscn"


func suite_name() -> String:
	return "Training ground"


func run() -> void:
	_test_flick()
	_test_reaction()
	_test_tracking()
	_test_movement()
	_test_scores()
	_test_maps()
	await _test_runtime()


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	return rng


func _test_flick() -> void:
	section("Flick range")
	var session := TrainingSession.new(TrainingDrills.FLICK, 12, _rng())
	var shown: Array[int] = []
	session.target_requested.connect(func(index: int) -> void: shown.append(index))
	session.record_shot()
	check(session.shots == 0 and shown.is_empty(), "nothing counts during the countdown")
	session.tick(TrainingDrills.COUNTDOWN + 0.01)
	check(session.phase == TrainingSession.Phase.RUNNING and shown.size() == 1, "the first target appears when the countdown ends")
	for i: int in 10:
		session.record_shot()
		session.record_shot()
		session.record_hit(i % 2 == 0, 100, true)
	var moved := true
	for i: int in range(1, shown.size()):
		moved = moved and shown[i] != shown[i - 1]
	check(session.kills == 10 and shown.size() == 11 and moved, "each kill moves the target to a different marker")
	var finished: Array[TrainingResult] = []
	session.finished.connect(func(result: TrainingResult) -> void: finished.append(result))
	session.tick(TrainingDrills.DRILLS[TrainingDrills.FLICK]["duration"] as float)
	check(finished.size() == 1 and finished[0].completed and session.phase == TrainingSession.Phase.DONE,
		"the drill ends after 60 seconds")
	var metrics := finished[0].metrics
	check(is_equal_approx(float(metrics["accuracy"]), 0.5) and is_equal_approx(float(metrics["headshot_rate"]), 0.5)
		and int(metrics["kills"]) == 10, "kills, accuracy and headshot rate are measured")


func _test_reaction() -> void:
	section("Reaction test")
	var session := TrainingSession.new(TrainingDrills.REACTION, 12, _rng())
	session.tick(TrainingDrills.COUNTDOWN + 0.01)
	session.record_shot()
	check(session.false_starts == 1 and not session.is_target_up(), "shooting before the target appears is a false start")
	session.tick(TrainingDrills.REACTION_WAIT_MAX + 0.01)
	check(session.is_target_up(), "the target appears after a random wait")
	session.tick(0.25)
	session.record_hit(false, 30, false)
	check(session.reaction_times.size() == 1 and absf(session.reaction_times[0] - 250.0) < 1.0 and not session.is_target_up(),
		"the time from appearing to the hit is the reaction time")
	session.tick(TrainingDrills.REACTION_WAIT_MAX + 0.01)
	session.tick(TrainingDrills.REACTION_WINDOW + 0.01)
	check(session.misses == 1, "a target left standing too long is a miss")
	while session.phase != TrainingSession.Phase.DONE:
		session.tick(TrainingDrills.REACTION_WAIT_MAX + 0.01)
		if session.is_target_up():
			session.tick(0.2)
			session.record_hit(false, 30, false)
	var result := session.result()
	check(result.completed and int(result.metrics["reps"]) == 12 and int(result.metrics["reps_hit"]) == 11
		and float(result.metrics["best_ms"]) <= 201.0, "twelve reps with average, best, false starts and misses")


func _test_tracking() -> void:
	section("Tracking lane")
	var session := TrainingSession.new(TrainingDrills.TRACKING, 1, _rng())
	var cleared: Array[int] = [0]
	session.target_cleared.connect(func() -> void: cleared[0] += 1)
	session.tick(TrainingDrills.COUNTDOWN + 0.01)
	session.record_shot()
	session.record_hit(false, 100, true)
	check(cleared[0] == 1 and not session.is_target_up(), "a downed target drops")
	session.tick(TrainingDrills.TRACKING_RESPAWN + 0.05)
	check(session.is_target_up(), "and stands up again moments later")
	session.tick(30.0)
	check(session.phase == TrainingSession.Phase.DONE and int(session.result().metrics["damage"]) == 100, "the lane runs 30 seconds")


func _test_movement() -> void:
	section("Movement course")
	var session := TrainingSession.new(TrainingDrills.MOVEMENT, 0, _rng(), 3)
	session.tick(TrainingDrills.COUNTDOWN + 0.01)
	session.tick(5.0)
	check(not session.course_started and session.course_time == 0.0, "the clock waits until you leave the start pad")
	session.leave_start()
	check(not session.reach_checkpoint(2), "checkpoints only count in order")
	session.tick(4.0)
	check(session.reach_checkpoint(1), "checkpoint 1 counts")
	session.reset_to_checkpoint()
	check(not session.reach_finish(), "the finish needs every checkpoint")
	session.reach_checkpoint(2)
	session.reach_checkpoint(3)
	session.tick(16.0)
	check(session.reach_finish() and session.result().completed, "the finish ends the run")
	var metrics := session.result().metrics
	check(is_equal_approx(float(metrics["time"]), 20.0) and int(metrics["resets"]) == 1 and bool(metrics["finished"]),
		"time and resets are measured")
	var quit := TrainingSession.new(TrainingDrills.MOVEMENT, 0, _rng(), 3)
	quit.tick(TrainingDrills.COUNTDOWN + 0.01)
	quit.leave_start()
	check(not quit.abandon().completed, "leaving early is not a completed session")


func _test_scores() -> void:
	section("Scores")
	var weak := TrainingDrills.score(TrainingDrills.FLICK, {"kills": 15, "duration": 60.0, "accuracy": 0.3, "headshot_rate": 0.1})
	var strong := TrainingDrills.score(TrainingDrills.FLICK, {"kills": 50, "duration": 60.0, "accuracy": 0.65, "headshot_rate": 0.45})
	check(weak < strong and strong >= 70 and weak <= 35, "more kills at better accuracy score higher (%d vs %d)" % [weak, strong])
	var slow := TrainingDrills.score(TrainingDrills.REACTION, {"reps_hit": 12, "average_ms": 380.0})
	var fast := TrainingDrills.score(TrainingDrills.REACTION, {"reps_hit": 12, "average_ms": 190.0})
	check(fast > slow and fast >= 95 and slow <= 40, "faster reactions score higher (%d vs %d)" % [fast, slow])
	check(TrainingDrills.score(TrainingDrills.MOVEMENT, {"finished": true, "time": 21.0, "par": 30.0}) == 100
		and TrainingDrills.score(TrainingDrills.MOVEMENT, {"finished": true, "time": 60.0, "par": 30.0}) == 35
		and TrainingDrills.score(TrainingDrills.MOVEMENT, {"finished": false}) == 1, "the course scores against par")
	var result := TrainingResult.make(TrainingDrills.FLICK, {"kills": 50, "duration": 60.0, "accuracy": 0.65}, true)
	var copy := TrainingResult.from_dict(result.to_dict())
	check(copy != null and copy.score == result.score and copy.drill_id == TrainingDrills.FLICK
		and TrainingResult.from_dict({"format_version": 99}) == null, "results round-trip with a format version")


func _test_maps() -> void:
	section("Training maps")
	var range_map := MapTemplates.training_range()
	var statics := 0
	var strafers := 0
	for piece: Dictionary in range_map.pieces_of_type("target_dummy"):
		if str((piece["props"] as Dictionary).get("motion", "static")) == "strafe":
			strafers += 1
		else:
			statics += 1
	check(statics >= 10 and strafers >= 1 and not MapBuilder.spawn_points(range_map, "attack").is_empty(),
		"the range has a dozen targets, a strafing lane and a spawn")
	var course := MapTemplates.training_course()
	var orders: Array[int] = []
	for piece: Dictionary in course.pieces_of_type("course_checkpoint"):
		orders.append(int((piece["props"] as Dictionary)["order"]))
	orders.sort()
	check(course.pieces_of_type("course_start").size() == 1 and course.pieces_of_type("course_finish").size() == 1
		and orders == [1, 2, 3], "the course has a start, checkpoints 1–3 and a finish")
	check(PieceCatalog.has_type("course_checkpoint") and PieceCatalog.kind("course_finish") == "zone",
		"course pads are ordinary catalog pieces (placeable in the Creation Studio)")
	var restored := MapDocument.from_dict(course.to_dict())
	check(restored != null and restored.pieces_of_type("course_checkpoint").size() == 3, "the course saves and loads like any map")


func _test_runtime() -> void:
	section("A drill in the FPS runtime")
	var app := tree.root.get_node("App")
	app.set("pending_training", {"drill": TrainingDrills.FLICK, "map": MapTemplates.training_range(), "career": false})
	var sandbox := spawn_scene(FPS_SANDBOX_SCENE)
	if sandbox == null:
		return
	await wait_physics_frames(3)
	var director := sandbox.get("training_director") as TrainingDirector
	check(director != null and not bool(app.call("has_pending_training")), "the runtime starts the pending drill")
	if director == null:
		await despawn(sandbox)
		return
	var player := sandbox.get_node("Player") as FirstPersonController
	player.input_enabled = false
	check(player.weapons.loadout_ids() == [WeaponCatalog.AK47], "the flick drill hands you its rifle")
	check(director.dummy != null and not director.dummy.visible, "the target waits for the countdown")
	director.session.tick(TrainingDrills.COUNTDOWN + 0.01)
	await wait_physics_frames(1)
	check(director.dummy.visible and director.status_text().contains("kills"), "the target appears and the HUD counts")
	var first := director.dummy.position
	var info := DamageInfo.new()
	info.applied = 100
	director.call("_on_hit", info, director.dummy.health, true)
	check(director.session.kills == 1 and director.dummy.position != first and director.dummy.visible,
		"a kill moves the target to another marker")
	var reported: Array[TrainingResult] = []
	director.training_finished.connect(func(result: TrainingResult) -> void: reported.append(result))
	director.session.tick(61.0)
	await wait_frames(1)
	check(reported.size() == 1 and reported[0].completed and app.get("last_training_result") == reported[0],
		"the finished drill is handed to App (the runtime writes nothing itself)")
	check(director.is_finished() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the result screen frees the mouse")
	await despawn(sandbox)
