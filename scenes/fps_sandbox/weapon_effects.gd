class_name WeaponEffects
extends Node3D
## Presentation only: first-person viewmodel, muzzle flash, tracers and bullet impact marks.
## Listens to a [WeaponController]; never affects where shots go or what they hit.

const MAX_IMPACTS: int = 80
const IMPACT_LIFETIME: float = 12.0
const TRACER_LIFETIME: float = 0.06
const VIEWMODEL_REST := Vector3(0.17, -0.17, -0.3)
const VIEWMODEL_SCALE: float = 0.62
## Seconds a weapon inspection takes (shows the left side, then the right, then returns).
const INSPECT_TIME: float = 3.2

var weapons: WeaponController
var viewmodel: Node3D
var impact_count: int = 0
## The modelled weapon in hand (null while a development weapon without a model is held).
var weapon_visual: WeaponVisual = null

var _camera: Camera3D
var _gun_root: Node3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_left: float = 0.0
var _kick: float = 0.0
var _inspect_left: float = 0.0
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
	_camera = camera
	viewmodel = Node3D.new()
	viewmodel.name = "Viewmodel"
	viewmodel.position = VIEWMODEL_REST
	viewmodel.scale = Vector3.ONE * VIEWMODEL_SCALE
	camera.add_child(viewmodel)
	weapons.shot_fired.connect(_on_shot_fired)
	weapons.weapon_switched.connect(func(_s: WeaponState) -> void: _build_gun())
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
	if _inspect_left > 0.0:
		_inspect_left = 0.0 if lower > 0.0 else maxf(_inspect_left - delta, 0.0)
		_apply_inspect_pose(1.0 - _inspect_left / INSPECT_TIME)
	if _flash_left > 0.0:
		_flash_left -= delta
		var on := _flash_left > 0.0
		_flash_light.visible = on
		_flash_mesh.visible = on


## Starts the weapon inspection (turns the weapon to show both sides). Returns false when there
## is nothing to inspect or the weapon is busy.
func inspect() -> bool:
	var state := weapons.current() if weapons != null else null
	if state == null or state.is_reloading() or weapons.draw_remaining > 0.0:
		return false
	_inspect_left = INSPECT_TIME
	return true


func is_inspecting() -> bool:
	return _inspect_left > 0.0


## Inspection pose at [param progress] 0..1: bring the weapon to the middle of the view, turn
## it to show its left side, then its right side, then return.
func _apply_inspect_pose(progress: float) -> void:
	var blend := smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.85, 1.0, progress))
	var turn := sin(clampf((progress - 0.1) / 0.8, 0.0, 1.0) * TAU)
	viewmodel.position = viewmodel.position.lerp(Vector3(0.02, -0.1, -0.42), blend)
	viewmodel.rotation_degrees += Vector3(8.0, -75.0 * turn, 12.0 * turn) * blend


## Re-applies the saved Coat and Magnets to the weapon in hand (after a change in the Armoury).
func refresh_cosmetics() -> void:
	if weapon_visual != null:
		weapon_visual.apply_loadout(CosmeticProfile.current().loadout(weapon_visual.weapon_id))


func _build_gun() -> void:
	if _gun_root != null:
		_gun_root.queue_free()
	_gun_root = Node3D.new()
	viewmodel.add_child(_gun_root)
	weapon_visual = null
	_inspect_left = 0.0
	var state := weapons.current()
	var id := state.definition.id if state != null else &""
	if WeaponModels.has_model(id):
		_build_modelled_gun(id)
		return
	var length := 0.55
	var color := Color("2b2f36")
	match id:
		WeaponCatalog.KESTREL_PISTOL:
			length = 0.22
			color = Color("3a3f47")
		WeaponCatalog.WASP_SMG:
			length = 0.38
			color = Color("33363c")
	_part(Vector3(0.06, 0.09, length), Vector3(0, 0, -length / 2.0), color)
	_part(Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, -0.05), color.darkened(0.2))
	_part(Vector3(0.02, 0.02, 0.12), Vector3(0, 0.0, -length - 0.06), Color("15171a"))
	if id != WeaponCatalog.KESTREL_PISTOL:
		_part(Vector3(0.05, 0.14, 0.05), Vector3(0, -0.11, -length * 0.55), Color("ff6a2a").darkened(0.35))
	_add_muzzle(Vector3(0, 0, -length - 0.14))


## A modelled weapon at true size, wearing the player's Coat and Magnets.
func _build_modelled_gun(id: StringName) -> void:
	_gun_root.scale = Vector3.ONE / VIEWMODEL_SCALE  # The viewmodel node is scaled for the old boxes.
	weapon_visual = WeaponVisual.new()
	_gun_root.add_child(weapon_visual)
	weapon_visual.setup(id)
	weapon_visual.apply_loadout(CosmeticProfile.current().loadout(id))
	var length := weapon_visual.size.z
	# Long guns sit with the butt just behind the view; pistols are held out in front.
	var centre_z := 0.36 - length / 2.0 if length > 0.5 else 0.08 - length / 2.0
	var view: Vector3 = WeaponModels.info(id).get("view_offset", Vector3.ZERO)
	weapon_visual.position = Vector3(0, -weapon_visual.size.y * 0.22, centre_z) + view
	_add_muzzle(weapon_visual.position + Vector3(0, weapon_visual.size.y * 0.3, -length / 2.0 - 0.02))


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


func _part(size: Vector3, local_position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = local_position
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun_root.add_child(part)


func _on_shot_fired(_origin: Vector3, end_position: Vector3, result: Hitscan.Result) -> void:
	_kick = 1.0
	_inspect_left = 0.0
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
