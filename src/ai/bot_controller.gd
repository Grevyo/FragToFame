class_name BotController
extends CombatantMovementBody
## An AI combatant. Navigates the baked navmesh toward a goal, spots enemies (vision cone, line of
## sight, close-range awareness), reacts with a human-like delay, aims through [AimModel] and
## fires through the same [WeaponController] the player uses. Takes cover while reloading under
## fire and searches the last known position of a lost enemy.
##
## It moves like a player (Milestone 7 A): in a fight it strafes between bursts and stops dead to
## shoot (counter-strafe); on the move it clears the places in sight that its team has not
## checked ([TeamKnowledge]) by looking and pre-aiming at them; it walks where the enemy was just
## seen; when an enemy drops out of sight it holds the angle before following; holding a spot it
## jiggle-peeks for information.
##
## Objective decisions (where to go, when to plant or defuse) come from its owner — the
## MatchDirector today, team tactics and the IGL in Milestone 7.

signal died(info: DamageInfo)

enum Mode { MOVE, ENGAGE, SEARCH }

const LOS_INTERVAL: float = 0.1
## A bot this blind ([method CombatantMovementBody.blind_amount]) sees nothing.
const BLIND_SIGHT_LIMIT: float = 0.35
const SEARCH_TIME: float = 4.0
const REPATH_INTERVAL: float = 0.5
## Idle/navigation turning speed as a fraction of the skill's turn speed.
const CALM_TURN: float = 0.5
## Clearing an angle turns faster than idling (a share of the skill's turn speed).
const CLEAR_TURN: float = 0.8
## A gun is only fired at the skill's share of full-run speed or less (a counter-strafe,
## [member BotSkill.accurate_share]), unless the enemy is close enough for running fire.
const RUN_AND_GUN_DISTANCE: float = 5.0
## Seconds of one strafe between bursts (random in this range).
const STRAFE_TIME: Vector2 = Vector2(0.18, 0.42)
## Places are re-picked this often while clearing, within this reach (metres).
const CLEAR_INTERVAL: float = 0.2
const CLEAR_REACH: float = 40.0
## Looking within this many degrees of a place clears it.
const CLEAR_ANGLE: float = 14.0
## Standing in a place (this close to its centre) clears it.
const INSIDE_PLACE: float = 4.0
## A jiggle peek's step out (seconds, random in this range), and the pause between peeks.
const JIGGLE_TIME: Vector2 = Vector2(0.14, 0.26)
const JIGGLE_PAUSE: Vector2 = Vector2(1.5, 4.0)
## Walk (quietly) when a teammate saw an enemy this close in the last few seconds.
const CAUTION_RADIUS: float = 22.0

enum Strafe { HOLD, MOVE, STOP }

## A line-up is thrown once the view is this close to it (degrees) and the bot nearly still.
const THROW_ANGLE: float = 0.4
const THROW_STILL_SPEED: float = 0.4
## A throw not made within this many seconds is given up.
const THROW_GIVE_UP: float = 4.0
## Teammates' flashes within this range are looked away from.
const FLASH_AVOID_RANGE: float = 26.0

## A grenade left the hand along a line-up (or the throw was given up: thrown false).
signal utility_finished(utility_id: StringName, thrown: bool)

var bot_id: String = ""
var display_name: String = ""
var team: StringName = &""
var skill: BotSkill = BotSkill.new()
var body_color: Color = Color("3c4a5c")
## When set before the bot enters the tree, it wears this character model instead of the box
## body: a saved Character Creator preset, else a random look ([method CharacterAvatar.bot_look]),
## unless [method DevOptions.bot_character_models] is switched off. Hitboxes are unchanged.
var appearance: CharacterAppearance = null
var avatar: CharacterAvatar = null
## Enemy (and other) combatants this bot may perceive; filtered by team.
var enemies: Array[Health] = []
var goal_position: Vector3 = Vector3.ZERO
var has_goal: bool = false
## Where to look when not fighting or moving (e.g. the direction enemies come from).
var watch_point: Vector3 = Vector3.ZERO
var has_watch_point: bool = false
## Frozen bots look around but do not move or shoot (freeze time).
var frozen: bool = false
## Set by the owner while the bot plants/defuses: it stands still and holds interact.
var interact_held: bool = false
## Requests the same slow walk as the player's Shift input.
var walk_requested: bool = false
## Shared with the bot's teammates (set by the squad; null: the bot clears nothing and looks along
## its path).
var knowledge: TeamKnowledge = null
var rng := RandomNumberGenerator.new()

