class_name TacticPreview
extends Node3D
## Runs the authored waypoints through the existing bot navigation controller, without combat.

signal status_changed(slot: int, text: String)

const COLORS: Array[Color] = [Color("ffb75a"), Color("51d9e8"), Color("8ad876"), Color("ef88bd"), Color("b49aff")]
const NAV_TOLERANCE: float = 1.0
const SYNC_TIMEOUT: float = 2.0

var bots: Array[BotController] = []
var completed: Array[int] = []
var statuses: Array[String] = []

var _routes: Array[TacticDocument.Slot] = []
var _deadlines: Array[float] = []
var _map: RID
var _region: RID
var _navigation_sample: Vector3
var _sync_left: float = SYNC_TIMEOUT
var _waiting: bool = false


func begin(tactic: TacticDocument, geometry: Node3D) -> void:
	_routes = tactic.slots
	bots.resize(TacticDocument.SLOT_COUNT)
	completed.resize(TacticDocument.SLOT_COUNT)
	completed.fill(0)
	_deadlines.resize(TacticDocument.SLOT_COUNT)
	_deadlines.fill(0.0)
	statuses.resize(TacticDocument.SLOT_COUNT)
	_map = get_world_3d().navigation_map
	var region := NavigationRegion3D.new()
	add_child(region)
	var mesh := NavigationBuilder.bake(region, geometry)
	_region = region.get_rid()
	_waiting = mesh.get_polygon_count() > 0
	if _waiting:
		var vertices := mesh.get_vertices()
		var polygon := mesh.get_polygon(0)
		for vertex: int in polygon:
			_navigation_sample += vertices[vertex]
		_navigation_sample /= polygon.size()
	for i: int in TacticDocument.SLOT_COUNT:
		_set_status(i, "Preparing navigation…" if _waiting else "Map has no walkable navigation")
	set_physics_process(_waiting)


func _physics_process(delta: float) -> void:
	if _waiting:
		_sync_left -= delta
		# A map iteration can also change when a previous preview finishes tearing down.
		if (NavigationServer3D.map_get_iteration_id(_map) > 0
				and NavigationServer3D.map_get_closest_point_owner(_map, _navigation_sample) == _region):
			_waiting = false
			for i: int in _routes.size():
				_spawn(i)
		elif _sync_left <= 0.0:
			for i: int in _routes.size():
				_set_status(i, "Navigation did not become ready")
			set_physics_process(false)
		return

	var any_moving := false
	for i: int in bots.size():
		var bot := bots[i]
		if bot == null or not bot.has_goal:
			continue
		if not bot.is_alive():
			_block(i, "Left the walkable map")
		elif bot.at_goal(0.8):
			completed[i] += 1
			_set_next_goal(i)
		else:
			_deadlines[i] -= delta
			if _deadlines[i] <= 0.0:
				_block(i, "Could not reach waypoint %d" % (completed[i] + 1))
		any_moving = any_moving or bot.has_goal
	set_physics_process(any_moving)


func _spawn(index: int) -> void:
	var authored := _routes[index].start
	var position_on_mesh := NavigationServer3D.map_get_closest_point(_map, authored)
	if authored.distance_to(position_on_mesh) > NAV_TOLERANCE:
		_set_status(index, "Start is off the walkable map")
		return
	var bot := BotController.new()
	bot.setup(str(index + 1), "Player %d" % (index + 1), &"preview", BotSkill.preset(&"normal"), COLORS[index])
	add_child(bot)
	# Preview agents use world collision and can pass each other in shared route segments.
	bot.collision_mask = Hitscan.LAYER_WORLD
	bot.collision_layer = 0
	bot.respawn_at(position_on_mesh, 0.0)
	bots[index] = bot
	_set_next_goal(index)


func _set_next_goal(index: int) -> void:
	var bot := bots[index]
	var route := _routes[index].route
	var next := completed[index]
	if next >= route.size():
		bot.clear_goal()
		_set_status(index, "Holding at start" if route.is_empty() else "Finished %d / %d" % [next, route.size()])
		return
	var point := route[next]
	var goal := NavigationServer3D.map_get_closest_point(_map, point)
	var path_length := NavigationBuilder.path_length(_map, bot.global_position, goal, 0.5)
	if point.distance_to(goal) > NAV_TOLERANCE or path_length < 0.0:
		_block(index, "Waypoint %d is unreachable" % (next + 1))
		return
	bot.set_goal(goal)
	_deadlines[index] = maxf(5.0, 4.0 + path_length / BotController.RUN_SPEED * 3.0)
	_set_status(index, "Moving to %d / %d" % [next + 1, route.size()])


func _block(index: int, reason: String) -> void:
	bots[index].clear_goal()
	_set_status(index, reason)


func _set_status(index: int, text: String) -> void:
	statuses[index] = text
	status_changed.emit(index, text)
