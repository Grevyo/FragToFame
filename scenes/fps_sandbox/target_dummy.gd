class_name TargetDummy
extends Node3D
## Training target with per-zone hitboxes. Shows floating damage numbers, tips over when
## eliminated and stands back up after [member respawn_delay]. Optionally strafes side to side.

signal eliminated(dummy: TargetDummy, info: DamageInfo)

const MOTION_STATIC: StringName = &"static"
const MOTION_STRAFE: StringName = &"strafe"
const STRAFE_HALF_WIDTH: float = 2.0
## Peak strafe speed (m/s), close to a walking player.
const STRAFE_SPEED: float = 2.6

@export var motion: StringName = MOTION_STATIC
## Seconds before standing back up; negative = stay down (match combatants).
@export var respawn_delay: float = 2.5
## Match player ID when used as a passive match combatant, empty for training targets.
var combatant_id: String = ""

var health: Health
var hitboxes: Array[Hitbox] = []
var body_root: Node3D

var _blocker: StaticBody3D
var _materials: Array[StandardMaterial3D] = []
var _flash_left: float = 0.0
var _respawn_left: float = 0.0
var _strafe_time: float = 0.0


func _ready() -> void:
	health = Health.new()
	health.name = "Health"
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	_build_body()


func _build_body() -> void:
	_blocker = StaticBody3D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = Hitscan.LAYER_CHARACTERS
	_blocker.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var blocker_shape := CollisionShape3D.new()
	blocker_shape.shape = capsule
	blocker_shape.position.y = 0.9
	_blocker.add_child(blocker_shape)
	body_root.add_child(_blocker)

	var built := HumanoidRig.build(body_root, health, true)
	hitboxes = built.hitboxes
	_materials = built.materials
	# Visor marks the front (-Z).
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.2, 0.06, 0.04)
	visor.mesh = visor_mesh
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color("ff6a2a")
	visor.material_override = visor_material
	visor.position = Vector3(0, 1.63, -0.13)
	body_root.add_child(visor)


## Global position of a hitbox centre for [param zone] (useful for aiming in tests and bots).
func zone_position(zone: StringName) -> Vector3:
	for hitbox: Hitbox in hitboxes:
		if hitbox.zone == zone:
			return hitbox.global_position
	return global_position


func _physics_process(delta: float) -> void:
	if health.is_dead:
		if respawn_delay < 0.0:
			return
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_stand_up()
		return
	if motion == MOTION_STRAFE:
		_strafe_time += delta
		var omega := STRAFE_SPEED / STRAFE_HALF_WIDTH
		body_root.position.x = sin(_strafe_time * omega) * STRAFE_HALF_WIDTH


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		var emit := _flash_left > 0.0
		for material: StandardMaterial3D in _materials:
			material.emission_enabled = emit
			material.emission = Color(1.0, 0.3, 0.2)


func _on_damaged(info: DamageInfo) -> void:
	_flash_left = 0.08
	_spawn_damage_number(info)


func _on_died(info: DamageInfo) -> void:
	_respawn_left = respawn_delay
	for hitbox: Hitbox in hitboxes:
		hitbox.set_enabled(false)
	_blocker.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(body_root, "rotation_degrees:x", 85.0, 0.35).set_ease(Tween.EASE_IN)
	eliminated.emit(self, info)


func _stand_up() -> void:
	body_root.rotation_degrees.x = 0.0
	for hitbox: Hitbox in hitboxes:
		hitbox.set_enabled(true)
	_blocker.collision_layer = Hitscan.LAYER_CHARACTERS
	health.revive()


func _spawn_damage_number(info: DamageInfo) -> void:
	var label := Label3D.new()
	label.text = str(info.applied)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.004
	label.modulate = Color("ff5050") if info.is_headshot() else Color(1, 1, 1)
	add_child(label)
	label.global_position = info.position + Vector3(randf_range(-0.1, 0.1), 0.15, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.6, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