var health: Health
var agent: NavigationAgent3D
var mode: Mode = Mode.MOVE
## The enemy currently seen and engaged (null when none is visible).
var target: Health = null
var reaction_left: float = 0.0
var aim: AimModel

var _jump_requested: bool = false
var _los_timer: float = 0.0
var _aim_head: bool = false
var _last_known: Vector3 = Vector3.ZERO
var _search_left: float = 0.0
var _burst_pause: float = 0.0
var _semi_toggle: bool = false
var _cover_point: Vector3 = Vector3.ZERO
var _has_cover: bool = false
var _nav_target: Vector3 = Vector3(INF, INF, INF)
var _repath_left: float = 0.0
var _strafe_state: Strafe = Strafe.HOLD
var _strafe_dir: float = 1.0
var _strafe_left: float = 0.0
## The place being cleared ({} when none) and when to choose again.
var _clearing: Dictionary = {}
## A sound to check: where, and for how much longer the bot looks there (seconds).
var heard_at: Vector3 = Vector3.ZERO
var heard_left: float = 0.0
## Seconds a bot looks towards a sound it heard (after its reaction time).
const HEARD_LOOK: float = 1.8
var _clear_timer: float = 0.0
var _search_hold_left: float = 0.0
## Jiggle peek: seconds left stepping out, then stepping back; side (+1 right, −1 left).
var _jiggle_out: float = 0.0
var _jiggle_back: float = 0.0
var _jiggle_dir: float = 1.0
var _jiggle_pause: float = 2.0
var _strafing_now: bool = false
## The line-up being thrown (null when none) and how long is left to throw it.
var _throw: UtilityLineup = null
var _throw_left: float = 0.0
## Seconds still to spend lined up before letting go, and the release spread of this throw
## (from [method BotSkill.throw_timing]).
var _throw_settle: float = 0.0
var _throw_spread: float = 0.0


## Configures identity before the bot enters the tree.
func setup(id: String, name_text: String, team_key: StringName, bot_skill: BotSkill, color: Color) -> void:
	bot_id = id
	display_name = name_text
	team = team_key
	skill = bot_skill
	body_color = color
	name = "Bot_%s" % id
	if DevOptions.bot_character_models():
		appearance = CharacterAvatar.bot_look(hash(id), color)


func _ready() -> void:
	collision_layer = Hitscan.LAYER_CHARACTERS
	collision_mask = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = STAND_HEIGHT
	collision = CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = STAND_HEIGHT / 2.0
	add_child(collision)
	_initialize_movement()

	health = Health.new()
	health.name = "Health"
	health.owner_id = bot_id
	health.team = team
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = STAND_EYE
	add_child(head)

	weapons = WeaponController.new()
	weapons.name = "Weapons"
	weapons.shooter_id = bot_id
	weapons.team = team
	weapons.set_loadout([WeaponCatalog.DEFAULT_SECONDARY])
	add_child(weapons)
	weapons.eye = head

	var wears_character := appearance != null and not appearance.body.is_empty()
	hitboxes = HumanoidRig.build(self, health, not wears_character, Color("c9b48a"), body_color).hitboxes
	var own: Array[RID] = [get_rid()]
	for hitbox: Hitbox in hitboxes:
		own.append(hitbox.get_rid())
	weapons.exclude = own
	CombatantSounds.attach(self, health, false)
	if wears_character:
		avatar = CharacterAvatar.new()
		add_child(avatar)
		avatar.apply(appearance)
	else:
		_add_visor()

	agent = NavigationAgent3D.new()
	agent.name = "Agent"
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.radius = NavigationBuilder.AGENT_RADIUS
	agent.height = NavigationBuilder.AGENT_HEIGHT
	add_child(agent)

	aim = AimModel.new(skill)
	rng.seed = hash(bot_id)


func _add_visor() -> void:
	var visor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 0.06, 0.04)
	visor.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color.lightened(0.5)
	material.emission_enabled = true
	material.emission = body_color.lightened(0.3)
	visor.material_override = material
	visor.position = Vector3(0, 0.0, -0.13)
	head.add_child(visor)


# --- Owner API -------------------------------------------------------------------------------

