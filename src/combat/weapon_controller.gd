class_name WeaponController
extends Node
## Carries a set of weapons for one shooter and turns trigger input into hitscan shots, knife
## swings and grenade throws.
##
## Input-agnostic: the owner sets [member trigger], [member secondary_trigger], [member motion]
## and calls [method select_slot] / [method request_reload]. The local player does this from the
## keyboard; bots from AI. Presentation (tracers, viewmodel, sounds) listens to the signals.
##
## Knife: the trigger slashes (repeating while held), the secondary trigger stabs. A hit on a
## victim facing away is a backstab.
## Utility: holding either trigger readies the throw; letting go of everything throws it. Left
## alone is a full throw, right alone a lob, both together a medium throw. Grenades go into the
## level's [UtilityField].

signal shot_attempted(weapon_id: StringName)
signal shot_fired(origin: Vector3, end_position: Vector3, result: Hitscan.Result)
signal target_hit(info: DamageInfo, target: Health, killed: bool)
signal weapon_switched(state: WeaponState)
signal reload_started(state: WeaponState)
signal reload_finished(state: WeaponState)
## A knife swing (hit or miss).
signal melee_swung(heavy: bool)
## A grenade left the hand.
signal utility_thrown(utility_id: StringName)

## Shot origin and aim direction (forward = -Z). For players this is the head, not the camera,
## so camera punch never changes where bullets go.
var eye: Node3D
## Optional node that receives recoil view punch as its local rotation (the player camera).
var punch_target: Node3D
## Physics bodies the shots must ignore (the shooter's own body and hitboxes).
var exclude: Array[RID] = []
var motion := ShooterMotion.new()
var trigger: bool = false
## Right mouse button: knife stab, grenade lob.
var secondary_trigger: bool = false
## Velocity of the shooter's body (grenades inherit it).
var carrier_velocity: Vector3 = Vector3.ZERO
## Stable ID recorded on damage events.
var shooter_id: String = "player_local"
## Team key of the shooter; hits on the same team deal no damage unless [member friendly_fire].
var team: StringName = &""
var friendly_fire: bool = false
var rng := RandomNumberGenerator.new()

var weapons: Array[WeaponState] = []
var current_index: int = 0
var draw_remaining: float = 0.0
## Seconds until the knife can swing again.
var melee_cooldown: float = 0.0
## Which throws have been asked for since the grenade was readied (empty = not readied).
var throw_buttons: Dictionary[StringName, bool] = {}

var _melee_chain: int = 0
var _secondary_was_held: bool = false
## The weapon to return to after the last grenade of a kind is thrown.
var _previous_index: int = 0


func _init() -> void:
	set_loadout(WeaponCatalog.SANDBOX_LOADOUT)


## Carries [param weapon_ids] in loadout order. Utility may repeat (two flashbangs = two
## entries); each kind of utility is one entry whose ammo is how many are carried.
func set_loadout(weapon_ids: Array[StringName]) -> void:
	weapons.clear()
	for id: StringName in weapon_ids:
		var definition := WeaponCatalog.get_definition(id)
		if definition == null:
			continue
		var existing := _state_for(id)
		if existing != null:
			if definition.is_utility():
				existing.ammo = mini(existing.ammo + 1, definition.magazine_size)
			continue
		var state := WeaponState.new(definition)
		if definition.is_utility():
			state.ammo = 1
		weapons.append(state)
	weapons.sort_custom(func(a: WeaponState, b: WeaponState) -> bool: return _order(a) < _order(b))
	current_index = 0
	_previous_index = 0
	draw_remaining = 0.0
	_reset_actions()
	_apply_punch()
	weapon_switched.emit(current())


## Weapon IDs currently carried, in loadout order (each kind of utility once).
func loadout_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for state: WeaponState in weapons:
		ids.append(state.definition.id)
	return ids


func has_weapon(id: StringName) -> bool:
	return loadout_ids().has(id)


## How many of utility [param id] are carried (0 when none).
func utility_count(id: StringName) -> int:
	var state := _state_for(id)
	return state.ammo if state != null and state.definition.is_utility() else 0


## Utility carried as {id: count}, in [constant EquipmentCatalog.UTILITY] order.
func utility_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for id: StringName in EquipmentCatalog.UTILITY:
		var count := utility_count(id)
		if count > 0:
			counts[id] = count
	return counts


## Adds one [param id] (up to its carry limit) without switching to it. Returns false when that
## kind is full or [param id] is not utility.
func give_utility(id: StringName) -> bool:
	var definition := WeaponCatalog.get_definition(id)
	if definition == null or not definition.is_utility():
		return false
	var state := _state_for(id)
	if state != null:
		if state.ammo >= definition.magazine_size:
			return false
		state.ammo += 1
		return true
	state = WeaponState.new(definition)
	state.ammo = 1
	var held := current()
	weapons.append(state)
	_sort_keeping(held)
	return true


