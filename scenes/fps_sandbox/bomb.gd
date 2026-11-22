class_name BombDevice
extends Node3D
## Visual bomb: dropped (idle) or planted (blinking faster as the timer runs down).
## Presentation only; [MatchState] owns the timer and the outcome.

var planted: bool = false
var time_left: float = 0.0
var total_time: float = 1.0

var _light: OmniLight3D
var _lamp_material := StandardMaterial3D.new()
var _blink_clock: float = 0.0
var _was_on: bool = false


func _ready() -> void:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.12, 0.24)
	body.mesh = mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("2a2d33")
	body.material_override = body_material
	body.position.y = 0.06
	add_child(body)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.03
	lamp_mesh.height = 0.06
	lamp.mesh = lamp_mesh
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_material.albedo_color = Color("ff3b30")
	lamp.material_override = _lamp_material
	lamp.position = Vector3(0.1, 0.14, 0)
	add_child(lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color("ff3b30")
	_light.omni_range = 2.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.3, 0)
	add_child(_light)


func set_planted(seconds_left: float, total: float) -> void:
	planted = true
	time_left = seconds_left
	total_time = maxf(total, 0.01)


func _process(delta: float) -> void:
	if not planted:
		_lamp_material.albedo_color = Color("5a1a18")
		_light.light_energy = 0.0
		return
	# Blink interval shrinks from 1 s to 0.1 s as the timer runs out.
	var interval := lerpf(0.1, 1.0, clampf(time_left / total_time, 0.0, 1.0))
	_blink_clock += delta
	var on := fmod(_blink_clock, interval) < interval * 0.4
	if on and not _was_on:
		SoundPlayer.play_at(self, &"bomb_beep", global_position + Vector3(0, 0.2, 0), &"bomb")
	_was_on = on
	_lamp_material.albedo_color = Color("ff3b30") if on else Color("5a1a18")
	_light.light_energy = 1.5 if on else 0.0
