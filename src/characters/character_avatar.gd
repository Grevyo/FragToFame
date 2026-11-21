class_name CharacterAvatar
extends Node3D
## A [CharacterRig] worn by a moving combatant in the FPS runtime: bots (developer option) and
## other players in a networked match. It turns the rig to face forward (-Z), picks a movement
## clip from the velocity in its own frame for the legs, lays a crouch over it, and holds the
## current weapon: the gun-holding clip plays on the upper body whatever the legs do, the weapon
## is placed from the right shoulder pointed where the combatant aims (a long gun's butt in the
## shoulder, a pistol out in front, a knife low), and both hands are pulled onto its grips
## ([method WeaponModels.hand_points]). It plays the death clip on [method die] and goes back to
## moving on [method revive]. Presentation only: hitboxes, collision, movement and aim belong to
## the combatant, never to this.
##
## Velocity, crouch and aim come from [member body] when it is a [CombatantMovementBody] (bots);
## otherwise the owner sets [member crouch] and [member aim_pitch] and velocity is measured from
## this node's own movement (remote players, whose position arrives over the network).

## Below this flat speed (m/s) the character stands.
const IDLE_SPEED: float = 0.4
## Below this flat speed (m/s) the character walks; above it, it runs.
const WALK_SPEED: float = 3.4
## The run clips are authored for about this speed (m/s); playback is scaled to match.
const RUN_CLIP_SPEED: float = 5.0
## Where a held item goes, from the right shoulder in the aim frame (x right, y up, -z forward):
## a long gun's butt, a pistol's firing palm, a knife's palm.
const LONG_GUN_BUTT := Vector3(-0.07, -0.05, -0.04)
const PISTOL_PALM := Vector3(-0.15, -0.07, -0.42)
const KNIFE_PALM := Vector3(0.03, -0.3, -0.32)
## Guns longer than this (m) are shouldered, the shoulders turned this far (radians) so the
## support hand reaches the handguard.
const LONG_GUN: float = 0.5
const LONG_GUN_TWIST: float = 0.6
## Where the elbows point while holding, in the aim frame (x toward that arm's side).
const ELBOW_HINT := Vector3(0.6, -1.0, 0.25)
## How far the fingers close on a grip (firing hand) and under a handguard (support hand).
const GRIP_CURL: float = 0.85
const SUPPORT_CURL: float = 1.0
const HAND_BONE: StringName = &"RightHand"
## How far the hips drop at a full crouch (m). The hitboxes go from 1.8 m to 1.2 m tall; a
## knees-bent crouch with the upper body leaning brings the head down that far with this drop.
const CROUCH_HIP_DROP: float = 0.46

var rig: CharacterRig
## The combatant whose velocity, crouch and aim drive the character (defaults to the parent).
var body: Node3D = null
## 0 = standing, 1 = fully crouched (used when [member body] does not say).
var crouch: float = 0.0
## Aim pitch in radians, positive = up (used when [member body] does not say).
var aim_pitch: float = 0.0
## The weapon held in the hand ("" = empty hands).
var weapon_id: StringName = &""
var weapon_visual: WeaponVisual = null
## Where the right hand was in the last final (animated) pose, in world space.
var held_at: Vector3 = Vector3.ZERO
## Where the held item goes this frame (world space), worked out from the posed shoulder.
var held_transform: Transform3D = Transform3D.IDENTITY

var _dead: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _measured_velocity: Vector3 = Vector3.ZERO


func _init() -> void:
	name = "Avatar"
	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.rotation.y = PI
	add_child(rig)


func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent() as Node3D


## Dresses the character. Returns what sanitising changed.
func apply(appearance: CharacterAppearance) -> PackedStringArray:
	var notes := rig.apply(appearance)
	rig.play(CharacterRig.ANIM_IDLE, 0.0)
	return notes


## Puts a weapon in the hand ("" or a weapon without a model = empty hands).
func set_weapon(id: StringName) -> void:
	if id == weapon_id:
		return
	weapon_id = id
	if not WeaponModels.has_model(id):
		if weapon_visual != null:
			weapon_visual.queue_free()
			weapon_visual = null
		rig.set_upper_clip(&"")
		return
	rig.set_upper_clip(upper_clip_for(id))
	if weapon_visual == null:
		weapon_visual = WeaponVisual.new()
		weapon_visual.name = "HeldWeapon"
		add_child(weapon_visual)
	weapon_visual.setup(id)


