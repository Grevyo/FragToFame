class_name FirstPersonArms
extends Node3D
## The player's own arms in first person: their character look ([method CharacterAvatar.player_look])
## on a rig carried by the camera, with the head and legs collapsed away. The hands are pulled onto
## whatever the viewmodel holds ([method hold]), so they follow every inspection, knife swing and
## throw the viewmodel plays. Presentation only: nothing here affects aim or shots.
##
## Add it as a child of the camera. The rig faces the camera's forward, its head bone just behind
## and below the eye.

## Bones shrunk away so only the arms (and the shoulders they hang from) remain.
const COLLAPSED: Array[StringName] = [&"Neck", &"Head", &"LeftUpperLeg", &"RightUpperLeg", &"LeftFoot", &"RightFoot",
	&"LeftLowerLeg", &"RightLowerLeg"]
## Where the head bone sits relative to the eye (camera space).
const HEAD_FROM_EYE := Vector3(0.0, -0.1, 0.04)
## How far the shoulders turn (radians) so the support hand reaches a long gun's handguard: the
## viewmodel holds guns further right than a third-person hold, so further than there.
const LONG_GUN_TWIST: float = 1.0
## Where the elbows point (camera space; x toward that arm's side).
const ELBOW_HINT := Vector3(0.7, -1.0, 0.2)
## A grenade further than this (m) from where it rests in the hand has been tossed (an inspection
## throws the frag up): the hand stays where it holds it at rest instead of chasing it.
const TOSSED: float = 0.08

var rig: CharacterRig
## The item in the hands (a [WeaponVisual] or a utility model) and the model it shows.
var held: Node3D = null
var held_model: StringName = &""
var held_size: Vector3 = Vector3.ZERO


func _init() -> void:
	name = "FirstPersonArms"
	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.rotation.y = PI
	add_child(rig)
	rig.rebuilt.connect(func(_notes: PackedStringArray) -> void: _prepare())


## Dresses the arms in [param look] (null hides them). Returns whether arms are shown.
func apply(look: CharacterAppearance) -> bool:
	if look == null or look.body.is_empty():
		visible = false
		return false
	rig.apply(look)
	rig.play(CharacterRig.ANIM_AIM, 0.0)
	_prepare()
	visible = held != null
	return true


## Holds [param item] ([param model_id] / [param size] give its grips, see
## [method WeaponModels.hand_points]); null leaves the hands empty and hides the arms.
func hold(item: Node3D, model_id: StringName, size: Vector3) -> void:
	held = item
	held_model = model_id
	held_size = size
	visible = item != null and rig.skeleton != null


func _prepare() -> void:
	if rig.skeleton == null or rig.retargeter == null:
		return
	rig.retargeter.collapsed = COLLAPSED
	rig.retargeter.before_reach = _reach_for_held
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := rig.skeleton.find_bone(&"Head")
	if head >= 0:
		var head_at := rig.transform * rig.skeleton.transform * rig.skeleton.get_bone_global_rest(head).origin
		rig.position += HEAD_FROM_EYE - head_at


func _reach_for_held() -> void:
	var retargeter := rig.retargeter
	retargeter.reach.clear()
	retargeter.hand_frames.clear()
	if held == null or not is_instance_valid(held) or not held.is_visible_in_tree():
		return
	var at := held.global_transform
	var parent := held.get_parent() as Node3D
	if held_model.is_empty() and parent != null and parent.get_parent() is Node3D:
		# Utility items sit in a root the viewmodel moves; at rest that root has no offset.
		var at_rest := (parent.get_parent() as Node3D).global_transform * held.transform
		if at.origin.distance_to(at_rest.origin) > TOSSED:
			at = at_rest
	var points := WeaponModels.hand_points(held_model, held_size)
	var frames := WeaponModels.hand_frames(held_model)
	var facing := global_transform.basis.orthonormalized()
	var long_gun := held_size.z > CharacterAvatar.LONG_GUN and not WeaponModels.is_knife(held_model)
	retargeter.upper_twist = LONG_GUN_TWIST if long_gun else 0.0
	for side: StringName in points:
		retargeter.reach[side] = at * points[side]
		if frames.has(side):
			retargeter.hand_frames[side] = at.basis.orthonormalized() * frames[side]
		retargeter.finger_curl[side] = CharacterAvatar.GRIP_CURL if side == &"Right" else CharacterAvatar.SUPPORT_CURL
		retargeter.elbow_hints[side] = facing * (ELBOW_HINT * Vector3(1.0 if side == &"Right" else -1.0, 1.0, 1.0))
