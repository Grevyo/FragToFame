class_name CharacterRetargeter
extends SkeletonModifier3D
## Plays an animation skeleton's pose on this modifier's skeleton, a different rig whose bones were
## renamed to the humanoid profile at import (assets/characters/rigs/*.bone_map.tres).
##
## The packs disagree on hierarchy (the modular rig hangs its feet off Root, its legs off Body),
## on rest pose (T-pose against A-pose) and on bone axes, so poses are copied in model space:
## each mapped bone takes the source bone's rotation away from its rest, applied to a "virtual
## rest" in which the target bone points the way the source bone points at rest. Only the hips
## move; their offset is scaled by hip height, so every body keeps its own proportions.
## Bones the source lacks follow their parent at rest (e.g. toes, extra leaf bones).
## A bone hung off a different parent than the profile expects (the modular rig's feet, children
## of Root for its IK) is placed where its profile parent carries it, so it follows the leg.
##
## Layers laid over the copied pose, in order:
## 1. Upper body ([member upper_source]): the spine, head, arms and fingers copy a second animation
##    rig (e.g. one playing the gun-holding clip) relative to the hips, so the weapon stays raised
##    whatever the legs play.
## 2. Crouch ([member crouch_drop]).
## 3. Reach ([member reach]): each hand is pulled to a point by a two-bone solve of its arm, the
##    elbow bending toward a hint. [member before_reach] runs first, so the owner can place what the
##    hands hold from the posed body ([method posed_position]).
## 4. Collapsed bones ([member collapsed]) shrink to nothing (first-person arms hide head and legs).

## The skeleton the AnimationPlayer drives.
var source: Skeleton3D = null
## How far the hips drop for a crouch, in metres of this skeleton's model space (0 = standing).
## The animation set has no crouch clips, so the crouch is laid over whatever plays: thighs swing
## forward, shins back and the upper body leans, keeping the feet where the clip puts them.
var crouch_drop: float = 0.0
## Upper-body layer: a second copy of the animation rig, or null for none (see the class notes).
var upper_source: Skeleton3D = null
## Turns the shoulders about the spine (radians, positive = right shoulder back), spread over the
## spine bones; the neck turns back so the head still looks ahead. A rifle's support hand needs it
## to reach the handguard.
var upper_twist: float = 0.0
## Points in world space for the hands to reach: &"Left" / &"Right" -> position. A hand with a
## frame in [member hand_frames] puts the middle of its closed grip there (measured from this
## rig's own hand, so big and small hands both close around it); otherwise the wrist goes there.
var reach: Dictionary[StringName, Vector3] = {}
## World-space direction each reaching elbow bends toward: &"Left" / &"Right" -> direction.
var elbow_hints: Dictionary[StringName, Vector3] = {}
## How each reaching hand is turned (world space): basis x = from the wrist toward the knuckles,
## basis y = out of the palm. A reaching hand with no frame keeps its turn relative to the forearm.
var hand_frames: Dictionary[StringName, Basis] = {}
## How far each reaching hand's fingers close around what it holds (0 open … 1 a fist).
var finger_curl: Dictionary[StringName, float] = {}
## Per side, single fingers closed by their own amount instead ("Index", "Middle", "Ring",
## "Little", "Thumb" -> 0..1), e.g. a finger lifted off a knife while it spins. The thumb
## otherwise closes [constant THUMB_SHARE] as far as the fingers.
var finger_curls: Dictionary[StringName, Dictionary] = {}
## Called with no arguments once the pose is built, before the hands reach.
var before_reach: Callable = Callable()
## Bones shrunk to nothing every frame (with everything hung from them).
var collapsed: Array[StringName] = []

## Largest share of the leg length the hips may drop.
const MAX_CROUCH_SHARE: float = 0.7
## Upper-body lean per radian of thigh swing.
const CROUCH_LEAN: float = 0.55