func die() -> void:
	_dead = true
	rig.set_upper_clip(&"")
	rig.play(CharacterRig.ANIM_DEATH, 0.1)
	if weapon_visual != null:
		weapon_visual.visible = false


func revive() -> void:
	_dead = false
	_has_last = false
	if weapon_visual != null:
		rig.set_upper_clip(upper_clip_for(weapon_id))
	rig.play(CharacterRig.ANIM_IDLE, 0.0)
	if weapon_visual != null:
		weapon_visual.visible = true


func is_dead() -> bool:
	return _dead


## Where the right hand is in world space (the avatar's origin when the body has no hand bone).
## Only the final animated pose while the skeleton reports [signal Skeleton3D.skeleton_updated];
## at other times the pose before animation modifiers (see [member held_at]).
func hand_position() -> Vector3:
	var skeleton := rig.skeleton
	var bone := skeleton.find_bone(HAND_BONE) if skeleton != null else -1
	if bone < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _process(delta: float) -> void:
	_measure_velocity(delta)
	_read_body()
	if rig.retargeter != null:
		rig.retargeter.crouch_drop = 0.0 if _dead else CROUCH_HIP_DROP * crouch
		if not rig.retargeter.before_reach.is_valid():
			rig.retargeter.before_reach = _place_held
	if _dead:
		return
	var velocity := _measured_velocity
	if body is CharacterBody3D:
		velocity = (body as CharacterBody3D).velocity
	var clip_and_speed := movement_clip(global_transform.basis.inverse() * velocity, weapon_visual != null)
	rig.play(clip_and_speed[0] as StringName, 0.2, float(clip_and_speed[1]))
	_watch_skeleton()


func _read_body() -> void:
	var mover := body as CombatantMovementBody
	if mover == null:
		return
	crouch = mover.crouch_amount
	var head := mover.get_node_or_null(^"Head") as Node3D
	if head != null:
		aim_pitch = head.rotation.x
	var controller := mover.get_node_or_null(^"Weapons") as WeaponController
	if controller != null:
		var state := controller.current()
		set_weapon(held_model(state.definition.id if state != null else &""))


func _measure_velocity(delta: float) -> void:
	if delta <= 0.0:
		return
	if _has_last:
		var step := (global_position - _last_position) / delta
		_measured_velocity = _measured_velocity.lerp(step, clampf(delta * 12.0, 0.0, 1.0))
	_last_position = global_position
	_has_last = true


## The hand is read once the skeleton's final (animated) pose is known: modifier results are not
## visible to ordinary _process code.
func _watch_skeleton() -> void:
	var skeleton := rig.skeleton
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_hold_weapon):
		skeleton.skeleton_updated.connect(_hold_weapon)


## Shows the held weapon where [method _place_held] put it, once the final pose is known.
func _hold_weapon() -> void:
	# A removed bot's skeleton can still finish one last update outside the tree.
	if weapon_visual == null or _dead or not is_inside_tree():
		return
	held_at = hand_position()
	weapon_visual.global_transform = held_transform


## Runs inside the retargeter once the body is posed: places the held item from the right shoulder
## and sends both hands to its grips.
func _place_held() -> void:
	var retargeter := rig.retargeter
	retargeter.reach.clear()
	if weapon_visual == null or _dead:
		retargeter.upper_twist = 0.0
		return
	retargeter.upper_twist = LONG_GUN_TWIST if weapon_visual.size.z > LONG_GUN and not WeaponModels.is_knife(weapon_visual.weapon_id) else 0.0
	held_transform = hold_transform(weapon_visual.weapon_id, weapon_visual.size,
		retargeter.posed_position(&"RightUpperArm"), global_transform.basis.orthonormalized(), aim_pitch)
	var facing := global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, aim_pitch)
	var points := WeaponModels.hand_points(weapon_visual.weapon_id, weapon_visual.size)
	var frames := WeaponModels.hand_frames(weapon_visual.weapon_id)
	retargeter.hand_frames.clear()
	for side: StringName in points:
		retargeter.reach[side] = held_transform * points[side]
		if frames.has(side):
			retargeter.hand_frames[side] = held_transform.basis * frames[side]
		retargeter.finger_curl[side] = GRIP_CURL if side == &"Right" else SUPPORT_CURL
		var hint := ELBOW_HINT * Vector3(1.0 if side == &"Right" else -1.0, 1.0, 1.0)
		retargeter.elbow_hints[side] = facing * hint


## The clip the upper body plays while holding [param model_id]: the gun-holding clip for guns,
## none for a knife (the free arm keeps moving with the legs).
static func upper_clip_for(model_id: StringName) -> StringName:
	return &"" if WeaponModels.is_knife(model_id) or not WeaponModels.has_model(model_id) else CharacterRig.ANIM_AIM


