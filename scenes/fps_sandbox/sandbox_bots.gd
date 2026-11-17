extends Node
## Local free-for-all opponents. Reuses the normal combatant and navigation without round rules.
## Every bot is on its own team, so bots fight the human and each other. With no team plan,
## each bot roams the map with [RoamPlanner]: it tours sites, callout areas and corners, lingers
## to look around, investigates gunfire it hears and keeps away from fights when badly hurt.

signal roster_changed(count: int, at_capacity: bool)
signal spawn_failed
## A kill not involving the human, for the kill feed.
signal kill_reported(text: String)

const MAX_BOTS: int = 10
const RESPAWN_DELAY: float = 3.0
const GOAL_INTERVAL: float = 0.25
## Random navmesh points added to the map's authored places of interest.
const WANDER_POINTS: int = 14
## Interest points closer than this to an existing one are merged.
const POINT_SPACING: float = 3.0
## A spawn this far from everyone else is good enough; nearer offsets are only used if none is.
const MIN_SPAWN_DISTANCE: float = 12.0


## What one bot is doing while roaming.
class Mind extends RefCounted:
	var destination: int = -1
	var recent: Array[int] = []
	var linger_left: float = 0.0
	var arrived: bool = false
	var noises: Array[RoamNoise] = []
	var heard_new: bool = false
const SPAWN_OFFSETS: Array[Vector3] = [
	Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5),
]

var bots: Array[BotController] = []
var _level: SandboxLevel
var _player: FirstPersonController
var _paused: bool = false
var _pending: int = 0
var _next_id: int = 1
var _goal_left: float = 0.0
var _respawns: Dictionary[BotController, float] = {}
var _spawn_capsule := CapsuleShape3D.new()
var _minds: Dictionary[BotController, Mind] = {}
## Everyone who can be shot: the human and every bot (shared with each bot as its enemy list;
## team checks skip the bot itself).
var _combatants: Array[Health] = []
var _points: Array[RoamPoint] = []
var _rng := RandomNumberGenerator.new()


## [param _player_side] is kept for the caller; free-for-all bots spawn anywhere clear.
func _init(level: SandboxLevel, player: FirstPersonController, _player_side: String) -> void:
	name = "SandboxBots"
	_level = level
	_player = player
	_spawn_capsule.radius = CombatantMovementBody.BODY_RADIUS
	_spawn_capsule.height = CombatantMovementBody.STAND_HEIGHT
	_rng.randomize()
	_combatants.append(player.health)
	player.weapons.shot_fired.connect(_on_shot.bind(player.health.owner_id))


## The places bots consider visiting (built once the navigation map is ready).
func interest_points() -> Array[RoamPoint]:
	return _points


func mind_of(bot: BotController) -> Mind:
	return _minds.get(bot)


func request_add() -> void:
	if bots.size() + _pending < MAX_BOTS:
		_pending += 1


func clear() -> void:
	_pending = 0
	_respawns.clear()
	for bot: BotController in bots:
		remove_child(bot)
		bot.queue_free()
	bots.clear()
	_minds.clear()
	_combatants.assign([_player.health])
	roster_changed.emit(0, false)


func set_paused(paused: bool) -> void:
	_paused = paused
	for bot: BotController in bots:
		bot.weapons.trigger = false
		bot.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT


func display_name_for(id: String) -> String:
	for bot: BotController in bots:
		if bot.bot_id == id:
			return bot.display_name
	return ""


func _physics_process(delta: float) -> void:
	if _pending > 0:
		_pending -= 1
		_add_bot()
	if _paused or bots.is_empty():
		return
	for mind: Mind in _minds.values():
		for noise: RoamNoise in mind.noises:
			noise.age += delta
		mind.noises.assign(mind.noises.filter(func(n: RoamNoise) -> bool: return n.age < RoamPlanner.NOISE_MEMORY))
		mind.linger_left = maxf(mind.linger_left - delta, 0.0)
	_goal_left -= delta
	if _goal_left <= 0.0:
		_goal_left = GOAL_INTERVAL
		if _points.is_empty():
			_build_points()
		for bot: BotController in bots:
			if bot.is_alive():
				_think(bot)
	for bot: BotController in bots:
		if bot.is_alive() and bot.global_position.y < _player.kill_height:
			bot.health.kill(DamageInfo.world(bot.health.current))
	for bot: BotController in _respawns.keys():
		_respawns[bot] -= delta
		if _respawns[bot] > 0.0:
			continue
		var spawn := _find_spawn()
		if spawn.is_empty():
			_respawns[bot] = GOAL_INTERVAL
		else:
			bot.respawn_at(spawn[0] as Vector3, float(spawn[1]))
			bot.show()
			_respawns.erase(bot)
			_minds[bot] = Mind.new()


