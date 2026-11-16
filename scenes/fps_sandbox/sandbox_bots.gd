extends Node
## Local free-roam opponents. Reuses the normal combatant and navigation without round rules.

signal roster_changed(count: int, at_capacity: bool)
signal spawn_failed

const MAX_BOTS: int = 10
const RESPAWN_DELAY: float = 3.0
const GOAL_INTERVAL: float = 0.25
const SPAWN_OFFSETS: Array[Vector3] = [
	Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5),
]

var bots: Array[BotController] = []
var _level: SandboxLevel
var _player: FirstPersonController
var _spawn_side: String
var _fallback_side: String
var _paused: bool = false
var _pending: int = 0
var _next_id: int = 1
var _goal_left: float = 0.0
var _respawns: Dictionary[BotController, float] = {}
var _spawn_capsule := CapsuleShape3D.new()


func _init(level: SandboxLevel, player: FirstPersonController, player_side: String) -> void:
	name = "SandboxBots"
	_level = level
	_player = player
	_fallback_side = player_side
	_spawn_side = "attack" if player_side == "defence" else "defence"
	_spawn_capsule.radius = CombatantMovementBody.BODY_RADIUS
	_spawn_capsule.height = CombatantMovementBody.STAND_HEIGHT


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
	_goal_left -= delta
	if _goal_left <= 0.0:
		_goal_left = GOAL_INTERVAL
		var map := _level.get_world_3d().navigation_map
		var goal := NavigationServer3D.map_get_closest_point(map, _player.global_position)
		for bot: BotController in bots:
			if bot.is_alive():
				bot.set_goal(goal)
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


func _add_bot() -> void:
	var spawn := _find_spawn()
	if spawn.is_empty():
		spawn_failed.emit()
		return
	if _level.navigation_region == null:
		_level.build_navigation()
	var bot := BotController.new()
	bot.setup("sandbox_bot_%d" % _next_id, "Bot %d" % _next_id, &"sandbox_opponents",
		BotSkill.preset(&"normal"), Color("b8542a"))
	_next_id += 1
	# Keep the body in place while paused so additional bots cannot spawn on top of it.
	bot.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	add_child(bot)
	bot.enemies = [_player.health]
	bot.weapons.set_loadout([WeaponCatalog.AK47, WeaponCatalog.DEFAULT_SECONDARY])
	bot.respawn_at(spawn[0] as Vector3, float(spawn[1]))
	bot.died.connect(_on_bot_died.bind(bot))
	if _paused:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	bots.append(bot)
	roster_changed.emit(bots.size(), bots.size() == MAX_BOTS)


func _find_spawn() -> Array:
	var spawns := MapBuilder.spawn_points(_level.document, _spawn_side)
	spawns.append_array(_level.spawn_points(_fallback_side))
	var space := _level.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _spawn_capsule
	query.collision_mask = Hitscan.LAYER_WORLD | Hitscan.LAYER_CHARACTERS
	for offset: Vector3 in SPAWN_OFFSETS:
		for spawn: Array in spawns:
			var point := (spawn[0] as Vector3) + offset
			var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP,
				Hitscan.LAYER_WORLD)
			var floor_hit := space.intersect_ray(floor_ray)
			if floor_hit.is_empty() or (floor_hit["normal"] as Vector3).y < 0.7:
				continue
			var feet := floor_hit["position"] as Vector3
			query.transform.origin = feet + Vector3.UP * (CombatantMovementBody.STAND_HEIGHT * 0.5 + 0.05)
			if space.intersect_shape(query, 1).is_empty():
				return [feet, spawn[1]]
	return []


func _on_bot_died(_info: DamageInfo, bot: BotController) -> void:
	bot.hide()
	_respawns[bot] = RESPAWN_DELAY
