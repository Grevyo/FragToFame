class_name NavigationBuilder
extends RefCounted
## Bakes a navigation mesh at runtime from the static world colliders of a built map, using
## Godot's native NavigationServer3D. Every editor-made map becomes walkable for bots without
## a separate authoring step. The editor's navmesh preview and MapAnalysis bake through the same
## function, so what the editor shows is what bots get.

## Must match project setting navigation/3d/default_cell_size (agent radius = 2 cells).
const CELL_SIZE: float = 0.2
## Must match project setting navigation/3d/default_cell_height.
const CELL_HEIGHT: float = 0.1
const AGENT_RADIUS: float = 0.4
const AGENT_HEIGHT: float = 1.8
## One cell: CharacterBody3D does not auto-step (stairs have a walk slope), so the navmesh must
## not route bots up ledges such as the side lip of a ramp.
const AGENT_MAX_CLIMB: float = 0.1
const AGENT_MAX_SLOPE: float = 46.0


## Parses the world colliders under [param source_root], bakes, and assigns the result to
## [param region]. Runs synchronously (maps are small); must be called on the main thread.
static func bake(region: NavigationRegion3D, source_root: Node3D) -> NavigationMesh:
	var navmesh := bake_mesh(source_root)
	region.navigation_mesh = navmesh
	return navmesh


## Bakes and returns a navigation mesh for the colliders under [param source_root] (which must
## be inside the scene tree). The defaults are the bot agent; MapAnalysis passes a crouching,
## jumping "human" agent to find routes people can take but bots cannot.
static func bake_mesh(source_root: Node3D, agent_height: float = AGENT_HEIGHT,
		agent_max_climb: float = AGENT_MAX_CLIMB) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = CELL_SIZE
	navmesh.cell_height = CELL_HEIGHT
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_height = agent_height
	navmesh.agent_max_climb = agent_max_climb
	navmesh.agent_max_slope = AGENT_MAX_SLOPE
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Hitscan.LAYER_WORLD
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, source_root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	return navmesh


## Length of the navigation path between two points, or -1 if no path reaches near [param to].
static func path_length(map: RID, from: Vector3, to: Vector3, tolerance: float = 1.0) -> float:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty() or path[path.size() - 1].distance_to(to) > tolerance:
		return -1.0
	var length := 0.0
	for i: int in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length