var _profile := SkeletonProfileHumanoid.new()
## Target bones in parent-first order.
var _order: PackedInt32Array = PackedInt32Array()
## Per target bone: the source bone it copies (-1 = follows its parent at rest).
var _source_of: PackedInt32Array = PackedInt32Array()
## Per target bone: rotation applied after the source's model-space pose (see [method bind]).
var _after: Array[Quaternion] = []
var _hips_target: int = -1
var _hips_source: int = -1
var _hips_scale: float = 1.0
var _bound_to: Skeleton3D = null
## Detached target bone -> the target bone the profile hangs it from (its anchor).
var _anchor_of: Dictionary[int, int] = {}
## Detached target bone -> its rest position in its anchor's rest frame (rotation only).
var _anchor_offset: Dictionary[int, Vector3] = {}
## Crouch: thigh bones, shin bones, the spine bones that lean, and the leg length.
var _thighs: PackedInt32Array = PackedInt32Array()
var _shins: PackedInt32Array = PackedInt32Array()
var _leaning: Dictionary[int, bool] = {}
var _leg_length: float = 0.0
## Target bones the upper-body layer poses.
var _upper: Dictionary[int, bool] = {}
## Share of [member upper_twist] each twisted bone carries (spine bones part, above them all of it,
## the neck and head none).
var _twist_share: Dictionary[int, float] = {}
## Per side: the hand's own frame in hand-bone space, from its rest finger positions
## (Basis x = wrist to knuckles, y = out of the palm), or absent when the hand has no fingers.
var _hand_rest_frame: Dictionary[StringName, Basis] = {}
## Per side: the middle of the closed grip in hand-bone space (part way to the knuckles, out
## toward the palm by a share of the hand's length).
var _grip_point: Dictionary[StringName, Vector3] = {}
## Per side: finger bones, each finger's chain base first.
var _finger_chains: Dictionary[StringName, Array] = {}
## Per side: the finger each chain in [member _finger_chains] belongs to.
var _finger_names: Dictionary[StringName, PackedStringArray] = {}
## Per side: the thumb's bones, base first.
var _thumb_chains: Dictionary[StringName, PackedInt32Array] = {}

## A finger's knuckle is its first joint at least this share of the way out to its last joint.
const KNUCKLE_SHARE: float = 0.35
## Where a closed hand's grip sits: this share of the way from the wrist to the knuckles, and out
## from the bones toward the palm by this share of that length.
const GRIP_ALONG: float = 0.75
const GRIP_OUT: float = 0.35
## Closing angles (radians at full curl) for the three joints of a finger, base first.
const CURL_ANGLES: Array[float] = [1.25, 1.4, 0.9]
const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
## The thumb's bones, base first, and how far (radians) each bends toward the palm when closed.
const THUMB_JOINTS: Array[String] = ["Metacarpal", "Proximal", "Distal"]
const THUMB_ANGLES: Array[float] = [1.1, 0.9, 0.8]
## Which way each thumb bone bends: toward the palm's face by this much, the rest across toward
## the little finger, so the base turns the thumb in front of the palm and the tip wraps over.
const THUMB_TOWARD_PALM: Array[float] = [0.6, 0.0, 0.0]
## How far the thumb closes, as a share of the fingers' curl, unless told otherwise.
const THUMB_SHARE: float = 0.7
const JOINTS: Array[String] = ["Proximal", "Intermediate", "Distal"]
## The last pose built, in this skeleton's model space (for [method posed_position]).
var _posed: PackedVector3Array = PackedVector3Array()


