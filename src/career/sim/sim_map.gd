class_name SimMap
extends RefCounted
## A map as the career match engine sees it: its places (spawns, sites, callout areas), which
## places connect, and how far apart they are on foot. Pure data, baked from the map's navmesh by
## SimGraphBuilder (tools/bake_sim_maps.gd); no nodes, scenes or FPS runtime here.
##
## Official maps load from res://data/maps/sim/<map_id>.json; a local map baked for testing
## loads from user://maps/sim/.

const OFFICIAL_DIR: String = "res://data/maps/sim"
const LOCAL_DIR: String = "user://maps/sim"
const FORMAT: String = "f2f.sim_map"
const FORMAT_VERSION: int = 1
const KIND_SPAWN: String = "spawn"
const KIND_SITE: String = "site"
const KIND_AREA: String = "area"

static var _cache: Dictionary[String, SimMap] = {}

var map_id: String = ""
var map_name: String = ""
var content_hash: String = ""
## id -> {"id", "kind", "name", "role", "site", "side", "centre": Vector3, "floor"}
var nodes: Dictionary[String, Dictionary] = {}
## id -> {neighbour id: metres}
var links: Dictionary[String, Dictionary] = {}
## id -> {id: metres} (-1 when there is no walk between them)
var distances: Dictionary[String, Dictionary] = {}
## Walked routes from each spawn and site: id -> {id: Array of place IDs in order}.
var walked: Dictionary[String, Dictionary] = {}


## The graph for [param map_id] (cached), or null when none has been baked.
static func for_map(map_id: String) -> SimMap:
	if _cache.has(map_id):
		return _cache[map_id]
	for dir: String in [OFFICIAL_DIR, LOCAL_DIR]:
		var path := dir.path_join(map_id + ".json")
		if FileAccess.file_exists(path):
			var made := from_json(FileAccess.get_file_as_string(path))
			if made != null and made.map_id == map_id:
				_cache[map_id] = made
				return made
	return null


static func clear_cache() -> void:
	_cache.clear()


## Reads a baked graph; null when the text is not a valid graph of this format.
static func from_json(text: String) -> SimMap:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	var data := json.data as Dictionary
	if data.get("format") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION:
		return null
	var made := SimMap.new()
	made.map_id = str(data.get("map_id", ""))
	made.map_name = str(data.get("map_name", ""))
	made.content_hash = str(data.get("content_hash", ""))
	for raw: Variant in data.get("nodes", []) as Array:
		var node := (raw as Dictionary).duplicate()
		var centre := node.get("centre", [0, 0, 0]) as Array
		node["centre"] = Vector3(float(centre[0]), float(centre[1]), float(centre[2]))
		made.nodes[str(node["id"])] = node
		made.links[str(node["id"])] = {}
	for raw: Variant in data.get("edges", []) as Array:
		var edge := raw as Array
		var a := str(edge[0])
		var b := str(edge[1])
		if made.links.has(a) and made.links.has(b):
			made.links[a][b] = float(edge[2])
			made.links[b][a] = float(edge[2])
	var stored := data.get("distances", {}) as Dictionary
	for a: Variant in stored:
		made.distances[str(a)] = (stored[a] as Dictionary).duplicate()
	var routes := data.get("routes", {}) as Dictionary
	for a: Variant in routes:
		made.walked[str(a)] = (routes[a] as Dictionary).duplicate()
	return made if not made.nodes.is_empty() else null


func ids_of_kind(kind: String) -> Array[String]:
	var list: Array[String] = []
	for id: String in nodes:
		if nodes[id]["kind"] == kind:
			list.append(id)
	list.sort()
	return list


## Site node IDs ("site_A", "site_B", …).
func sites() -> Array[String]:
	return ids_of_kind(KIND_SITE)


## The spawn node of "attack" or "defence" ("" when the map has none).
func spawn(side: String) -> String:
	var id := "spawn_" + side
	return id if nodes.has(id) else ""


func name_of(id: String) -> String:
	return str(nodes.get(id, {}).get("name", id))


func neighbours(id: String) -> Array[String]:
	var list: Array[String] = []
	list.assign((links.get(id, {}) as Dictionary).keys())
	list.sort()
	return list


## Walking distance in metres (-1 when unknown or unreachable).
func distance(a: String, b: String) -> float:
	return float((distances.get(a, {}) as Dictionary).get(b, -1.0))


## Seconds to walk from [param a] to [param b] at [param speed] metres per second.
func seconds(a: String, b: String, speed: float) -> float:
	var metres := distance(a, b)
	return metres / speed if metres >= 0.0 and speed > 0.0 else INF


## The places on a site and its surrounding areas (areas whose measuring point lies on the site).
func site_cluster(site_id: String) -> Array[String]:
	var letter := str(nodes.get(site_id, {}).get("site", ""))
	var cluster: Array[String] = [site_id]
	var index := 0
	while index < cluster.size():
		for next: String in neighbours(cluster[index]):
			if not cluster.has(next) and not letter.is_empty() and str(nodes[next].get("site", "")) == letter:
				cluster.append(next)
		index += 1
	return cluster


## The places a site is entered from: neighbours of the site (and of the areas on it) that are
## not on the site themselves.
func entrances(site_id: String) -> Array[String]:
	var cluster := site_cluster(site_id)
	var list: Array[String] = []
	for id: String in cluster:
		for next: String in neighbours(id):
			if not cluster.has(next) and not list.has(next):
				list.append(next)
	list.sort()
	return list


## The places along the way from [param from] to [param to], both ends included (empty when
## there is no route). From a spawn or site this is the route a player actually walks (baked);
## otherwise the shortest chain of connected places.
func route(from: String, to: String) -> Array[String]:
	if not nodes.has(from) or not nodes.has(to):
		return []
	var baked := (walked.get(from, {}) as Dictionary).get(to, []) as Array
	if not baked.is_empty():
		var list: Array[String] = []
		list.assign(baked)
		return list
	var best: Dictionary[String, float] = {from: 0.0}
	var previous: Dictionary[String, String] = {}
	var open: Array[String] = [from]
	while not open.is_empty():
		open.sort_custom(func(x: String, y: String) -> bool: return best[x] < best[y])
		var here: String = open.pop_front()
		if here == to:
			break
		for next: String in neighbours(here):
			var cost := best[here] + float(links[here][next])
			if not best.has(next) or cost < best[next]:
				best[next] = cost
				previous[next] = here
				if not open.has(next):
					open.append(next)
	if not best.has(to):
		return []
	var path: Array[String] = [to]
	while path[0] != from:
		path.push_front(previous[path[0]])
	return path


## True when every place can be reached from every other over connected places.
func is_fully_connected() -> bool:
	if nodes.is_empty():
		return false
	var start: String = nodes.keys()[0]
	var seen: Dictionary[String, bool] = {start: true}
	var stack: Array[String] = [start]
	while not stack.is_empty():
		for next: String in neighbours(stack.pop_back()):
			if not seen.has(next):
				seen[next] = true
				stack.append(next)
	return seen.size() == nodes.size()
