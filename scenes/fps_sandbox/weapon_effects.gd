class_name WeaponEffects
extends Node3D
## Presentation only: first-person viewmodel (with the player's own character arms holding it,
## see [FirstPersonArms]), muzzle flash, tracers, bullet impact marks, knife swings and grenade
## throws. Listens to a [WeaponController]; never affects where shots go or
## what they hit.

const MAX_IMPACTS: int = 80
const IMPACT_LIFETIME: float = 12.0
const TRACER_LIFETIME: float = 0.06
const VIEWMODEL_REST := Vector3(0.17, -0.17, -0.3)
const SLASH_TIME: float = 0.3
const STAB_TIME: float = 0.55
const THROW_TIME: float = 0.3
## Where the knife's centre sits in the viewmodel and how it is turned (degrees).
const KNIFE_HOLD := Vector3(-0.02, -0.03, 0.02)
const KNIFE_HOLD_ROTATION := Vector3(8, 12, -10)
## Where a pistol sits from the viewmodel's rest (m): further out and nearer the middle than a
## long gun, so both first-person hands reach it in a two-handed grip and look their real size.
const PISTOL_HOLD := Vector3(-0.08, 0.0, -0.06)
## How far (degrees: x pitch, y yaw, z roll) the hands turn with an inspected item before it turns
## on in the fingers, roughly how far a wrist bends and a forearm twists: a knife spun round keeps
## turning while the hand turns this far and back (see [method _hand_angle]).
const HAND_TURN_LIMIT := Vector3(50.0, 50.0, 90.0)
## How far (m) the hand follows an item while it is in the air (an entry's "toss" span): the
## knife flies on, the hand flicks up only this far.
const HAND_FOLLOW: float = 0.06

var weapons: WeaponController
var viewmodel: Node3D
var impact_count: int = 0
## The modelled weapon in hand (null when there is no visible weapon).
var weapon_visual: WeaponVisual = null

var _gun_root: Node3D
## Where the hands hold the item: a stand-in for it in a root that follows the inspection more
## gently than the item itself (see [method _apply_inspect_pose]); the arms hold this.
var _hand_root: Node3D
var _hand_item: Node3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_left: float = 0.0
var _kick: float = 0.0
var _inspect_left: float = 0.0
## The item being inspected and how long its inspection lasts (see [InspectLibrary]).
var _inspect_id: StringName = &""
var _inspect_seconds: float = InspectLibrary.DEFAULT_SECONDS
## Knife swing / grenade throw animation: seconds left and which one.
var _swing_left: float = 0.0
var _swing_kind: StringName = &""
var _swing_side: float = 1.0
## 0..1: how far a readied grenade is drawn back.
var _ready_pose: float = 0.0
## The utility model in hand (null for guns and the knife).
var utility_model: Node3D = null
## The player's own arms holding the viewmodel (hidden when the player has no character look).
var arms: FirstPersonArms = null
var _impacts: Array[Node3D] = []
var _tracer_material := StandardMaterial3D.new()
var _impact_material := StandardMaterial3D.new()


func _ready() -> void:
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_impact_material.albedo_color = Color(0.06, 0.06, 0.07)
	_impact_material.roughness = 1.0


func bind(controller: WeaponController, camera: Camera3D) -> void:
	weapons = controller
	viewmodel = Node3D.new()
	viewmodel.name = "Viewmodel"
	viewmodel.position = VIEWMODEL_REST
	camera.add_child(viewmodel)
	arms = FirstPersonArms.new()
	camera.add_child(arms)
	arms.apply(CharacterAvatar.player_look())
	weapons.shot_fired.connect(_on_shot_fired)
	weapons.weapon_switched.connect(func(_s: WeaponState) -> void: _build_gun())
	weapons.melee_swung.connect(_on_melee_swung)
	weapons.utility_thrown.connect(func(_id: StringName) -> void: _start_swing(&"throw", THROW_TIME))
	_build_gun()


