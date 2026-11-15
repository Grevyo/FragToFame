extends Node3D
## FPS sandbox root: owns mouse capture and pause state, wires the HUD to the player.

@onready var player: FirstPersonController = $Player
@onready var hud: SandboxHud = $Hud

var is_paused: bool = false


func _ready() -> void:
	hud.resume_requested.connect(resume)
	hud.main_menu_requested.connect(_on_main_menu_requested)
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
	App.go_to(App.SCENE_MAIN_MENU)
