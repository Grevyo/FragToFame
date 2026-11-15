class_name WorldDatabases
extends RefCounted
## The library of world databases a career can start from:
##
##   res://data/databases/*.f2fdb      shipped with the game (the default world)
##   user://databases/<id>.f2fdb       imported by the player (community databases)
##
## SQLite cannot open files inside an exported pack, so shipped databases are copied to
## `user://cache/databases/` before they are opened. Imports are validated on a private copy
## and never modify the file the player picked.

const BUILTIN_DIR: String = "res://data/databases"
const DEFAULT_FILE: String = "default.f2fdb"
const USER_DIR: String = "user://databases"
const CACHE_DIR: String = "user://cache/databases"

var user_dir: String = USER_DIR


func _init(user_path: String = USER_DIR) -> void:
	user_dir = user_path


static func default_path() -> String:
	return "%s/%s" % [BUILTIN_DIR, DEFAULT_FILE]


## Every available database, shipped first: {path, builtin, error, + WorldDatabase.summary()}.
func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for path: String in _files(BUILTIN_DIR):
		found.append(_describe(path, true))
	for path: String in _files(user_dir):
		found.append(_describe(path, false))
	return found


## Opens a database for reading. Returns null on failure (reason appended to [param errors]).
func open_database(path: String, errors: Array[String] = []) -> WorldDatabase:
	var local := path
	if path.begins_with("res://"):
		var hash := FileAccess.get_sha256(path)
		if hash.is_empty():
			errors.append("could not read %s" % path)
			return null
		local = "%s/%s-%s" % [CACHE_DIR, hash, path.get_file()]
		if FileAccess.get_sha256(local) != hash:
			var stage := local + "." + Ids.generate("stage")
			var copy_error := _copy(path, stage)
			if copy_error.is_empty():
				var installed := FileReplacement.install(stage, local, local + ".bak")
				if installed != OK:
					copy_error = "could not cache the world database: %s" % error_string(installed)
			if not copy_error.is_empty():
				DirAccess.remove_absolute(stage)
				errors.append(copy_error)
				return null
	var world := WorldDatabase.new()
	var error := world.open(local)
	if not error.is_empty():
		errors.append(error)
		return null
	return world


## Validates [param source_path] and adds it to the library. Returns
## {path, error, replaced, name, requires_confirmation}; replacing an existing ID is explicit.
func import_database(source_path: String, replace_existing: bool = false) -> Dictionary:
	var result := {"path": "", "error": "", "replaced": false, "name": "", "requires_confirmation": false}
	if source_path.get_extension().to_lower() != WorldDbSchema.FILE_EXTENSION:
		result["error"] = "choose a .%s world database file" % WorldDbSchema.FILE_EXTENSION
		return result
	for suffix: String in ["-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(source_path + suffix):
			result["error"] = "close the source database and export a standalone world file"
			return result
	var incoming := "%s/%s.%s" % [user_dir, Ids.generate("incoming"), WorldDbSchema.FILE_EXTENSION] + ".tmp"
	# Keep a non-library suffix on staging files so the import never appears in the picker.
	var copy_error := _copy(source_path, incoming)
	if not copy_error.is_empty():
		result["error"] = copy_error
		return result
	var world := WorldDatabase.new()
	var error := world.open(incoming)
	if error.is_empty():
		var problems := world.validate()
		if not problems.is_empty():
			error = "the database is not usable: %s" % "; ".join(problems)
	var database_id := world.database_id() if error.is_empty() else ""
	result["name"] = world.display_name() if error.is_empty() else ""
	world.close()
	if error.is_empty() and _builtin_ids().has(database_id.to_lower()):
		error = "it has the same ID as a database shipped with the game"
	if not error.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(incoming))
		result["error"] = error
		return result
	var target := "%s/%s.%s" % [user_dir, database_id, WorldDbSchema.FILE_EXTENSION]
	var replaced := FileAccess.file_exists(target)
	if replaced and not replace_existing:
		DirAccess.remove_absolute(incoming)
		result["requires_confirmation"] = true
		return result
	var moved := FileReplacement.install(incoming, target, target + ".bak")
	if moved != OK:
		DirAccess.remove_absolute(incoming)
		result["error"] = "could not store the database: %s. Check the existing file and its .bak copy." % error_string(moved)
		return result
	result["replaced"] = replaced
	result["path"] = target
	return result


func _describe(path: String, builtin: bool) -> Dictionary:
	var entry := {"path": path, "builtin": builtin, "error": "", "database_id": "", "name": path.get_file(),
		"author": "", "description": "", "status": "", "organisations": 0, "players": 0, "competitions": 0}
	var errors: Array[String] = []
	var world := open_database(path, errors)
	if world == null:
		entry["error"] = "; ".join(errors)
		return entry
	entry.merge(world.summary(), true)
	world.close()
	return entry


func _builtin_ids() -> Array[String]:
	var ids: Array[String] = []
	for path: String in _files(BUILTIN_DIR):
		var world := open_database(path)
		if world != null:
			ids.append(world.database_id().to_lower())
			world.close()
	return ids


static func _files(folder: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return files
	for file: String in dir.get_files():
		if file.get_extension() == WorldDbSchema.FILE_EXTENSION:
			files.append("%s/%s" % [folder, file])
	files.sort()
	return files


static func _copy(source: String, target: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		return "could not read %s" % source
	var folder := target.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK and not DirAccess.dir_exists_absolute(folder):
		return "could not create %s: %s" % [folder, error_string(made)]
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [target, error_string(FileAccess.get_open_error())]
	var written := file.store_buffer(bytes)
	file.close()
	if not written or FileAccess.get_sha256(target) != FileAccess.get_sha256(source):
		DirAccess.remove_absolute(target)
		return "could not verify the copy at %s" % target
	return ""