## Adds weapon [param id], replacing any carried weapon of the same category (primary or
## secondary), and switches to it. Returns false for unknown IDs.
func give_weapon(id: StringName) -> bool:
	var definition := WeaponCatalog.get_definition(id)
	if definition == null:
		return false
	if definition.is_utility():
		return give_utility(id)
	if current() != null:
		current().cancel_reload()
	for i: int in range(weapons.size() - 1, -1, -1):
		if weapons[i].definition.category == definition.category:
			weapons.remove_at(i)
	var state := WeaponState.new(definition)
	weapons.append(state)
	_sort_keeping(state)
	_previous_index = current_index
	draw_remaining = definition.draw_time
	_reset_actions()
	_apply_punch()
	weapon_switched.emit(state)
	return true


func current() -> WeaponState:
	if weapons.is_empty():
		return null
	return weapons[current_index]


func current_spread() -> float:
	var state := current()
	if state == null or not state.definition.is_firearm():
		return 0.0
	return state.current_spread(motion)


## Switches to the weapon in loadout position [param index] (0-based). Returns false if invalid
## or already selected.
func select_index(index: int) -> bool:
	if index < 0 or index >= weapons.size() or index == current_index:
		return false
	current().cancel_reload()
	current().reset_recoil()
	if not current().definition.is_utility():
		_previous_index = current_index
	current_index = index
	draw_remaining = current().definition.draw_time
	_reset_actions()
	_apply_punch()
	weapon_switched.emit(current())
	return true


## Switches to the weapon whose definition uses [param slot] (1-based key slot). Pressing the
## utility slot again moves on to the next kind of utility carried.
func select_slot(slot: int) -> bool:
	var matches: Array[int] = []
	for i: int in weapons.size():
		if weapons[i].definition.slot == slot:
			matches.append(i)
	if matches.is_empty():
		return false
	var at := matches.find(current_index)
	return select_index(matches[(at + 1) % matches.size()] if at >= 0 else matches[0])


func cycle(direction: int) -> bool:
	if weapons.size() < 2:
		return false
	return select_index(posmod(current_index + direction, weapons.size()))


func request_reload() -> bool:
	var state := current()
	return state != null and state.definition.is_firearm() and draw_remaining <= 0.0 and state.start_reload()


## Full ammo for every gun (utility counts are kept: utility is bought, never refilled).
func refill_all() -> void:
	for state: WeaponState in weapons:
		if state.definition.is_firearm():
			state.refill()
	draw_remaining = 0.0
	_reset_actions()
	_apply_punch()


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the current weapon by [param delta] seconds and resolves any shots, swings or
## throws.
func step(delta: float) -> void:
	var state := current()
	if state == null or eye == null or not eye.is_inside_tree():
		return
	draw_remaining = maxf(draw_remaining - delta, 0.0)
	melee_cooldown = maxf(melee_cooldown - delta, 0.0)
	if state.definition.is_melee():
		_step_melee(state)
		return
	if state.definition.is_utility():
		_step_throw(state)
		return
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
	# Record the attempt before damage can end the round.
	shot_attempted.emit(definition.id)
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


# --- Knife -----------------------------------------------------------------------------------

func _step_melee(state: WeaponState) -> void:
	var stab_pressed := secondary_trigger and not _secondary_was_held
	_secondary_was_held = secondary_trigger
	if not trigger:
		_melee_chain = 0
	if draw_remaining > 0.0 or melee_cooldown > 0.0:
		return
	var params := state.definition.equipment
	var light: Dictionary = params["light"]
	var heavy: Dictionary = params["heavy"]
	if secondary_trigger and (stab_pressed or not trigger):
		_swing(state, heavy, true)
		melee_cooldown = float(heavy["interval"])
		_melee_chain = 0
	elif trigger:
		_swing(state, light, false)
		melee_cooldown = float(light["first_interval"] if _melee_chain == 0 else light["interval"])
		_melee_chain += 1


## One knife swing: the centre ray first, then a small fan around it (a swipe is wide).
func _swing(state: WeaponState, attack: Dictionary, heavy: bool) -> void:
	melee_swung.emit(heavy)
	var origin := eye.global_position
	var space := eye.get_world_3d().direct_space_state
	var reach := float(attack["range"])
	for offset: Vector2 in [Vector2.ZERO, Vector2(-5, 0), Vector2(5, 0), Vector2(0, -4), Vector2(0, 4)]:
		var direction := Hitscan.offset_direction(eye.global_basis, offset)
		var result := Hitscan.trace(space, origin, direction, reach, exclude)
		if result.hitbox == null:
			if result.hit and offset == Vector2.ZERO:
				return  # The blade met a wall straight ahead.
			continue
		var target := result.hitbox.health
		if target == null or target.is_dead or not (friendly_fire or target.is_enemy_of(team)):
			return
		var backstab := is_backstab(target, direction, float(state.definition.equipment["backstab_angle"]))
		var info := DamageInfo.new()
		info.amount = int(attack["backstab" if backstab else "damage"])
		info.armour_penetration = state.definition.armour_penetration
		info.zone = DamageModel.ZONE_CHEST
		info.weapon_id = state.definition.id
		info.source_id = shooter_id
		info.distance = result.distance
		info.position = result.position
		info.direction = direction
		target.apply_damage(info)
		target_hit.emit(info, target, target.is_dead)
		return