func set_goal(position_value: Vector3) -> void:
	goal_position = position_value
	has_goal = true


func clear_goal() -> void:
	has_goal = false


## Queues one jump press for the next tick. The shared movement rules require solid ground.
func request_jump() -> void:
	_jump_requested = true


func at_goal(radius: float = 1.5) -> bool:
	if not has_goal:
		return false
	var flat := global_position - goal_position
	flat.y = 0.0
	return flat.length() <= radius and absf(global_position.y - goal_position.y) < 1.5


func set_watch_point(point: Vector3) -> void:
	watch_point = point
	has_watch_point = true


func is_alive() -> bool:
	return health != null and not health.is_dead


func sees_enemy() -> bool:
	return target != null


## Places the bot alive at a spawn with a fresh state (weapons refilled by the owner).
func respawn_at(feet_position: Vector3, yaw: float) -> void:
	global_position = feet_position + Vector3(0, 0.05, 0)
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	_reset_movement()
	walk_requested = false
	_jump_requested = false
	collision_layer = Hitscan.LAYER_CHARACTERS
	for hitbox: Hitbox in hitboxes:
		hitbox.set_enabled(true)
	health.revive()
	if avatar != null:
		avatar.revive()
	weapons.refill_all()
	weapons.trigger = false
	target = null
	mode = Mode.MOVE
	interact_held = false
	_has_cover = false
	_search_left = 0.0
	_search_hold_left = 0.0
	_nav_target = Vector3(INF, INF, INF)
	_strafe_state = Strafe.HOLD
	_clearing = {}
	_jiggle_out = 0.0
	_jiggle_back = 0.0
	_throw = null


func view_angles() -> Vector2:
	return Vector2(rad_to_deg(rotation.y), rad_to_deg(head.rotation.x))


func set_view(angles: Vector2) -> void:
	rotation.y = deg_to_rad(wrapf(angles.x, -180.0, 180.0))
	head.rotation.x = deg_to_rad(clampf(angles.y, -89.0, 89.0))


# --- Frame update ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var jump_pressed := _jump_requested
	_jump_requested = false
	if health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		_step_movement(Vector2.ZERO, false, false, delta, false)
		return
	_perceive(delta)
	var move_dir := Vector3.ZERO
	var want_fire := false
	if frozen:
		_look_idle(delta)
	elif target != null:
		if _throw != null or weapons.current().definition.is_utility():
			_cancel_throw()
		want_fire = _engage(delta)
		move_dir = _engage_movement(delta, want_fire)
	elif _throw != null:
		_strafe_state = Strafe.HOLD
		_throw_step(delta)
	else:
		_strafe_state = Strafe.HOLD
		move_dir = _navigate(delta)
		_avoid_flash(delta)
	var can_move := not frozen and not interact_held
	weapons.trigger = want_fire and can_move
	var direction := Vector2(move_dir.x, move_dir.z) if can_move else Vector2.ZERO
	# Strafes and peeks go at full speed; otherwise walk when asked, in a fight, or near the enemy.
	var walking := can_move and not _strafing_now and (walk_requested or target != null or _cautious())
	_step_movement(direction, walking, jump_pressed, delta, can_move)
	_maybe_reload()


# --- Utility -------------------------------------------------------------------------------

## Throws [param lineup] (stand still, take the utility out, line up and throw) at the thrower's
## own pace, quicker when [param hurry] is below 1. False when the bot carries none of it.
func throw_utility(lineup: UtilityLineup, hurry: float = 1.0) -> bool:
	if lineup == null or weapons.utility_count(lineup.utility_id) <= 0:
		return false
	for index: int in weapons.weapons.size():
		if weapons.weapons[index].definition.id == lineup.utility_id:
			weapons.select_index(index)
			break
	_throw = lineup
	var timing := skill.throw_timing(rng, hurry)
	_throw_settle = timing.x
	_throw_spread = timing.y
	_throw_left = THROW_GIVE_UP + _throw_settle
	return true


func is_throwing() -> bool:
	return _throw != null


