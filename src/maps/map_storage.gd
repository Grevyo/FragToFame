class_name MapStorage
extends RefCounted
## Saves and loads map documents as JSON files in a folder (default user://maps).
##
## Stage and verify the document before publishing it. The previous version is kept as ".bak".

const DEFAULT_DIR: String = "user://maps"
const EXTENSION: String = ".f2fmap.json"

var directory: String = DEFAULT_DIR


func _init(dir: String = DEFAULT_DIR) -> void:
	directory = dir


func path_for(map_id: String) -> String:
	return directory.path_join(map_id + EXTENSION) if Ids.is_file_id(map_id) else ""


## Saves [param doc], incrementing its revision. Returns OK or an error code.
func save(doc: MapDocument) -> Error:
	var target := path_for(doc.map_id)
	if target.is_empty():
		return ERR_INVALID_PARAMETER
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK and not DirAccess.dir_exists_absolute(directory):
		return err
	var next := doc.to_dict()
	next["revision"] = doc.revision + 1
	var temp := target + "." + Ids.generate("stage")
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_string(JSON.stringify(next, "\t"))
	file.close()
	if not written or load_path(temp) == null:
		DirAccess.remove_absolute(temp)
		return ERR_FILE_CANT_WRITE
	err = FileReplacement.install(temp, target, target + ".bak")
	if err == OK:
		doc.revision += 1
	else:
		DirAccess.remove_absolute(temp)
	return err


## Loads a map file. Returns null if it cannot be read or parsed.
func load_path(path: String) -> MapDocument:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	return MapDocument.from_json(text)


func load_map(map_id: String) -> MapDocument:
	var path := path_for(map_id)
	if path.is_empty():
		return null
	var doc := load_path(path)
	return doc if doc != null and doc.map_id == map_id else null


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
		if doc == null or path_for(doc.map_id) != path:
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