## True when the target faces within [param angle] degrees of the swing [param direction], so
## the blade comes from behind.
static func is_backstab(target: Health, direction: Vector3, angle: float) -> bool:
	var body := target.body()
	if body == null:
		return false
	var facing := -body.global_basis.z
	var flat_facing := Vector2(facing.x, facing.z)
	var flat_swing := Vector2(direction.x, direction.z)
	if flat_facing.length_squared() < 0.0001 or flat_swing.length_squared() < 0.0001:
		return false
	return flat_facing.normalized().dot(flat_swing.normalized()) >= cos(deg_to_rad(angle))


# --- Utility ---------------------------------------------------------------------------------

func _step_throw(state: WeaponState) -> void:
	_secondary_was_held = secondary_trigger
	if draw_remaining > 0.0 or state.ammo <= 0:
		return
	if trigger:
		throw_buttons[&"full"] = true
	if secondary_trigger:
		throw_buttons[&"lob"] = true
	if throw_buttons.is_empty() or trigger or secondary_trigger:
		return
	var speed := EquipmentCatalog.THROW_SPEED_FULL
	if throw_buttons.has(&"full") and throw_buttons.has(&"lob"):
		speed = EquipmentCatalog.THROW_SPEED_MEDIUM
	elif throw_buttons.has(&"lob"):
		speed = EquipmentCatalog.THROW_SPEED_LOB
	throw_buttons.clear()
	throw_current(speed)


## True while a throw is readied (a button is held on a grenade).
func is_throw_readied() -> bool:
	return not throw_buttons.is_empty()


## Throws the grenade in hand at [param speed] m/s along the view. Returns false when there is
## nothing to throw or no [UtilityField] in the world.
func throw_current(speed: float) -> bool:
	var state := current()
	var field := UtilityField.find(eye)
	if state == null or not state.definition.is_utility() or state.ammo <= 0 or field == null:
		return false
	var aim := -eye.global_basis.z.normalized()
	var origin := eye.global_position + aim * 0.25 + Vector3(0, -0.05, 0)
	# Never start inside a wall the thrower is pressed against.
	var space := eye.get_world_3d().direct_space_state
	var blocked := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position, origin, Hitscan.LAYER_WORLD, exclude))
	if not blocked.is_empty():
		origin = (blocked["position"] as Vector3) + (blocked["normal"] as Vector3) * 0.08
	var id := state.definition.id
	field.throw(id, origin, GrenadeFlight.throw_velocity(aim, speed, carrier_velocity), shooter_id, team, exclude)
	state.ammo -= 1
	utility_thrown.emit(id)
	if state.ammo <= 0:
		_drop_empty(state)
	return true


## Removes an exhausted kind of utility and returns to the weapon held before it.
func _drop_empty(state: WeaponState) -> void:
	var back: WeaponState = null
	if _previous_index < weapons.size() and _previous_index != current_index:
		back = weapons[_previous_index]
	weapons.erase(state)
	if back == null or not weapons.has(back):
		back = weapons[0] if not weapons.is_empty() else null
	current_index = maxi(weapons.find(back), 0)
	_previous_index = current_index
	draw_remaining = back.definition.draw_time if back != null else 0.0
	_reset_actions()
	weapon_switched.emit(current())


func _reset_actions() -> void:
	throw_buttons.clear()
	melee_cooldown = 0.0
	_melee_chain = 0


func _state_for(id: StringName) -> WeaponState:
	for state: WeaponState in weapons:
		if state.definition.id == id:
			return state
	return null


## Sorts into loadout order and keeps [param held] selected.
func _sort_keeping(held: WeaponState) -> void:
	weapons.sort_custom(func(a: WeaponState, b: WeaponState) -> bool: return _order(a) < _order(b))
	current_index = maxi(weapons.find(held), 0)


## Loadout order: primary, secondary, knife, then utility in shop order.
static func _order(state: WeaponState) -> int:
	var definition := state.definition
	if definition.is_utility():
		return 10 + EquipmentCatalog.UTILITY.find(definition.id)
	return 0 if definition.category == WeaponDefinition.CATEGORY_PRIMARY else definition.slot


func _apply_punch() -> void:
	if punch_target == null:
		return
	var state := current()
	var punch := state.recoil_offset * state.definition.view_punch if state != null else Vector2.ZERO
	punch_target.rotation = Vector3(deg_to_rad(punch.y), deg_to_rad(-punch.x), 0.0)
