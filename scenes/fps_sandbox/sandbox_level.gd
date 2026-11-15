class_name SandboxLevel
extends Node3D
## Level holder for the FPS runtime. Builds a MapDocument with MapBuilder in RUNTIME mode —
## the same builder the Creation Studio uses — so every playable level is an editor-made map.

var document: MapDocument
var map_root: Node3D


func load_map(doc: MapDocument) -> void:
	if map_root != null:
		remove_child(map_root)
		map_root.queue_free()
	document = doc
	map_root = MapBuilder.build(doc, MapBuilder.Mode.RUNTIME)
	add_child(map_root)


## First spawn for [param team], falling back to the other team, then to the origin.
## Returns [position, yaw_radians].
func spawn_point(team: String = "attack") -> Array:
	var spawns := MapBuilder.spawn_points(document, team)
	if spawns.is_empty():
		spawns = MapBuilder.spawn_points(document, "defence" if team == "attack" else "attack")
	if spawns.is_empty():
		return [Vector3(0, 1, 0), 0.0]
	return spawns[0]