## Prepares the mapping between [param source_skeleton] and this modifier's skeleton. Both must be
## in the tree, posed at rest, and facing the same way. Returns false if no bones match.
func bind(source_skeleton: Skeleton3D) -> bool:
	source = source_skeleton
	var target := get_skeleton()
	_bound_to = null
	if source == null or target == null:
		return false
	var to_target := _rotation_between(source, target)
	var count := target.get_bone_count()
	_find_detached(target)
	_order = _parent_first(target, _anchor_of)
	_source_of.resize(count)
	_after.resize(count)
	var deltas: Array[Quaternion] = []
	deltas.resize(count)
	var matched := 0
	for bone: int in _order:
		var parent: int = _anchor_of.get(bone, target.get_bone_parent(bone))
		var delta: Quaternion = deltas[parent] if parent >= 0 else Quaternion.IDENTITY
		var bone_name := target.get_bone_name(bone)
		var from := source.find_bone(bone_name)
		_source_of[bone] = from
		if from >= 0:
			matched += 1
			var tail := _tail(bone_name, source, target)
			var target_tail := target.find_bone(tail) if not tail.is_empty() else -1
			var source_tail := source.find_bone(tail) if not tail.is_empty() else -1
			if target_tail >= 0 and source_tail >= 0:
				var current := delta * (target.get_bone_global_rest(target_tail).origin - target.get_bone_global_rest(bone).origin)
				var wanted := to_target * (source.get_bone_global_rest(source_tail).origin - source.get_bone_global_rest(from).origin)
				if current.length() > 0.0001 and wanted.length() > 0.0001:
					delta = Quaternion(current.normalized(), wanted.normalized()) * delta
			var source_rest := to_target * source.get_bone_global_rest(from).basis.get_rotation_quaternion() * to_target.inverse()
			var target_rest := target.get_bone_global_rest(bone).basis.get_rotation_quaternion()
			# Model-space pose of the target = to_target * P * to_target^-1 * source_rest^-1 * delta * target_rest.
			_after[bone] = to_target.inverse() * source_rest.inverse() * delta * target_rest
		deltas[bone] = delta
	_hips_target = target.find_bone(&"Hips")
	_hips_source = source.find_bone(&"Hips")
	if _hips_target >= 0 and _hips_source >= 0:
		var source_height := (source.global_transform * source.get_bone_global_rest(_hips_source).origin).y - source.global_position.y
		var target_height := (target.global_transform * target.get_bone_global_rest(_hips_target).origin).y - target.global_position.y
		_hips_scale = target_height / source_height if absf(source_height) > 0.001 else 1.0
	_find_crouch_bones(target)
	_find_upper_bones(target)
	_find_hands(target)
	if matched == 0:
		return false
	_bound_to = target
	return true


## Whether [method bind] succeeded for the current skeleton.
func is_bound() -> bool:
	return _bound_to != null and _bound_to == get_skeleton() and is_instance_valid(source)