## Where a held model goes (world space) for a body facing [param facing] (-Z forward) with its
## right shoulder at [param shoulder], aiming [param pitch] radians up: pointed along the aim, a
## long gun's butt in the shoulder, a pistol held out in front, a knife low in the fist.
static func hold_transform(model_id: StringName, size: Vector3, shoulder: Vector3, facing: Basis, pitch: float) -> Transform3D:
	var aim := facing * Basis(Vector3.RIGHT, pitch)
	if WeaponModels.is_knife(model_id):
		var knife_palm := WeaponModels.hand_points(model_id, size)[&"Right"]
		return Transform3D(aim, shoulder + aim * KNIFE_PALM - aim * knife_palm)
	if size.z > LONG_GUN:
		return Transform3D(aim, shoulder + aim * LONG_GUN_BUTT - aim * Vector3(0, 0, size.z * 0.5))
	var palm := WeaponModels.hand_points(model_id, size)[&"Right"]
	return Transform3D(aim, shoulder + aim * PISTOL_PALM - aim * palm)


## The model shown in the hand for a carried weapon: the default knife look for the knife,
## nothing for utility, else the weapon's own model.
static func held_model(weapon_id: StringName) -> StringName:
	if weapon_id == EquipmentCatalog.KNIFE:
		return WeaponModels.DEFAULT_KNIFE
	return weapon_id if WeaponModels.has_model(weapon_id) else &""


## The look a bot wears: one of the player's saved Character Creator presets when any can be
## worn (picked by [param seed_value], so a bot keeps its preset), else a seeded random look.
## Either way its team-colour channels take [param team_colour]; other colours stay the preset's.
static func bot_look(seed_value: int, team_colour: Color) -> CharacterAppearance:
	var presets := wearable_presets()
	if presets.is_empty():
		return random_look(seed_value, team_colour)
	var look := presets[posmod(seed_value, presets.size())]
	CharacterWardrobe.apply_team_colours(CharacterCatalog.shared(), look, team_colour, team_colour.lightened(0.45))
	return look


## The saved presets that can be worn in this build (sanitised; unreadable ones skipped).
static func wearable_presets() -> Array[CharacterAppearance]:
	var looks: Array[CharacterAppearance] = []
	for entry: Dictionary in CharacterPresets.list():
		var look := CharacterPresets.load_preset(str(entry["id"]))
		if look == null:
			continue
		CharacterWardrobe.sanitize(CharacterCatalog.shared(), look)
		if not look.body.is_empty():
			looks.append(look)
	return looks


## The local player's look: the one stored in their cosmetic profile, else their newest saved
## preset, else null (shown as the plain capsule).
static func player_look() -> CharacterAppearance:
	var own := CosmeticProfile.current().appearance
	if not own.body.is_empty():
		return own.duplicate_appearance()
	var presets := wearable_presets()
	return presets[0] if not presets.is_empty() else null


## A seeded random look on an installed body, its team-colour channels in [param team_colour]
## (secondary: a lighter shade). Null when no body is installed.
static func random_look(seed_value: int, team_colour: Color) -> CharacterAppearance:
	var catalog := CharacterCatalog.shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var look := CharacterWardrobe.randomise(catalog, rng)
	if look.body.is_empty():
		return null
	CharacterWardrobe.apply_team_colours(catalog, look, team_colour, team_colour.lightened(0.45))
	return look


## The clip and playback speed for a velocity in the body's own frame (-Z forward):
## [clip: StringName, speed: float]. [param armed]: standing still the weapon is raised.
static func movement_clip(local_velocity: Vector3, armed: bool = false) -> Array:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var speed := flat.length()
	if speed < IDLE_SPEED:
		return [CharacterRig.ANIM_AIM if armed else CharacterRig.ANIM_IDLE, 1.0]
	if speed < WALK_SPEED:
		return [CharacterRig.ANIM_WALK, clampf(speed / 1.8, 0.6, 1.6)]
	var rate := clampf(speed / RUN_CLIP_SPEED, 0.7, 1.5)
	if absf(flat.x) > absf(flat.y):
		return [CharacterRig.ANIM_RUN_RIGHT if flat.x > 0.0 else CharacterRig.ANIM_RUN_LEFT, rate]
	return [CharacterRig.ANIM_RUN if flat.y < 0.0 else CharacterRig.ANIM_RUN_BACK, rate]
