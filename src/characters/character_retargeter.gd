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

## The skeleton the AnimationPlayer drives.
var source: Skeleton3D = null
## How far the hips drop for a crouch, in metres of this skeleton's model space (0 = standing).
## The animation set has no crouch clips, so the crouch is laid over whatever plays: thighs swing
## forward, shins back and the upper body leans, keeping the feet where the clip puts them.
var crouch_drop: float = 0.0

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
	for bone: int in _order:
		var parent := target.get_bone_parent(bone)
		var parent_global: Quaternion = globals[parent] if parent >= 0 else Quaternion.IDENTITY
		var parent_position: Vector3 = positions[parent] if parent >= 0 else Vector3.ZERO
		var rest := target.get_bone_rest(bone)
		var from := _source_of[bone]
		var global: Quaternion
		if from >= 0:
			global = to_target * source.get_bone_global_pose(from).basis.get_rotation_quaternion() * _after[bone]
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
