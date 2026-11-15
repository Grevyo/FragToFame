class_name TacticStorage
extends RefCounted
## Keeps tactics outside map documents and stages a verified copy before every replacement.
## Files are only ever written by [method save], i.e. when the author saves a tactic.

const DIRECTORY: String = "user://tactics"
const EXTENSION: String = ".f2ftactic.json"
const MAX_FILE_BYTES: int = 256 * 1024

var directory: String


func _init(path: String = DIRECTORY) -> void:
	directory = path


func path_for(id: String) -> String:
	return directory.path_join(id + EXTENSION) if Ids.is_file_id(id) else ""


## Saves the tactic and binds it to [param map] as it is now (revision, content version and
## fingerprint). Returns "" or the reason it was not saved.
func save(tactic: TacticDocument, map: MapDocument) -> String:
	var problem := tactic.compatibility_error(map)
	if problem.is_empty():
		tactic.stamp(map)
		problem = tactic.validate()
	if not problem.is_empty():
		return problem
	var created := DirAccess.make_dir_recursive_absolute(directory)
	if created != OK and not DirAccess.dir_exists_absolute(directory):
		return "Could not create the tactics folder: %s." % error_string(created)
	var target := path_for(tactic.tactic_id)
	var staged := target + "." + Ids.generate("stage")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return "Could not stage the tactic: %s." % error_string(FileAccess.get_open_error())
	var written := file.store_string(JSON.stringify(tactic.to_dict(), "\t", true, true))
	file.close()
	if not written or _read(staged) == null:
		DirAccess.remove_absolute(staged)
		return "Could not verify the staged tactic."
	var installed := FileReplacement.install(staged, target, target + ".bak")
	if installed != OK:
		DirAccess.remove_absolute(staged)
		return "Could not save the tactic: %s. Check the existing file and its .bak copy." % error_string(installed)
	return ""


## Returns {tactic, error, warnings}. A tactic for a different (or missing) map is an error and
## is not returned. A tactic whose map has changed since it was saved IS returned, with
## [code]warnings[/code] naming each step that no longer fits (see TacticCompatibility); pass a
## MapAnalysis to include reachability. The file is never modified.
func load_path(path: String, map: MapDocument, analysis: MapAnalysis = null) -> Dictionary:
	var tactic := _read(path)
	var warnings: Array[String] = []
	if tactic == null or path.get_file() != tactic.tactic_id + EXTENSION:
		return {"tactic": null, "warnings": warnings,
			"error": "This tactic file is unreadable, malformed or has an unsupported format."}
	var problem := tactic.compatibility_error(map)
	if not problem.is_empty():
		return {"tactic": null, "error": problem, "warnings": warnings}
	if not tactic.is_current(map):
		warnings.append("The map has changed since this tactic was saved (map content version %s, now %d)." % [
			str(tactic.map_content_version) if tactic.map_content_version > 0 else "unknown", map.content_version])
		warnings.append_array(TacticCompatibility.texts(TacticCompatibility.check(tactic, map, analysis)))
	return {"tactic": tactic, "error": "", "warnings": warnings}


## Every readable tactic saved for [param map_id]: [{"path", "tactic"}]. Read-only.
func list_for_map(map_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(EXTENSION):
			continue
		var path := directory.path_join(file_name)
		var tactic := _read(path)
		if tactic != null and tactic.map_id == map_id and file_name == tactic.tactic_id + EXTENSION:
			found.append({"path": path, "tactic": tactic})
	return found


static func _read(path: String) -> TacticDocument:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return null
	var json := JSON.new()
	var parsed := json.parse(file.get_as_text())
	file.close()
	return TacticDocument.from_dict(json.data as Dictionary) if parsed == OK and json.data is Dictionary else null