func _process_modification() -> void:
	if not is_bound():
		return
	var target := get_skeleton()
	var to_target := _rotation_between(source, target)
	var count := target.get_bone_count()
	var globals: Array[Quaternion] = []
	globals.resize(count)
	var positions: PackedVector3Array = PackedVector3Array()
	positions.resize(count)
	var hips_position := _hips_position(target)
	var swing := crouch_angle()
	var thigh_turn := Quaternion(Vector3.RIGHT, -swing)
	var shin_turn := Quaternion(Vector3.RIGHT, swing)
	var lean_turn := Quaternion(Vector3.RIGHT, swing * CROUCH_LEAN)
	if swing > 0.0:
		hips_position.y -= crouch_amount_metres()
	# World up in model space: turning about it by a negative angle takes the right shoulder back
	# whichever way the body faces.
	var twist_axis := (target.global_transform.basis.orthonormalized().inverse() * Vector3.UP).normalized()
	var layered := upper_source != null and is_instance_valid(upper_source) and upper_source.is_inside_tree() \
		and _hips_target >= 0 and _hips_source >= 0
	var upper_hips := Quaternion.IDENTITY
	if layered:
		upper_hips = (to_target * upper_source.get_bone_global_pose(_hips_source).basis.get_rotation_quaternion() * _after[_hips_target]).inverse()
	for bone: int in _order:
		var parent := target.get_bone_parent(bone)
		var parent_global: Quaternion = globals[parent] if parent >= 0 else Quaternion.IDENTITY
		var parent_position: Vector3 = positions[parent] if parent >= 0 else Vector3.ZERO
		var rest := target.get_bone_rest(bone)
		var from := _source_of[bone]
		var global: Quaternion
		if from >= 0:
			if layered and _upper.has(bone):
				global = globals[_hips_target] * upper_hips \
					* to_target * upper_source.get_bone_global_pose(from).basis.get_rotation_quaternion() * _after[bone]
			else:
				global = to_target * source.get_bone_global_pose(from).basis.get_rotation_quaternion() * _after[bone]
			if upper_twist != 0.0 and _twist_share.has(bone):
				global = Quaternion(twist_axis, -upper_twist * _twist_share[bone]) * global
			if swing > 0.0:
				if _thighs.has(bone):
					global = thigh_turn * global
				elif _shins.has(bone):
					global = shin_turn * global
				elif _leaning.has(bone):
					global = lean_turn * global
			target.set_bone_pose_rotation(bone, (parent_global.inverse() * global).normalized())
		else:
			global = parent_global * rest.basis.get_rotation_quaternion()
			target.set_bone_pose_rotation(bone, rest.basis.get_rotation_quaternion())
		globals[bone] = global
		var wanted_position := parent_position + parent_global * rest.origin
		if bone == _hips_target:
			wanted_position = hips_position
		elif _anchor_of.has(bone):
			var anchor := _anchor_of[bone]
			wanted_position = positions[anchor] + globals[anchor] * _anchor_offset[bone]
		else:
			positions[bone] = wanted_position
			continue
		target.set_bone_pose_position(bone, parent_global.inverse() * (wanted_position - parent_position))
		positions[bone] = wanted_position
	_posed = positions
	if before_reach.is_valid():
		before_reach.call()
	var to_model := target.global_transform.affine_inverse()
	var to_model_turn := target.global_transform.basis.orthonormalized().inverse()
	for side: StringName in reach:
		var hint: Vector3 = elbow_hints.get(side, Vector3.DOWN)
		var goal := to_model * reach[side]
		if hand_frames.has(side) and _hand_rest_frame.has(side):
			var wanted := (to_model_turn * hand_frames[side]).orthonormalized()
			var hand_turn := Basis(_frame(wanted)) * Basis(_frame(_hand_rest_frame[side])).inverse()
			goal -= hand_turn * _grip_point[side]
		_reach_with(target, side, goal, to_model.basis * hint, globals, positions)
	for bone_name: StringName in collapsed:
		var bone := target.find_bone(bone_name)
		if bone >= 0:
			target.set_bone_pose_scale(bone, Vector3.ONE * 0.001)


## Where a hand's grip is in world space (the point [member reach] aims; the wrist for a hand
## without fingers). Reads the final pose, so call it from [signal Skeleton3D.skeleton_updated].
func grip_position(side: StringName) -> Vector3:
	var target := get_skeleton()
	var hand := target.find_bone(String(side) + "Hand") if target != null else -1
	if hand < 0:
		return Vector3.ZERO
	var pose := target.get_bone_global_pose(hand)
	var local: Vector3 = _grip_point.get(side, Vector3.ZERO) if hand_frames.has(side) else Vector3.ZERO
	return target.global_transform * (pose * local)


## Where a bone is in world space in the pose being built (call from [member before_reach], before
## any reach). The skeleton's origin when the bone is missing.
func posed_position(bone_name: StringName) -> Vector3:
	var target := get_skeleton()
	var bone := target.find_bone(bone_name) if target != null else -1
	if bone < 0 or bone >= _posed.size():
		return target.global_position if target != null else Vector3.ZERO
	return target.global_transform * _posed[bone]


