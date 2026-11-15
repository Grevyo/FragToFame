extends Node3D
## FPS sandbox root: owns mouse capture and pause state, wires the HUD to the player and
## to the local match network session.

@onready var player: FirstPersonController = $Player
@onready var hud: SandboxHud = $Hud
@onready var match_session: MatchSession = $MatchSession

var is_paused: bool = false
var _last_network_message: String = ""


func _ready() -> void:
	hud.resume_requested.connect(resume)
	hud.main_menu_requested.connect(_on_main_menu_requested)
	hud.host_match_requested.connect(_on_host_match_requested)
	hud.join_match_requested.connect(_on_join_match_requested)
	hud.leave_match_requested.connect(func() -> void: match_session.leave("left"))
	match_session.local_body = player
	match_session.session_ended.connect(_on_session_ended)
	resume()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		if is_paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
		return
	# Recapture after the mouse was freed without pausing (e.g. window focus loss).
	var click := event as InputEventMouseButton
	if click != null and click.pressed and not is_paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var p := player.global_position
	hud.set_debug_text("pos %.1f, %.1f, %.1f   speed %.2f m/s   %s   %d fps" % [
		p.x, p.y, p.z, player.horizontal_speed(),
		"grounded" if player.is_on_floor() else "airborne",
		Engine.get_frames_per_second(),
	])
	_update_network_hud()


func pause() -> void:
	is_paused = true
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_paused(true)


func resume() -> void:
	is_paused = false
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_paused(false)


func _on_main_menu_requested() -> void:
	match_session.leave("returned to main menu")
	App.go_to(App.SCENE_MAIN_MENU)


func _on_host_match_requested(port: int) -> void:
	var err := match_session.host(port)
	_last_network_message = "Hosting on port %d" % port if err == OK 		else "Could not host on port %d (error %d)" % [port, err]


func _on_join_match_requested(address: String, port: int) -> void:
	var err := match_session.join(address, port)
	_last_network_message = "Connecting to %s:%d..." % [address, port] if err == OK 		else "Could not start connection (error %d)" % err


func _on_session_ended(reason: String) -> void:
	_last_network_message = "Session ended: %s" % reason


func _update_network_hud() -> void:
	var role := match_session.role
	var badge := ""
	var status := _last_network_message if not _last_network_message.is_empty() else "Offline"
	if match_session.is_connected_to_match():
		var role_text := "HOST" if role == MatchSession.Role.HOST else "CLIENT"
		badge = "NET %s · peer %d · %d player(s)" % [role_text, match_session.local_peer_id(), match_session.player_count()]
		status = "%s · match %s" % [badge, match_session.match_id]
	elif role == MatchSession.Role.CLIENT:
		badge = "NET connecting..."
	hud.set_network_state(match_session.is_active(), status, badge)
