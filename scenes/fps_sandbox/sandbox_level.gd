class_name SandboxLevel
extends Node3D
## Level holder for the FPS runtime. Builds a MapDocument with MapBuilder in RUNTIME mode —
## the same builder the Creation Studio uses — so every playable level is an editor-made map.
## Runtime entities placed as map markers (target dummies) are spawned here, so the map module
## stays unaware of combat code.

var document: MapDocument
var map_root: Node3D
var targets_root: Node3D
var dummies: Array[TargetDummy] = []
## Created on demand by [method build_navigation] (bots need it; the plain sandbox does not).
var navigation_region: NavigationRegion3D
## Grenades, smoke and fire in this level (rebuilt with every map).
var utility: UtilityField


## Builds [param doc]. Training dummies are only spawned when [param spawn_training] is true
## (matches spawn their own combatants).
func load_map(doc: MapDocument, spawn_training: bool = true) -> void:
	for node: Node3D in [map_root, targets_root, utility]:
		if node != null:
			remove_child(node)
			node.queue_free()
	dummies.clear()
	document = doc
	map_root = MapBuilder.build(doc, MapBuilder.Mode.RUNTIME)
	add_child(map_root)
	utility = UtilityField.new()
	utility.name = "Utility"
	utility.model_factory = UtilityModels.build
	add_child(utility)
	targets_root = Node3D.new()
	targets_root.name = "Targets"
	add_child(targets_root)
	if not spawn_training:
		return
	for piece: Dictionary in doc.pieces_of_type("target_dummy"):
		var dummy := TargetDummy.new()
		dummy.name = "Dummy_%s" % piece["id"]
		var props: Dictionary = piece.get("props", {})
		dummy.motion = StringName(str(props.get("motion", "static")))
		dummy.position = piece["position"]
		dummy.rotation_degrees.y = float(piece["rotation_y"])
		targets_root.add_child(dummy)
		dummies.append(dummy)


## Bakes a navigation mesh from the current map's world colliders (for bots).
func build_navigation() -> NavigationRegion3D:
	if navigation_region == null:
		navigation_region = NavigationRegion3D.new()
		navigation_region.name = "Navigation"
		add_child(navigation_region)
	NavigationBuilder.bake(navigation_region, map_root)
	return navigation_region


## All spawn points for [param team] as [position, yaw] pairs (falls back like [method spawn_point]).
func spawn_points(team: String) -> Array[Array]:
	var spawns := MapBuilder.spawn_points(document, team)
	if spawns.is_empty():
		spawns = MapBuilder.spawn_points(document, "defence" if team == "attack" else "attack")
	if spawns.is_empty():
		spawns.append([Vector3(0, 1, 0), 0.0])
	return spawns


## First spawn for [param team], falling back to the other team, then to the origin.
## Returns [position, yaw_radians].
func spawn_point(team: String = "attack") -> Array:
	var spawns := MapBuilder.spawn_points(document, team)
	if spawns.is_empty():
		spawns = MapBuilder.spawn_points(document, "defence" if team == "attack" else "attack")
	if spawns.is_empty():
		return [Vector3(0, 1, 0), 0.0]
	return spawns[0]
