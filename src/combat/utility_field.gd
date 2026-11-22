class_name UtilityField
extends Node3D
## Every grenade in flight and every active smoke and fire in one runtime world, plus what they
## do: frag blasts, flash blindness, smoke that blocks sight, and burning floor.
##
## One field per level (group [constant GROUP]); [WeaponController] throws into it and bots ask
## it whether smoke blocks their view. Damage goes through each target's [Health] with
## [constant DamageInfo.CAUSE_UTILITY], so match rules and statistics see it like any hit.
## Bullets pass through smoke; only sight is blocked.

signal utility_thrown(thrower_id: String, utility_id: StringName)
signal detonated(utility_id: StringName, position: Vector3, thrower_id: String)
## A grenade in flight bounced off something at [param speed] m/s (sound listens).
signal grenade_bounced(utility_id: StringName, position: Vector3, speed: float)
## A flash reached [param victim_id] for [param seconds] of blindness (teammates included).
signal combatant_flashed(thrower_id: String, victim_id: String, seconds: float)

const GROUP: StringName = &"utility_field"
## Flashes shorter than this are ignored (a glance at a distant flash).
const MIN_FLASH: float = 0.25
## Spacing of the floor samples a fire spreads over.
const FIRE_GRID: float = 0.75
const FIRE_PATCH_RADIUS: float = 0.55


class Smoke extends RefCounted:
	var centre: Vector3  # base of the cloud (on the floor)
	var radius: float
	var height: float
	var age: float = 0.0
	var bloom: float
	var duration: float
	var fade: float
	var thrower_id: String
	var node: Node3D

	## 0..1 share of the full size reached so far.
	func growth() -> float:
		return clampf(age / bloom, 0.0, 1.0)

	## 0..1 opacity (fades out over the last [member fade] seconds).
	func opacity() -> float:
		return clampf((duration - age) / fade, 0.0, 1.0)

	## Sight is blocked while the cloud is at least half grown and not more than half faded.
	func blocks() -> bool:
		return growth() >= 0.5 and opacity() >= 0.5

	func ellipsoid_centre() -> Vector3:
		return centre + Vector3(0, height * 0.5, 0)


class Fire extends RefCounted:
	var patches: PackedVector3Array
	var age: float = 0.0
	var duration: float
	var dps: float
	var tick: float
	var tick_left: float = 0.0
	var thrower_id: String
	var team: StringName
	var node: Node3D


var friendly_fire: bool = false
## Builds the model shown in flight for a utility ID (set by the runtime; may stay empty).
var model_factory: Callable
var grenades: Array[ThrownGrenade] = []
var smokes: Array[Smoke] = []
var fires: Array[Fire] = []
var time: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)


## The field of the world [param node] is in, or null.
static func find(node: Node) -> UtilityField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as UtilityField


## Throws [param id] from [param origin] at [param start_velocity]. [param exclude] keeps the
## grenade from bouncing off the thrower's own body.
func throw(id: StringName, origin: Vector3, start_velocity: Vector3, thrower_id: String, team: StringName,
		exclude: Array[RID] = []) -> ThrownGrenade:
	var grenade := ThrownGrenade.new()
	var model: Node3D = model_factory.call(id) if model_factory.is_valid() else null
	grenade.setup(id, origin, start_velocity, thrower_id, team, exclude, model)
	add_child(grenade)
	grenade.sync(0.0)
	grenades.append(grenade)
	utility_thrown.emit(thrower_id, id)
	return grenade


## Removes every grenade, smoke and fire (a new round).
func clear() -> void:
	for grenade: ThrownGrenade in grenades:
		grenade.queue_free()
	for smoke: Smoke in smokes:
		smoke.node.queue_free()
	for fire: Fire in fires:
		fire.node.queue_free()
	grenades.clear()
	smokes.clear()
	fires.clear()


# --- Queries ---------------------------------------------------------------------------------

## True when an active smoke cloud lies across the line from [param from] to [param to].
func blocks_sight(from: Vector3, to: Vector3) -> bool:
	for smoke: Smoke in smokes:
		if smoke.blocks() and _segment_hits_ellipsoid(from, to, smoke):
			return true
	return false