func _add_bot() -> void:
	var spawn := _find_spawn()
	if spawn.is_empty():
		spawn_failed.emit()
		return
	if _level.navigation_region == null:
		_level.build_navigation()
	var bot := BotController.new()
	# Free for all: each bot is its own team.
	bot.setup("sandbox_bot_%d" % _next_id, "Bot %d" % _next_id, StringName("ffa_%d" % _next_id),
		BotSkill.preset(&"normal"), Color.from_hsv(fmod(_next_id * 0.13, 1.0), 0.6, 0.75))
	_next_id += 1
	# Keep the body in place while paused so additional bots cannot spawn on top of it.
	bot.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	add_child(bot)
	_combatants.append(bot.health)
	bot.enemies = _combatants
	bot.weapons.shot_fired.connect(_on_shot.bind(bot.bot_id))
	_minds[bot] = Mind.new()
	bot.weapons.set_loadout([WeaponCatalog.AK47, WeaponCatalog.DEFAULT_SECONDARY])
	bot.respawn_at(spawn[0] as Vector3, float(spawn[1]))
	bot.died.connect(_on_bot_died.bind(bot))
	if _paused:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	bots.append(bot)
	roster_changed.emit(bots.size(), bots.size() == MAX_BOTS)


## Free-for-all spawn: the clear spot (both teams' spawns, then the roam points) farthest from
## every living combatant, so a bot does not appear in someone's face. Returns [feet, yaw] or [].
func _find_spawn() -> Array:
	var candidates: Array[Array] = []
	for side: String in ["attack", "defence"]:
		candidates.append_array(MapBuilder.spawn_points(_level.document, side) if _level.document != null else [])
		candidates.append_array(_level.spawn_points(side))
	for point: RoamPoint in _points:
		candidates.append([point.position, _rng.randf() * TAU])
	var others: Array[Vector3] = []
	for health: Health in _combatants:
		if is_instance_valid(health) and not health.is_dead and health.body().is_inside_tree() \
				and (health.body() as Node3D).visible:
			others.append(health.body().global_position)
	var best: Array = []
	var best_distance := -1.0
	for offset: Vector3 in SPAWN_OFFSETS:
		for spawn: Array in candidates:
			var feet := _clear_floor((spawn[0] as Vector3) + offset)
			if is_nan(feet.x):
				continue
			var nearest := INF
			for other: Vector3 in others:
				nearest = minf(nearest, feet.distance_to(other))
			if nearest > best_distance:
				best_distance = nearest
				best = [feet, spawn[1]]
		if best_distance >= MIN_SPAWN_DISTANCE:
			break
	return best


## Floor point under [param point] with room to stand, or a NaN vector.
func _clear_floor(point: Vector3) -> Vector3:
	var space := _level.get_world_3d().direct_space_state
	var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, Hitscan.LAYER_WORLD)
	var floor_hit := space.intersect_ray(floor_ray)
	if floor_hit.is_empty() or (floor_hit["normal"] as Vector3).y < 0.7:
		return Vector3(NAN, NAN, NAN)
	var feet := floor_hit["position"] as Vector3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _spawn_capsule
	query.collision_mask = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS
	query.transform.origin = feet + Vector3.UP * (CombatantMovementBody.STAND_HEIGHT * 0.5 + 0.05)
	return feet if space.intersect_shape(query, 1).is_empty() else Vector3(NAN, NAN, NAN)


func _on_bot_died(info: DamageInfo, bot: BotController) -> void:
	bot.hide()
	_respawns[bot] = RESPAWN_DELAY
	# The human's own kills are reported by the sandbox with hit details.
	if info.source_id == _player.health.owner_id and not info.source_id.is_empty():
		return
	if info.cause == DamageInfo.CAUSE_WORLD or info.source_id.is_empty():
		kill_reported.emit("%s fell out of the world" % bot.display_name)
		return
	var weapon := WeaponCatalog.get_definition(info.weapon_id)
	kill_reported.emit("%s  [%s%s]  %s  · %.0f m" % [display_name_for(info.source_id),
		weapon.display_name if weapon != null else "?", " · HEADSHOT" if info.is_headshot() else "",
		bot.display_name, info.distance])