## Two-bone solve: turns the upper and lower arm of [param side] so its hand bone lands on
## [param goal] (model space), the elbow bending toward [param hint]. Out-of-reach goals are
## reached for as far as the arm goes. The hand keeps its turn relative to the forearm.
func _reach_with(target: Skeleton3D, side: StringName, goal: Vector3, hint: Vector3,
		globals: Array[Quaternion], positions: PackedVector3Array) -> void:
	var upper := target.find_bone(String(side) + "UpperArm")
	var lower := target.find_bone(String(side) + "LowerArm")
	var hand := target.find_bone(String(side) + "Hand")
	if upper < 0 or lower < 0 or hand < 0 or target.get_bone_parent(lower) != upper or target.get_bone_parent(hand) != lower:
		return
	var shoulder := positions[upper]
	var elbow := positions[lower]
	var wrist := positions[hand]
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var to_goal := goal - shoulder
	if a < 0.0001 or b < 0.0001 or to_goal.length() < 0.0001:
		return
	var direction := to_goal.normalized()
	var d := clampf(to_goal.length(), absf(a - b) + 0.0001, a + b - 0.0001)
	var bend := hint - direction * hint.dot(direction)
	if bend.length() < 0.0001:
		bend = (elbow - shoulder) - direction * (elbow - shoulder).dot(direction)
	bend = bend.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var new_elbow := shoulder + direction * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	var new_wrist := shoulder + direction * d
	var turn_upper := Quaternion((elbow - shoulder).normalized(), (new_elbow - shoulder).normalized())
	var moved_wrist := new_elbow + turn_upper * (wrist - elbow)
	var turn_lower := Quaternion((moved_wrist - new_elbow).normalized(), (new_wrist - new_elbow).normalized())
	var upper_global := (turn_upper * globals[upper]).normalized()
	var lower_global := (turn_lower * turn_upper * globals[lower]).normalized()
	var parent := target.get_bone_parent(upper)
	var parent_global: Quaternion = globals[parent] if parent >= 0 else Quaternion.IDENTITY
	target.set_bone_pose_rotation(upper, (parent_global.inverse() * upper_global).normalized())
	target.set_bone_pose_rotation(lower, (upper_global.inverse() * lower_global).normalized())
	globals[upper] = upper_global
	globals[lower] = lower_global
	globals[hand] = (turn_lower * turn_upper * globals[hand]).normalized()
	positions[lower] = new_elbow
	positions[hand] = new_wrist
	if hand_frames.has(side) and _hand_rest_frame.has(side):
		var wanted := (target.global_transform.basis.orthonormalized().inverse() * hand_frames[side]).orthonormalized()
		var hand_global := (Basis(_frame(wanted)) * Basis(_frame(_hand_rest_frame[side])).inverse()).get_rotation_quaternion()
		target.set_bone_pose_rotation(hand, (lower_global.inverse() * hand_global).normalized())
		globals[hand] = hand_global
		_curl(target, side, hand_global, wanted, clampf(finger_curl.get(side, 0.0), 0.0, 1.0), finger_curls.get(side, {}))


## Closes a hand's fingers by [param amount] about the knuckle line ([param frame]: x wrist to
## knuckles, y out of the palm, model space), from their straight rest.
func _curl(target: Skeleton3D, side: StringName, hand_global: Quaternion, frame: Basis, amount: float,
		single: Dictionary) -> void:
	var axis := frame.x.cross(frame.y).normalized()
	var chains: Array = _finger_chains.get(side, [])
	var names: PackedStringArray = _finger_names.get(side, PackedStringArray())
	for index: int in chains.size():
		var chain: PackedInt32Array = chains[index]
		var finger_amount := amount
		if index < names.size() and single.has(names[index]):
			finger_amount = clampf(float(single[names[index]]), 0.0, 1.0)
		var parent_global := hand_global
		var joint := 0
		for bone: int in chain:
			var rest := target.get_bone_rest(bone).basis.get_rotation_quaternion()
			var angle: float = CURL_ANGLES[mini(joint, CURL_ANGLES.size() - 1)] * finger_amount
			var local := (Quaternion(parent_global.inverse() * axis, angle) * rest).normalized()
			target.set_bone_pose_rotation(bone, local)
			parent_global = parent_global * local
			joint += 1
	var thumb_amount := clampf(float(single.get("Thumb", amount * THUMB_SHARE)), 0.0, 1.0)
	var little_side := frame.z.normalized() * (-1.0 if side == &"Right" else 1.0)
	_curl_thumb(target, side, hand_global, frame.y.normalized(), little_side, thumb_amount)


