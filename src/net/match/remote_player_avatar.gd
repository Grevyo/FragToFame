class_name RemotePlayerAvatar
extends Node3D
## Visual stand-in for another player in a networked match. Smoothly follows the latest
## network state. No collision or hit detection yet (Milestone 4+).
##
## A player who sent a character look is shown as that model ([CharacterAvatar]: animated from
## its movement, crouching and holding the weapon they hold); without one, as a coloured capsule.

const SMOOTHING: float = 18.0
const COLORS: Array[Color] = [Color("2ec4d6"), Color("e3b341"), Color("3fb950"), Color("d65db1"), Color("f85149")]

var peer_id: int = 0
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
## The character model, when the player sent a wearable look (null = capsule).
var character: CharacterAvatar = null
var _capsule_parts: Array[Node3D] = []

var _has_state: bool = false


func setup(owner_peer_id: int) -> void:
	peer_id = owner_peer_id
	name = "Avatar_%d" % owner_peer_id
	visible = false  # Shown once the first network state arrives.
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[owner_peer_id % COLORS.size()]

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.8
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.material_override = material
	body.position.y = 0.9
	add_child(body)
	_capsule_parts.append(body)

	# A visor on the -Z side shows which way the player faces.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.4, 0.12, 0.2)
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = visor_mesh
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.05, 0.05, 0.06)
	visor.material_override = visor_material
	visor.position = Vector3(0, 1.55, -0.3)
	add_child(visor)
	_capsule_parts.append(visor)


## Shows the player's character look ([method CharacterAppearance.to_dict]), sanitised against
## this game's catalog. An empty or unwearable look shows the capsule. Returns whether a model
## is shown.
func apply_appearance(look: Dictionary) -> bool:
	var appearance := CharacterAppearance.from_dict(look) if not look.is_empty() else null
	if appearance != null:
		CharacterWardrobe.sanitize(CharacterCatalog.shared(), appearance)
	var wearable := appearance != null and not appearance.body.is_empty()
	if wearable:
		if character == null:
			character = CharacterAvatar.new()
			add_child(character)
		character.apply(appearance)
	elif character != null:
		character.queue_free()
		character = null
	for part: Node3D in _capsule_parts:
		part.visible = not wearable
	return wearable


func apply_state(world_position: Vector3, yaw: float, crouch: float = 0.0, pitch: float = 0.0,
		weapon: StringName = &"") -> void:
	target_position = world_position
	target_yaw = yaw
	if character != null:
		character.crouch = clampf(crouch, 0.0, 1.0)
		character.aim_pitch = pitch
		character.set_weapon(CharacterAvatar.held_model(weapon))
	if not _has_state:
		_has_state = true
		visible = true
		global_position = world_position
		rotation.y = yaw


func _process(delta: float) -> void:
	if not _has_state:
		return
	var weight := 1.0 - exp(-SMOOTHING * delta)
	global_position = global_position.lerp(target_position, weight)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
