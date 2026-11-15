class_name MapAutosave
extends RefCounted
## Recovery copies of unsaved editor work. One file per map ID in a folder beside the saved maps;
## written while the map has unsaved changes and removed when it is saved or discarded.

const DEFAULT_DIR: String = "user://maps/autosave"
const EXTENSION: String = ".autosave.json"
const FORMAT: String = "f2f.map_autosave"
const FORMAT_VERSION: int = 1

var directory: String = DEFAULT_DIR


func _init(dir: String = DEFAULT_DIR) -> void:
	directory = dir


func path_for(map_id: String) -> String:
	return directory.path_join(map_id + EXTENSION) if Ids.is_file_id(map_id) else ""


## Writes a recovery copy of [param doc]. [param source_path] is the saved file it came from.
func write(doc: MapDocument, source_path: String) -> Error:
	var target := path_for(doc.map_id)
	if target.is_empty():
		return ERR_INVALID_PARAMETER
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK and not DirAccess.dir_exists_absolute(directory):
		return err
	var staged := target + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_string(JSON.stringify({
		"format": FORMAT, "format_version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()), "source_path": source_path,
		"document": doc.to_dict(),
	}))
	file.close()
	if not written:
		DirAccess.remove_absolute(staged)
		return ERR_FILE_CANT_WRITE
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(staged, target)


## Returns {"document": MapDocument, "source_path": String, "saved_at": int} or {} if unreadable.
func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var data := json.data as Dictionary
	if data.get("format") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION \
			or not data.get("document") is Dictionary:
		return {}
	var doc := MapDocument.from_dict(data["document"] as Dictionary)
	if doc == null:
		return {}
	return {"document": doc, "source_path": str(data.get("source_path", "")), "saved_at": int(data.get("saved_at", 0))}


## Recovery copies, newest first: [{"path", "map_id", "name", "saved_at", "pieces"}].
func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if not file_name.ends_with(EXTENSION):
			continue
		var path := directory.path_join(file_name)
		var entry := read(path)
		if entry.is_empty():
			continue
		var doc := entry["document"] as MapDocument
		found.append({"path": path, "map_id": doc.map_id, "name": doc.name, "saved_at": entry["saved_at"],
			"pieces": doc.pieces.size()})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return found


func clear(map_id: String) -> void:
	var path := path_for(map_id)
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