## Bends a hand's thumb in by [param amount] (model space: [param palm] out of the palm,
## [param little_side] toward the little finger): each bone turns its own length toward a mix of
## the two (see [constant THUMB_TOWARD_PALM]), so the thumb folds over whatever the hand holds
## whichever way the rig built it.
func _curl_thumb(target: Skeleton3D, side: StringName, hand_global: Quaternion, palm: Vector3, little_side: Vector3,
		amount: float) -> void:
	var thumb: PackedInt32Array = _thumb_chains.get(side, PackedInt32Array())
	var parent_global := hand_global
	for joint: int in thumb.size():
		var bone := thumb[joint]
		var rest := target.get_bone_rest(bone).basis.get_rotation_quaternion()
		var along := target.get_bone_rest(thumb[joint + 1]).origin if joint + 1 < thumb.size() 			else rest.inverse() * target.get_bone_rest(bone).origin
		var direction := (parent_global * rest) * along
		var weight: float = THUMB_TOWARD_PALM[mini(joint, THUMB_TOWARD_PALM.size() - 1)]
		var axis := direction.cross(palm * weight + little_side * (1.0 - weight * 0.5))
		if axis.length() < 0.000001:
			target.set_bone_pose_rotation(bone, rest)
			parent_global = parent_global * rest
			continue
		var angle: float = THUMB_ANGLES[mini(joint, THUMB_ANGLES.size() - 1)] * amount
		var local := (Quaternion(parent_global.inverse() * axis.normalized(), angle) * rest).normalized()
		target.set_bone_pose_rotation(bone, local)
		parent_global = parent_global * local


## An orthonormal basis from a frame's x (forward) and y (palm), keeping x exact.
static func _frame(frame: Basis) -> Basis:
	var forward := frame.x.normalized()
	var palm := (frame.y - forward * frame.y.dot(forward)).normalized()
	return Basis(forward, palm, forward.cross(palm))


## Each hand's rest frame, grip point and finger chains, from where its knuckles are at rest.
##
## Rigs disagree on where a finger starts: on most the Proximal bone sits at the knuckle, but the
## modular rig starts every finger's Proximal bone at one point beside the wrist (a palm bone) and
## its knuckles are a joint further out. So a finger's knuckle is its first joint at least
## [constant KNUCKLE_SHARE] of the way out to its last joint; the hand's direction, its sideways
## line and the grip come from those knuckles, and only the joints from the knuckle out curl.
func _find_hands(target: Skeleton3D) -> void:
	_hand_rest_frame.clear()
	_grip_point.clear()
	_finger_chains.clear()
	_finger_names.clear()
	_thumb_chains.clear()
	for side: String in ["Left", "Right"]:
		var hand := target.find_bone(side + "Hand")
		if hand < 0:
			continue
		var to_hand := target.get_bone_global_rest(hand).affine_inverse()
		var knuckles: Dictionary[String, Vector3] = {}
		var chains: Array[PackedInt32Array] = []
		var names := PackedStringArray()
		for finger: String in FINGERS:
			var joints := PackedInt32Array()
			for joint: String in JOINTS:
				var bone := target.find_bone(side + finger + joint)
				if bone >= 0:
					joints.append(bone)
			if joints.is_empty():
				continue
			var reach_out := (to_hand * target.get_bone_global_rest(joints[joints.size() - 1]).origin).length()
			var chain := PackedInt32Array()
			for bone: int in joints:
				var at := to_hand * target.get_bone_global_rest(bone).origin
				if chain.is_empty() and at.length() < reach_out * KNUCKLE_SHARE:
					continue
				if chain.is_empty():
					knuckles[finger] = at
				chain.append(bone)
			if not chain.is_empty():
				chains.append(chain)
				names.append(finger)
		_finger_chains[StringName(side)] = chains
		_finger_names[StringName(side)] = names
		var thumb := PackedInt32Array()
		for joint: String in THUMB_JOINTS:
			var bone := target.find_bone(side + "Thumb" + joint)
			if bone >= 0:
				thumb.append(bone)
		_thumb_chains[StringName(side)] = thumb
		if not knuckles.has("Index") or not knuckles.has("Little"):
			continue
		var middle: Vector3 = knuckles.get("Middle", (knuckles["Index"] + knuckles["Little"]) * 0.5)
		var forward := middle.normalized()
		var across: Vector3 = knuckles["Index"] - knuckles["Little"]
		if across.length() < 0.0001 or forward.length() < 0.0001:
			continue
		# Handedness: with the index finger's knuckle ahead of the little finger's, the palm faces
		# forward x across on a left hand and across x forward on a right hand.
		var palm := (forward.cross(across) if side == "Left" else across.cross(forward)).normalized()
		palm = (palm - forward * palm.dot(forward)).normalized()
		_hand_rest_frame[StringName(side)] = Basis(forward, palm, forward.cross(palm))
		_grip_point[StringName(side)] = middle * GRIP_ALONG + palm * middle.length() * GRIP_OUT