func _process(delta: float) -> void:
	if weapons == null or viewmodel == null:
		return
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var state := weapons.current()
	var lower := 0.0
	if state != null and state.is_reloading():
		lower = sin(state.reload_progress() * PI)
	if state != null and weapons.draw_remaining > 0.0:
		lower = maxf(lower, weapons.draw_remaining / state.definition.draw_time)
	viewmodel.position = VIEWMODEL_REST + Vector3(0, -0.18 * lower, 0.06 * _kick)
	viewmodel.rotation_degrees = Vector3(4.0 * _kick - 35.0 * lower, 0, 0)
	_ready_pose = move_toward(_ready_pose, 1.0 if weapons.is_throw_readied() else 0.0, delta * 6.0)
	if _ready_pose > 0.0:
		viewmodel.position += Vector3(0.02, 0.09, 0.1) * _ready_pose
		viewmodel.rotation_degrees += Vector3(-30.0, 0, 8.0) * _ready_pose
	if _swing_left > 0.0:
		_swing_left = maxf(_swing_left - delta, 0.0)
		_apply_swing_pose()
	if _inspect_left > 0.0:
		_inspect_left = maxf(_inspect_left - delta, 0.0)
		if lower > 0.0 or _inspect_left <= 0.0:
			_end_inspect()
		else:
			_apply_inspect_pose(1.0 - _inspect_left / _inspect_seconds)
	var item: Node3D = weapon_visual if weapon_visual != null else utility_model
	if item != null and _hand_item != null:
		_hand_item.transform = item.transform
	if _flash_left > 0.0:
		_flash_left -= delta
		var on := _flash_left > 0.0
		_flash_light.visible = on
		_flash_mesh.visible = on


## Starts the weapon inspection (turns the weapon to show both sides). Returns false when there
## is nothing to inspect or the weapon is busy.
func inspect() -> bool:
	var state := weapons.current() if weapons != null else null
	if (weapon_visual == null and utility_model == null) or state == null or state.is_reloading() \
			or weapons.draw_remaining > 0.0 or weapons.is_throw_readied():
		return false
	_inspect_id = weapon_visual.weapon_id if weapon_visual != null else state.definition.id
	_inspect_seconds = InspectLibrary.seconds(_inspect_id)
	_inspect_left = _inspect_seconds
	return true


func is_inspecting() -> bool:
	return _inspect_left > 0.0


## Inspection pose at [param progress] 0..1 from the item's [InspectLibrary] choreography. The
## pose moves the item's own root, turning it about the choreography's pivot.
##
## The hands follow a gentler version ([member _hand_root]): the firing hand stays on the item's
## grip wherever it goes, but each turn is wrapped and folded back past [constant HAND_TURN_LIMIT],
## so a spin or flip carries on in the fingers while a held pose is followed exactly. During the
## entry's "toss" span the hand follows the item only [constant HAND_FOLLOW] far. An entry with
## "grip_pivot" turns about the firing grip; one with "support" false lets the support hand go.
func _apply_inspect_pose(progress: float) -> void:
	var pose := InspectLibrary.sample(_inspect_id, progress)
	var entry := InspectLibrary.for_item(_inspect_id)
	var rot := pose["rot"] as Vector3
	var pos := pose["pos"] as Vector3
	var pivot := _item_point(pose["pivot"] as Vector3)
	if bool(entry.get("grip_pivot", false)) and weapon_visual != null:
		pivot = _grip_point()
	var turn := Basis.from_euler(rot * (PI / 180.0))
	_gun_root.transform = Transform3D(turn, pivot - turn * pivot + pos)
	var hand_rot := Vector3(_hand_angle(rot.x, HAND_TURN_LIMIT.x), _hand_angle(rot.y, HAND_TURN_LIMIT.y),
		_hand_angle(rot.z, HAND_TURN_LIMIT.z))
	var hand_turn := Basis.from_euler(hand_rot * (PI / 180.0))
	var grip := _grip_point()
	var follow := _gun_root.transform * grip - grip
	var toss: Vector2 = entry.get("toss", Vector2(2.0, 2.0))
	var airborne := smoothstep(toss.x, toss.x + 0.05, progress) * (1.0 - smoothstep(toss.y - 0.05, toss.y, progress))
	follow = follow.limit_length(lerpf(follow.length(), HAND_FOLLOW, airborne))
	_hand_root.transform = Transform3D(hand_turn, grip + follow - hand_turn * grip)
	if arms != null:
		arms.support_released = not bool(entry.get("support", true))
	var parts: Dictionary = pose["parts"]
	if weapon_visual != null:
		for part: StringName in parts:
			weapon_visual.set_part_angle(part, float(parts[part]))


