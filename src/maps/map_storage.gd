class_name MapStorage
extends RefCounted
## Saves and loads map documents as JSON files in a folder (default user://maps).
##
## Writes are atomic: the document is written to "<file>.tmp" and then renamed over the target,
## so a crash mid-save never leaves a half-written map. The previous version is kept as "<file>.bak".

const DEFAULT_DIR: String = "user://maps"
const EXTENSION: String = ".f2fmap.json"

var directory: String = DEFAULT_DIR


func _init(dir: String = DEFAULT_DIR) -> void:
	directory = dir


func path_for(map_id: String) -> String:
	return directory.path_join(map_id + EXTENSION)


## Saves [param doc], incrementing its revision. Returns OK or an error code.
func save(doc: MapDocument) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	doc.revision += 1
	var target := path_for(doc.map_id)
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		doc.revision -= 1
		return FileAccess.get_open_error()
	file.store_string(doc.to_json())
	file.close()
	if FileAccess.file_exists(target):
		var backup := target + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(target, backup)
	err = DirAccess.rename_absolute(temp, target)
	if err != OK:
		doc.revision -= 1
	return err


## Loads a map file. Returns null if it cannot be read or parsed.
func load_path(path: String) -> MapDocument:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	return MapDocument.from_json(text)


func load_map(map_id: String) -> MapDocument:
	return load_path(path_for(map_id))


func delete_map(map_id: String) -> Error:
	var path := path_for(map_id)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


## Lists saved maps, newest first: [{map_id, name, path, modified, pieces}].
func list_maps() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return list
	for file_name: String in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var path := directory.path_join(file_name)
		var doc := load_path(path)
		if doc == null:
			continue
		list.append({
			"map_id": doc.map_id,
			"name": doc.name,
			"path": path,
			"modified": FileAccess.get_modified_time(path),
			"pieces": doc.pieces.size(),
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified"]) > int(b["modified"]))
	return list
