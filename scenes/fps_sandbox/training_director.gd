class_name TrainingDirector
extends Node
## Runs one training drill in the FPS runtime: moves a single target dummy where the
## [TrainingSession] asks, feeds it the player's shots and hits, watches the movement course's
## pads, shows a small HUD and the result. It never touches the career; the result goes out
## through [signal training_finished].

signal training_finished(result: TrainingResult)
signal again_requested()
signal leave_requested()

## How far below the lowest course pad counts as a fall.
const FALL_MARGIN: float = 3.0

var session: TrainingSession
var drill_id: StringName
var dummy: TargetDummy
## Saved with the result ("Saved to your career …"), set by the runtime after reporting.
var result_message: String = ""

var _level: SandboxLevel
var _player: FirstPersonController
var _markers: Array[Dictionary] = []
var _start_pad: Dictionary = {}
var _checkpoints: Array[Dictionary] = []
var _finish_pad: Dictionary = {}
var _fall_height: float = -1000.0
var _in_start: bool = false
var _spawn: Array = []
var _overlay: CanvasLayer
var _status: Label
var _panel: PanelContainer
var _panel_title: Label
var _panel_body: Label


## [param rng] makes target order repeatable in tests.
func begin(drill: StringName, level: SandboxLevel, player: FirstPersonController, rng: RandomNumberGenerator = null) -> void:
	drill_id = drill
	_level = level
	_player = player
	_read_map()
	session = TrainingSession.new(drill, _markers.size(), rng, _checkpoints.size())
	if not _finish_pad.is_empty():
		session.par = float(_finish_pad.get("props", {}).get("par", TrainingDrills.COURSE_PAR))
	session.target_requested.connect(_show_target)
	session.target_cleared.connect(func() -> void:
		if dummy != null:
			dummy.set_active(false))
	session.finished.connect(_on_finished)
	if drill != TrainingDrills.MOVEMENT and not _markers.is_empty():
		dummy = TargetDummy.new()
		dummy.name = "DrillTarget"
		dummy.respawn_delay = -1.0
		_level.targets_root.add_child(dummy)
		dummy.set_active(false)
	var weapon := TrainingDrills.DRILLS.get(drill, {}).get("weapon", WeaponCatalog.G17) as StringName
	player.weapons.set_loadout([weapon])
	player.weapons.shot_fired.connect(_on_shot)
	player.weapons.target_hit.connect(_on_hit)
	_spawn = _level.spawn_point("attack")
	_build_overlay()


func is_finished() -> bool:
	return session != null and session.phase == TrainingSession.Phase.DONE


## One line for the HUD: countdown, time left, kills, reps or the course clock.
func status_text() -> String:
	if session == null:
		return ""
	var title := TrainingDrills.drill_name(drill_id).to_upper()
	match session.phase:
		TrainingSession.Phase.COUNTDOWN:
			return "%s · starts in %d" % [title, ceili(session.countdown)]
		TrainingSession.Phase.DONE:
			return "%s · finished" % title
	match drill_id:
		TrainingDrills.FLICK:
			return "%s · %.0f s · %d kills · %d%% accuracy" % [title, session.time_left(), session.kills,
				roundi(100.0 * session.hits / maxf(session.shots, 1.0))]
		TrainingDrills.TRACKING:
			return "%s · %.0f s · %d damage · %d%% accuracy" % [title, session.time_left(), session.damage,
				roundi(100.0 * session.hits / maxf(session.shots, 1.0))]
		TrainingDrills.REACTION:
			var last := session.reaction_times[-1] if not session.reaction_times.is_empty() else 0.0
			return "%s · rep %d of %d · last %s · %s" % [title, session.rep, int(TrainingDrills.DRILLS[drill_id]["reps"]),
				"%d ms" % roundi(last) if last > 0.0 else "—", "SHOOT!" if session.is_target_up() else "wait…"]
		TrainingDrills.MOVEMENT:
			if not session.course_started:
				return "%s · leave the START pad to begin" % title
			return "%s · %.2f s · checkpoint %d of %d · %d resets" % [title, session.course_time, session.checkpoints_reached,
				session.checkpoint_total, session.resets]
	return title


func _physics_process(delta: float) -> void:
	if session == null or session.phase == TrainingSession.Phase.DONE:
		return
	var was_counting := session.phase == TrainingSession.Phase.COUNTDOWN
	session.tick(delta)
	if was_counting and session.phase == TrainingSession.Phase.RUNNING and drill_id == TrainingDrills.MOVEMENT:
		_in_start = MapZones.contains(_start_pad, _player.global_position) if not _start_pad.is_empty() else true
	if drill_id == TrainingDrills.MOVEMENT and session.phase == TrainingSession.Phase.RUNNING:
		_watch_course()
	if _player.weapons.current() != null and _player.weapons.current().reserve == 0:
		_player.weapons.refill_all()
	if _status != null:
		_status.text = status_text()


