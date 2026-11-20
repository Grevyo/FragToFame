class_name BotController
extends CombatantMovementBody
## An AI combatant. Navigates the baked navmesh toward a goal, spots enemies (vision cone, line of
## sight, close-range awareness), reacts with a human-like delay, aims through [AimModel] and
## fires through the same [WeaponController] the player uses. Takes cover while reloading under
## fire and searches the last known position of a lost enemy.
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

var bot_id: String = ""
var display_name: String = ""
var team: StringName = &""
var skill: BotSkill = BotSkill.new()
var body_color: Color = Color("3c4a5c")
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


## Configures identity before the bot enters the tree.
func setup(id: String, name_text: String, team_key: StringName, bot_skill: BotSkill, color: Color) -> void:
	bot_id = id
	display_name = name_text
	team = team_key
	skill = bot_skill
	body_color = color
	name = "Bot_%s" % id


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

	hitboxes = HumanoidRig.build(self, health, true, Color("c9b48a"), body_color).hitboxes
	var own: Array[RID] = [get_rid()]
	for hitbox: Hitbox in hitboxes:
		own.append(hitbox.get_rid())
	weapons.exclude = own
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
	weapons.refill_all()
	weapons.trigger = false
	target = null
	mode = Mode.MOVE
	interact_held = false
	_has_cover = false
	_search_left = 0.0
	_nav_target = Vector3(INF, INF, INF)


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
		want_fire = _engage(delta)
		move_dir = _engage_movement()
	else:
		move_dir = _navigate(delta)
	var can_move := not frozen and not interact_held
	weapons.trigger = want_fire and can_move
	var direction := Vector2(move_dir.x, move_dir.z) if can_move else Vector2.ZERO
	var walking := can_move and (walk_requested or target != null)
	_step_movement(direction, walking, jump_pressed, delta, can_move)
	_maybe_reload()


# --- Perception ------------------------------------------------------------------------------

func _perceive(delta: float) -> void:
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


func _engage_movement() -> Vector3:
	var state := weapons.current()
	if state != null and state.is_reloading():
		if not _has_cover:
			_find_cover()
		if _has_cover:
			return _path_direction(_cover_point)
	return Vector3.ZERO


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
	var destination := Vector3.ZERO
	var moving := false
	if mode == Mode.SEARCH and _search_left > 0.0:
		_search_left -= delta
		destination = _last_known
		moving = global_position.distance_to(_last_known) > 1.0
		if not moving:
			_search_left = 0.0
	elif has_goal:
		mode = Mode.MOVE
		destination = goal_position
		moving = not at_goal(0.8)
	if not moving or interact_held:
		_look_idle(delta)
		return Vector3.ZERO
	var direction := _path_direction(destination)
	if direction != Vector3.ZERO:
		var look := AimModel.angles_to(head.global_position, head.global_position + direction)
		_turn_toward(Vector2(look.x, 0.0), delta)
	return direction


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


func _look_idle(delta: float) -> void:
	if has_watch_point:
		_turn_toward(AimModel.angles_to(head.global_position, watch_point), delta)


func _turn_toward(angles: Vector2, delta: float) -> void:
	var current := view_angles()
	var diff := Vector2(wrapf(angles.x - current.x, -180.0, 180.0), angles.y - current.y)
	var max_step := skill.turn_speed * CALM_TURN * delta
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
	died.emit(info)