# --- Roaming ---------------------------------------------------------------------------------

## One decision for a living bot. Fighting and searching are the bot's own business; between
## fights the roam planner chooses where it goes next.
func _think(bot: BotController) -> void:
	var mind := _minds[bot]
	bot.walk_requested = RoamPlanner.should_walk(bot.global_position, mind.noises)
	if bot.target != null or bot.mode == BotController.Mode.SEARCH or _points.is_empty():
		return
	var health_share := float(bot.health.current) / maxf(bot.health.max_health, 1.0)
	var investigate := mind.heard_new and health_share > RoamPlanner.HURT_SHARE
	mind.heard_new = false
	if mind.destination >= 0 and not investigate:
		if not bot.at_goal(1.2):
			return
		if not mind.arrived:
			mind.arrived = true
			mind.linger_left = RoamPlanner.linger_time(_rng)
			bot.set_watch_point(_look_target(bot, mind))
			return
		if mind.linger_left > 0.0:
			return
	var choice := RoamPlanner.choose(_points, bot.global_position, mind.recent, mind.noises, health_share, _rng)
	if choice < 0:
		return
	mind.destination = choice
	mind.arrived = false
	mind.recent.append(choice)
	if mind.recent.size() > RoamPlanner.MEMORY:
		mind.recent.pop_front()
	bot.set_goal(_points[choice].position)


## While lingering, watch the latest gunfire, otherwise the most interesting place in view range.
func _look_target(bot: BotController, mind: Mind) -> Vector3:
	if not mind.noises.is_empty():
		return mind.noises[-1].position + Vector3(0, 1.5, 0)
	var best := _points[_rng.randi() % _points.size()].position
	var best_distance := 0.0
	for point: RoamPoint in _points:
		var distance := bot.global_position.distance_to(point.position)
		if distance > best_distance and distance < 30.0 and bot.has_line_of_sight(point.position + Vector3(0, 1.5, 0)):
			best = point.position
			best_distance = distance
	return best + Vector3(0, 1.5, 0)


## Gunfire is heard by every other living bot in range.
func _on_shot(origin: Vector3, _end: Vector3, _result: Hitscan.Result, shooter_id: String) -> void:
	for bot: BotController in bots:
		if bot.bot_id == shooter_id or not bot.is_alive() or not _minds.has(bot):
			continue
		if RoamPlanner.hears(bot.global_position, origin):
			var mind := _minds[bot]
			mind.noises.append(RoamNoise.new(origin, shooter_id))
			mind.heard_new = true


## Bombsites, callout areas, tactical anchors, AI hints and spawns from the map, plus random
## navmesh corners, all snapped to the navmesh. Waits until the navigation map has synced.
func _build_points() -> void:
	var map := _level.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var doc := _level.document
	var raw: Array[RoamPoint] = []
	if doc != null:
		for site: Dictionary in doc.pieces_of_type("bombsite"):
			raw.append(RoamPoint.new(site["position"] as Vector3, &"site"))
		for area: Dictionary in MapTactical.areas(doc):
			raw.append(RoamPoint.new(area["position"] as Vector3, &"area"))
		for anchor: Dictionary in MapTactical.anchors(doc):
			raw.append(RoamPoint.new(anchor["position"] as Vector3, &"anchor"))
		for type: String in MapTactical.HINT_TYPES:
			for hint: Dictionary in MapTactical.hints(doc, type):
				raw.append(RoamPoint.new(hint["position"] as Vector3, &"anchor"))
	for side: String in ["attack", "defence"]:
		for spawn: Array in _level.spawn_points(side):
			raw.append(RoamPoint.new(spawn[0] as Vector3, &"spawn"))
	for i: int in WANDER_POINTS:
		raw.append(RoamPoint.new(NavigationServer3D.map_get_random_point(map, 1, false), &"wander"))
	for point: RoamPoint in raw:
		var snapped := NavigationServer3D.map_get_closest_point(map, point.position)
		if snapped.distance_to(point.position) > 3.0:
			continue
		var duplicate := _points.any(func(p: RoamPoint) -> bool:
			return p.position.distance_to(snapped) < POINT_SPACING)
		if not duplicate:
			_points.append(RoamPoint.new(snapped, point.kind))
