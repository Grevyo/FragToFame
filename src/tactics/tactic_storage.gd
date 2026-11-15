class_name TacticStorage
extends RefCounted
## Keeps tactics outside map documents and stages a verified copy before every replacement.

const DIRECTORY: String = "user://tactics"
const EXTENSION: String = ".f2ftactic.json"
const MAX_FILE_BYTES: int = 256 * 1024

var directory: String


func _init(path: String = DIRECTORY) -> void:
	directory = path


func path_for(id: String) -> String:
	return directory.path_join(id + EXTENSION) if Ids.is_file_id(id) else ""


func save(tactic: TacticDocument, map: MapDocument) -> String:
	var problem := tactic.validate()
	if problem.is_empty():
		problem = tactic.compatibility_error(map)
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


## Returns {tactic, error}. Load failure leaves the current editor document intact.
func load_path(path: String, map: MapDocument) -> Dictionary:
	var tactic := _read(path)
	if tactic == null or path.get_file() != tactic.tactic_id + EXTENSION:
		return {"tactic": null, "error": "This tactic file is unreadable, malformed or has an unsupported format."}
	var problem := tactic.compatibility_error(map)
	return {"tactic": tactic if problem.is_empty() else null, "error": problem}


static func _read(path: String) -> TacticDocument:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return null
	var json := JSON.new()
	var parsed := json.parse(file.get_as_text())
	file.close()
	return TacticDocument.from_dict(json.data as Dictionary) if parsed == OK and json.data is Dictionary else null