func _throw_step(delta: float) -> void:
	_throw_left -= delta
	var wanted := Vector2(_throw.yaw, _throw.pitch)
	_turn_toward(wanted, delta, 1.0)
	if _throw_left <= 0.0:
		_cancel_throw()
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if AimModel.angle_between(view_angles(), wanted) > THROW_ANGLE or flat_speed > THROW_STILL_SPEED \
			or weapons.draw_remaining > 0.0 or frozen or not is_on_floor():
		return
	# Lining up takes the thrower's time, then the release is only as exact as the thrower.
	_throw_settle -= delta
	if _throw_settle > 0.0:
		return
	set_view(wanted + Vector2(rng.randfn(0.0, _throw_spread), rng.randfn(0.0, _throw_spread)))
	var lineup := _throw
	_throw = null
	var thrown := weapons.throw_current(lineup.speed)
	if thrown and knowledge != null and EquipmentCatalog.utility_kind(lineup.utility_id) == EquipmentCatalog.KIND_FLASH:
		knowledge.warn_flash(lineup.burst, lineup.seconds)
	_back_to_gun()
	utility_finished.emit(lineup.utility_id, thrown)


func _cancel_throw() -> void:
	var id := _throw.utility_id if _throw != null else &""
	_throw = null
	_back_to_gun()
	if id != &"":
		utility_finished.emit(id, false)


## Out with the best gun carried (primary, else secondary).
func _back_to_gun() -> void:
	if weapons.current() != null and not weapons.current().definition.is_utility():
		return
	if not weapons.select_slot(1):
		weapons.select_slot(2)


## Turns away from a teammate's flash about to go off nearby (overrides the walking look).
func _avoid_flash(delta: float) -> void:
	if knowledge == null:
		return
	var flash := knowledge.flash_to_avoid(head.global_position, FLASH_AVOID_RANGE, skill.flash_lead)
	if flash == Vector3.INF:
		return
	var toward := AimModel.angles_to(head.global_position, flash)
	_turn_toward(Vector2(toward.x + 180.0, 0.0), delta, 1.0)


# --- Perception ------------------------------------------------------------------------------

## The bot heard an enemy at [param position] (a footstep, a shot, a reload...). Unless it is
## already fighting, it turns to check the spot for a moment after its reaction time.
func hear(position: Vector3) -> void:
	if health.is_dead or target != null:
		return
	if heard_left <= 0.0:
		heard_left = HEARD_LOOK + skill.reaction_time
	heard_at = position + Vector3(0, 1.2, 0)


func _perceive(delta: float) -> void:
	heard_left = maxf(heard_left - delta, 0.0)
	if target != null and (not is_instance_valid(target) or target.is_dead):
		_lose_target(false)
	if blind_amount() >= BLIND_SIGHT_LIMIT:
		# Flashed: nothing to see. Keep the last known position and search once vision returns.
		if target != null:
			_lose_target(true)
		return
	_los_timer -= delta
	if _los_timer > 0.0:
		return
	_los_timer = LOS_INTERVAL
	var best: Health = null
	var best_distance := INF
	for enemy: Health in enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead or not enemy.is_enemy_of(team):
			continue
		var chest := enemy.aim_point(false)
		var distance := head.global_position.distance_to(chest)
		if distance > skill.view_distance:
			continue
		var noticed := enemy == target or distance <= skill.awareness_radius \
			or _angle_off(chest) <= skill.view_angle / 2.0
		if not noticed:
			continue
		if not (has_line_of_sight(chest) or has_line_of_sight(enemy.aim_point(true))):
			continue
		if distance < best_distance:
			best = enemy
			best_distance = distance
	if best != null:
		if best != target:
			_acquire(best)
		_last_known = best.body().global_position
		if knowledge != null:
			knowledge.report_enemy(_last_known)
	elif target != null:
		_lose_target(true)


func _acquire(enemy: Health) -> void:
	var point := enemy.aim_point(false)
	target = enemy
	mode = Mode.ENGAGE
	reaction_left = skill.reaction_time * rng.randf_range(0.85, 1.25)
	_aim_head = rng.randf() < skill.headshot_bias
	aim.acquire(_angle_off(point), rng)
	_semi_toggle = false


func _lose_target(search: bool) -> void:
	target = null
	_has_cover = false
	if search:
		mode = Mode.SEARCH
		_search_left = SEARCH_TIME
		_search_hold_left = skill.search_hold * rng.randf_range(0.8, 1.2)
	else:
		mode = Mode.MOVE


