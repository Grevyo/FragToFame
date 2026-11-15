class_name WeaponController
extends Node
## Carries a set of weapons for one shooter and turns trigger input into hitscan shots.
##
## Input-agnostic: the owner sets [member trigger], [member motion] and calls
## [method select_slot] / [method request_reload]. The local player does this from the keyboard;
## bots will do it from AI. Presentation (tracers, viewmodel, sounds) listens to the signals.

signal shot_fired(origin: Vector3, end_position: Vector3, result: Hitscan.Result)
signal target_hit(info: DamageInfo, target: Health, killed: bool)
signal weapon_switched(state: WeaponState)
signal reload_started(state: WeaponState)
signal reload_finished(state: WeaponState)

## Shot origin and aim direction (forward = -Z). For players this is the head, not the camera,
## so camera punch never changes where bullets go.
var eye: Node3D
## Optional node that receives recoil view punch as its local rotation (the player camera).
var punch_target: Node3D
## Physics bodies the shots must ignore (the shooter's own body and hitboxes).
var exclude: Array[RID] = []
var motion := ShooterMotion.new()
var trigger: bool = false
## Stable ID recorded on damage events.
var shooter_id: String = "player_local"
## Team key of the shooter; hits on the same team deal no damage unless [member friendly_fire].
var team: StringName = &""
var friendly_fire: bool = false
var rng := RandomNumberGenerator.new()

var weapons: Array[WeaponState] = []
var current_index: int = 0
var draw_remaining: float = 0.0


func _init() -> void:
	set_loadout(WeaponCatalog.SANDBOX_LOADOUT)


func set_loadout(weapon_ids: Array[StringName]) -> void:
	weapons.clear()
	for id: StringName in weapon_ids:
		var definition := WeaponCatalog.get_definition(id)
		if definition != null:
			weapons.append(WeaponState.new(definition))
	current_index = 0
	draw_remaining = 0.0


## Weapon IDs currently carried, in loadout order.
func loadout_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for state: WeaponState in weapons:
		ids.append(state.definition.id)
	return ids


func has_weapon(id: StringName) -> bool:
	return loadout_ids().has(id)


## Adds weapon [param id], replacing any carried weapon of the same category (primary or
## secondary), and switches to it. Returns false for unknown IDs.
func give_weapon(id: StringName) -> bool:
	var definition := WeaponCatalog.get_definition(id)
	if definition == null:
		return false
	if current() != null:
		current().cancel_reload()
	for i: int in range(weapons.size() - 1, -1, -1):
		if weapons[i].definition.category == definition.category:
			weapons.remove_at(i)
	var state := WeaponState.new(definition)
	if definition.category == WeaponDefinition.CATEGORY_PRIMARY:
		weapons.insert(0, state)
	else:
		weapons.append(state)
	current_index = weapons.find(state)
	draw_remaining = definition.draw_time
	_apply_punch()
	weapon_switched.emit(state)
	return true


func current() -> WeaponState:
	if weapons.is_empty():
		return null
	return weapons[current_index]


func current_spread() -> float:
	var state := current()
	return state.current_spread(motion) if state != null else 0.0


## Switches to the weapon in loadout position [param index] (0-based). Returns false if invalid
## or already selected.
func select_index(index: int) -> bool:
	if index < 0 or index >= weapons.size() or index == current_index:
		return false
	current().cancel_reload()
	current().reset_recoil()
	current_index = index
	draw_remaining = current().definition.draw_time
	_apply_punch()
	weapon_switched.emit(current())
	return true


## Switches to the weapon whose definition uses [param slot] (1-based key slot).
func select_slot(slot: int) -> bool:
	for i: int in weapons.size():
		if weapons[i].definition.slot == slot:
			return select_index(i)
	return false


func cycle(direction: int) -> bool:
	if weapons.size() < 2:
		return false
	return select_index(posmod(current_index + direction, weapons.size()))


func request_reload() -> bool:
	var state := current()
	return state != null and draw_remaining <= 0.0 and state.start_reload()


func refill_all() -> void:
	for state: WeaponState in weapons:
		state.refill()
	draw_remaining = 0.0
	_apply_punch()


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the current weapon by [param delta] seconds and resolves any shots fired.
func step(delta: float) -> void:
	var state := current()
	if state == null or eye == null or not eye.is_inside_tree():
		return
	draw_remaining = maxf(draw_remaining - delta, 0.0)
	var offsets := state.update(delta, trigger and draw_remaining <= 0.0, motion, rng)
	if state.reload_started_this_step:
		reload_started.emit(state)
	if state.reload_finished_this_step:
		reload_finished.emit(state)
	for offset: Vector2 in offsets:
		_resolve_shot(state, offset)
	_apply_punch()


func _resolve_shot(state: WeaponState, offset: Vector2) -> void:
	var definition := state.definition
	var origin := eye.global_position
	var direction := Hitscan.offset_direction(eye.global_basis, offset)
	var space := eye.get_world_3d().direct_space_state
	var result := Hitscan.trace(space, origin, direction, definition.range_m, exclude)
	if result.hitbox != null and result.hitbox.health != null and not result.hitbox.health.is_dead \
			and (friendly_fire or result.hitbox.health.is_enemy_of(team)):
		var info := DamageInfo.new()
		info.amount = DamageModel.damage_for(definition, result.hitbox.zone, result.distance)
		info.armour_penetration = definition.armour_penetration
		info.zone = result.hitbox.zone
		info.weapon_id = definition.id
		info.source_id = shooter_id
		info.distance = result.distance
		info.position = result.position
		info.direction = direction
		var target := result.hitbox.health
		target.apply_damage(info)
		target_hit.emit(info, target, target.is_dead)
	shot_fired.emit(origin, result.position, result)


func _apply_punch() -> void:
	if punch_target == null:
		return
	var state := current()
	var punch := state.recoil_offset * state.definition.view_punch if state != null else Vector2.ZERO
	punch_target.rotation = Vector3(deg_to_rad(punch.y), deg_to_rad(-punch.x), 0.0)