## 0..1: how deep inside smoke [param point] is (for the in-smoke screen tint).
func smoke_cover(point: Vector3) -> float:
	var best := 0.0
	for smoke: Smoke in smokes:
		var local := _to_unit(point, smoke)
		var depth := 1.0 - local.length()
		if depth > 0.0:
			best = maxf(best, clampf(depth * 3.0, 0.0, 1.0) * smoke.opacity() * smoke.growth())
	return best


## True when [param feet] stands in fire.
func is_burning(feet: Vector3) -> bool:
	for fire: Fire in fires:
		if _in_fire(fire, feet):
			return true
	return false


## True while a grenade, smoke or fire is still active.
func is_active() -> bool:
	return not (grenades.is_empty() and smokes.is_empty() and fires.is_empty())


# --- Simulation ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	time += delta
	var space := get_world_3d().direct_space_state
	for grenade: ThrownGrenade in grenades.duplicate():
		var bounces := grenade.flight.bounces
		grenade.flight.advance(space, delta)
		grenade.sync(delta)
		if grenade.flight.bounces > bounces:
			grenade_bounced.emit(grenade.utility_id, grenade.flight.position, grenade.flight.velocity.length())
		if grenade.should_detonate():
			grenades.erase(grenade)
			_detonate(grenade)
			grenade.queue_free()
	for smoke: Smoke in smokes.duplicate():
		smoke.age += delta
		if smoke.age >= smoke.duration:
			smokes.erase(smoke)
			smoke.node.queue_free()
		else:
			UtilityVisuals.set_smoke_growth(smoke.node, smoke.growth(), smoke.opacity(), time)
	for fire: Fire in fires.duplicate():
		fire.age += delta
		if fire.age >= fire.duration:
			fires.erase(fire)
			fire.node.queue_free()
			continue
		UtilityVisuals.animate_fire(fire.node, time, clampf((fire.duration - fire.age) / 1.0, 0.0, 1.0))
		fire.tick_left -= delta
		while fire.tick_left <= 0.0:
			fire.tick_left += fire.tick
			_burn(fire)


func _detonate(grenade: ThrownGrenade) -> void:
	var at := grenade.flight.position
	match EquipmentCatalog.utility_kind(grenade.utility_id):
		EquipmentCatalog.KIND_FRAG:
			_frag(grenade, at)
		EquipmentCatalog.KIND_FLASH:
			_flash(grenade, at)
		EquipmentCatalog.KIND_SMOKE:
			_smoke(grenade, at)
		EquipmentCatalog.KIND_FIRE:
			_fire(grenade, at)
	detonated.emit(grenade.utility_id, at, grenade.thrower_id)


func _frag(grenade: ThrownGrenade, at: Vector3) -> void:
	var params := grenade.params
	var radius := float(params["radius"])
	var definition := WeaponCatalog.get_definition(grenade.utility_id)
	UtilityVisuals.burst(self, at, Color(1.0, 0.7, 0.35), 6.0, radius * 1.4, 0.35, 0.5)
	for health: Health in _targets():
		if not _may_hurt(health, grenade.thrower_id, grenade.team):
			continue
		var chest := health.aim_point(false)
		var distance := at.distance_to(chest)
		if distance >= radius or not _exposed(at, health):
			continue
		var info := DamageInfo.new()
		info.amount = roundi(float(params["damage"]) * pow(1.0 - distance / radius, 1.25))
		if info.amount <= 0:
			continue
		info.cause = DamageInfo.CAUSE_UTILITY
		info.armour_penetration = definition.armour_penetration
		info.zone = DamageModel.ZONE_CHEST
		info.weapon_id = grenade.utility_id
		info.source_id = grenade.thrower_id
		info.distance = distance
		info.position = chest
		info.direction = (chest - at).normalized()
		health.apply_damage(info)


func _flash(grenade: ThrownGrenade, at: Vector3) -> void:
	var params := grenade.params
	UtilityVisuals.burst(self, at, Color(1.0, 1.0, 0.95), 14.0, 16.0, 0.22, 0.25)
	for health: Health in _targets():
		var body := health.body() as CombatantMovementBody
		if health.is_dead or body == null or body.head == null:
			continue
		var eye := body.head.global_position
		var seconds := flash_seconds(params, at, eye, -body.head.global_basis.z)
		if seconds < MIN_FLASH or not _clear_line(at, eye) or blocks_sight(at, eye):
			continue
		body.apply_flash(seconds)
		combatant_flashed.emit(grenade.thrower_id, health.owner_id, seconds)