## True if nothing in the world, and no smoke, blocks the view from the bot's eyes to
## [param point].
func has_line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(head.global_position, point, Hitscan.LAYER_WORLD, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	var field := UtilityField.find(self)
	return field == null or not field.blocks_sight(head.global_position, point)


func _angle_off(point: Vector3) -> float:
	return AimModel.angle_between(view_angles(), AimModel.angles_to(head.global_position, point))


func _on_damaged(info: DamageInfo) -> void:
	if target != null or info.source_id.is_empty():
		return
	for enemy: Health in enemies:
		if is_instance_valid(enemy) and enemy.owner_id == info.source_id and not enemy.is_dead:
			_last_known = enemy.body().global_position
			mode = Mode.SEARCH
			_search_left = SEARCH_TIME
			_los_timer = 0.0
			return


# --- Combat ----------------------------------------------------------------------------------

func _engage(delta: float) -> bool:
	reaction_left -= delta
	_burst_pause = maxf(_burst_pause - delta, 0.0)
	var point := target.aim_point(_aim_head)
	var desired := AimModel.angles_to(head.global_position, point)
	var state := weapons.current()
	var recoil := state.recoil_offset if state != null else Vector2.ZERO
	# Bullets follow view + recoil; pull the view against a skill-dependent share of it.
	var compensated := Vector2(desired.x + recoil.x * skill.recoil_control, desired.y - recoil.y * skill.recoil_control)
	set_view(aim.step(view_angles(), compensated, delta))
	if reaction_left > 0.0 or state == null or state.is_reloading() or state.ammo <= 0:
		return false
	var distance := head.global_position.distance_to(point)
	# Moving guns miss: wait for the counter-strafe unless the enemy is in your face.
	if _strafe_state == Strafe.MOVE and distance > RUN_AND_GUN_DISTANCE:
		return false
	if accuracy_speed() > ShooterMotion.REFERENCE_SPEED * skill.accurate_share and distance > RUN_AND_GUN_DISTANCE:
		return false
	var radius := 0.14 if _aim_head else 0.25
	var tolerance := rad_to_deg(atan2(radius, distance)) * skill.fire_tolerance
	var bullet := view_angles() + Vector2(-recoil.x, recoil.y)
	if AimModel.angle_between(bullet, desired) > tolerance:
		return false
	if state.definition.is_automatic():
		if distance > skill.burst_distance:
			if _burst_pause > 0.0:
				return false
			if state.recoil_offset.length() > 2.2:
				_burst_pause = 0.3
				return false
		return true
	# Semi-automatic weapons need the trigger released between shots.
	_semi_toggle = not _semi_toggle
	return _semi_toggle


func _engage_movement(delta: float, firing: bool) -> Vector3:
	_strafing_now = false
	var state := weapons.current()
	if state != null and state.is_reloading():
		_strafe_state = Strafe.HOLD
		if not _has_cover:
			_find_cover()
		if _has_cover:
			return _path_direction(_cover_point)
		return Vector3.ZERO
	return _strafe_step(delta, state, firing)


## Between bursts: strafe a short way, then press the other way until slow enough to shoot
## accurately (a counter-strafe), shoot, and go again. Disciplined bots strafe more often. Never
## starts a strafe in a frame it is [param firing] (the shot would leave on the move).
func _strafe_step(delta: float, state: WeaponState, firing: bool) -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	match _strafe_state:
		Strafe.MOVE:
			_strafe_left -= delta
			if _strafe_left <= 0.0:
				_strafe_state = Strafe.STOP
			_strafing_now = true
			return right * _strafe_dir
		Strafe.STOP:
			if accuracy_speed() <= ShooterMotion.REFERENCE_SPEED * skill.accurate_share * 0.6:
				_strafe_state = Strafe.HOLD
				return Vector3.ZERO
			return -right * _strafe_dir
	# Holding still and shooting: a burst over (or the first sight of an enemy) is the time to move.
	var burst_over := _burst_pause > 0.0 or (state != null and state.recoil_offset.length() > 4.0)
	if not firing and (burst_over or reaction_left > 0.0) and rng.randf() < skill.strafe * delta * 6.0:
		var side := _strafe_dir if rng.randf() < 0.35 else -_strafe_dir
		if not _floor_beside(side):
			side = -side
		if _floor_beside(side):
			_strafe_dir = side
			_strafe_state = Strafe.MOVE
			_strafe_left = rng.randf_range(STRAFE_TIME.x, STRAFE_TIME.y)
	return Vector3.ZERO


## True when there is walkable floor a step to the bot's right (+1) or left (−1).
func _floor_beside(side: float, step: float = 1.0) -> bool:
	var right := global_transform.basis.x
	right.y = 0.0
	var wanted := global_position + right.normalized() * side * step
	var map := get_world_3d().navigation_map
	var nearest := NavigationServer3D.map_get_closest_point(map, wanted)
	return Vector2(nearest.x - wanted.x, nearest.z - wanted.z).length() < 0.35 and absf(nearest.y - wanted.y) < 0.8


func _maybe_reload() -> void:
	var state := weapons.current()
	if state == null or state.is_reloading():
		return
	if state.ammo <= 0 or (target == null and state.ammo < state.definition.magazine_size * 0.35):
		weapons.request_reload()


## Picks a nearby navmesh point that the threat cannot see.
func _find_cover() -> void:
	var map := get_world_3d().navigation_map
	var threat := _last_known + Vector3(0, STAND_EYE, 0)
	var best_distance := INF
	for i: int in 12:
		var angle := rng.randf() * TAU
		var candidate := global_position + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(2.5, 7.0)
		var point := NavigationServer3D.map_get_closest_point(map, candidate)
		var query := PhysicsRayQueryParameters3D.create(threat, point + Vector3(0, 1.4, 0), Hitscan.LAYER_WORLD)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var distance := global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			_cover_point = point
			_has_cover = true


# --- Movement --------------------------------------------------------------------------------

func _navigate(delta: float) -> Vector3:
	_strafing_now = false
	var destination := Vector3.ZERO
	var moving := false
	if mode == Mode.SEARCH and _search_left > 0.0:
		var lost_at := _last_known + Vector3(0, STAND_EYE, 0)
		if _search_hold_left > 0.0:
			# Hold the angle the enemy left by: they often come straight back.
			_search_hold_left -= delta
			_turn_toward(AimModel.angles_to(head.global_position, lost_at), delta, CLEAR_TURN)
			return Vector3.ZERO
		_search_left -= delta
		moving = global_position.distance_to(_last_known) > 1.0
		if not moving:
			_search_left = 0.0
		else:
			# Follow up slowly, aimed where they were.
			var follow := _path_direction(_last_known)
			_turn_toward(AimModel.angles_to(head.global_position, lost_at), delta, CLEAR_TURN)
			return follow
	elif has_goal:
		mode = Mode.MOVE
		destination = goal_position
		moving = not at_goal(0.8)
	if not moving or interact_held:
		if not interact_held:
			var peek := _jiggle(delta)
			if peek != Vector3.ZERO:
				return peek
		_look_idle(delta)
		return Vector3.ZERO
	var direction := _path_direction(destination)
	if direction != Vector3.ZERO:
		var check := _angle_to_clear(delta, direction)
		if check != Vector3.INF:
			_turn_toward(AimModel.angles_to(head.global_position, check), delta, CLEAR_TURN)
		else:
			var look := AimModel.angles_to(head.global_position, head.global_position + direction)
			_turn_toward(Vector2(look.x, 0.0), delta)
	return direction


## The point to pre-aim while moving: the nearest place in sight that the team has not cleared,
## ahead or to the side (Vector3.INF when there is none: look where you are going). Looking at it
## clears it for the whole team.
func _angle_to_clear(delta: float, travel: Vector3) -> Vector3:
	if _checking_sound():
		return heard_at
	if knowledge == null:
		return Vector3.INF
	_clear_timer -= delta
	if not _clearing.is_empty():
		var point := (_clearing["centre"] as Vector3) + Vector3(0, STAND_EYE, 0)
		if knowledge.is_cleared(str(_clearing["id"])):
			_clearing = {}
		elif _angle_off(point) <= CLEAR_ANGLE:
			knowledge.mark_cleared(str(_clearing["id"]))
			_clearing = {}
		elif _clear_timer > 0.0:
			return point
	if _clear_timer > 0.0:
		return Vector3.INF
	_clear_timer = CLEAR_INTERVAL
	var heading := Vector2(travel.x, travel.z).normalized()
	var best: Dictionary = {}
	var best_score := INF
	var tried := 0
	for place: Dictionary in knowledge.uncleared_near(global_position, CLEAR_REACH):
		var centre := place["centre"] as Vector3
		var offset := Vector2(centre.x - global_position.x, centre.z - global_position.z)
		if offset.length() <= INSIDE_PLACE:
			knowledge.mark_cleared(str(place["id"]))
			continue
		# Behind the bot is a teammate's job (or the way it came).
		var angle := rad_to_deg(absf(heading.angle_to(offset.normalized())))
		if angle > 110.0:
			continue
		tried += 1
		if tried > 6:
			break
		if not has_line_of_sight(centre + Vector3(0, STAND_EYE, 0)):
			continue
		var score := offset.length() * (1.0 + angle / 90.0)
		if score < best_score:
			best_score = score
			best = place
	# A careless player skips some angles (and moves on as if they were clear).
	if not best.is_empty() and rng.randf() > skill.clearing:
		knowledge.mark_cleared(str(best["id"]))
		best = {}
	_clearing = best
	return (best["centre"] as Vector3) + Vector3(0, STAND_EYE, 0) if not best.is_empty() else Vector3.INF


## Holding a spot: now and then step out to one side and straight back to look (a jiggle peek),
## more readily when the team has just seen the enemy near where the bot is watching.
func _jiggle(delta: float) -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	if _jiggle_out > 0.0:
		_jiggle_out -= delta
		if _jiggle_out <= 0.0:
			_jiggle_back = JIGGLE_TIME.y
		_strafing_now = true
		return right * _jiggle_dir
	if _jiggle_back > 0.0:
		_jiggle_back -= delta
		_strafing_now = true
		return -right * _jiggle_dir
	if not has_watch_point or skill.peek <= 0.0:
		return Vector3.ZERO
	_jiggle_pause -= delta
	if _jiggle_pause > 0.0:
		return Vector3.ZERO
	_jiggle_pause = rng.randf_range(JIGGLE_PAUSE.x, JIGGLE_PAUSE.y)
	var alerted := knowledge != null and knowledge.enemy_near(watch_point, CLEAR_REACH, 4.0)
	if rng.randf() >= skill.peek * (1.0 if alerted else 0.3):
		return Vector3.ZERO
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if not _floor_beside(side):
		side = -side
		if not _floor_beside(side):
			return Vector3.ZERO
	_jiggle_dir = side
	_jiggle_out = rng.randf_range(JIGGLE_TIME.x, JIGGLE_TIME.y)
	return Vector3.ZERO


## True when a teammate saw an enemy close by just now: move quietly.
func _cautious() -> bool:
	return knowledge != null and target == null and knowledge.enemy_near(global_position, CAUTION_RADIUS, 4.0)


func _path_direction(destination: Vector3) -> Vector3:
	_repath_left -= get_physics_process_delta_time()
	var flat := Vector2(destination.x - global_position.x, destination.z - global_position.z)
	var stale := agent.is_navigation_finished() and flat.length() > agent.target_desired_distance + 0.1
	if destination.distance_to(_nav_target) > 0.5 or (stale and _repath_left <= 0.0):
		# Re-request a finished-but-short path too: a query made before the navigation map
		# synced (or after being pushed off the path) returns empty and would strand the bot.
		agent.target_position = destination
		_nav_target = destination
		_repath_left = REPATH_INTERVAL
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var next := agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	return direction.normalized() if direction.length() > 0.05 else Vector3.ZERO


## Checking a heard sound (after the reaction time has passed).
func _checking_sound() -> bool:
	return heard_left > 0.0 and heard_left <= HEARD_LOOK


func _look_idle(delta: float) -> void:
	if _checking_sound():
		_turn_toward(AimModel.angles_to(head.global_position, heard_at), delta, CLEAR_TURN)
	elif has_watch_point:
		_turn_toward(AimModel.angles_to(head.global_position, watch_point), delta)


func _turn_toward(angles: Vector2, delta: float, share: float = CALM_TURN) -> void:
	var current := view_angles()
	var diff := Vector2(wrapf(angles.x - current.x, -180.0, 180.0), angles.y - current.y)
	var max_step := skill.turn_speed * share * delta
	if diff.length() > max_step:
		diff = diff.normalized() * max_step
	set_view(current + diff)


func _on_died(info: DamageInfo) -> void:
	weapons.trigger = false
	target = null
	interact_held = false
	collision_layer = 0
	for hitbox: Hitbox in hitboxes:
		hitbox.set_enabled(false)
	if avatar != null:
		avatar.die()
	died.emit(info)