func _end_inspect() -> void:
	_inspect_left = 0.0
	if arms != null:
		arms.support_released = false
	if _gun_root != null:
		_gun_root.transform = Transform3D.IDENTITY
		_hand_root.transform = Transform3D.IDENTITY
	if weapon_visual != null:
		for part: StringName in weapon_visual.part_names():
			weapon_visual.set_part_angle(part, 0.0)


## Where the firing hand holds the item in hand (viewmodel space, the item at rest).
func _grip_point() -> Vector3:
	if weapon_visual != null:
		return weapon_visual.transform * WeaponModels.hand_points(weapon_visual.weapon_id, weapon_visual.size)[&"Right"]
	return utility_model.position if utility_model != null else Vector3.ZERO


## How far the hands turn (degrees) when an inspected item has turned [param degrees] about one
## axis: whole turns count as none, up to [param limit] the hand turns with the item, and past it
## the hand turns back to rest at a half turn (the item turning on in the fingers).
static func _hand_angle(degrees: float, limit: float) -> float:
	var angle := wrapf(degrees, -180.0, 180.0)
	if absf(angle) <= limit:
		return angle
	return signf(angle) * limit * (180.0 - absf(angle)) / (180.0 - limit)


## A point given as a share of the item's size in its own space (see [InspectLibrary]), placed
## where the item is held.
func _item_point(share: Vector3) -> Vector3:
	if weapon_visual != null:
		return weapon_visual.transform * (share * weapon_visual.size)
	var centre := utility_model.position + Vector3(0, 0.06, 0) if utility_model != null else Vector3.ZERO
	return centre + share * Vector3(0.06, 0.12, 0.06)


func _on_melee_swung(heavy: bool) -> void:
	_swing_side = -_swing_side
	_start_swing(&"stab" if heavy else &"slash", STAB_TIME if heavy else SLASH_TIME)


func _start_swing(kind: StringName, seconds: float) -> void:
	_end_inspect()
	_swing_kind = kind
	_swing_left = seconds


## Knife slash (a sideways arc, alternating sides), stab (draw back, thrust) or throw (the arm
## comes forward and down).
func _apply_swing_pose() -> void:
	var duration := STAB_TIME if _swing_kind == &"stab" else (THROW_TIME if _swing_kind == &"throw" else SLASH_TIME)
	var t := 1.0 - _swing_left / duration
	match _swing_kind:
		&"slash":
			var arc := sin(t * PI)
			viewmodel.position += Vector3(-0.12 * _swing_side * (t - 0.5) * 2.0, 0.02 * arc, -0.06 * arc)
			viewmodel.rotation_degrees += Vector3(-10.0 * arc, 55.0 * _swing_side * (t - 0.5), -35.0 * _swing_side * arc)
		&"stab":
			var back := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.45, t))
			var thrust := smoothstep(0.3, 0.45, t) * (1.0 - smoothstep(0.6, 1.0, t))
			viewmodel.position += Vector3(-0.05 * thrust, 0.03 * back, 0.08 * back - 0.2 * thrust)
			viewmodel.rotation_degrees += Vector3(20.0 * back - 15.0 * thrust, 0, 0)
		&"throw":
			var follow := sin(t * PI)
			viewmodel.position += Vector3(-0.03, -0.15 * t, -0.18 * follow)
			viewmodel.rotation_degrees += Vector3(-50.0 * follow, 0, 0)


## Re-applies the saved Coat and Magnets to the weapon in hand (after a change in the Armoury),
## and swaps the knife model if another knife look was chosen.
func refresh_cosmetics() -> void:
	if arms != null:
		arms.apply(CharacterAvatar.player_look())
		_hold_in_arms()
	var state := weapons.current() if weapons != null else null
	if state != null and state.definition.is_melee() 			and (weapon_visual == null or weapon_visual.weapon_id != CosmeticProfile.current().model_for(state.definition.id)):
		_build_gun()
	elif weapon_visual != null:
		weapon_visual.apply_loadout(CosmeticProfile.current().loadout(weapon_visual.weapon_id))