func _watch_course() -> void:
	var feet := _player.global_position
	if not _start_pad.is_empty():
		var inside := MapZones.contains(_start_pad, feet)
		if _in_start and not inside:
			session.leave_start()
		_in_start = inside
	elif not session.course_started:
		session.leave_start()
	for checkpoint: Dictionary in _checkpoints:
		if MapZones.contains(checkpoint, feet) and session.reach_checkpoint(int(checkpoint.get("props", {}).get("order", 0))):
			_player.set_spawn(checkpoint["position"] as Vector3, _player.rotation.y)
	if not _finish_pad.is_empty() and MapZones.contains(_finish_pad, feet):
		session.reach_finish()
	if feet.y < _fall_height:
		session.reset_to_checkpoint()
		_player.respawn()


func _read_map() -> void:
	var doc := _level.document
	var strafe: Array[Dictionary] = []
	var still: Array[Dictionary] = []
	for piece: Dictionary in doc.pieces_of_type("target_dummy"):
		if str(piece.get("props", {}).get("motion", "static")) == "strafe":
			strafe.append(piece)
		else:
			still.append(piece)
	if drill_id == TrainingDrills.TRACKING:
		_markers = strafe if not strafe.is_empty() else still
	else:
		_markers = still if not still.is_empty() else strafe
	var starts := doc.pieces_of_type("course_start")
	_start_pad = starts[0] if not starts.is_empty() else {}
	var finishes := doc.pieces_of_type("course_finish")
	_finish_pad = finishes[0] if not finishes.is_empty() else {}
	_checkpoints = doc.pieces_of_type("course_checkpoint")
	_checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("props", {}).get("order", 0)) < int(b.get("props", {}).get("order", 0)))
	var lowest := INF
	for pad: Dictionary in [_start_pad, _finish_pad] + _checkpoints:
		if not pad.is_empty():
			lowest = minf(lowest, (pad["position"] as Vector3).y)
	if lowest < INF:
		_fall_height = lowest - FALL_MARGIN


func _show_target(index: int) -> void:
	if dummy == null or _markers.is_empty():
		return
	var marker := _markers[clampi(index, 0, _markers.size() - 1)]
	dummy.motion = StringName(str(marker.get("props", {}).get("motion", "static")))
	dummy.position = marker["position"] as Vector3
	dummy.rotation_degrees.y = float(marker["rotation_y"])
	dummy.set_active(true)


func _on_shot(_origin: Vector3, _end: Vector3, _result: Hitscan.Result) -> void:
	session.record_shot()


func _on_hit(info: DamageInfo, target: Health, killed: bool) -> void:
	if dummy == null or target != dummy.health:
		return
	session.record_hit(info.is_headshot(), info.applied, killed)
	if killed or drill_id == TrainingDrills.REACTION:
		_player.weapons.refill_all()


func _on_finished(result: TrainingResult) -> void:
	training_finished.emit(result)
	_show_result(result)


## Called by the runtime once it has handed the result on (e.g. "Saved to your career").
func set_result_message(text: String) -> void:
	result_message = text
	if _panel != null and _panel.visible and session.result() != null:
		_show_result(session.result())


func _show_result(result: TrainingResult) -> void:
	_player.input_enabled = false
	_player.weapons.trigger = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_panel_title.text = "%s · %d / 100" % [TrainingDrills.drill_name(drill_id), result.score] if result.completed \
		else "%s · not completed" % TrainingDrills.drill_name(drill_id)
	_panel_body.text = TrainingDrills.describe(drill_id, result.metrics) + ("\n" + result_message if not result_message.is_empty() else "")
	_panel.visible = true


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 5
	add_child(_overlay)
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.add_theme_constant_override(&"margin_top", 70)
	_status = UIFactory.label("", &"HeaderLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_status)
	_overlay.add_child(top)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"CardPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.visible = false
	var box := UIFactory.vbox(12)
	_panel.add_child(box)
	_panel_title = UIFactory.label("", &"HeaderLabel", true)
	box.add_child(_panel_title)
	_panel_body = UIFactory.label("", &"", true)
	box.add_child(_panel_body)
	var buttons := UIFactory.hbox(8)
	var again := UIFactory.button("Go again", &"AccentButton")
	again.pressed.connect(func() -> void: again_requested.emit())
	buttons.add_child(again)
	var leave := UIFactory.button("Leave training")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(leave)
	box.add_child(buttons)
	_overlay.add_child(_panel)