## The bones the upper-body layer poses: the spine and everything above it.
func _find_upper_bones(target: Skeleton3D) -> void:
	_upper.clear()
	var spine := target.find_bone(&"Spine")
	if spine < 0:
		return
	for bone: int in target.get_bone_count():
		if bone == spine or _is_ancestor(target, spine, bone):
			_upper[bone] = true
	_twist_share.clear()
	var spine_chain: Array[int] = []
	for bone_name: StringName in [&"Spine", &"Chest", &"UpperChest"]:
		var bone := target.find_bone(bone_name)
		if bone >= 0:
			spine_chain.append(bone)
	var neck := target.find_bone(&"Neck")
	var head := target.find_bone(&"Head")
	for bone: int in _upper:
		if spine_chain.has(bone):
			_twist_share[bone] = float(spine_chain.find(bone) + 1) / spine_chain.size()
		elif bone == neck or bone == head or (neck >= 0 and _is_ancestor(target, neck, bone)) 				or (head >= 0 and _is_ancestor(target, head, bone)):
			_twist_share[bone] = 0.0
		else:
			_twist_share[bone] = 1.0


## The hips' drop actually used (limited by the leg length).
func crouch_amount_metres() -> float:
	return clampf(crouch_drop, 0.0, _leg_length * MAX_CROUCH_SHARE)


## How far the thighs swing forward for the current [member crouch_drop] (radians): with thigh
## and shin swung by the same angle the hips drop by leg length × (1 − cos angle) above the feet.
func crouch_angle() -> float:
	if _leg_length <= 0.0 or crouch_drop <= 0.0:
		return 0.0
	return acos(clampf(1.0 - crouch_amount_metres() / _leg_length, -1.0, 1.0))


func _find_crouch_bones(target: Skeleton3D) -> void:
	_thighs = PackedInt32Array()
	_shins = PackedInt32Array()
	_leaning.clear()
	_leg_length = 0.0
	for side: String in ["Left", "Right"]:
		var thigh := target.find_bone(side + "UpperLeg")
		var shin := target.find_bone(side + "LowerLeg")
		var foot := target.find_bone(side + "Foot")
		if thigh < 0 or shin < 0 or foot < 0:
			continue
		_thighs.append(thigh)
		_shins.append(shin)
		var length := target.get_bone_global_rest(thigh).origin.distance_to(target.get_bone_global_rest(shin).origin) 			+ target.get_bone_global_rest(shin).origin.distance_to(target.get_bone_global_rest(foot).origin)
		_leg_length = length if _leg_length <= 0.0 else minf(_leg_length, length)
	# Only the spine leans: arms, neck and head keep the clip's directions, so the aim and the
	# gaze stay level while the torso bends forward.
	for bone_name: StringName in [&"Spine", &"Chest", &"UpperChest"]:
		var bone := target.find_bone(bone_name)
		if bone >= 0:
			_leaning[bone] = true