func _build_gun() -> void:
	if _gun_root != null:
		viewmodel.remove_child(_gun_root)
		_gun_root.queue_free()
		viewmodel.remove_child(_hand_root)
		_hand_root.queue_free()
	_gun_root = Node3D.new()
	viewmodel.add_child(_gun_root)
	_hand_root = Node3D.new()
	_hand_root.name = "HandHold"
	viewmodel.add_child(_hand_root)
	_hand_item = Node3D.new()
	_hand_root.add_child(_hand_item)
	weapon_visual = null
	utility_model = null
	_muzzle = null
	if arms != null:
		arms.hold(null, &"", Vector3.ZERO)
	_flash_left = 0.0
	_inspect_left = 0.0
	if _swing_kind != &"throw":
		_swing_left = 0.0
	var state := weapons.current()
	if state == null:
		return
	var id := state.definition.id
	if state.definition.is_utility():
		utility_model = UtilityModels.build(id)
		utility_model.position = Vector3(-0.02, -0.05, -0.02)
		utility_model.rotation_degrees = Vector3(-10, 25, -8)
		_gun_root.add_child(utility_model)
		_hold_in_arms()
		return
	var model_id := CosmeticProfile.current().model_for(id)
	var visual := WeaponVisual.new()
	_gun_root.add_child(visual)
	if not visual.setup(model_id):
		visual.queue_free()
		return
	weapon_visual = visual
	weapon_visual.apply_loadout(CosmeticProfile.current().loadout(model_id))
	_hold_in_arms()
	if state.definition.is_melee():
		# A knife is held out in the fist, blade forward and tilted in toward the centre.
		weapon_visual.rotation_degrees = KNIFE_HOLD_ROTATION
		weapon_visual.position = KNIFE_HOLD + weapon_visual.basis * Vector3(0, 0, -weapon_visual.size.z * 0.25)
		return
	var length := weapon_visual.size.z
	# Long guns sit with the butt just behind the view; pistols are held out at arm's length.
	var long_gun := length > 0.5
	var centre_z := 0.36 - length / 2.0 if long_gun else -length / 2.0
	var view: Vector3 = WeaponModels.info(id).get("view_offset", Vector3.ZERO)
	weapon_visual.position = Vector3(0, -weapon_visual.size.y * 0.22, centre_z) + view + (Vector3.ZERO if long_gun else PISTOL_HOLD)
	_add_muzzle(weapon_visual.position + Vector3(0, weapon_visual.size.y * 0.3, -length / 2.0 - 0.02))


## Puts whatever the viewmodel shows into the first-person arms' hands.
func _hold_in_arms() -> void:
	if arms == null:
		return
	var item: Node3D = weapon_visual if weapon_visual != null else utility_model
	if item != null:
		_hand_item.transform = item.transform
	if weapon_visual != null:
		arms.hold(_hand_item, weapon_visual.weapon_id, weapon_visual.size)
	elif utility_model != null:
		arms.hold(_hand_item, &"", Vector3.ZERO)
	else:
		arms.hold(null, &"", Vector3.ZERO)


func _add_muzzle(at: Vector3) -> void:
	_muzzle = Node3D.new()
	_muzzle.position = at
	_gun_root.add_child(_muzzle)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 2.5
	_flash_light.omni_range = 3.0
	_flash_light.visible = false
	_muzzle.add_child(_flash_light)
	var flash_sphere := SphereMesh.new()
	flash_sphere.radius = 0.035
	flash_sphere.height = 0.07
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = flash_sphere
	_flash_mesh.material_override = _tracer_material
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash_mesh)


func _on_shot_fired(_origin: Vector3, end_position: Vector3, result: Hitscan.Result) -> void:
	_kick = 1.0
	_end_inspect()
	if _muzzle != null:
		_flash_left = 0.045
	var start := _muzzle.global_position if _muzzle != null else _origin
	_spawn_tracer(start, end_position)
	if result.hit and result.hitbox == null:
		_spawn_impact(result.position, result.normal)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.material_override = _tracer_material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	tracer.global_position = from.lerp(to, 0.5)
	tracer.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(TRACER_LIFETIME).timeout.connect(tracer.queue_free)


func _spawn_impact(at: Vector3, normal: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.01)
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	mark.material_override = _impact_material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	mark.global_position = at + normal * 0.006
	var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD
	mark.look_at(at + normal, up)
	_impacts.append(mark)
	impact_count += 1
	if _impacts.size() > MAX_IMPACTS:
		_impacts.pop_front().queue_free()
	get_tree().create_timer(IMPACT_LIFETIME).timeout.connect(_expire_impact.bind(mark.get_instance_id()))


func _expire_impact(mark_id: int) -> void:
	var mark := instance_from_id(mark_id) as Node3D
	if mark != null and is_instance_valid(mark):
		_impacts.erase(mark)
		mark.queue_free()