## Seconds of blindness a flash at [param at] causes for eyes at [param eye] looking along
## [param view] (before cover is checked): full facing it up close, less turned away or far off.
static func flash_seconds(params: Dictionary, at: Vector3, eye: Vector3, view: Vector3) -> float:
	var distance := eye.distance_to(at)
	var flash_range := float(params["range"])
	if distance >= flash_range:
		return 0.0
	var full := float(params["full_range"])
	var near := 1.0 if distance <= full else pow(1.0 - (distance - full) / (flash_range - full), 1.6)
	var facing := clampf((view.normalized().dot((at - eye).normalized()) + 0.35) / 1.35, 0.0, 1.0)
	var behind := float(params["behind_share"])
	return float(params["max_blind"]) * near * lerpf(behind, 1.0, pow(facing, 1.4))


func _smoke(grenade: ThrownGrenade, at: Vector3) -> void:
	var params := grenade.params
	var smoke := Smoke.new()
	smoke.centre = _floor_below(at, 1.5, at)
	smoke.radius = float(params["radius"])
	smoke.height = float(params["height"])
	smoke.bloom = float(params["bloom"])
	smoke.duration = float(params["duration"])
	smoke.fade = float(params["fade"])
	smoke.thrower_id = grenade.thrower_id
	smoke.node = UtilityVisuals.smoke_cloud(smoke.radius, smoke.height, params["colour"])
	add_child(smoke.node)
	smoke.node.global_position = smoke.centre
	smokes.append(smoke)
	# Smoke puts out any fire under it.
	for fire: Fire in fires.duplicate():
		var kept := PackedVector3Array()
		for patch: Vector3 in fire.patches:
			if not _under(smoke, patch):
				kept.append(patch)
		if kept.size() != fire.patches.size():
			fires.erase(fire)
			fire.node.queue_free()
			if not kept.is_empty():
				_start_fire(kept, fire.duration - fire.age, fire.dps, fire.tick, fire.thrower_id, fire.team)


func _fire(grenade: ThrownGrenade, at: Vector3) -> void:
	var params := grenade.params
	var origin := at
	if grenade.flight.floor_touches == 0:
		var floor_point := _floor_below(at, float(params["drop"]), Vector3.INF)
		if floor_point == Vector3.INF:
			UtilityVisuals.burst(self, at, Color(1.0, 0.5, 0.2), 2.0, 3.0, 0.3, 0.15)
			return
		origin = floor_point
	if _in_any_smoke(origin):
		UtilityVisuals.burst(self, origin, Color(1.0, 0.5, 0.2), 1.5, 3.0, 0.3, 0.12)
		return
	var patches := fire_patches(get_world_3d().direct_space_state, origin, float(params["radius"]), float(params["step"]))
	if patches.is_empty():
		return
	_start_fire(patches, float(params["duration"]), float(params["dps"]), float(params["tick"]), grenade.thrower_id, grenade.team)


func _start_fire(patches: PackedVector3Array, duration: float, dps: float, tick: float, thrower_id: String,
		team: StringName) -> void:
	var fire := Fire.new()
	fire.patches = patches
	fire.duration = duration
	fire.dps = dps
	fire.tick = tick
	fire.thrower_id = thrower_id
	fire.team = team
	fire.node = UtilityVisuals.fire_patches(patches, FIRE_PATCH_RADIUS)
	add_child(fire.node)
	fire.node.global_position = Vector3.ZERO
	fires.append(fire)


## Floor points a fire burst at [param origin] spreads over: on a grid within [param radius],
## within [param step] metres of the burst's height, with open floor between them and the burst
## (fire never climbs walls or crosses them).
static func fire_patches(space: PhysicsDirectSpaceState3D, origin: Vector3, radius: float, step: float) -> PackedVector3Array:
	var patches := PackedVector3Array()
	var cells := ceili(radius / FIRE_GRID)
	for gx: int in range(-cells, cells + 1):
		for gz: int in range(-cells, cells + 1):
			var offset := Vector3(gx * FIRE_GRID, 0.0, gz * FIRE_GRID)
			if offset.length() > radius:
				continue
			var top := origin + offset + Vector3(0, step + 0.1, 0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - Vector3(0, step * 2.0 + 0.2, 0), Hitscan.LAYER_WORLD))
			if hit.is_empty() or (hit["normal"] as Vector3).y < GrenadeFlight.FLOOR_NORMAL_Y:
				continue
			var point: Vector3 = hit["position"]
			if absf(point.y - origin.y) > step:
				continue
			var lift := Vector3(0, 0.25, 0)
			var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + lift, point + lift, Hitscan.LAYER_WORLD))
			if not wall.is_empty():
				continue
			patches.append(point)
	return patches


