class_name OfficialMaps
extends RefCounted
## Registry of official maps shipped with the game. Each one is an ordinary saved map document
## (the file the Creation Studio writes), copied into res://data/maps/official. Nothing here can
## do more than a player's own saved map.

const DIRECTORY: String = "res://data/maps/official"
## map_id -> file name. Order is the order shown in menus.
const MAPS: Dictionary[String, String] = {
	"map_f2f_kilnmarket": "kilnmarket.f2fmap.json",
}
const DEFAULT_ID: String = "map_f2f_kilnmarket"

static var _cache: Dictionary[String, Dictionary] = {}


static func ids() -> Array[String]:
	var list: Array[String] = []
	list.assign(MAPS.keys())
	return list


static func is_official(map_id: String) -> bool:
	return MAPS.has(map_id)


static func path_for(map_id: String) -> String:
	return DIRECTORY.path_join(MAPS[map_id]) if MAPS.has(map_id) else ""


## A fresh copy of the official map, or null when it is missing or unreadable.
static func load_map(map_id: String) -> MapDocument:
	if not MAPS.has(map_id):
		return null
	if not _cache.has(map_id):
		var json := JSON.new()
		var path := path_for(map_id)
		if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK \
				or not json.data is Dictionary:
			return null
		_cache[map_id] = json.data as Dictionary
	var doc := MapDocument.from_dict(_cache[map_id])
	return doc if doc != null and doc.map_id == map_id else null


## [{"map_id", "name"}] for every official map that loads.
static func listing() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for map_id: String in MAPS:
		var doc := load_map(map_id)
		if doc != null:
			list.append({"map_id": map_id, "name": doc.name})
	return list


## Resolves any playable map ID: an official map, the development arena, or (when [param storage]
## is given) a map saved by the player.
static func find_map(map_id: String, storage: MapStorage = null) -> MapDocument:
	if is_official(map_id):
		return load_map(map_id)
	if map_id == MapTemplates.SANDBOX_ARENA_ID:
		return MapTemplates.sandbox_arena()
	return storage.load_map(map_id) if storage != null else null