## Where the target's hips go: their rest position plus the source hips' movement, scaled by hip
## height and turned into the target's space.
func _hips_position(target: Skeleton3D) -> Vector3:
	var rest_position := target.get_bone_global_rest(_hips_target).origin if _hips_target >= 0 else Vector3.ZERO
	if _hips_target < 0 or _hips_source < 0:
		return rest_position
	var moved := source.get_bone_global_pose(_hips_source).origin - source.get_bone_global_rest(_hips_source).origin
	var world_offset := source.global_transform.basis * moved * _hips_scale
	return rest_position + target.global_transform.basis.inverse() * world_offset


## Finds mapped bones whose parent is not the bone the profile hangs them from (or an ancestor of
## it): they get re-placed from that anchor every frame.
func _find_detached(target: Skeleton3D) -> void:
	_anchor_of.clear()
	_anchor_offset.clear()
	for bone: int in target.get_bone_count():
		var index := _profile.find_bone(target.get_bone_name(bone))
		if index < 0:
			continue
		var anchor := -1
		var up := _profile.get_bone_parent(index)
		while not up.is_empty() and anchor < 0:
			anchor = target.find_bone(up)
			up = _profile.get_bone_parent(_profile.find_bone(up))
		if anchor < 0 or _is_ancestor(target, anchor, bone):
			continue
		var anchor_rest := target.get_bone_global_rest(anchor)
		_anchor_of[bone] = anchor
		_anchor_offset[bone] = anchor_rest.basis.get_rotation_quaternion().inverse() 			* (target.get_bone_global_rest(bone).origin - anchor_rest.origin)


static func _is_ancestor(skeleton: Skeleton3D, ancestor: int, bone: int) -> bool:
	var current := skeleton.get_bone_parent(bone)
	while current >= 0:
		if current == ancestor:
			return true
		current = skeleton.get_bone_parent(current)
	return false


## The profile bone [param bone_name] points at, present in both skeletons, or "" when there is
## none: the profile's named tail, else its only child, walking down single-child chains past bones
## one of the rigs lacks (Spine -> Chest -> UpperChest). Bones with several children (UpperChest,
## Head) or none follow their parent's alignment.
func _tail(bone_name: StringName, a: Skeleton3D, b: Skeleton3D) -> StringName:
	var index := _profile.find_bone(bone_name)
	if index < 0:
		return &""
	var next := _profile.get_bone_tail(index)
	if next.is_empty():
		next = _only_child(bone_name)
	while not next.is_empty():
		if a.find_bone(next) >= 0 and b.find_bone(next) >= 0:
			return next
		next = _only_child(next)
	return &""


func _only_child(bone_name: StringName) -> StringName:
	var found: StringName = &""
	for index: int in _profile.bone_size:
		if _profile.get_bone_parent(index) == bone_name:
			if not found.is_empty():
				return &""
			found = _profile.get_bone_name(index)
	return found


## Rotation that turns directions in [param from]'s model space into [param to]'s.
static func _rotation_between(from: Skeleton3D, to: Skeleton3D) -> Quaternion:
	var relative := to.global_transform.affine_inverse() * from.global_transform
	return relative.basis.orthonormalized().get_rotation_quaternion()


## Bones ordered so every bone comes after its parent and after its anchor (if detached).
static func _parent_first(skeleton: Skeleton3D, anchors: Dictionary[int, int]) -> PackedInt32Array:
	var order := PackedInt32Array()
	var placed: Dictionary[int, bool] = {}
	for bone: int in skeleton.get_bone_count():
		_place(skeleton, bone, anchors, placed, order)
	return order


static func _place(skeleton: Skeleton3D, bone: int, anchors: Dictionary[int, int], placed: Dictionary[int, bool], order: PackedInt32Array) -> void:
	if placed.has(bone):
		return
	placed[bone] = true
	var parent := skeleton.get_bone_parent(bone)
	if parent >= 0:
		_place(skeleton, parent, anchors, placed, order)
	if anchors.has(bone):
		_place(skeleton, anchors[bone], anchors, placed, order)
	order.append(bone)