func _burn(fire: Fire) -> void:
	var definition := WeaponCatalog.get_definition(EquipmentCatalog.FIRE)
	for health: Health in _targets():
		var body := health.body()
		if health.is_dead or body == null or not _may_hurt(health, fire.thrower_id, fire.team):
			continue
		if not _in_fire(fire, body.global_position):
			continue
		var info := DamageInfo.new()
		info.amount = maxi(roundi(fire.dps * fire.tick), 1)
		info.cause = DamageInfo.CAUSE_UTILITY
		info.armour_penetration = definition.armour_penetration
		info.zone = DamageModel.ZONE_LEGS
		info.weapon_id = EquipmentCatalog.FIRE
		info.source_id = fire.thrower_id
		info.position = body.global_position
		health.apply_damage(info)


# --- Helpers ---------------------------------------------------------------------------------

func _targets() -> Array[Health]:
	var list: Array[Health] = []
	for node: Node in get_tree().get_nodes_in_group(Health.GROUP):
		var health := node as Health
		if health != null and not health.is_dead and health.body() != null:
			list.append(health)
	return list


## The thrower always suffers their own blast and fire; teammates only with friendly fire.
func _may_hurt(health: Health, thrower_id: String, team: StringName) -> bool:
	return health.owner_id == thrower_id or friendly_fire or health.is_enemy_of(team)


## True when any part of the target (chest, head or feet) is in the open from [param at].
func _exposed(at: Vector3, health: Health) -> bool:
	var feet := health.body().global_position + Vector3(0, 0.25, 0)
	for point: Vector3 in [health.aim_point(false), health.aim_point(true), feet]:
		if _clear_line(at + Vector3(0, 0.1, 0), point):
			return true
	return false


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Hitscan.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _floor_below(at: Vector3, depth: float, fallback: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.1, 0), at - Vector3(0, depth, 0), Hitscan.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else fallback


func _in_fire(fire: Fire, feet: Vector3) -> bool:
	for patch: Vector3 in fire.patches:
		var rise := feet.y - patch.y
		if rise > -0.3 and rise < 1.0 and Vector2(feet.x - patch.x, feet.z - patch.z).length() <= FIRE_PATCH_RADIUS + 0.1:
			return true
	return false


## True when floor point [param point] lies under a smoke (fire cannot burn there).
func _in_any_smoke(point: Vector3) -> bool:
	for smoke: Smoke in smokes:
		if _under(smoke, point):
			return true
	return false


## Floor under a smoke: within its radius and between just below its base and its top.
static func _under(smoke: Smoke, point: Vector3) -> bool:
	var rise := point.y - smoke.centre.y
	return rise > -1.0 and rise < smoke.height \
		and Vector2(point.x - smoke.centre.x, point.z - smoke.centre.z).length() <= smoke.radius + 0.3


## [param point] in the smoke's unit-sphere space, at [param size] of its current growth.
func _to_unit(point: Vector3, smoke: Smoke, size: float = -1.0) -> Vector3:
	var scale_now := smoke.growth() if size < 0.0 else size
	var radius := maxf(smoke.radius * scale_now, 0.01)
	var half := maxf(smoke.height * 0.5 * scale_now, 0.01)
	var local := point - smoke.ellipsoid_centre()
	return Vector3(local.x / radius, local.y / half, local.z / radius)


func _segment_hits_ellipsoid(from: Vector3, to: Vector3, smoke: Smoke) -> bool:
	var a := _to_unit(from, smoke)
	var b := _to_unit(to, smoke)
	var d := b - a
	var length_sq := d.length_squared()
	if length_sq <= 0.000001:
		return a.length() <= 1.0
	var t := clampf(-a.dot(d) / length_sq, 0.0, 1.0)
	return (a + d * t).length() <= 1.0
